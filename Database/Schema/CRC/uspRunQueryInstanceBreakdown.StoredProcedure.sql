SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunQueryInstanceBreakdown]
	@QueryMasterID INT,
	@DomainID VARCHAR(50),
	@UserID VARCHAR(50),
	@ProjectID VARCHAR(50),
	@BreakdownName VARCHAR(100)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	--*********************************************************************
	--*********************************************************************
	--**** Hard-coded breakdowns
	--*********************************************************************
	--*********************************************************************

	-- This is a fake example of a custom breakdown by SEX_CD
	IF @BreakdownName = 'CUSTOM_PATIENT_GENDER_COUNT_XML'
	BEGIN
		-- Generate the counts
		INSERT INTO #GlobalBreakdownCounts(column_name,real_size)
			SELECT (CASE WHEN SEX_CD='F' THEN 'Female' ELSE 'Male' END), COUNT(*) n
			FROM #GlobalResultPatientList p
				INNER JOIN ..PATIENT_DIMENSION b
					ON p.patient_num = b.patient_num
			WHERE SEX_CD IN ('F','M')
			GROUP BY SEX_CD
			ORDER BY 1
		-- Exit the procedure
		RETURN;
	END

	--*********************************************************************
	--*********************************************************************
	--**** Regular breakdowns
	--*********************************************************************
	--*********************************************************************

	-----------------------------------------------------------------------
	-- Declare variables and temp tables
	-----------------------------------------------------------------------

	DECLARE @Schema VARCHAR(100)
	DECLARE @OntSchema VARCHAR(100)

	DECLARE @Key VARCHAR(900)
	DECLARE @Table VARCHAR(200)
	DECLARE @Path VARCHAR(700)
	DECLARE @TableName VARCHAR(100)

	DECLARE @UseCQ2Tables BIT
	DECLARE @i INT
	DECLARE @maxi INT

	DECLARE @sql NVARCHAR(MAX)

	CREATE TABLE #Items (
		item_id INT IDENTITY(1,1) PRIMARY KEY,
		item_table VARCHAR(200),
		c_hlevel INT,
		c_fullname VARCHAR(700),
		c_name VARCHAR(2000),
		c_facttablecolumn VARCHAR(50),
		c_tablename VARCHAR(50),
		c_columnname VARCHAR(50),
		c_columndatatype VARCHAR(50),
		c_operator VARCHAR(10),
		c_dimcode VARCHAR(700),
		concept_path_id INT,
		concept_cd VARCHAR(50),
		set_size INT
	)

	-----------------------------------------------------------------------
	-- Set variables and validate
	-----------------------------------------------------------------------

	-- Get the schema
	SELECT @Schema = OBJECT_SCHEMA_NAME(@@PROCID)

	-- Get the ontology cell schema
	EXEC [HIVE].[uspGetCellSchema]	@Service = 'OntologyService',
									@DomainID = @DomainID,
									@UserID = @UserID,
									@ProjectID = @ProjectID,
									@CellSchema = @OntSchema OUTPUT

	SELECT @Key = VALUE
		FROM ..QT_BREAKDOWN_PATH
		WHERE NAME = @BreakdownName

	IF @Key IS NULL
		RETURN -- Unknown path

	SELECT @Table = SUBSTRING(@Key,3,CHARINDEX('\',@Key,3)-3),
			@Path = SUBSTRING(@Key,CHARINDEX('\',@Key,3),700)

	IF (@Table IS NULL) OR (@Path IS NULL)
		RETURN -- Invalid path

	-----------------------------------------------------------------------
	-- Get the breakdown paths from the ontology
	-----------------------------------------------------------------------

	-- Get the ontology table name
	SELECT @sql = 'SELECT @TableNameOUT = c_table_name
					FROM '+@OntSchema+'.TABLE_ACCESS
					WHERE c_table_cd = @Table'
					+(CASE WHEN HIVE.fnHasUserRole(@ProjectID,@UserID,'DATA_PROT')=1 THEN '' ELSE ' AND ISNULL(C_PROTECTED_ACCESS,''N'') <> ''Y''' END)
	EXEC sp_executesql @sql,
			N'@Table VARCHAR(200), @TableNameOUT VARCHAR(100) OUTPUT',
			@Table = @Table,
			@TableNameOUT = @TableName OUTPUT

	-- Get the breakdown items
	SELECT @sql = 'SELECT 
			'''+@OntSchema+'.'+@TableName+''' item_table, 
			c_hlevel, c_fullname, c_name, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, NULL concept_path_id, NULL concept_cd, 0 set_size
		FROM '+@OntSchema+'.'+@TableName+'
		WHERE C_FULLNAME LIKE '''+REPLACE(@Path,'''','''''')+'%''
			AND C_HLEVEL = 1 +
				(SELECT C_HLEVEL
				FROM '+@OntSchema+'.'+@TableName+'
				WHERE C_FULLNAME = '''+REPLACE(@Path,'''','''''')+''')'
	INSERT INTO #Items (item_table, c_hlevel, c_fullname, c_name, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, concept_path_id, concept_cd, set_size)
		EXEC sp_executesql @sql

	-- Escape item fields
	UPDATE #Items
		SET c_dimcode = ''''+replace(c_dimcode,'''','''''')+'%'''
		WHERE c_operator = 'LIKE'
	UPDATE #Items
		SET c_dimcode = '('+c_dimcode+')'
		WHERE c_operator = 'IN'
	UPDATE #Items
		SET c_dimcode = ''''+replace(c_dimcode,'''','''''')+''''
		WHERE c_columndatatype = 'T' AND c_operator NOT IN ('LIKE','IN')

	-----------------------------------------------------------------------
	-- Use CQ2 tables if possible to get breakdown counts
	-----------------------------------------------------------------------

	-- Determine if CQ2 tables can be used
	SELECT @UseCQ2Tables = 0
	SELECT @UseCQ2Tables = 1
		FROM ..CQ2_PARAMS
		WHERE PARAM_NAME_CD = 'USE_CQ2_TABLES' AND VALUE = 'Y'

	-- Use CQ2 tables to get breakdowns
	IF (@UseCQ2Tables = 1)
	BEGIN
		-- Convert paths to IDs and concepts
		SELECT @sql = '
			UPDATE i
				SET i.concept_path_id = p.CONCEPT_PATH_ID, i.concept_cd = p.CONCEPT_CD
				FROM #Items i INNER JOIN '+@Schema+'.CQ2_CONCEPT_PATH p ON i.c_fullname = p.C_FULLNAME'
		EXEC sp_executesql @sql

		-- Get counts for concepts
		SELECT @sql = '
			UPDATE i
				SET set_size = n
				FROM #Items i
					INNER JOIN (
						SELECT i.item_id, COUNT(*) n
						FROM #Items i
							INNER JOIN '+@Schema+'.CQ2_FACT_COUNTS_CONCEPT_PATIENT t
								ON i.concept_cd = t.CONCEPT_CD
							INNER JOIN #GlobalResultPatientList p
								ON t.PATIENT_NUM = p.PATIENT_NUM '--AND p.query_master_id = '+CAST(@QueryMasterID AS VARCHAR(50))+'
						+'WHERE i.concept_path_id IS NOT NULL AND i.concept_cd IS NOT NULL
						GROUP BY i.item_id
					) t ON t.item_id = i.item_id 
				OPTION(RECOMPILE)'
		EXEC sp_executesql @sql

		-- Get counts for paths
		SELECT @sql = '
			UPDATE i
				SET set_size = n
				FROM #Items i
					INNER JOIN (
						SELECT i.item_id, COUNT(*) n
						FROM #Items i
							INNER JOIN '+@Schema+'.CQ2_FACT_COUNTS_PATH_PATIENT t
								ON i.concept_path_id = t.CONCEPT_PATH_ID
							INNER JOIN #GlobalResultPatientList p
								ON t.PATIENT_NUM = p.PATIENT_NUM '--AND p.query_master_id = '+CAST(@QueryMasterID AS VARCHAR(50))+'
						+'WHERE i.concept_path_id IS NOT NULL AND i.concept_cd IS NULL
						GROUP BY i.item_id
					) t ON t.item_id = i.item_id 
				OPTION(RECOMPILE)'
		EXEC sp_executesql @sql

	END

	-----------------------------------------------------------------------
	-- Use non-CQ2 tables get the rest of the breakdown counts
	-----------------------------------------------------------------------

	-- Use non-CQ2 tables to get breakdowns
	SELECT @i = IsNull((SELECT MIN(item_id) FROM #items WHERE concept_path_id IS NULL),1), 
		@maxi = IsNull((SELECT MAX(item_id) FROM #items WHERE concept_path_id IS NULL),0)
	WHILE (@i <= @maxi) AND (1=1)
	BEGIN
		SELECT @sql = '
			UPDATE #items
				SET set_size = (
					SELECT COUNT(DISTINCT p.PATIENT_NUM)
					'+(CASE 
					WHEN i.concept_path_id IS NOT NULL AND i.CONCEPT_CD IS NOT NULL THEN '
						FROM '+@Schema+'.CQ2_FACT_COUNTS_CONCEPT_PATIENT t, #GlobalResultPatientList p
						WHERE t.CONCEPT_CD = '''+REPLACE(i.concept_cd,'''','''''')+'''
							AND t.PATIENT_NUM = p.PATIENT_NUM '--AND p.query_master_id = '+CAST(@QueryMasterID AS VARCHAR(50))
					WHEN i.concept_path_id IS NOT NULL THEN '
						FROM '+@Schema+'.CQ2_FACT_COUNTS_PATH_PATIENT t, #GlobalResultPatientList p
						WHERE t.CONCEPT_PATH_ID = '+CAST(i.concept_path_id AS VARCHAR(50))+'
							AND t.PATIENT_NUM = p.PATIENT_NUM '--AND p.query_master_id = '+CAST(@QueryMasterID AS VARCHAR(50))
					WHEN i.c_tablename IN ('patient_dimension','visit_dimension') THEN '
						FROM '+@Schema+'.'+i.c_tablename+' t, #GlobalResultPatientList p
						WHERE t.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode+'
							AND t.PATIENT_NUM = p.PATIENT_NUM '--AND p.query_master_id = '+CAST(@QueryMasterID AS VARCHAR(50))
					ELSE '
						FROM '+@Schema+'.OBSERVATION_FACT f, #GlobalResultPatientList p
						WHERE f.'+i.c_facttablecolumn+' IN (
								SELECT '+i.c_facttablecolumn+'
								FROM '+@Schema+'.'+i.c_tablename+' t
								WHERE t.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode+'
							)
							AND f.PATIENT_NUM = p.PATIENT_NUM '--AND p.query_master_id = '+CAST(@QueryMasterID AS VARCHAR(50))
					END)+'
				)
				WHERE item_id = '+CAST(@i AS VARCHAR(50))
				+' OPTION(RECOMPILE)'
			FROM #items i
			WHERE item_id = @i
		EXEC sp_executesql @sql
		SELECT @i = IsNull((SELECT MIN(item_id) FROM #items WHERE item_id > @i AND concept_path_id IS NULL),@maxi+1)
	END

	-----------------------------------------------------------------------
	-- Save the breakdowns to the #GlobalBreakdownCounts table
	-----------------------------------------------------------------------

	IF @BreakdownName IN ('FAKE_BREAKDOWN_SORT_BY_SIZE_XML')
	BEGIN
		INSERT INTO #GlobalBreakdownCounts(column_name,real_size)
			SELECT TOP(10) c_name, set_size
				FROM #items
				WHERE set_size>0
				ORDER BY set_size DESC
	END
	ELSE
	BEGIN
		INSERT INTO #GlobalBreakdownCounts(column_name,real_size)
			SELECT c_name, set_size
				FROM #items
				WHERE set_size>0
				ORDER BY c_name
	END

END
GO
