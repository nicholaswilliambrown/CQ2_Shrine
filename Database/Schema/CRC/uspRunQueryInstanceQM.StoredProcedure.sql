SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunQueryInstanceQM]
	@QueryMasterID INT,
	@DomainID VARCHAR(50),
	@UserID VARCHAR(50),
	@ProjectID VARCHAR(50),
	@ReturnPatientCount BIT = 0,
	@ReturnPatientList BIT = 0,
	@ReturnEncounterCount BIT = 0,
	@ReturnEncounterList BIT = 0,
	@ReturnTemporalListStart VARCHAR(50) = NULL,
	@ReturnTemporalListEnd VARCHAR(50) = NULL,
	@QueryMethod VARCHAR(100) = 'EXACT'
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Declare variables
	-- ***************************************************************************
	-- ***************************************************************************

	DECLARE @QueryStartTime DATETIME
	SELECT @QueryStartTime = GETDATE()

	DECLARE @Schema VARCHAR(100)
	DECLARE @OntSchema VARCHAR(255)

	-- Debug options
	DECLARE @DebugEnableCQ2Tables BIT
	DECLARE @DebugEnableCQ2SketchTables BIT
	DECLARE @DebugEnableCQ2PathTables BIT
	DECLARE @DebugEnablePanelReorder BIT
	DECLARE @DebugEnableAvoidTempListTables BIT
	DECLARE @DebugEnableEstimatedCountAsActual BIT
	DECLARE @DebugShowDetails BIT
	SELECT	@DebugEnableCQ2Tables = 1,
			@DebugEnableCQ2SketchTables = 1,
			@DebugEnableCQ2PathTables = 1,
			@DebugEnablePanelReorder = 1,
			@DebugEnableAvoidTempListTables = 1,
			@DebugEnableEstimatedCountAsActual = 1,
			@DebugShowDetails = 0

	-- Execution options
	DECLARE @UseCQ2Tables BIT
	DECLARE @UseCQ2SketchTables BIT
	SELECT	@UseCQ2Tables = @DebugEnableCQ2Tables,
			@UseCQ2SketchTables = @DebugEnableCQ2SketchTables
	IF (@UseCQ2Tables=1)
		SELECT @UseCQ2Tables=0 FROM CRC.CQ2_PARAMS WHERE PARAM_NAME_CD='USE_CQ2_TABLES' AND VALUE='N'
	IF (@UseCQ2Tables=1) AND (@UseCQ2SketchTables=1)
		SELECT @UseCQ2SketchTables=0 FROM CRC.CQ2_PARAMS WHERE PARAM_NAME_CD='USE_CQ2_SKETCH_TABLES' AND VALUE='N'
	ELSE
		SELECT @UseCQ2SketchTables=0

	DECLARE @QueryDefinition XML
	
	DECLARE @query_name VARCHAR(250)
	DECLARE @query_timing VARCHAR(100)	--ANY, SAMEVISIT, SAMEINSTANCENUM
	DECLARE @specificity_scale INT
	
	DECLARE @p INT
	DECLARE @i INT
	DECLARE @MaxP INT
	DECLARE @MaxI INT

	DECLARE @k INT
	DECLARE @ProcessStartTime DATETIME
	DECLARE @sql NVARCHAR(MAX)
	DECLARE @sqlTemp1 NVARCHAR(MAX)
	DECLARE @sqlTemp2 NVARCHAR(MAX)
	
	DECLARE @ItemType VARCHAR(100)
	DECLARE @ItemKeyID INT

	DECLARE @panel_date_from DATETIME
	DECLARE @panel_date_to DATETIME
	DECLARE @panel_accuracy_scale INT
	DECLARE @invert TINYINT
	DECLARE @panel_timing VARCHAR(100)
	DECLARE @total_item_occurrences INT
	DECLARE @has_date_constraint TINYINT
	DECLARE @has_date_range_constraint TINYINT
	DECLARE @has_modifier_constraint TINYINT
	DECLARE @has_value_constraint TINYINT
	DECLARE @number_of_items INT
	DECLARE @previous_panel_timing VARCHAR(100)
	DECLARE @panel_table VARCHAR(200)
	DECLARE @join_to_temp NVARCHAR(MAX)
	DECLARE @previous_panel_temp_table NVARCHAR(MAX)
	DECLARE @panel_temp_table NVARCHAR(MAX)
	DECLARE @panel_temp_table_columns NVARCHAR(MAX)
	
	DECLARE @UseTempListTables BIT
	DECLARE @UseEstimatedCountAsActual BIT

	DECLARE @PanelMaxdop VARCHAR(50)

	DECLARE @SketchPanel INT
	DECLARE @SketchPanelE INT
	DECLARE @SketchPanelN INT
	DECLARE @SketchPanelQ INT
	DECLARE @SketchPanelM INT

	DECLARE @result_type_id INT
	DECLARE @result_instance_id INT

	DECLARE @HasProtectedAccess BIT

	CREATE TABLE #Panels (
		panel_number INT PRIMARY KEY,
		panel_date_from DATETIME,
		panel_date_to DATETIME,
		panel_accuracy_scale INT,
		invert TINYINT,
		panel_timing VARCHAR(100),
		total_item_occurrences INT,
		items XML,
		estimated_count INT,
		has_multiple_occurrences TINYINT,
		has_date_constraint TINYINT,
		has_date_range_constraint TINYINT,
		has_modifier_constraint TINYINT,
		has_value_constraint TINYINT,
		has_complex_value_constraint TINYINT,
		number_of_constraints TINYINT,
		all_concept_paths TINYINT,
		number_of_items INT,
		panel_table VARCHAR(200),
		process_order INT,
		previous_panel_timing VARCHAR(100),
		panel_sql NVARCHAR(MAX),
		actual_count INT,
		run_time_ms INT
	)							

	CREATE TABLE #Items (
		item_id INT IDENTITY(1,1) PRIMARY KEY,
		panel_number INT,
		item_key VARCHAR(900),
		item_type VARCHAR(100),
		item_key_id INT,
		item_table VARCHAR(200),
		item_path VARCHAR(700),
		concept_path_id INT,
		concept_cd VARCHAR(50),
		modifier_key VARCHAR(900),
		modifier_path VARCHAR(700),
		date_from DATETIME,
		date_to DATETIME,
		value_constraint VARCHAR(MAX),
		value_operator VARCHAR(MAX),
		value_unit_of_measure VARCHAR(MAX),
		value_type VARCHAR(MAX),
		c_facttablecolumn VARCHAR(50),
		c_tablename VARCHAR(50),
		c_columnname VARCHAR(50),
		c_columndatatype VARCHAR(50),
		c_operator VARCHAR(10),
		c_dimcode VARCHAR(700),
		m_facttablecolumn VARCHAR(50),
		m_tablename VARCHAR(50),
		m_columnname VARCHAR(50),
		m_columndatatype VARCHAR(50),
		m_operator VARCHAR(10),
		m_dimcode VARCHAR(700),
		c_totalnum INT,
		valid TINYINT,
		ont_table VARCHAR(255)
	)
	
	CREATE TABLE #Concepts (
		panel_number INT NOT NULL,
		concept_cd VARCHAR(50) NOT NULL,
		date_from DATETIME,
		date_to DATETIME,
		value_constraint VARCHAR(MAX),
		value_operator VARCHAR(MAX),
		value_unit_of_measure VARCHAR(MAX),
		value_type VARCHAR(MAX),
		estimated_count INT
	)

	CREATE TABLE #QueryCounts (
		num_patients int,
		num_encounters bigint,
		num_instances bigint,
		num_facts bigint
	)

	CREATE TABLE #PatientList (
		panels INT NOT NULL,
		patient_num INT NOT NULL,
	)
	
	CREATE TABLE #EncounterList (
		panels INT NOT NULL,
		encounter_num BIGINT NOT NULL,
		patient_num INT NOT NULL
	)

	CREATE TABLE #InstanceList (
		panels INT NOT NULL,
		encounter_num BIGINT NOT NULL,
		patient_num INT NOT NULL,
		concept_cd VARCHAR(50) NOT NULL,
		provider_id VARCHAR(50) NOT NULL,
		start_date DATETIME NOT NULL,
		instance_num INT NOT NULL
	)

	-- Get the schema
	SELECT @Schema = OBJECT_SCHEMA_NAME(@@PROCID)
	DECLARE @uspRunQueryInstanceQM VARCHAR(100)
	SELECT @uspRunQueryInstanceQM = @Schema+'.uspRunQueryInstanceQM'

	-- Get the ontology cell schema
	EXEC [HIVE].[uspGetCellSchema]	@Service = 'OntologyService',
									@DomainID = @DomainID,
									@UserID = @UserID,
									@ProjectID = @ProjectID,
									@CellSchema = @OntSchema OUTPUT

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Parse the Query Definition
	-- ***************************************************************************
	-- ***************************************************************************

	------------------------------------------------------------------------------
	-- Get the query definition and confirm that the user can run the query
	------------------------------------------------------------------------------

	-- Get Query Master data
	IF @QueryMasterID >= 0
	BEGIN
		SELECT	@QueryDefinition = m.REQUEST_XML,
				@ProjectID = ISNULL(@ProjectID,m.[GROUP_ID])
			FROM ..QT_QUERY_MASTER m
			WHERE m.QUERY_MASTER_ID = @QueryMasterID
	END
	ELSE
	BEGIN
		SELECT	@QueryDefinition = query_definition
			FROM #GlobalSubqueryList
			WHERE subquery_id = @QueryMasterID
	END
	
	-- Check for security
	IF HIVE.fnHasUserRole(@ProjectID,@UserID,'DATA_OBFSC') = 0
	BEGIN
		-- TODO: Add error handling
		RETURN
	END
	SELECT @HasProtectedAccess = HIVE.fnHasUserRole(@ProjectID,@UserID,'DATA_PROT')

	------------------------------------------------------------------------------
	-- Parse the query definition
	------------------------------------------------------------------------------

	-- Get query-level information from Query Definition
	SELECT	@query_name = @QueryDefinition.value('query_definition[1]/query_name[1]','VARCHAR(250)'),
			@query_timing = @QueryDefinition.value('query_definition[1]/query_timing[1]','VARCHAR(100)'),
			@specificity_scale = @QueryDefinition.value('query_definition[1]/specificity_scale[1]','INT')
	
	-- Get panel-level information from Query Definition
	INSERT INTO #Panels (panel_number, panel_date_from, panel_date_to, panel_accuracy_scale, invert, panel_timing, total_item_occurrences, items,
							estimated_count, has_date_constraint, has_value_constraint)
		SELECT	P.x.value('panel_number[1]','INT'),
				--P.x.value('panel_date_from[1]','DATETIME'),
				--P.x.value('panel_date_to[1]','DATETIME'),
				(case when IsDate(date_from_string)=1
						then cast(date_from_string as datetime)
					when right(date_from_string,6) like '-__:__' and IsDate(left(date_from_string,len(date_from_string)-6))=1
						then cast(left(date_from_string,len(date_from_string)-6) as datetime)
					else null end),
				(case when IsDate(date_to_string)=1
						then cast(date_to_string as datetime)
					when right(date_to_string,6) like '-__:__' and IsDate(left(date_to_string,len(date_to_string)-6))=1
						then cast(left(date_to_string,len(date_to_string)-6) as datetime)
					else null end),
				P.x.value('panel_accuracy_scale[1]','INT'),
				P.x.value('invert[1]','TINYINT'),
				P.x.value('panel_timing[1]','VARCHAR(100)'),
				P.x.value('total_item_occurrences[1]','INT'),
				P.x.query('item'),
				0, 0, 0
		FROM @QueryDefinition.nodes('query_definition[1]/panel') as P(x)
			CROSS APPLY (
				SELECT P.x.value('panel_date_from[1]','VARCHAR(100)') date_from_string,
					P.x.value('panel_date_to[1]','VARCHAR(100)') date_to_string
			) d

	-- Get item-level information from Query Definition
	INSERT INTO #Items (panel_number, item_key, modifier_key, date_from, date_to, value_constraint, value_operator, value_unit_of_measure, value_type, valid)
		SELECT	p.panel_number,
				I.x.value('item_key[1]','VARCHAR(900)'),
				I.x.value('constrain_by_modifier[1]/modifier_key[1]','VARCHAR(900)'),
				(case when IsDate(date_from_string)=1
						then cast(date_from_string as datetime)
					when right(date_from_string,6) like '-__:__' and IsDate(left(date_from_string,len(date_from_string)-6))=1
						then cast(left(date_from_string,len(date_from_string)-6) as datetime)
					else null end),
				(case when IsDate(date_to_string)=1
						then cast(date_to_string as datetime)
					when right(date_to_string,6) like '-__:__' and IsDate(left(date_to_string,len(date_to_string)-6))=1
						then cast(left(date_to_string,len(date_to_string)-6) as datetime)
					else null end),
				IsNull(I.x.value('constrain_by_value[1]/value_constraint[1]','VARCHAR(MAX)'),
					I.x.value('constrain_by_modifier[1]/constrain_by_value[1]/value_constraint[1]','VARCHAR(MAX)')),
				IsNull(I.x.value('constrain_by_value[1]/value_operator[1]','VARCHAR(MAX)'),
					I.x.value('constrain_by_modifier[1]/constrain_by_value[1]/value_operator[1]','VARCHAR(MAX)')),
				IsNull(I.x.value('constrain_by_value[1]/value_unit_of_measure[1]','VARCHAR(MAX)'),
					I.x.value('constrain_by_modifier[1]/constrain_by_value[1]/value_unit_of_measure[1]','VARCHAR(MAX)')),
				IsNull(I.x.value('constrain_by_value[1]/value_type[1]','VARCHAR(MAX)'),
					I.x.value('constrain_by_modifier[1]/constrain_by_value[1]/value_type[1]','VARCHAR(MAX)')),
				0
		FROM #Panels p CROSS APPLY p.items.nodes('//item') as I(x)
			CROSS APPLY (
				SELECT I.x.value('constrain_by_date[1]/date_from[1]','VARCHAR(100)') date_from_string,
					I.x.value('constrain_by_date[1]/date_to[1]','VARCHAR(100)') date_to_string
			) d
	UPDATE #Items
		SET item_type = (CASE WHEN item_key LIKE '\\%\%' THEN 'concept'
							WHEN item_key LIKE 'masterid:%' THEN 'masterid'
							WHEN item_key LIKE 'patient_set_coll_id:%' THEN 'patient_set_coll_id'
							WHEN item_key LIKE 'patient_set_enc_id:%' THEN 'patient_set_enc_id'
							ELSE NULL END)
	UPDATE #Items
		SET item_key_id = SUBSTRING(item_key,LEN(item_type)+2,LEN(item_key))
		WHERE (item_type IS NOT NULL) AND (item_type <> 'concept')
	UPDATE #Items
		SET	item_table = SUBSTRING(item_key,3,CHARINDEX('\',item_key,3)-3),
			item_path = SUBSTRING(item_key,CHARINDEX('\',item_key,3),700),
			modifier_path = SUBSTRING(modifier_key,CHARINDEX('\',modifier_key,3),700)
		WHERE item_type = 'concept'

	------------------------------------------------------------------------------
	-- Get information about each item in the query
	------------------------------------------------------------------------------

	-- Get item details from ontology tables
	-- Process each item as needed
	SELECT @i = 1, @MaxI = IsNull((SELECT MAX(item_id) FROM #Items),0)
	WHILE @i <= @MaxI
	BEGIN
		SELECT @ItemType = item_type, @ItemKeyID = item_key_id
			FROM #Items
			WHERE item_id = @i
		IF @ItemType = 'concept'
		BEGIN
			-- Lookup table_name
			SELECT @sql = 'UPDATE i
							SET i.ont_table = '''+REPLACE(@OntSchema,'''','''''')+'.''+t.c_table_name
							FROM #Items i, '+@OntSchema+'.TABLE_ACCESS t
							WHERE i.item_id = '+CAST(@i AS VARCHAR(50))+' 
								AND i.item_table = t.c_table_cd
							'
							+(CASE WHEN @HasProtectedAccess=1 THEN '' ELSE 'AND ISNULL(C_PROTECTED_ACCESS,''N'') <> ''Y''' END)
			EXEC sp_executesql @sql
			-- Get item details
			SELECT @sql = 'UPDATE i
								SET	i.valid = 1,
									i.c_facttablecolumn = o.c_facttablecolumn,
									i.c_tablename = o.c_tablename,
									i.c_columnname = o.c_columnname,
									i.c_columndatatype = o.c_columndatatype,
									i.c_operator = o.c_operator,
									i.c_dimcode = o.c_dimcode,
									i.c_totalnum = o.c_totalnum
								FROM #Items i, '+i.ont_table+' o
								WHERE i.item_id = '+CAST(@i AS VARCHAR(50))+' AND i.item_path = o.c_fullname'
				FROM #Items i
				WHERE i.item_id = @i
			EXEC sp_executesql @sql
			-- Get modifier details
			SELECT @sql = 'UPDATE i
								SET	i.m_facttablecolumn = o.c_facttablecolumn,
									i.m_tablename = o.c_tablename,
									i.m_columnname = o.c_columnname,
									i.m_columndatatype = o.c_columndatatype,
									i.m_operator = o.c_operator,
									i.m_dimcode = o.c_dimcode
								FROM #Items i, '+i.ont_table+' o
								WHERE i.item_id = '+CAST(@i AS VARCHAR(50))+' AND i.modifier_path = o.c_fullname
									AND i.item_path LIKE o.m_applied_path AND ISNULL(o.m_exclusion_cd,'''') <> ''X'' '
				FROM #Items i
				WHERE i.item_id = @i AND i.modifier_path<>''
			EXEC sp_executesql @sql
		END
		IF @ItemType = 'masterid'
		BEGIN
			--IF NOT EXISTS (SELECT * FROM #GlobalPatientList WHERE query_master_id = @ItemKeyID)
			IF NOT EXISTS (SELECT * FROM #GlobalQueryCounts WHERE query_master_id = @ItemKeyID)
			BEGIN
				EXEC @uspRunQueryInstanceQM
					@QueryMasterID = @ItemKeyID,
					@DomainID = @DomainID,
					@UserID = @UserID,
					@ProjectID = @ProjectID,
					@ReturnPatientCount = 1,
					@ReturnPatientList = 1
			END
			UPDATE #Items
				SET	valid = 1,
					c_facttablecolumn = 'patient_num',
					c_tablename = 'patient_dimension',
					c_columnname = 'patient_num',
					c_columndatatype = 'N',
					c_operator = 'IN',
					c_dimcode = 'SELECT patient_num FROM #GlobalPatientList WHERE query_master_id = '+cast(@ItemKeyID AS VARCHAR(50)),
					c_totalnum = (SELECT num_patients FROM #GlobalQueryCounts WHERE query_master_id = @ItemKeyID)
				WHERE item_id = @i
		END
		IF @ItemType = 'patient_set_coll_id'
		BEGIN
			UPDATE #Items
				SET	valid = 1,
					c_facttablecolumn = 'patient_num',
					c_tablename = 'patient_dimension',
					c_columnname = 'patient_num',
					c_columndatatype = 'N',
					c_operator = 'IN',
					c_dimcode = 'SELECT patient_num FROM '+@Schema+'.QT_PATIENT_SET_COLLECTION WHERE result_instance_id = '+cast(@ItemKeyID AS VARCHAR(50)),
					c_totalnum = (SELECT real_set_size FROM ..QT_QUERY_RESULT_INSTANCE WHERE result_instance_id = @ItemKeyID)
				WHERE item_id = @i
		END
		IF @ItemType = 'patient_set_enc_id'
		BEGIN
			UPDATE #Items
				SET	valid = 1,
					c_facttablecolumn = 'encounter_num',
					c_tablename = 'visit_dimension',
					c_columnname = 'encounter_num',
					c_columndatatype = 'N',
					c_operator = 'IN',
					c_dimcode = 'SELECT encounter_num FROM '+@Schema+'.QT_PATIENT_ENC_COLLECTION WHERE result_instance_id = '+cast(@ItemKeyID AS VARCHAR(50)),
					c_totalnum = (SELECT real_set_size FROM ..QT_QUERY_RESULT_INSTANCE WHERE result_instance_id = @ItemKeyID)
				WHERE item_id = @i
		END
		SELECT @i = @i + 1
	END

	------------------------------------------------------------------------------
	-- Validate query
	------------------------------------------------------------------------------

	-- Escape and validate item fields
	UPDATE #Items
		SET c_dimcode = ''''+replace(c_dimcode,'''','''''')+'%'''
		WHERE c_operator = 'LIKE'
	UPDATE #Items
		SET c_dimcode = '('+c_dimcode+')'
		WHERE c_operator = 'IN'
	UPDATE #Items
		SET c_dimcode = ''''+replace(c_dimcode,'''','''''')+''''
		WHERE c_columndatatype = 'T' AND c_operator NOT IN ('LIKE','IN')
	UPDATE #Items
		SET value_constraint = ''''+replace(value_constraint,'''','''''')+''''
		WHERE value_type IN ('TEXT','FLAG') AND value_operator <> 'IN'
	UPDATE #Items
		SET valid = 0
		WHERE value_type = 'NUMBER' AND value_operator <> 'BETWEEN' AND IsNumeric(value_constraint) = 0
	UPDATE #Items
		SET valid = 0
		WHERE item_id IN (
				SELECT item_id
				FROM (
					SELECT CHARINDEX(' AND ',value_constraint) x, *
					FROM #Items
					WHERE value_type = 'NUMBER' AND value_operator = 'BETWEEN'
				) t
				WHERE IsNumeric(CASE WHEN x > 0 THEN LEFT(value_constraint,x-1) ELSE NULL END) = 0
					OR IsNumeric(CASE WHEN x > 0 THEN SUBSTRING(value_constraint,x+5,LEN(value_constraint)) ELSE NULL END) = 0
			)
	UPDATE #Items
		SET value_type = NULL
		WHERE IsNull(value_type,'') NOT IN ('','TEXT','NUMBER','FLAG')
	UPDATE #Items
		SET value_operator = (CASE	WHEN value_operator IN ('EQ','E') THEN '='
									WHEN value_operator IN ('LT','L') THEN '<'
									WHEN value_operator IN ('GT','G') THEN '>'
									WHEN value_operator IN ('NE','N') THEN '<>'
									WHEN value_operator IN ('LTEQ','LE') THEN '<='
									WHEN value_operator IN ('GTEQ','GE') THEN '>='
									WHEN value_operator IN ('BETWEEN','IN') THEN value_operator
									ELSE NULL
									END)

	-- Escape and validate modifier fields
	UPDATE #Items
		SET m_dimcode = ''''+replace(m_dimcode,'''','''''')+'%'''
		WHERE m_operator = 'LIKE'
	UPDATE #Items
		SET m_dimcode = '('+m_dimcode+')'
		WHERE m_operator = 'IN'
	UPDATE #Items
		SET m_dimcode = ''''+replace(m_dimcode,'''','''''')+''''
		WHERE m_columndatatype = 'T' AND m_operator NOT IN ('LIKE','IN')

	-- Validate query timing
	-- Make sure the overall query timing is not null
	SELECT @query_timing = ISNULL(@query_timing,'ANY')
	-- Make sure the panel timing is not more specific than the query timing
	UPDATE #Panels
		SET panel_timing = @query_timing
		WHERE (panel_timing IS NULL)
			OR (@query_timing = 'SAMEVISIT' AND panel_timing = 'SAMEINSTANCENUM')
			OR (@query_timing = 'ANY')
	-- Make sure the panel timing is not more specific than the table
	UPDATE p
		SET p.panel_timing = 'SAMEVISIT'
		FROM #Panels p
		WHERE panel_timing = 'SAMEINSTANCENUM' AND NOT EXISTS (SELECT * FROM #Items i WHERE i.panel_number = p.panel_number AND i.c_facttablecolumn NOT IN ('patient_num','encounter_num'))
	UPDATE p
		SET p.panel_timing = 'ANY'
		FROM #Panels p
		WHERE panel_timing = 'SAMEVISIT' AND NOT EXISTS (SELECT * FROM #Items i WHERE i.panel_number = p.panel_number AND i.c_facttablecolumn NOT IN ('patient_num'))
	-- Make sure there are at least two panels to combine at each timing level
	UPDATE #Panels
		SET panel_timing = 'SAMEVISIT'
		WHERE panel_timing = 'SAMEINSTANCENUM'
			AND NOT EXISTS (SELECT 1 p FROM #Panels WHERE panel_timing = 'SAMEINSTANCENUM' HAVING (COUNT(*) >= 1) AND (SUM(1-invert) > 0))
	UPDATE #Panels
		SET panel_timing = 'ANY'
		WHERE panel_timing = 'SAMEVISIT'
			AND NOT EXISTS (SELECT 1 p FROM #Panels WHERE panel_timing IN ('SAMEVISIT','SAMEINSTANCENUM') HAVING (COUNT(*) >= 1) AND (SUM(1-invert) > 0))

	-- Confirm user has permissions to access items
	IF EXISTS (SELECT * FROM #Items WHERE IsNull(valid,0) = 0)
	BEGIN
		SELECT 'ERROR' Error, * FROM #Items WHERE IsNull(valid,0) = 0
		--ToDo: Set error status
		RETURN
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Analyze the query to determine execution plan
	-- ***************************************************************************
	-- ***************************************************************************

	------------------------------------------------------------------------------
	-- Combine invert panels if possible
	------------------------------------------------------------------------------

	DECLARE @PanelMerge TABLE (
		panel_number INT,
		new_panel_number INT
	)
	INSERT INTO @PanelMerge (panel_number, new_panel_number)
		SELECT p.panel_number, m.new_panel_number
			FROM #Panels p, (
					SELECT MIN(panel_number) new_panel_number, panel_date_from, panel_date_to, panel_accuracy_scale, panel_timing, total_item_occurrences
						FROM #Panels
						WHERE Invert = 1
						GROUP BY panel_date_from, panel_date_to, panel_accuracy_scale, panel_timing, total_item_occurrences
						HAVING COUNT(*)>10
				) m
			WHERE p.invert = 1 AND p.panel_number > m.new_panel_number
				AND ( (p.panel_date_from IS NULL AND m.panel_date_from IS NULL) OR (p.panel_date_from = m.panel_date_from) )
				AND ( (p.panel_date_to IS NULL AND m.panel_date_to IS NULL) OR (p.panel_date_to = m.panel_date_to) )
				AND ( (p.panel_accuracy_scale IS NULL AND m.panel_accuracy_scale IS NULL) OR (p.panel_accuracy_scale = m.panel_accuracy_scale) )
				AND ( (p.panel_timing IS NULL AND m.panel_timing IS NULL) OR (p.panel_timing = m.panel_timing) )
				AND ( (p.total_item_occurrences IS NULL AND m.total_item_occurrences IS NULL) OR (p.total_item_occurrences = m.total_item_occurrences) )
	DELETE
		FROM #Panels
		WHERE panel_number IN (SELECT panel_number FROM @PanelMerge)
	UPDATE i
		SET i.panel_number = m.new_panel_number
		FROM #Items i, @PanelMerge m
		WHERE i.panel_number = m.panel_number

	------------------------------------------------------------------------------
	-- Get item and panel information
	------------------------------------------------------------------------------

	IF @UseCQ2Tables = 1
	BEGIN
		-- Get item path information
		UPDATE i
			SET i.concept_path_id = p.concept_path_id, i.concept_cd = p.concept_cd, i.c_totalnum = coalesce(c.num_patients,d.num_patients,0)
			FROM #Items i
				INNER JOIN ..CQ2_CONCEPT_PATH p
					ON i.item_path = p.c_fullname
				LEFT OUTER JOIN ..CQ2_FACT_COUNTS_PATH c
					ON p.concept_path_id = c.concept_path_id
				LEFT OUTER JOIN ..CQ2_FACT_COUNTS_CONCEPT d
					ON p.concept_cd <> '' and p.concept_cd = d.concept_cd
			WHERE i.item_type = 'concept'

		-- Get estimated item counts when there is no count from the ontology or the path
		IF EXISTS (SELECT * FROM #Items WHERE c_totalnum IS NULL)
		BEGIN
			UPDATE j
				SET j.c_totalnum = t.n
				FROM #Items j, (
					SELECT i.item_id, i.panel_number, SUM(c.num_patients) n
						FROM #Items i, ..CQ2_FACT_COUNTS_CONCEPT c, ..CONCEPT_DIMENSION d
						WHERE i.c_totalnum IS NULL
							AND i.c_facttablecolumn = 'concept_cd' 
							AND i.c_tablename = 'concept_dimension' 
							AND i.c_columnname = 'concept_path'
							AND i.c_operator = 'LIKE'
							AND c.concept_cd = d.concept_cd 
							AND d.concept_path LIKE SUBSTRING(i.c_dimcode,2,LEN(i.c_dimcode)-2)
							AND i.item_type = 'concept'
						GROUP BY i.item_id, i.panel_number
				) t
				WHERE j.item_id = t.item_id AND j.panel_number = t.panel_number
		END
	END

	-- Calculate stats about panels
	UPDATE p
		SET p.has_multiple_occurrences = (CASE WHEN p.total_item_occurrences > 1 THEN 1 ELSE 0 END),
			p.has_date_constraint = (
				CASE WHEN (p.panel_date_from IS NOT NULL) OR (p.panel_date_to IS NOT NULL) THEN 1
					WHEN (i.has_item_date_from = 1) OR (i.has_item_date_to = 1) THEN 1 
					ELSE 0 END),
			p.has_date_range_constraint = (
				CASE WHEN (p.panel_date_from IS NOT NULL) AND (p.panel_date_to IS NOT NULL) THEN 1 
					WHEN i.has_item_date_range = 1 THEN 1
					WHEN (p.panel_date_from IS NOT NULL) AND (has_item_date_to = 1) THEN 1
					WHEN (p.panel_date_to IS NOT NULL) AND (has_item_date_from = 1) THEN 1
					ELSE 0 END),
			p.has_modifier_constraint = i.has_modifier_constraint,
			p.has_value_constraint = i.has_value_contraint,
			p.has_complex_value_constraint = i.has_complex_value_constraint,
			p.panel_table = i.panel_table,
			p.all_concept_paths = i.all_concept_paths,
			p.estimated_count = i.estimated_count,
			p.number_of_items = i.number_of_items
		FROM #Panels p, (
				SELECT panel_number,
					MAX(CASE WHEN modifier_path IS NOT NULL THEN 1 ELSE 0 END) has_modifier_constraint,
					MAX(CASE WHEN date_from IS NOT NULL THEN 1 ELSE 0 END) has_item_date_from,
					MAX(CASE WHEN date_to IS NOT NULL THEN 1 ELSE 0 END) has_item_date_to,
					MAX(CASE WHEN (date_from IS NOT NULL) AND (date_to IS NOT NULL) THEN 1 ELSE 0 END) has_item_date_range,
					MAX(CASE WHEN (value_constraint IS NOT NULL) 
									OR (value_operator IS NOT NULL) 
									OR (value_unit_of_measure IS NOT NULL) 
									OR (value_type IS NOT NULL) 
							THEN 1 ELSE 0 END) has_value_contraint,
					MAX(CASE WHEN (IsNull(value_operator,'') IN ('BETWEEN','IN','=','<>')) 
									OR (IsNull(value_type,'') IN ('TEXT','FLAG')) 
							THEN 1 ELSE 0 END) has_complex_value_constraint,
					(CASE WHEN MAX(c_tablename)=MIN(c_tablename) THEN MAX(c_tablename) ELSE NULL END) panel_table,
					MIN(CASE WHEN concept_path_id IS NOT NULL THEN 1 ELSE 0 END) all_concept_paths,
					SUM(IsNull(c_totalnum,1000000)) estimated_count,
					COUNT(*) number_of_items
				FROM #Items
				GROUP BY panel_number
			) i
		WHERE p.panel_number = i.panel_number
	UPDATE #Panels
		SET number_of_constraints = has_modifier_constraint + has_date_constraint + has_multiple_occurrences + has_value_constraint

	------------------------------------------------------------------------------
	-- Return a fast exact count if possible
	------------------------------------------------------------------------------

	IF (@UseCQ2Tables = 1) AND (@DebugEnableEstimatedCountAsActual = 1)
	BEGIN
		SELECT @UseEstimatedCountAsActual = 0
		SELECT @UseEstimatedCountAsActual = 1
			FROM #Panels
			WHERE all_concept_paths = 1 AND number_of_constraints = 0 AND invert = 0
				AND number_of_items=1
				AND (SELECT COUNT(*) FROM #Panels) = 1
				AND (@ReturnPatientList = 0 AND @ReturnEncounterList = 0)
		IF (@UseEstimatedCountAsActual = 1)
		BEGIN
			INSERT INTO #GlobalQueryCounts (query_master_id, num_patients, num_encounters, num_instances, num_facts, sketch_e, sketch_n, sketch_q)
				SELECT @QueryMasterID, estimated_count, null, null, null, null, null, null
				FROM #Panels t
			RETURN;
		END
	END

	------------------------------------------------------------------------------
	-- Return a fast sketch estimate if possible
	------------------------------------------------------------------------------

	IF (@UseCQ2SketchTables = 1) AND (@QueryMethod IN ('MINHASH8','MINHASH15')) AND (@DebugEnableEstimatedCountAsActual = 1)
	BEGIN
		SELECT @UseEstimatedCountAsActual = 0
		-- Make sure this is a Boolean-only query (no constraints)
		SELECT @UseEstimatedCountAsActual =	MIN(CASE WHEN all_concept_paths = 1 AND number_of_constraints = 0 AND invert = 0 THEN 1 ELSE 0 END)
			FROM #Panels
			WHERE (@ReturnPatientList = 0 AND @ReturnEncounterList = 0)
		-- Don't use this method with MINHASH15 if more than one panel (just ORs, no ANDs)
		SELECT @UseEstimatedCountAsActual = 0
			WHERE @QueryMethod='MINHASH15'
				AND (SELECT COUNT(*) FROM #Panels)>1
		-- Run the estimate
		IF (@UseEstimatedCountAsActual = 1)
		BEGIN
			-- Calculate a 15x256 sketch estimate
			select @SketchPanelE = HIVE.fnSketchEstimate(sV15, N15, J15, 32768, 1), @SketchPanelN = N15, @SketchPanelQ = J15
				from (
					select sum(sV15) sV15, sum(N15) N15, sum(J15) J15
					from (
						select B,
							cast(0 as float)+isnull(V0,0)+isnull(V1,0)+isnull(V2,0)+isnull(V3,0)+isnull(V4,0)+isnull(V5,0)+isnull(V6,0)+isnull(V7,0)+isnull(V8,0)+isnull(V9,0)+isnull(V10,0)+isnull(V11,0)+isnull(V12,0)+isnull(V13,0)+isnull(V14,0)+isnull(V15,0)+isnull(V16,0)+isnull(V17,0)+isnull(V18,0)+isnull(V19,0)+isnull(V20,0)+isnull(V21,0)+isnull(V22,0)+isnull(V23,0)+isnull(V24,0)+isnull(V25,0)+isnull(V26,0)+isnull(V27,0)+isnull(V28,0)+isnull(V29,0)+isnull(V30,0)+isnull(V31,0)+isnull(V32,0)+isnull(V33,0)+isnull(V34,0)+isnull(V35,0)+isnull(V36,0)+isnull(V37,0)+isnull(V38,0)+isnull(V39,0)+isnull(V40,0)+isnull(V41,0)+isnull(V42,0)+isnull(V43,0)+isnull(V44,0)+isnull(V45,0)+isnull(V46,0)+isnull(V47,0)+isnull(V48,0)+isnull(V49,0)+isnull(V50,0)+isnull(V51,0)+isnull(V52,0)+isnull(V53,0)+isnull(V54,0)+isnull(V55,0)+isnull(V56,0)+isnull(V57,0)+isnull(V58,0)+isnull(V59,0)+isnull(V60,0)+isnull(V61,0)+isnull(V62,0)+isnull(V63,0)+isnull(V64,0)+isnull(V65,0)+isnull(V66,0)+isnull(V67,0)+isnull(V68,0)+isnull(V69,0)+isnull(V70,0)+isnull(V71,0)+isnull(V72,0)+isnull(V73,0)+isnull(V74,0)+isnull(V75,0)+isnull(V76,0)+isnull(V77,0)+isnull(V78,0)+isnull(V79,0)+isnull(V80,0)+isnull(V81,0)+isnull(V82,0)+isnull(V83,0)+isnull(V84,0)+isnull(V85,0)+isnull(V86,0)+isnull(V87,0)+isnull(V88,0)+isnull(V89,0)+isnull(V90,0)+isnull(V91,0)+isnull(V92,0)+isnull(V93,0)+isnull(V94,0)+isnull(V95,0)+isnull(V96,0)+isnull(V97,0)+isnull(V98,0)+isnull(V99,0)+isnull(V100,0)+isnull(V101,0)+isnull(V102,0)+isnull(V103,0)+isnull(V104,0)+isnull(V105,0)+isnull(V106,0)+isnull(V107,0)+isnull(V108,0)+isnull(V109,0)+isnull(V110,0)+isnull(V111,0)+isnull(V112,0)+isnull(V113,0)+isnull(V114,0)+isnull(V115,0)+isnull(V116,0)+isnull(V117,0)+isnull(V118,0)+isnull(V119,0)+isnull(V120,0)+isnull(V121,0)+isnull(V122,0)+isnull(V123,0)+isnull(V124,0)+isnull(V125,0)+isnull(V126,0)+isnull(V127,0)+isnull(V128,0)+isnull(V129,0)+isnull(V130,0)+isnull(V131,0)+isnull(V132,0)+isnull(V133,0)+isnull(V134,0)+isnull(V135,0)+isnull(V136,0)+isnull(V137,0)+isnull(V138,0)+isnull(V139,0)+isnull(V140,0)+isnull(V141,0)+isnull(V142,0)+isnull(V143,0)+isnull(V144,0)+isnull(V145,0)+isnull(V146,0)+isnull(V147,0)+isnull(V148,0)+isnull(V149,0)+isnull(V150,0)+isnull(V151,0)+isnull(V152,0)+isnull(V153,0)+isnull(V154,0)+isnull(V155,0)+isnull(V156,0)+isnull(V157,0)+isnull(V158,0)+isnull(V159,0)+isnull(V160,0)+isnull(V161,0)+isnull(V162,0)+isnull(V163,0)+isnull(V164,0)+isnull(V165,0)+isnull(V166,0)+isnull(V167,0)+isnull(V168,0)+isnull(V169,0)+isnull(V170,0)+isnull(V171,0)+isnull(V172,0)+isnull(V173,0)+isnull(V174,0)+isnull(V175,0)+isnull(V176,0)+isnull(V177,0)+isnull(V178,0)+isnull(V179,0)+isnull(V180,0)+isnull(V181,0)+isnull(V182,0)+isnull(V183,0)+isnull(V184,0)+isnull(V185,0)+isnull(V186,0)+isnull(V187,0)+isnull(V188,0)+isnull(V189,0)+isnull(V190,0)+isnull(V191,0)+isnull(V192,0)+isnull(V193,0)+isnull(V194,0)+isnull(V195,0)+isnull(V196,0)+isnull(V197,0)+isnull(V198,0)+isnull(V199,0)+isnull(V200,0)+isnull(V201,0)+isnull(V202,0)+isnull(V203,0)+isnull(V204,0)+isnull(V205,0)+isnull(V206,0)+isnull(V207,0)+isnull(V208,0)+isnull(V209,0)+isnull(V210,0)+isnull(V211,0)+isnull(V212,0)+isnull(V213,0)+isnull(V214,0)+isnull(V215,0)+isnull(V216,0)+isnull(V217,0)+isnull(V218,0)+isnull(V219,0)+isnull(V220,0)+isnull(V221,0)+isnull(V222,0)+isnull(V223,0)+isnull(V224,0)+isnull(V225,0)+isnull(V226,0)+isnull(V227,0)+isnull(V228,0)+isnull(V229,0)+isnull(V230,0)+isnull(V231,0)+isnull(V232,0)+isnull(V233,0)+isnull(V234,0)+isnull(V235,0)+isnull(V236,0)+isnull(V237,0)+isnull(V238,0)+isnull(V239,0)+isnull(V240,0)+isnull(V241,0)+isnull(V242,0)+isnull(V243,0)+isnull(V244,0)+isnull(V245,0)+isnull(V246,0)+isnull(V247,0)+isnull(V248,0)+isnull(V249,0)+isnull(V250,0)+isnull(V251,0)+isnull(V252,0)+isnull(V253,0)+isnull(V254,0)+isnull(V255,0) sV15,
							(case when V0 is null then 0 else 1 end)+(case when V1 is null then 0 else 1 end)+(case when V2 is null then 0 else 1 end)+(case when V3 is null then 0 else 1 end)+(case when V4 is null then 0 else 1 end)+(case when V5 is null then 0 else 1 end)+(case when V6 is null then 0 else 1 end)+(case when V7 is null then 0 else 1 end)+(case when V8 is null then 0 else 1 end)+(case when V9 is null then 0 else 1 end)+(case when V10 is null then 0 else 1 end)+(case when V11 is null then 0 else 1 end)+(case when V12 is null then 0 else 1 end)+(case when V13 is null then 0 else 1 end)+(case when V14 is null then 0 else 1 end)+(case when V15 is null then 0 else 1 end)+(case when V16 is null then 0 else 1 end)+(case when V17 is null then 0 else 1 end)+(case when V18 is null then 0 else 1 end)+(case when V19 is null then 0 else 1 end)+(case when V20 is null then 0 else 1 end)+(case when V21 is null then 0 else 1 end)+(case when V22 is null then 0 else 1 end)+(case when V23 is null then 0 else 1 end)+(case when V24 is null then 0 else 1 end)+(case when V25 is null then 0 else 1 end)+(case when V26 is null then 0 else 1 end)+(case when V27 is null then 0 else 1 end)+(case when V28 is null then 0 else 1 end)+(case when V29 is null then 0 else 1 end)+(case when V30 is null then 0 else 1 end)+(case when V31 is null then 0 else 1 end)+(case when V32 is null then 0 else 1 end)+(case when V33 is null then 0 else 1 end)+(case when V34 is null then 0 else 1 end)+(case when V35 is null then 0 else 1 end)+(case when V36 is null then 0 else 1 end)+(case when V37 is null then 0 else 1 end)+(case when V38 is null then 0 else 1 end)+(case when V39 is null then 0 else 1 end)+(case when V40 is null then 0 else 1 end)+(case when V41 is null then 0 else 1 end)+(case when V42 is null then 0 else 1 end)+(case when V43 is null then 0 else 1 end)+(case when V44 is null then 0 else 1 end)+(case when V45 is null then 0 else 1 end)+(case when V46 is null then 0 else 1 end)+(case when V47 is null then 0 else 1 end)+(case when V48 is null then 0 else 1 end)+(case when V49 is null then 0 else 1 end)+(case when V50 is null then 0 else 1 end)+(case when V51 is null then 0 else 1 end)+(case when V52 is null then 0 else 1 end)+(case when V53 is null then 0 else 1 end)+(case when V54 is null then 0 else 1 end)+(case when V55 is null then 0 else 1 end)+(case when V56 is null then 0 else 1 end)+(case when V57 is null then 0 else 1 end)+(case when V58 is null then 0 else 1 end)+(case when V59 is null then 0 else 1 end)+(case when V60 is null then 0 else 1 end)+(case when V61 is null then 0 else 1 end)+(case when V62 is null then 0 else 1 end)+(case when V63 is null then 0 else 1 end)+(case when V64 is null then 0 else 1 end)+(case when V65 is null then 0 else 1 end)+(case when V66 is null then 0 else 1 end)+(case when V67 is null then 0 else 1 end)+(case when V68 is null then 0 else 1 end)+(case when V69 is null then 0 else 1 end)+(case when V70 is null then 0 else 1 end)+(case when V71 is null then 0 else 1 end)+(case when V72 is null then 0 else 1 end)+(case when V73 is null then 0 else 1 end)+(case when V74 is null then 0 else 1 end)+(case when V75 is null then 0 else 1 end)+(case when V76 is null then 0 else 1 end)+(case when V77 is null then 0 else 1 end)+(case when V78 is null then 0 else 1 end)+(case when V79 is null then 0 else 1 end)+(case when V80 is null then 0 else 1 end)+(case when V81 is null then 0 else 1 end)+(case when V82 is null then 0 else 1 end)+(case when V83 is null then 0 else 1 end)+(case when V84 is null then 0 else 1 end)+(case when V85 is null then 0 else 1 end)+(case when V86 is null then 0 else 1 end)+(case when V87 is null then 0 else 1 end)+(case when V88 is null then 0 else 1 end)+(case when V89 is null then 0 else 1 end)+(case when V90 is null then 0 else 1 end)+(case when V91 is null then 0 else 1 end)+(case when V92 is null then 0 else 1 end)+(case when V93 is null then 0 else 1 end)+(case when V94 is null then 0 else 1 end)+(case when V95 is null then 0 else 1 end)+(case when V96 is null then 0 else 1 end)+(case when V97 is null then 0 else 1 end)+(case when V98 is null then 0 else 1 end)+(case when V99 is null then 0 else 1 end)+(case when V100 is null then 0 else 1 end)+(case when V101 is null then 0 else 1 end)+(case when V102 is null then 0 else 1 end)+(case when V103 is null then 0 else 1 end)+(case when V104 is null then 0 else 1 end)+(case when V105 is null then 0 else 1 end)+(case when V106 is null then 0 else 1 end)+(case when V107 is null then 0 else 1 end)+(case when V108 is null then 0 else 1 end)+(case when V109 is null then 0 else 1 end)+(case when V110 is null then 0 else 1 end)+(case when V111 is null then 0 else 1 end)+(case when V112 is null then 0 else 1 end)+(case when V113 is null then 0 else 1 end)+(case when V114 is null then 0 else 1 end)+(case when V115 is null then 0 else 1 end)+(case when V116 is null then 0 else 1 end)+(case when V117 is null then 0 else 1 end)+(case when V118 is null then 0 else 1 end)+(case when V119 is null then 0 else 1 end)+(case when V120 is null then 0 else 1 end)+(case when V121 is null then 0 else 1 end)+(case when V122 is null then 0 else 1 end)+(case when V123 is null then 0 else 1 end)+(case when V124 is null then 0 else 1 end)+(case when V125 is null then 0 else 1 end)+(case when V126 is null then 0 else 1 end)+(case when V127 is null then 0 else 1 end)+(case when V128 is null then 0 else 1 end)+(case when V129 is null then 0 else 1 end)+(case when V130 is null then 0 else 1 end)+(case when V131 is null then 0 else 1 end)+(case when V132 is null then 0 else 1 end)+(case when V133 is null then 0 else 1 end)+(case when V134 is null then 0 else 1 end)+(case when V135 is null then 0 else 1 end)+(case when V136 is null then 0 else 1 end)+(case when V137 is null then 0 else 1 end)+(case when V138 is null then 0 else 1 end)+(case when V139 is null then 0 else 1 end)+(case when V140 is null then 0 else 1 end)+(case when V141 is null then 0 else 1 end)+(case when V142 is null then 0 else 1 end)+(case when V143 is null then 0 else 1 end)+(case when V144 is null then 0 else 1 end)+(case when V145 is null then 0 else 1 end)+(case when V146 is null then 0 else 1 end)+(case when V147 is null then 0 else 1 end)+(case when V148 is null then 0 else 1 end)+(case when V149 is null then 0 else 1 end)+(case when V150 is null then 0 else 1 end)+(case when V151 is null then 0 else 1 end)+(case when V152 is null then 0 else 1 end)+(case when V153 is null then 0 else 1 end)+(case when V154 is null then 0 else 1 end)+(case when V155 is null then 0 else 1 end)+(case when V156 is null then 0 else 1 end)+(case when V157 is null then 0 else 1 end)+(case when V158 is null then 0 else 1 end)+(case when V159 is null then 0 else 1 end)+(case when V160 is null then 0 else 1 end)+(case when V161 is null then 0 else 1 end)+(case when V162 is null then 0 else 1 end)+(case when V163 is null then 0 else 1 end)+(case when V164 is null then 0 else 1 end)+(case when V165 is null then 0 else 1 end)+(case when V166 is null then 0 else 1 end)+(case when V167 is null then 0 else 1 end)+(case when V168 is null then 0 else 1 end)+(case when V169 is null then 0 else 1 end)+(case when V170 is null then 0 else 1 end)+(case when V171 is null then 0 else 1 end)+(case when V172 is null then 0 else 1 end)+(case when V173 is null then 0 else 1 end)+(case when V174 is null then 0 else 1 end)+(case when V175 is null then 0 else 1 end)+(case when V176 is null then 0 else 1 end)+(case when V177 is null then 0 else 1 end)+(case when V178 is null then 0 else 1 end)+(case when V179 is null then 0 else 1 end)+(case when V180 is null then 0 else 1 end)+(case when V181 is null then 0 else 1 end)+(case when V182 is null then 0 else 1 end)+(case when V183 is null then 0 else 1 end)+(case when V184 is null then 0 else 1 end)+(case when V185 is null then 0 else 1 end)+(case when V186 is null then 0 else 1 end)+(case when V187 is null then 0 else 1 end)+(case when V188 is null then 0 else 1 end)+(case when V189 is null then 0 else 1 end)+(case when V190 is null then 0 else 1 end)+(case when V191 is null then 0 else 1 end)+(case when V192 is null then 0 else 1 end)+(case when V193 is null then 0 else 1 end)+(case when V194 is null then 0 else 1 end)+(case when V195 is null then 0 else 1 end)+(case when V196 is null then 0 else 1 end)+(case when V197 is null then 0 else 1 end)+(case when V198 is null then 0 else 1 end)+(case when V199 is null then 0 else 1 end)+(case when V200 is null then 0 else 1 end)+(case when V201 is null then 0 else 1 end)+(case when V202 is null then 0 else 1 end)+(case when V203 is null then 0 else 1 end)+(case when V204 is null then 0 else 1 end)+(case when V205 is null then 0 else 1 end)+(case when V206 is null then 0 else 1 end)+(case when V207 is null then 0 else 1 end)+(case when V208 is null then 0 else 1 end)+(case when V209 is null then 0 else 1 end)+(case when V210 is null then 0 else 1 end)+(case when V211 is null then 0 else 1 end)+(case when V212 is null then 0 else 1 end)+(case when V213 is null then 0 else 1 end)+(case when V214 is null then 0 else 1 end)+(case when V215 is null then 0 else 1 end)+(case when V216 is null then 0 else 1 end)+(case when V217 is null then 0 else 1 end)+(case when V218 is null then 0 else 1 end)+(case when V219 is null then 0 else 1 end)+(case when V220 is null then 0 else 1 end)+(case when V221 is null then 0 else 1 end)+(case when V222 is null then 0 else 1 end)+(case when V223 is null then 0 else 1 end)+(case when V224 is null then 0 else 1 end)+(case when V225 is null then 0 else 1 end)+(case when V226 is null then 0 else 1 end)+(case when V227 is null then 0 else 1 end)+(case when V228 is null then 0 else 1 end)+(case when V229 is null then 0 else 1 end)+(case when V230 is null then 0 else 1 end)+(case when V231 is null then 0 else 1 end)+(case when V232 is null then 0 else 1 end)+(case when V233 is null then 0 else 1 end)+(case when V234 is null then 0 else 1 end)+(case when V235 is null then 0 else 1 end)+(case when V236 is null then 0 else 1 end)+(case when V237 is null then 0 else 1 end)+(case when V238 is null then 0 else 1 end)+(case when V239 is null then 0 else 1 end)+(case when V240 is null then 0 else 1 end)+(case when V241 is null then 0 else 1 end)+(case when V242 is null then 0 else 1 end)+(case when V243 is null then 0 else 1 end)+(case when V244 is null then 0 else 1 end)+(case when V245 is null then 0 else 1 end)+(case when V246 is null then 0 else 1 end)+(case when V247 is null then 0 else 1 end)+(case when V248 is null then 0 else 1 end)+(case when V249 is null then 0 else 1 end)+(case when V250 is null then 0 else 1 end)+(case when V251 is null then 0 else 1 end)+(case when V252 is null then 0 else 1 end)+(case when V253 is null then 0 else 1 end)+(case when V254 is null then 0 else 1 end)+(case when V255 is null then 0 else 1 end) N15,
							(case when V0=W0 and N0=n then 1 else 0 end)+(case when V1=W1 and N1=n then 1 else 0 end)+(case when V2=W2 and N2=n then 1 else 0 end)+(case when V3=W3 and N3=n then 1 else 0 end)+(case when V4=W4 and N4=n then 1 else 0 end)+(case when V5=W5 and N5=n then 1 else 0 end)+(case when V6=W6 and N6=n then 1 else 0 end)+(case when V7=W7 and N7=n then 1 else 0 end)+(case when V8=W8 and N8=n then 1 else 0 end)+(case when V9=W9 and N9=n then 1 else 0 end)+(case when V10=W10 and N10=n then 1 else 0 end)+(case when V11=W11 and N11=n then 1 else 0 end)+(case when V12=W12 and N12=n then 1 else 0 end)+(case when V13=W13 and N13=n then 1 else 0 end)+(case when V14=W14 and N14=n then 1 else 0 end)+(case when V15=W15 and N15=n then 1 else 0 end)+(case when V16=W16 and N16=n then 1 else 0 end)+(case when V17=W17 and N17=n then 1 else 0 end)+(case when V18=W18 and N18=n then 1 else 0 end)+(case when V19=W19 and N19=n then 1 else 0 end)+(case when V20=W20 and N20=n then 1 else 0 end)+(case when V21=W21 and N21=n then 1 else 0 end)+(case when V22=W22 and N22=n then 1 else 0 end)+(case when V23=W23 and N23=n then 1 else 0 end)+(case when V24=W24 and N24=n then 1 else 0 end)+(case when V25=W25 and N25=n then 1 else 0 end)+(case when V26=W26 and N26=n then 1 else 0 end)+(case when V27=W27 and N27=n then 1 else 0 end)+(case when V28=W28 and N28=n then 1 else 0 end)+(case when V29=W29 and N29=n then 1 else 0 end)+(case when V30=W30 and N30=n then 1 else 0 end)+(case when V31=W31 and N31=n then 1 else 0 end)+(case when V32=W32 and N32=n then 1 else 0 end)+(case when V33=W33 and N33=n then 1 else 0 end)+(case when V34=W34 and N34=n then 1 else 0 end)+(case when V35=W35 and N35=n then 1 else 0 end)+(case when V36=W36 and N36=n then 1 else 0 end)+(case when V37=W37 and N37=n then 1 else 0 end)+(case when V38=W38 and N38=n then 1 else 0 end)+(case when V39=W39 and N39=n then 1 else 0 end)+(case when V40=W40 and N40=n then 1 else 0 end)+(case when V41=W41 and N41=n then 1 else 0 end)+(case when V42=W42 and N42=n then 1 else 0 end)+(case when V43=W43 and N43=n then 1 else 0 end)+(case when V44=W44 and N44=n then 1 else 0 end)+(case when V45=W45 and N45=n then 1 else 0 end)+(case when V46=W46 and N46=n then 1 else 0 end)+(case when V47=W47 and N47=n then 1 else 0 end)+(case when V48=W48 and N48=n then 1 else 0 end)+(case when V49=W49 and N49=n then 1 else 0 end)+(case when V50=W50 and N50=n then 1 else 0 end)+(case when V51=W51 and N51=n then 1 else 0 end)+(case when V52=W52 and N52=n then 1 else 0 end)+(case when V53=W53 and N53=n then 1 else 0 end)+(case when V54=W54 and N54=n then 1 else 0 end)+(case when V55=W55 and N55=n then 1 else 0 end)+(case when V56=W56 and N56=n then 1 else 0 end)+(case when V57=W57 and N57=n then 1 else 0 end)+(case when V58=W58 and N58=n then 1 else 0 end)+(case when V59=W59 and N59=n then 1 else 0 end)+(case when V60=W60 and N60=n then 1 else 0 end)+(case when V61=W61 and N61=n then 1 else 0 end)+(case when V62=W62 and N62=n then 1 else 0 end)+(case when V63=W63 and N63=n then 1 else 0 end)+(case when V64=W64 and N64=n then 1 else 0 end)+(case when V65=W65 and N65=n then 1 else 0 end)+(case when V66=W66 and N66=n then 1 else 0 end)+(case when V67=W67 and N67=n then 1 else 0 end)+(case when V68=W68 and N68=n then 1 else 0 end)+(case when V69=W69 and N69=n then 1 else 0 end)+(case when V70=W70 and N70=n then 1 else 0 end)+(case when V71=W71 and N71=n then 1 else 0 end)+(case when V72=W72 and N72=n then 1 else 0 end)+(case when V73=W73 and N73=n then 1 else 0 end)+(case when V74=W74 and N74=n then 1 else 0 end)+(case when V75=W75 and N75=n then 1 else 0 end)+(case when V76=W76 and N76=n then 1 else 0 end)+(case when V77=W77 and N77=n then 1 else 0 end)+(case when V78=W78 and N78=n then 1 else 0 end)+(case when V79=W79 and N79=n then 1 else 0 end)+(case when V80=W80 and N80=n then 1 else 0 end)+(case when V81=W81 and N81=n then 1 else 0 end)+(case when V82=W82 and N82=n then 1 else 0 end)+(case when V83=W83 and N83=n then 1 else 0 end)+(case when V84=W84 and N84=n then 1 else 0 end)+(case when V85=W85 and N85=n then 1 else 0 end)+(case when V86=W86 and N86=n then 1 else 0 end)+(case when V87=W87 and N87=n then 1 else 0 end)+(case when V88=W88 and N88=n then 1 else 0 end)+(case when V89=W89 and N89=n then 1 else 0 end)+(case when V90=W90 and N90=n then 1 else 0 end)+(case when V91=W91 and N91=n then 1 else 0 end)+(case when V92=W92 and N92=n then 1 else 0 end)+(case when V93=W93 and N93=n then 1 else 0 end)+(case when V94=W94 and N94=n then 1 else 0 end)+(case when V95=W95 and N95=n then 1 else 0 end)+(case when V96=W96 and N96=n then 1 else 0 end)+(case when V97=W97 and N97=n then 1 else 0 end)+(case when V98=W98 and N98=n then 1 else 0 end)+(case when V99=W99 and N99=n then 1 else 0 end)+(case when V100=W100 and N100=n then 1 else 0 end)+(case when V101=W101 and N101=n then 1 else 0 end)+(case when V102=W102 and N102=n then 1 else 0 end)+(case when V103=W103 and N103=n then 1 else 0 end)+(case when V104=W104 and N104=n then 1 else 0 end)+(case when V105=W105 and N105=n then 1 else 0 end)+(case when V106=W106 and N106=n then 1 else 0 end)+(case when V107=W107 and N107=n then 1 else 0 end)+(case when V108=W108 and N108=n then 1 else 0 end)+(case when V109=W109 and N109=n then 1 else 0 end)+(case when V110=W110 and N110=n then 1 else 0 end)+(case when V111=W111 and N111=n then 1 else 0 end)+(case when V112=W112 and N112=n then 1 else 0 end)+(case when V113=W113 and N113=n then 1 else 0 end)+(case when V114=W114 and N114=n then 1 else 0 end)+(case when V115=W115 and N115=n then 1 else 0 end)+(case when V116=W116 and N116=n then 1 else 0 end)+(case when V117=W117 and N117=n then 1 else 0 end)+(case when V118=W118 and N118=n then 1 else 0 end)+(case when V119=W119 and N119=n then 1 else 0 end)+(case when V120=W120 and N120=n then 1 else 0 end)+(case when V121=W121 and N121=n then 1 else 0 end)+(case when V122=W122 and N122=n then 1 else 0 end)+(case when V123=W123 and N123=n then 1 else 0 end)+(case when V124=W124 and N124=n then 1 else 0 end)+(case when V125=W125 and N125=n then 1 else 0 end)+(case when V126=W126 and N126=n then 1 else 0 end)+(case when V127=W127 and N127=n then 1 else 0 end)+(case when V128=W128 and N128=n then 1 else 0 end)+(case when V129=W129 and N129=n then 1 else 0 end)+(case when V130=W130 and N130=n then 1 else 0 end)+(case when V131=W131 and N131=n then 1 else 0 end)+(case when V132=W132 and N132=n then 1 else 0 end)+(case when V133=W133 and N133=n then 1 else 0 end)+(case when V134=W134 and N134=n then 1 else 0 end)+(case when V135=W135 and N135=n then 1 else 0 end)+(case when V136=W136 and N136=n then 1 else 0 end)+(case when V137=W137 and N137=n then 1 else 0 end)+(case when V138=W138 and N138=n then 1 else 0 end)+(case when V139=W139 and N139=n then 1 else 0 end)+(case when V140=W140 and N140=n then 1 else 0 end)+(case when V141=W141 and N141=n then 1 else 0 end)+(case when V142=W142 and N142=n then 1 else 0 end)+(case when V143=W143 and N143=n then 1 else 0 end)+(case when V144=W144 and N144=n then 1 else 0 end)+(case when V145=W145 and N145=n then 1 else 0 end)+(case when V146=W146 and N146=n then 1 else 0 end)+(case when V147=W147 and N147=n then 1 else 0 end)+(case when V148=W148 and N148=n then 1 else 0 end)+(case when V149=W149 and N149=n then 1 else 0 end)+(case when V150=W150 and N150=n then 1 else 0 end)+(case when V151=W151 and N151=n then 1 else 0 end)+(case when V152=W152 and N152=n then 1 else 0 end)+(case when V153=W153 and N153=n then 1 else 0 end)+(case when V154=W154 and N154=n then 1 else 0 end)+(case when V155=W155 and N155=n then 1 else 0 end)+(case when V156=W156 and N156=n then 1 else 0 end)+(case when V157=W157 and N157=n then 1 else 0 end)+(case when V158=W158 and N158=n then 1 else 0 end)+(case when V159=W159 and N159=n then 1 else 0 end)+(case when V160=W160 and N160=n then 1 else 0 end)+(case when V161=W161 and N161=n then 1 else 0 end)+(case when V162=W162 and N162=n then 1 else 0 end)+(case when V163=W163 and N163=n then 1 else 0 end)+(case when V164=W164 and N164=n then 1 else 0 end)+(case when V165=W165 and N165=n then 1 else 0 end)+(case when V166=W166 and N166=n then 1 else 0 end)+(case when V167=W167 and N167=n then 1 else 0 end)+(case when V168=W168 and N168=n then 1 else 0 end)+(case when V169=W169 and N169=n then 1 else 0 end)+(case when V170=W170 and N170=n then 1 else 0 end)+(case when V171=W171 and N171=n then 1 else 0 end)+(case when V172=W172 and N172=n then 1 else 0 end)+(case when V173=W173 and N173=n then 1 else 0 end)+(case when V174=W174 and N174=n then 1 else 0 end)+(case when V175=W175 and N175=n then 1 else 0 end)+(case when V176=W176 and N176=n then 1 else 0 end)+(case when V177=W177 and N177=n then 1 else 0 end)+(case when V178=W178 and N178=n then 1 else 0 end)+(case when V179=W179 and N179=n then 1 else 0 end)+(case when V180=W180 and N180=n then 1 else 0 end)+(case when V181=W181 and N181=n then 1 else 0 end)+(case when V182=W182 and N182=n then 1 else 0 end)+(case when V183=W183 and N183=n then 1 else 0 end)+(case when V184=W184 and N184=n then 1 else 0 end)+(case when V185=W185 and N185=n then 1 else 0 end)+(case when V186=W186 and N186=n then 1 else 0 end)+(case when V187=W187 and N187=n then 1 else 0 end)+(case when V188=W188 and N188=n then 1 else 0 end)+(case when V189=W189 and N189=n then 1 else 0 end)+(case when V190=W190 and N190=n then 1 else 0 end)+(case when V191=W191 and N191=n then 1 else 0 end)+(case when V192=W192 and N192=n then 1 else 0 end)+(case when V193=W193 and N193=n then 1 else 0 end)+(case when V194=W194 and N194=n then 1 else 0 end)+(case when V195=W195 and N195=n then 1 else 0 end)+(case when V196=W196 and N196=n then 1 else 0 end)+(case when V197=W197 and N197=n then 1 else 0 end)+(case when V198=W198 and N198=n then 1 else 0 end)+(case when V199=W199 and N199=n then 1 else 0 end)+(case when V200=W200 and N200=n then 1 else 0 end)+(case when V201=W201 and N201=n then 1 else 0 end)+(case when V202=W202 and N202=n then 1 else 0 end)+(case when V203=W203 and N203=n then 1 else 0 end)+(case when V204=W204 and N204=n then 1 else 0 end)+(case when V205=W205 and N205=n then 1 else 0 end)+(case when V206=W206 and N206=n then 1 else 0 end)+(case when V207=W207 and N207=n then 1 else 0 end)+(case when V208=W208 and N208=n then 1 else 0 end)+(case when V209=W209 and N209=n then 1 else 0 end)+(case when V210=W210 and N210=n then 1 else 0 end)+(case when V211=W211 and N211=n then 1 else 0 end)+(case when V212=W212 and N212=n then 1 else 0 end)+(case when V213=W213 and N213=n then 1 else 0 end)+(case when V214=W214 and N214=n then 1 else 0 end)+(case when V215=W215 and N215=n then 1 else 0 end)+(case when V216=W216 and N216=n then 1 else 0 end)+(case when V217=W217 and N217=n then 1 else 0 end)+(case when V218=W218 and N218=n then 1 else 0 end)+(case when V219=W219 and N219=n then 1 else 0 end)+(case when V220=W220 and N220=n then 1 else 0 end)+(case when V221=W221 and N221=n then 1 else 0 end)+(case when V222=W222 and N222=n then 1 else 0 end)+(case when V223=W223 and N223=n then 1 else 0 end)+(case when V224=W224 and N224=n then 1 else 0 end)+(case when V225=W225 and N225=n then 1 else 0 end)+(case when V226=W226 and N226=n then 1 else 0 end)+(case when V227=W227 and N227=n then 1 else 0 end)+(case when V228=W228 and N228=n then 1 else 0 end)+(case when V229=W229 and N229=n then 1 else 0 end)+(case when V230=W230 and N230=n then 1 else 0 end)+(case when V231=W231 and N231=n then 1 else 0 end)+(case when V232=W232 and N232=n then 1 else 0 end)+(case when V233=W233 and N233=n then 1 else 0 end)+(case when V234=W234 and N234=n then 1 else 0 end)+(case when V235=W235 and N235=n then 1 else 0 end)+(case when V236=W236 and N236=n then 1 else 0 end)+(case when V237=W237 and N237=n then 1 else 0 end)+(case when V238=W238 and N238=n then 1 else 0 end)+(case when V239=W239 and N239=n then 1 else 0 end)+(case when V240=W240 and N240=n then 1 else 0 end)+(case when V241=W241 and N241=n then 1 else 0 end)+(case when V242=W242 and N242=n then 1 else 0 end)+(case when V243=W243 and N243=n then 1 else 0 end)+(case when V244=W244 and N244=n then 1 else 0 end)+(case when V245=W245 and N245=n then 1 else 0 end)+(case when V246=W246 and N246=n then 1 else 0 end)+(case when V247=W247 and N247=n then 1 else 0 end)+(case when V248=W248 and N248=n then 1 else 0 end)+(case when V249=W249 and N249=n then 1 else 0 end)+(case when V250=W250 and N250=n then 1 else 0 end)+(case when V251=W251 and N251=n then 1 else 0 end)+(case when V252=W252 and N252=n then 1 else 0 end)+(case when V253=W253 and N253=n then 1 else 0 end)+(case when V254=W254 and N254=n then 1 else 0 end)+(case when V255=W255 and N255=n then 1 else 0 end) J15
						from (
							select B,
								min(V0) V0, min(V1) V1, min(V2) V2, min(V3) V3, min(V4) V4, min(V5) V5, min(V6) V6, min(V7) V7, min(V8) V8, min(V9) V9, min(V10) V10, min(V11) V11, min(V12) V12, min(V13) V13, min(V14) V14, min(V15) V15, min(V16) V16, min(V17) V17, min(V18) V18, min(V19) V19, min(V20) V20, min(V21) V21, min(V22) V22, min(V23) V23, min(V24) V24, min(V25) V25, min(V26) V26, min(V27) V27, min(V28) V28, min(V29) V29, min(V30) V30, min(V31) V31, min(V32) V32, min(V33) V33, min(V34) V34, min(V35) V35, min(V36) V36, min(V37) V37, min(V38) V38, min(V39) V39, min(V40) V40, min(V41) V41, min(V42) V42, min(V43) V43, min(V44) V44, min(V45) V45, min(V46) V46, min(V47) V47, min(V48) V48, min(V49) V49, min(V50) V50, min(V51) V51, min(V52) V52, min(V53) V53, min(V54) V54, min(V55) V55, min(V56) V56, min(V57) V57, min(V58) V58, min(V59) V59, min(V60) V60, min(V61) V61, min(V62) V62, min(V63) V63, min(V64) V64, min(V65) V65, min(V66) V66, min(V67) V67, min(V68) V68, min(V69) V69, min(V70) V70, min(V71) V71, min(V72) V72, min(V73) V73, min(V74) V74, min(V75) V75, min(V76) V76, min(V77) V77, min(V78) V78, min(V79) V79, min(V80) V80, min(V81) V81, min(V82) V82, min(V83) V83, min(V84) V84, min(V85) V85, min(V86) V86, min(V87) V87, min(V88) V88, min(V89) V89, min(V90) V90, min(V91) V91, min(V92) V92, min(V93) V93, min(V94) V94, min(V95) V95, min(V96) V96, min(V97) V97, min(V98) V98, min(V99) V99, min(V100) V100, min(V101) V101, min(V102) V102, min(V103) V103, min(V104) V104, min(V105) V105, min(V106) V106, min(V107) V107, min(V108) V108, min(V109) V109, min(V110) V110, min(V111) V111, min(V112) V112, min(V113) V113, min(V114) V114, min(V115) V115, min(V116) V116, min(V117) V117, min(V118) V118, min(V119) V119, min(V120) V120, min(V121) V121, min(V122) V122, min(V123) V123, min(V124) V124, min(V125) V125, min(V126) V126, min(V127) V127, min(V128) V128, min(V129) V129, min(V130) V130, min(V131) V131, min(V132) V132, min(V133) V133, min(V134) V134, min(V135) V135, min(V136) V136, min(V137) V137, min(V138) V138, min(V139) V139, min(V140) V140, min(V141) V141, min(V142) V142, min(V143) V143, min(V144) V144, min(V145) V145, min(V146) V146, min(V147) V147, min(V148) V148, min(V149) V149, min(V150) V150, min(V151) V151, min(V152) V152, min(V153) V153, min(V154) V154, min(V155) V155, min(V156) V156, min(V157) V157, min(V158) V158, min(V159) V159, min(V160) V160, min(V161) V161, min(V162) V162, min(V163) V163, min(V164) V164, min(V165) V165, min(V166) V166, min(V167) V167, min(V168) V168, min(V169) V169, min(V170) V170, min(V171) V171, min(V172) V172, min(V173) V173, min(V174) V174, min(V175) V175, min(V176) V176, min(V177) V177, min(V178) V178, min(V179) V179, min(V180) V180, min(V181) V181, min(V182) V182, min(V183) V183, min(V184) V184, min(V185) V185, min(V186) V186, min(V187) V187, min(V188) V188, min(V189) V189, min(V190) V190, min(V191) V191, min(V192) V192, min(V193) V193, min(V194) V194, min(V195) V195, min(V196) V196, min(V197) V197, min(V198) V198, min(V199) V199, min(V200) V200, min(V201) V201, min(V202) V202, min(V203) V203, min(V204) V204, min(V205) V205, min(V206) V206, min(V207) V207, min(V208) V208, min(V209) V209, min(V210) V210, min(V211) V211, min(V212) V212, min(V213) V213, min(V214) V214, min(V215) V215, min(V216) V216, min(V217) V217, min(V218) V218, min(V219) V219, min(V220) V220, min(V221) V221, min(V222) V222, min(V223) V223, min(V224) V224, min(V225) V225, min(V226) V226, min(V227) V227, min(V228) V228, min(V229) V229, min(V230) V230, min(V231) V231, min(V232) V232, min(V233) V233, min(V234) V234, min(V235) V235, min(V236) V236, min(V237) V237, min(V238) V238, min(V239) V239, min(V240) V240, min(V241) V241, min(V242) V242, min(V243) V243, min(V244) V244, min(V245) V245, min(V246) V246, min(V247) V247, min(V248) V248, min(V249) V249, min(V250) V250, min(V251) V251, min(V252) V252, min(V253) V253, min(V254) V254, min(V255) V255,
								max(V0) W0, max(V1) W1, max(V2) W2, max(V3) W3, max(V4) W4, max(V5) W5, max(V6) W6, max(V7) W7, max(V8) W8, max(V9) W9, max(V10) W10, max(V11) W11, max(V12) W12, max(V13) W13, max(V14) W14, max(V15) W15, max(V16) W16, max(V17) W17, max(V18) W18, max(V19) W19, max(V20) W20, max(V21) W21, max(V22) W22, max(V23) W23, max(V24) W24, max(V25) W25, max(V26) W26, max(V27) W27, max(V28) W28, max(V29) W29, max(V30) W30, max(V31) W31, max(V32) W32, max(V33) W33, max(V34) W34, max(V35) W35, max(V36) W36, max(V37) W37, max(V38) W38, max(V39) W39, max(V40) W40, max(V41) W41, max(V42) W42, max(V43) W43, max(V44) W44, max(V45) W45, max(V46) W46, max(V47) W47, max(V48) W48, max(V49) W49, max(V50) W50, max(V51) W51, max(V52) W52, max(V53) W53, max(V54) W54, max(V55) W55, max(V56) W56, max(V57) W57, max(V58) W58, max(V59) W59, max(V60) W60, max(V61) W61, max(V62) W62, max(V63) W63, max(V64) W64, max(V65) W65, max(V66) W66, max(V67) W67, max(V68) W68, max(V69) W69, max(V70) W70, max(V71) W71, max(V72) W72, max(V73) W73, max(V74) W74, max(V75) W75, max(V76) W76, max(V77) W77, max(V78) W78, max(V79) W79, max(V80) W80, max(V81) W81, max(V82) W82, max(V83) W83, max(V84) W84, max(V85) W85, max(V86) W86, max(V87) W87, max(V88) W88, max(V89) W89, max(V90) W90, max(V91) W91, max(V92) W92, max(V93) W93, max(V94) W94, max(V95) W95, max(V96) W96, max(V97) W97, max(V98) W98, max(V99) W99, max(V100) W100, max(V101) W101, max(V102) W102, max(V103) W103, max(V104) W104, max(V105) W105, max(V106) W106, max(V107) W107, max(V108) W108, max(V109) W109, max(V110) W110, max(V111) W111, max(V112) W112, max(V113) W113, max(V114) W114, max(V115) W115, max(V116) W116, max(V117) W117, max(V118) W118, max(V119) W119, max(V120) W120, max(V121) W121, max(V122) W122, max(V123) W123, max(V124) W124, max(V125) W125, max(V126) W126, max(V127) W127, max(V128) W128, max(V129) W129, max(V130) W130, max(V131) W131, max(V132) W132, max(V133) W133, max(V134) W134, max(V135) W135, max(V136) W136, max(V137) W137, max(V138) W138, max(V139) W139, max(V140) W140, max(V141) W141, max(V142) W142, max(V143) W143, max(V144) W144, max(V145) W145, max(V146) W146, max(V147) W147, max(V148) W148, max(V149) W149, max(V150) W150, max(V151) W151, max(V152) W152, max(V153) W153, max(V154) W154, max(V155) W155, max(V156) W156, max(V157) W157, max(V158) W158, max(V159) W159, max(V160) W160, max(V161) W161, max(V162) W162, max(V163) W163, max(V164) W164, max(V165) W165, max(V166) W166, max(V167) W167, max(V168) W168, max(V169) W169, max(V170) W170, max(V171) W171, max(V172) W172, max(V173) W173, max(V174) W174, max(V175) W175, max(V176) W176, max(V177) W177, max(V178) W178, max(V179) W179, max(V180) W180, max(V181) W181, max(V182) W182, max(V183) W183, max(V184) W184, max(V185) W185, max(V186) W186, max(V187) W187, max(V188) W188, max(V189) W189, max(V190) W190, max(V191) W191, max(V192) W192, max(V193) W193, max(V194) W194, max(V195) W195, max(V196) W196, max(V197) W197, max(V198) W198, max(V199) W199, max(V200) W200, max(V201) W201, max(V202) W202, max(V203) W203, max(V204) W204, max(V205) W205, max(V206) W206, max(V207) W207, max(V208) W208, max(V209) W209, max(V210) W210, max(V211) W211, max(V212) W212, max(V213) W213, max(V214) W214, max(V215) W215, max(V216) W216, max(V217) W217, max(V218) W218, max(V219) W219, max(V220) W220, max(V221) W221, max(V222) W222, max(V223) W223, max(V224) W224, max(V225) W225, max(V226) W226, max(V227) W227, max(V228) W228, max(V229) W229, max(V230) W230, max(V231) W231, max(V232) W232, max(V233) W233, max(V234) W234, max(V235) W235, max(V236) W236, max(V237) W237, max(V238) W238, max(V239) W239, max(V240) W240, max(V241) W241, max(V242) W242, max(V243) W243, max(V244) W244, max(V245) W245, max(V246) W246, max(V247) W247, max(V248) W248, max(V249) W249, max(V250) W250, max(V251) W251, max(V252) W252, max(V253) W253, max(V254) W254, max(V255) W255,
								count(V0) N0, count(V1) N1, count(V2) N2, count(V3) N3, count(V4) N4, count(V5) N5, count(V6) N6, count(V7) N7, count(V8) N8, count(V9) N9, count(V10) N10, count(V11) N11, count(V12) N12, count(V13) N13, count(V14) N14, count(V15) N15, count(V16) N16, count(V17) N17, count(V18) N18, count(V19) N19, count(V20) N20, count(V21) N21, count(V22) N22, count(V23) N23, count(V24) N24, count(V25) N25, count(V26) N26, count(V27) N27, count(V28) N28, count(V29) N29, count(V30) N30, count(V31) N31, count(V32) N32, count(V33) N33, count(V34) N34, count(V35) N35, count(V36) N36, count(V37) N37, count(V38) N38, count(V39) N39, count(V40) N40, count(V41) N41, count(V42) N42, count(V43) N43, count(V44) N44, count(V45) N45, count(V46) N46, count(V47) N47, count(V48) N48, count(V49) N49, count(V50) N50, count(V51) N51, count(V52) N52, count(V53) N53, count(V54) N54, count(V55) N55, count(V56) N56, count(V57) N57, count(V58) N58, count(V59) N59, count(V60) N60, count(V61) N61, count(V62) N62, count(V63) N63, count(V64) N64, count(V65) N65, count(V66) N66, count(V67) N67, count(V68) N68, count(V69) N69, count(V70) N70, count(V71) N71, count(V72) N72, count(V73) N73, count(V74) N74, count(V75) N75, count(V76) N76, count(V77) N77, count(V78) N78, count(V79) N79, count(V80) N80, count(V81) N81, count(V82) N82, count(V83) N83, count(V84) N84, count(V85) N85, count(V86) N86, count(V87) N87, count(V88) N88, count(V89) N89, count(V90) N90, count(V91) N91, count(V92) N92, count(V93) N93, count(V94) N94, count(V95) N95, count(V96) N96, count(V97) N97, count(V98) N98, count(V99) N99, count(V100) N100, count(V101) N101, count(V102) N102, count(V103) N103, count(V104) N104, count(V105) N105, count(V106) N106, count(V107) N107, count(V108) N108, count(V109) N109, count(V110) N110, count(V111) N111, count(V112) N112, count(V113) N113, count(V114) N114, count(V115) N115, count(V116) N116, count(V117) N117, count(V118) N118, count(V119) N119, count(V120) N120, count(V121) N121, count(V122) N122, count(V123) N123, count(V124) N124, count(V125) N125, count(V126) N126, count(V127) N127, count(V128) N128, count(V129) N129, count(V130) N130, count(V131) N131, count(V132) N132, count(V133) N133, count(V134) N134, count(V135) N135, count(V136) N136, count(V137) N137, count(V138) N138, count(V139) N139, count(V140) N140, count(V141) N141, count(V142) N142, count(V143) N143, count(V144) N144, count(V145) N145, count(V146) N146, count(V147) N147, count(V148) N148, count(V149) N149, count(V150) N150, count(V151) N151, count(V152) N152, count(V153) N153, count(V154) N154, count(V155) N155, count(V156) N156, count(V157) N157, count(V158) N158, count(V159) N159, count(V160) N160, count(V161) N161, count(V162) N162, count(V163) N163, count(V164) N164, count(V165) N165, count(V166) N166, count(V167) N167, count(V168) N168, count(V169) N169, count(V170) N170, count(V171) N171, count(V172) N172, count(V173) N173, count(V174) N174, count(V175) N175, count(V176) N176, count(V177) N177, count(V178) N178, count(V179) N179, count(V180) N180, count(V181) N181, count(V182) N182, count(V183) N183, count(V184) N184, count(V185) N185, count(V186) N186, count(V187) N187, count(V188) N188, count(V189) N189, count(V190) N190, count(V191) N191, count(V192) N192, count(V193) N193, count(V194) N194, count(V195) N195, count(V196) N196, count(V197) N197, count(V198) N198, count(V199) N199, count(V200) N200, count(V201) N201, count(V202) N202, count(V203) N203, count(V204) N204, count(V205) N205, count(V206) N206, count(V207) N207, count(V208) N208, count(V209) N209, count(V210) N210, count(V211) N211, count(V212) N212, count(V213) N213, count(V214) N214, count(V215) N215, count(V216) N216, count(V217) N217, count(V218) N218, count(V219) N219, count(V220) N220, count(V221) N221, count(V222) N222, count(V223) N223, count(V224) N224, count(V225) N225, count(V226) N226, count(V227) N227, count(V228) N228, count(V229) N229, count(V230) N230, count(V231) N231, count(V232) N232, count(V233) N233, count(V234) N234, count(V235) N235, count(V236) N236, count(V237) N237, count(V238) N238, count(V239) N239, count(V240) N240, count(V241) N241, count(V242) N242, count(V243) N243, count(V244) N244, count(V245) N245, count(V246) N246, count(V247) N247, count(V248) N248, count(V249) N249, count(V250) N250, count(V251) N251, count(V252) N252, count(V253) N253, count(V254) N254, count(V255) N255
							from (						
								select q.panel_number, s.B,
									min(V0) V0, min(V1) V1, min(V2) V2, min(V3) V3, min(V4) V4, min(V5) V5, min(V6) V6, min(V7) V7, min(V8) V8, min(V9) V9, min(V10) V10, min(V11) V11, min(V12) V12, min(V13) V13, min(V14) V14, min(V15) V15, min(V16) V16, min(V17) V17, min(V18) V18, min(V19) V19, min(V20) V20, min(V21) V21, min(V22) V22, min(V23) V23, min(V24) V24, min(V25) V25, min(V26) V26, min(V27) V27, min(V28) V28, min(V29) V29, min(V30) V30, min(V31) V31, min(V32) V32, min(V33) V33, min(V34) V34, min(V35) V35, min(V36) V36, min(V37) V37, min(V38) V38, min(V39) V39, min(V40) V40, min(V41) V41, min(V42) V42, min(V43) V43, min(V44) V44, min(V45) V45, min(V46) V46, min(V47) V47, min(V48) V48, min(V49) V49, min(V50) V50, min(V51) V51, min(V52) V52, min(V53) V53, min(V54) V54, min(V55) V55, min(V56) V56, min(V57) V57, min(V58) V58, min(V59) V59, min(V60) V60, min(V61) V61, min(V62) V62, min(V63) V63, min(V64) V64, min(V65) V65, min(V66) V66, min(V67) V67, min(V68) V68, min(V69) V69, min(V70) V70, min(V71) V71, min(V72) V72, min(V73) V73, min(V74) V74, min(V75) V75, min(V76) V76, min(V77) V77, min(V78) V78, min(V79) V79, min(V80) V80, min(V81) V81, min(V82) V82, min(V83) V83, min(V84) V84, min(V85) V85, min(V86) V86, min(V87) V87, min(V88) V88, min(V89) V89, min(V90) V90, min(V91) V91, min(V92) V92, min(V93) V93, min(V94) V94, min(V95) V95, min(V96) V96, min(V97) V97, min(V98) V98, min(V99) V99, min(V100) V100, min(V101) V101, min(V102) V102, min(V103) V103, min(V104) V104, min(V105) V105, min(V106) V106, min(V107) V107, min(V108) V108, min(V109) V109, min(V110) V110, min(V111) V111, min(V112) V112, min(V113) V113, min(V114) V114, min(V115) V115, min(V116) V116, min(V117) V117, min(V118) V118, min(V119) V119, min(V120) V120, min(V121) V121, min(V122) V122, min(V123) V123, min(V124) V124, min(V125) V125, min(V126) V126, min(V127) V127, min(V128) V128, min(V129) V129, min(V130) V130, min(V131) V131, min(V132) V132, min(V133) V133, min(V134) V134, min(V135) V135, min(V136) V136, min(V137) V137, min(V138) V138, min(V139) V139, min(V140) V140, min(V141) V141, min(V142) V142, min(V143) V143, min(V144) V144, min(V145) V145, min(V146) V146, min(V147) V147, min(V148) V148, min(V149) V149, min(V150) V150, min(V151) V151, min(V152) V152, min(V153) V153, min(V154) V154, min(V155) V155, min(V156) V156, min(V157) V157, min(V158) V158, min(V159) V159, min(V160) V160, min(V161) V161, min(V162) V162, min(V163) V163, min(V164) V164, min(V165) V165, min(V166) V166, min(V167) V167, min(V168) V168, min(V169) V169, min(V170) V170, min(V171) V171, min(V172) V172, min(V173) V173, min(V174) V174, min(V175) V175, min(V176) V176, min(V177) V177, min(V178) V178, min(V179) V179, min(V180) V180, min(V181) V181, min(V182) V182, min(V183) V183, min(V184) V184, min(V185) V185, min(V186) V186, min(V187) V187, min(V188) V188, min(V189) V189, min(V190) V190, min(V191) V191, min(V192) V192, min(V193) V193, min(V194) V194, min(V195) V195, min(V196) V196, min(V197) V197, min(V198) V198, min(V199) V199, min(V200) V200, min(V201) V201, min(V202) V202, min(V203) V203, min(V204) V204, min(V205) V205, min(V206) V206, min(V207) V207, min(V208) V208, min(V209) V209, min(V210) V210, min(V211) V211, min(V212) V212, min(V213) V213, min(V214) V214, min(V215) V215, min(V216) V216, min(V217) V217, min(V218) V218, min(V219) V219, min(V220) V220, min(V221) V221, min(V222) V222, min(V223) V223, min(V224) V224, min(V225) V225, min(V226) V226, min(V227) V227, min(V228) V228, min(V229) V229, min(V230) V230, min(V231) V231, min(V232) V232, min(V233) V233, min(V234) V234, min(V235) V235, min(V236) V236, min(V237) V237, min(V238) V238, min(V239) V239, min(V240) V240, min(V241) V241, min(V242) V242, min(V243) V243, min(V244) V244, min(V245) V245, min(V246) V246, min(V247) V247, min(V248) V248, min(V249) V249, min(V250) V250, min(V251) V251, min(V252) V252, min(V253) V253, min(V254) V254, min(V255) V255
								from #items q inner join CRC.CQ2_SKETCH_PATH15x256 s
									on q.concept_path_id = s.concept_path_id
								group by q.panel_number, s.B				
							) t
							group by B
						) t cross join (select count(distinct panel_number) n from #items) panel_count
					) t
				) t
			-- Set NULLs to zero
			select @SketchPanelE = isnull(@SketchPanelE,0), @SketchPanelN = isnull(@SketchPanelN,0), @SketchPanelQ = isnull(@SketchPanelQ,0)
			-- Store the results
			INSERT INTO #GlobalQueryCounts (query_master_id, num_patients, num_encounters, num_instances, num_facts, sketch_e, sketch_n, sketch_q, sketch_m)
				SELECT @QueryMasterID, @SketchPanelE, null, null, null, @SketchPanelE, @SketchPanelN, @SketchPanelQ, 32768
			RETURN;
		END
	END

	------------------------------------------------------------------------------
	-- Get a 8x256 sketch size estimate for each panel and the total query
	------------------------------------------------------------------------------

	IF (@UseCQ2SketchTables = 1)
	BEGIN
		-- Get the sketch estimate for each panel
		select panel_number, 0 B, HIVE.fnSketchEstimate(sV15, N15, N15, 256, 1) SketchPanelE, N15 SketchPanelN,
				V0, V1, V2, V3, V4, V5, V6, V7, V8, V9, V10, V11, V12, V13, V14, V15, V16, V17, V18, V19, V20, V21, V22, V23, V24, V25, V26, V27, V28, V29, V30, V31, V32, V33, V34, V35, V36, V37, V38, V39, V40, V41, V42, V43, V44, V45, V46, V47, V48, V49, V50, V51, V52, V53, V54, V55, V56, V57, V58, V59, V60, V61, V62, V63, V64, V65, V66, V67, V68, V69, V70, V71, V72, V73, V74, V75, V76, V77, V78, V79, V80, V81, V82, V83, V84, V85, V86, V87, V88, V89, V90, V91, V92, V93, V94, V95, V96, V97, V98, V99, V100, V101, V102, V103, V104, V105, V106, V107, V108, V109, V110, V111, V112, V113, V114, V115, V116, V117, V118, V119, V120, V121, V122, V123, V124, V125, V126, V127, V128, V129, V130, V131, V132, V133, V134, V135, V136, V137, V138, V139, V140, V141, V142, V143, V144, V145, V146, V147, V148, V149, V150, V151, V152, V153, V154, V155, V156, V157, V158, V159, V160, V161, V162, V163, V164, V165, V166, V167, V168, V169, V170, V171, V172, V173, V174, V175, V176, V177, V178, V179, V180, V181, V182, V183, V184, V185, V186, V187, V188, V189, V190, V191, V192, V193, V194, V195, V196, V197, V198, V199, V200, V201, V202, V203, V204, V205, V206, V207, V208, V209, V210, V211, V212, V213, V214, V215, V216, V217, V218, V219, V220, V221, V222, V223, V224, V225, V226, V227, V228, V229, V230, V231, V232, V233, V234, V235, V236, V237, V238, V239, V240, V241, V242, V243, V244, V245, V246, V247, V248, V249, V250, V251, V252, V253, V254, V255
			into #PanelSketch
			from (
				select *,
					cast(0 as float)+isnull(V0,0)+isnull(V1,0)+isnull(V2,0)+isnull(V3,0)+isnull(V4,0)+isnull(V5,0)+isnull(V6,0)+isnull(V7,0)+isnull(V8,0)+isnull(V9,0)+isnull(V10,0)+isnull(V11,0)+isnull(V12,0)+isnull(V13,0)+isnull(V14,0)+isnull(V15,0)+isnull(V16,0)+isnull(V17,0)+isnull(V18,0)+isnull(V19,0)+isnull(V20,0)+isnull(V21,0)+isnull(V22,0)+isnull(V23,0)+isnull(V24,0)+isnull(V25,0)+isnull(V26,0)+isnull(V27,0)+isnull(V28,0)+isnull(V29,0)+isnull(V30,0)+isnull(V31,0)+isnull(V32,0)+isnull(V33,0)+isnull(V34,0)+isnull(V35,0)+isnull(V36,0)+isnull(V37,0)+isnull(V38,0)+isnull(V39,0)+isnull(V40,0)+isnull(V41,0)+isnull(V42,0)+isnull(V43,0)+isnull(V44,0)+isnull(V45,0)+isnull(V46,0)+isnull(V47,0)+isnull(V48,0)+isnull(V49,0)+isnull(V50,0)+isnull(V51,0)+isnull(V52,0)+isnull(V53,0)+isnull(V54,0)+isnull(V55,0)+isnull(V56,0)+isnull(V57,0)+isnull(V58,0)+isnull(V59,0)+isnull(V60,0)+isnull(V61,0)+isnull(V62,0)+isnull(V63,0)+isnull(V64,0)+isnull(V65,0)+isnull(V66,0)+isnull(V67,0)+isnull(V68,0)+isnull(V69,0)+isnull(V70,0)+isnull(V71,0)+isnull(V72,0)+isnull(V73,0)+isnull(V74,0)+isnull(V75,0)+isnull(V76,0)+isnull(V77,0)+isnull(V78,0)+isnull(V79,0)+isnull(V80,0)+isnull(V81,0)+isnull(V82,0)+isnull(V83,0)+isnull(V84,0)+isnull(V85,0)+isnull(V86,0)+isnull(V87,0)+isnull(V88,0)+isnull(V89,0)+isnull(V90,0)+isnull(V91,0)+isnull(V92,0)+isnull(V93,0)+isnull(V94,0)+isnull(V95,0)+isnull(V96,0)+isnull(V97,0)+isnull(V98,0)+isnull(V99,0)+isnull(V100,0)+isnull(V101,0)+isnull(V102,0)+isnull(V103,0)+isnull(V104,0)+isnull(V105,0)+isnull(V106,0)+isnull(V107,0)+isnull(V108,0)+isnull(V109,0)+isnull(V110,0)+isnull(V111,0)+isnull(V112,0)+isnull(V113,0)+isnull(V114,0)+isnull(V115,0)+isnull(V116,0)+isnull(V117,0)+isnull(V118,0)+isnull(V119,0)+isnull(V120,0)+isnull(V121,0)+isnull(V122,0)+isnull(V123,0)+isnull(V124,0)+isnull(V125,0)+isnull(V126,0)+isnull(V127,0)+isnull(V128,0)+isnull(V129,0)+isnull(V130,0)+isnull(V131,0)+isnull(V132,0)+isnull(V133,0)+isnull(V134,0)+isnull(V135,0)+isnull(V136,0)+isnull(V137,0)+isnull(V138,0)+isnull(V139,0)+isnull(V140,0)+isnull(V141,0)+isnull(V142,0)+isnull(V143,0)+isnull(V144,0)+isnull(V145,0)+isnull(V146,0)+isnull(V147,0)+isnull(V148,0)+isnull(V149,0)+isnull(V150,0)+isnull(V151,0)+isnull(V152,0)+isnull(V153,0)+isnull(V154,0)+isnull(V155,0)+isnull(V156,0)+isnull(V157,0)+isnull(V158,0)+isnull(V159,0)+isnull(V160,0)+isnull(V161,0)+isnull(V162,0)+isnull(V163,0)+isnull(V164,0)+isnull(V165,0)+isnull(V166,0)+isnull(V167,0)+isnull(V168,0)+isnull(V169,0)+isnull(V170,0)+isnull(V171,0)+isnull(V172,0)+isnull(V173,0)+isnull(V174,0)+isnull(V175,0)+isnull(V176,0)+isnull(V177,0)+isnull(V178,0)+isnull(V179,0)+isnull(V180,0)+isnull(V181,0)+isnull(V182,0)+isnull(V183,0)+isnull(V184,0)+isnull(V185,0)+isnull(V186,0)+isnull(V187,0)+isnull(V188,0)+isnull(V189,0)+isnull(V190,0)+isnull(V191,0)+isnull(V192,0)+isnull(V193,0)+isnull(V194,0)+isnull(V195,0)+isnull(V196,0)+isnull(V197,0)+isnull(V198,0)+isnull(V199,0)+isnull(V200,0)+isnull(V201,0)+isnull(V202,0)+isnull(V203,0)+isnull(V204,0)+isnull(V205,0)+isnull(V206,0)+isnull(V207,0)+isnull(V208,0)+isnull(V209,0)+isnull(V210,0)+isnull(V211,0)+isnull(V212,0)+isnull(V213,0)+isnull(V214,0)+isnull(V215,0)+isnull(V216,0)+isnull(V217,0)+isnull(V218,0)+isnull(V219,0)+isnull(V220,0)+isnull(V221,0)+isnull(V222,0)+isnull(V223,0)+isnull(V224,0)+isnull(V225,0)+isnull(V226,0)+isnull(V227,0)+isnull(V228,0)+isnull(V229,0)+isnull(V230,0)+isnull(V231,0)+isnull(V232,0)+isnull(V233,0)+isnull(V234,0)+isnull(V235,0)+isnull(V236,0)+isnull(V237,0)+isnull(V238,0)+isnull(V239,0)+isnull(V240,0)+isnull(V241,0)+isnull(V242,0)+isnull(V243,0)+isnull(V244,0)+isnull(V245,0)+isnull(V246,0)+isnull(V247,0)+isnull(V248,0)+isnull(V249,0)+isnull(V250,0)+isnull(V251,0)+isnull(V252,0)+isnull(V253,0)+isnull(V254,0)+isnull(V255,0) sV15,
					(case when V0 is null then 0 else 1 end)+(case when V1 is null then 0 else 1 end)+(case when V2 is null then 0 else 1 end)+(case when V3 is null then 0 else 1 end)+(case when V4 is null then 0 else 1 end)+(case when V5 is null then 0 else 1 end)+(case when V6 is null then 0 else 1 end)+(case when V7 is null then 0 else 1 end)+(case when V8 is null then 0 else 1 end)+(case when V9 is null then 0 else 1 end)+(case when V10 is null then 0 else 1 end)+(case when V11 is null then 0 else 1 end)+(case when V12 is null then 0 else 1 end)+(case when V13 is null then 0 else 1 end)+(case when V14 is null then 0 else 1 end)+(case when V15 is null then 0 else 1 end)+(case when V16 is null then 0 else 1 end)+(case when V17 is null then 0 else 1 end)+(case when V18 is null then 0 else 1 end)+(case when V19 is null then 0 else 1 end)+(case when V20 is null then 0 else 1 end)+(case when V21 is null then 0 else 1 end)+(case when V22 is null then 0 else 1 end)+(case when V23 is null then 0 else 1 end)+(case when V24 is null then 0 else 1 end)+(case when V25 is null then 0 else 1 end)+(case when V26 is null then 0 else 1 end)+(case when V27 is null then 0 else 1 end)+(case when V28 is null then 0 else 1 end)+(case when V29 is null then 0 else 1 end)+(case when V30 is null then 0 else 1 end)+(case when V31 is null then 0 else 1 end)+(case when V32 is null then 0 else 1 end)+(case when V33 is null then 0 else 1 end)+(case when V34 is null then 0 else 1 end)+(case when V35 is null then 0 else 1 end)+(case when V36 is null then 0 else 1 end)+(case when V37 is null then 0 else 1 end)+(case when V38 is null then 0 else 1 end)+(case when V39 is null then 0 else 1 end)+(case when V40 is null then 0 else 1 end)+(case when V41 is null then 0 else 1 end)+(case when V42 is null then 0 else 1 end)+(case when V43 is null then 0 else 1 end)+(case when V44 is null then 0 else 1 end)+(case when V45 is null then 0 else 1 end)+(case when V46 is null then 0 else 1 end)+(case when V47 is null then 0 else 1 end)+(case when V48 is null then 0 else 1 end)+(case when V49 is null then 0 else 1 end)+(case when V50 is null then 0 else 1 end)+(case when V51 is null then 0 else 1 end)+(case when V52 is null then 0 else 1 end)+(case when V53 is null then 0 else 1 end)+(case when V54 is null then 0 else 1 end)+(case when V55 is null then 0 else 1 end)+(case when V56 is null then 0 else 1 end)+(case when V57 is null then 0 else 1 end)+(case when V58 is null then 0 else 1 end)+(case when V59 is null then 0 else 1 end)+(case when V60 is null then 0 else 1 end)+(case when V61 is null then 0 else 1 end)+(case when V62 is null then 0 else 1 end)+(case when V63 is null then 0 else 1 end)+(case when V64 is null then 0 else 1 end)+(case when V65 is null then 0 else 1 end)+(case when V66 is null then 0 else 1 end)+(case when V67 is null then 0 else 1 end)+(case when V68 is null then 0 else 1 end)+(case when V69 is null then 0 else 1 end)+(case when V70 is null then 0 else 1 end)+(case when V71 is null then 0 else 1 end)+(case when V72 is null then 0 else 1 end)+(case when V73 is null then 0 else 1 end)+(case when V74 is null then 0 else 1 end)+(case when V75 is null then 0 else 1 end)+(case when V76 is null then 0 else 1 end)+(case when V77 is null then 0 else 1 end)+(case when V78 is null then 0 else 1 end)+(case when V79 is null then 0 else 1 end)+(case when V80 is null then 0 else 1 end)+(case when V81 is null then 0 else 1 end)+(case when V82 is null then 0 else 1 end)+(case when V83 is null then 0 else 1 end)+(case when V84 is null then 0 else 1 end)+(case when V85 is null then 0 else 1 end)+(case when V86 is null then 0 else 1 end)+(case when V87 is null then 0 else 1 end)+(case when V88 is null then 0 else 1 end)+(case when V89 is null then 0 else 1 end)+(case when V90 is null then 0 else 1 end)+(case when V91 is null then 0 else 1 end)+(case when V92 is null then 0 else 1 end)+(case when V93 is null then 0 else 1 end)+(case when V94 is null then 0 else 1 end)+(case when V95 is null then 0 else 1 end)+(case when V96 is null then 0 else 1 end)+(case when V97 is null then 0 else 1 end)+(case when V98 is null then 0 else 1 end)+(case when V99 is null then 0 else 1 end)+(case when V100 is null then 0 else 1 end)+(case when V101 is null then 0 else 1 end)+(case when V102 is null then 0 else 1 end)+(case when V103 is null then 0 else 1 end)+(case when V104 is null then 0 else 1 end)+(case when V105 is null then 0 else 1 end)+(case when V106 is null then 0 else 1 end)+(case when V107 is null then 0 else 1 end)+(case when V108 is null then 0 else 1 end)+(case when V109 is null then 0 else 1 end)+(case when V110 is null then 0 else 1 end)+(case when V111 is null then 0 else 1 end)+(case when V112 is null then 0 else 1 end)+(case when V113 is null then 0 else 1 end)+(case when V114 is null then 0 else 1 end)+(case when V115 is null then 0 else 1 end)+(case when V116 is null then 0 else 1 end)+(case when V117 is null then 0 else 1 end)+(case when V118 is null then 0 else 1 end)+(case when V119 is null then 0 else 1 end)+(case when V120 is null then 0 else 1 end)+(case when V121 is null then 0 else 1 end)+(case when V122 is null then 0 else 1 end)+(case when V123 is null then 0 else 1 end)+(case when V124 is null then 0 else 1 end)+(case when V125 is null then 0 else 1 end)+(case when V126 is null then 0 else 1 end)+(case when V127 is null then 0 else 1 end)+(case when V128 is null then 0 else 1 end)+(case when V129 is null then 0 else 1 end)+(case when V130 is null then 0 else 1 end)+(case when V131 is null then 0 else 1 end)+(case when V132 is null then 0 else 1 end)+(case when V133 is null then 0 else 1 end)+(case when V134 is null then 0 else 1 end)+(case when V135 is null then 0 else 1 end)+(case when V136 is null then 0 else 1 end)+(case when V137 is null then 0 else 1 end)+(case when V138 is null then 0 else 1 end)+(case when V139 is null then 0 else 1 end)+(case when V140 is null then 0 else 1 end)+(case when V141 is null then 0 else 1 end)+(case when V142 is null then 0 else 1 end)+(case when V143 is null then 0 else 1 end)+(case when V144 is null then 0 else 1 end)+(case when V145 is null then 0 else 1 end)+(case when V146 is null then 0 else 1 end)+(case when V147 is null then 0 else 1 end)+(case when V148 is null then 0 else 1 end)+(case when V149 is null then 0 else 1 end)+(case when V150 is null then 0 else 1 end)+(case when V151 is null then 0 else 1 end)+(case when V152 is null then 0 else 1 end)+(case when V153 is null then 0 else 1 end)+(case when V154 is null then 0 else 1 end)+(case when V155 is null then 0 else 1 end)+(case when V156 is null then 0 else 1 end)+(case when V157 is null then 0 else 1 end)+(case when V158 is null then 0 else 1 end)+(case when V159 is null then 0 else 1 end)+(case when V160 is null then 0 else 1 end)+(case when V161 is null then 0 else 1 end)+(case when V162 is null then 0 else 1 end)+(case when V163 is null then 0 else 1 end)+(case when V164 is null then 0 else 1 end)+(case when V165 is null then 0 else 1 end)+(case when V166 is null then 0 else 1 end)+(case when V167 is null then 0 else 1 end)+(case when V168 is null then 0 else 1 end)+(case when V169 is null then 0 else 1 end)+(case when V170 is null then 0 else 1 end)+(case when V171 is null then 0 else 1 end)+(case when V172 is null then 0 else 1 end)+(case when V173 is null then 0 else 1 end)+(case when V174 is null then 0 else 1 end)+(case when V175 is null then 0 else 1 end)+(case when V176 is null then 0 else 1 end)+(case when V177 is null then 0 else 1 end)+(case when V178 is null then 0 else 1 end)+(case when V179 is null then 0 else 1 end)+(case when V180 is null then 0 else 1 end)+(case when V181 is null then 0 else 1 end)+(case when V182 is null then 0 else 1 end)+(case when V183 is null then 0 else 1 end)+(case when V184 is null then 0 else 1 end)+(case when V185 is null then 0 else 1 end)+(case when V186 is null then 0 else 1 end)+(case when V187 is null then 0 else 1 end)+(case when V188 is null then 0 else 1 end)+(case when V189 is null then 0 else 1 end)+(case when V190 is null then 0 else 1 end)+(case when V191 is null then 0 else 1 end)+(case when V192 is null then 0 else 1 end)+(case when V193 is null then 0 else 1 end)+(case when V194 is null then 0 else 1 end)+(case when V195 is null then 0 else 1 end)+(case when V196 is null then 0 else 1 end)+(case when V197 is null then 0 else 1 end)+(case when V198 is null then 0 else 1 end)+(case when V199 is null then 0 else 1 end)+(case when V200 is null then 0 else 1 end)+(case when V201 is null then 0 else 1 end)+(case when V202 is null then 0 else 1 end)+(case when V203 is null then 0 else 1 end)+(case when V204 is null then 0 else 1 end)+(case when V205 is null then 0 else 1 end)+(case when V206 is null then 0 else 1 end)+(case when V207 is null then 0 else 1 end)+(case when V208 is null then 0 else 1 end)+(case when V209 is null then 0 else 1 end)+(case when V210 is null then 0 else 1 end)+(case when V211 is null then 0 else 1 end)+(case when V212 is null then 0 else 1 end)+(case when V213 is null then 0 else 1 end)+(case when V214 is null then 0 else 1 end)+(case when V215 is null then 0 else 1 end)+(case when V216 is null then 0 else 1 end)+(case when V217 is null then 0 else 1 end)+(case when V218 is null then 0 else 1 end)+(case when V219 is null then 0 else 1 end)+(case when V220 is null then 0 else 1 end)+(case when V221 is null then 0 else 1 end)+(case when V222 is null then 0 else 1 end)+(case when V223 is null then 0 else 1 end)+(case when V224 is null then 0 else 1 end)+(case when V225 is null then 0 else 1 end)+(case when V226 is null then 0 else 1 end)+(case when V227 is null then 0 else 1 end)+(case when V228 is null then 0 else 1 end)+(case when V229 is null then 0 else 1 end)+(case when V230 is null then 0 else 1 end)+(case when V231 is null then 0 else 1 end)+(case when V232 is null then 0 else 1 end)+(case when V233 is null then 0 else 1 end)+(case when V234 is null then 0 else 1 end)+(case when V235 is null then 0 else 1 end)+(case when V236 is null then 0 else 1 end)+(case when V237 is null then 0 else 1 end)+(case when V238 is null then 0 else 1 end)+(case when V239 is null then 0 else 1 end)+(case when V240 is null then 0 else 1 end)+(case when V241 is null then 0 else 1 end)+(case when V242 is null then 0 else 1 end)+(case when V243 is null then 0 else 1 end)+(case when V244 is null then 0 else 1 end)+(case when V245 is null then 0 else 1 end)+(case when V246 is null then 0 else 1 end)+(case when V247 is null then 0 else 1 end)+(case when V248 is null then 0 else 1 end)+(case when V249 is null then 0 else 1 end)+(case when V250 is null then 0 else 1 end)+(case when V251 is null then 0 else 1 end)+(case when V252 is null then 0 else 1 end)+(case when V253 is null then 0 else 1 end)+(case when V254 is null then 0 else 1 end)+(case when V255 is null then 0 else 1 end) N15
				from (	
					select q.panel_number,
						min(V0) V0, min(V1) V1, min(V2) V2, min(V3) V3, min(V4) V4, min(V5) V5, min(V6) V6, min(V7) V7, min(V8) V8, min(V9) V9, min(V10) V10, min(V11) V11, min(V12) V12, min(V13) V13, min(V14) V14, min(V15) V15, min(V16) V16, min(V17) V17, min(V18) V18, min(V19) V19, min(V20) V20, min(V21) V21, min(V22) V22, min(V23) V23, min(V24) V24, min(V25) V25, min(V26) V26, min(V27) V27, min(V28) V28, min(V29) V29, min(V30) V30, min(V31) V31, min(V32) V32, min(V33) V33, min(V34) V34, min(V35) V35, min(V36) V36, min(V37) V37, min(V38) V38, min(V39) V39, min(V40) V40, min(V41) V41, min(V42) V42, min(V43) V43, min(V44) V44, min(V45) V45, min(V46) V46, min(V47) V47, min(V48) V48, min(V49) V49, min(V50) V50, min(V51) V51, min(V52) V52, min(V53) V53, min(V54) V54, min(V55) V55, min(V56) V56, min(V57) V57, min(V58) V58, min(V59) V59, min(V60) V60, min(V61) V61, min(V62) V62, min(V63) V63, min(V64) V64, min(V65) V65, min(V66) V66, min(V67) V67, min(V68) V68, min(V69) V69, min(V70) V70, min(V71) V71, min(V72) V72, min(V73) V73, min(V74) V74, min(V75) V75, min(V76) V76, min(V77) V77, min(V78) V78, min(V79) V79, min(V80) V80, min(V81) V81, min(V82) V82, min(V83) V83, min(V84) V84, min(V85) V85, min(V86) V86, min(V87) V87, min(V88) V88, min(V89) V89, min(V90) V90, min(V91) V91, min(V92) V92, min(V93) V93, min(V94) V94, min(V95) V95, min(V96) V96, min(V97) V97, min(V98) V98, min(V99) V99, min(V100) V100, min(V101) V101, min(V102) V102, min(V103) V103, min(V104) V104, min(V105) V105, min(V106) V106, min(V107) V107, min(V108) V108, min(V109) V109, min(V110) V110, min(V111) V111, min(V112) V112, min(V113) V113, min(V114) V114, min(V115) V115, min(V116) V116, min(V117) V117, min(V118) V118, min(V119) V119, min(V120) V120, min(V121) V121, min(V122) V122, min(V123) V123, min(V124) V124, min(V125) V125, min(V126) V126, min(V127) V127, min(V128) V128, min(V129) V129, min(V130) V130, min(V131) V131, min(V132) V132, min(V133) V133, min(V134) V134, min(V135) V135, min(V136) V136, min(V137) V137, min(V138) V138, min(V139) V139, min(V140) V140, min(V141) V141, min(V142) V142, min(V143) V143, min(V144) V144, min(V145) V145, min(V146) V146, min(V147) V147, min(V148) V148, min(V149) V149, min(V150) V150, min(V151) V151, min(V152) V152, min(V153) V153, min(V154) V154, min(V155) V155, min(V156) V156, min(V157) V157, min(V158) V158, min(V159) V159, min(V160) V160, min(V161) V161, min(V162) V162, min(V163) V163, min(V164) V164, min(V165) V165, min(V166) V166, min(V167) V167, min(V168) V168, min(V169) V169, min(V170) V170, min(V171) V171, min(V172) V172, min(V173) V173, min(V174) V174, min(V175) V175, min(V176) V176, min(V177) V177, min(V178) V178, min(V179) V179, min(V180) V180, min(V181) V181, min(V182) V182, min(V183) V183, min(V184) V184, min(V185) V185, min(V186) V186, min(V187) V187, min(V188) V188, min(V189) V189, min(V190) V190, min(V191) V191, min(V192) V192, min(V193) V193, min(V194) V194, min(V195) V195, min(V196) V196, min(V197) V197, min(V198) V198, min(V199) V199, min(V200) V200, min(V201) V201, min(V202) V202, min(V203) V203, min(V204) V204, min(V205) V205, min(V206) V206, min(V207) V207, min(V208) V208, min(V209) V209, min(V210) V210, min(V211) V211, min(V212) V212, min(V213) V213, min(V214) V214, min(V215) V215, min(V216) V216, min(V217) V217, min(V218) V218, min(V219) V219, min(V220) V220, min(V221) V221, min(V222) V222, min(V223) V223, min(V224) V224, min(V225) V225, min(V226) V226, min(V227) V227, min(V228) V228, min(V229) V229, min(V230) V230, min(V231) V231, min(V232) V232, min(V233) V233, min(V234) V234, min(V235) V235, min(V236) V236, min(V237) V237, min(V238) V238, min(V239) V239, min(V240) V240, min(V241) V241, min(V242) V242, min(V243) V243, min(V244) V244, min(V245) V245, min(V246) V246, min(V247) V247, min(V248) V248, min(V249) V249, min(V250) V250, min(V251) V251, min(V252) V252, min(V253) V253, min(V254) V254, min(V255) V255
					from #items q inner join CRC.CQ2_SKETCH_PATH8x256 s
						on q.concept_path_id = s.concept_path_id
					where q.panel_number IN (
						SELECT panel_number 
						FROM #Panels 
						WHERE all_concept_paths = 1 AND Invert=0
							AND ((@QueryMethod IN ('MINHASH8','MINHASH15')) OR (number_of_items > 1))
					)
					group by q.panel_number
				) t
			) t

		-- Update the panel estimate
		UPDATE p
			SET p.estimated_count = s.SketchPanelE
			FROM #Panels p 
				INNER JOIN #PanelSketch s
					ON p.panel_number = s.panel_number
			WHERE number_of_items > 1

		-- Switch to EXACT query mode if sketches provide no benefit
		IF @QueryMethod IN ('MINHASH8','MINHASH15')
		BEGIN
			SELECT @QueryMethod = 'EXACT'
				WHERE NOT EXISTS (SELECT * FROM #PanelSketch)
			IF @QueryMethod = 'MINHASH8'
				SELECT @QueryMethod = 'EXACT' WHERE (SELECT MIN(estimated_count) FROM #Panels WHERE Invert=0) <= 256
			IF @QueryMethod = 'MINHASH15'
				SELECT @QueryMethod = 'EXACT' WHERE (SELECT MIN(estimated_count) FROM #Panels WHERE Invert=0) <= 32768
		END
	END

	------------------------------------------------------------------------------
	-- Use sketches to get a sample of patients from the smallest panel
	------------------------------------------------------------------------------

	IF (@UseCQ2SketchTables = 0)
		SELECT @QueryMethod = 'EXACT'

	IF @QueryMethod IN ('MINHASH8','MINHASH15')
	BEGIN
		-- Determine the smallest panel
		SELECT @SketchPanel = panel_number
			FROM (
				SELECT panel_number, SketchPanelE, ROW_NUMBER() OVER (ORDER BY SketchPanelE, panel_number) k
				FROM #PanelSketch
			) t
			WHERE k=1

		-- Get the sketch size estimate of the smallest panel
		IF @QueryMethod = 'MINHASH8'
		BEGIN
			SELECT @SketchPanelE = SketchPanelE, @SketchPanelN = SketchPanelN
				FROM #PanelSketch
				WHERE panel_number = @SketchPanel

		END
		IF @QueryMethod = 'MINHASH15'
		BEGIN
			-- Replace the 8x256 sketch with a 15x256 sketch
			TRUNCATE TABLE #PanelSketch
			INSERT INTO #PanelSketch
				SELECT 0, B, 0, 0,
					min(V0) V0, min(V1) V1, min(V2) V2, min(V3) V3, min(V4) V4, min(V5) V5, min(V6) V6, min(V7) V7, min(V8) V8, min(V9) V9, min(V10) V10, min(V11) V11, min(V12) V12, min(V13) V13, min(V14) V14, min(V15) V15, min(V16) V16, min(V17) V17, min(V18) V18, min(V19) V19, min(V20) V20, min(V21) V21, min(V22) V22, min(V23) V23, min(V24) V24, min(V25) V25, min(V26) V26, min(V27) V27, min(V28) V28, min(V29) V29, min(V30) V30, min(V31) V31, min(V32) V32, min(V33) V33, min(V34) V34, min(V35) V35, min(V36) V36, min(V37) V37, min(V38) V38, min(V39) V39, min(V40) V40, min(V41) V41, min(V42) V42, min(V43) V43, min(V44) V44, min(V45) V45, min(V46) V46, min(V47) V47, min(V48) V48, min(V49) V49, min(V50) V50, min(V51) V51, min(V52) V52, min(V53) V53, min(V54) V54, min(V55) V55, min(V56) V56, min(V57) V57, min(V58) V58, min(V59) V59, min(V60) V60, min(V61) V61, min(V62) V62, min(V63) V63, min(V64) V64, min(V65) V65, min(V66) V66, min(V67) V67, min(V68) V68, min(V69) V69, min(V70) V70, min(V71) V71, min(V72) V72, min(V73) V73, min(V74) V74, min(V75) V75, min(V76) V76, min(V77) V77, min(V78) V78, min(V79) V79, min(V80) V80, min(V81) V81, min(V82) V82, min(V83) V83, min(V84) V84, min(V85) V85, min(V86) V86, min(V87) V87, min(V88) V88, min(V89) V89, min(V90) V90, min(V91) V91, min(V92) V92, min(V93) V93, min(V94) V94, min(V95) V95, min(V96) V96, min(V97) V97, min(V98) V98, min(V99) V99, min(V100) V100, min(V101) V101, min(V102) V102, min(V103) V103, min(V104) V104, min(V105) V105, min(V106) V106, min(V107) V107, min(V108) V108, min(V109) V109, min(V110) V110, min(V111) V111, min(V112) V112, min(V113) V113, min(V114) V114, min(V115) V115, min(V116) V116, min(V117) V117, min(V118) V118, min(V119) V119, min(V120) V120, min(V121) V121, min(V122) V122, min(V123) V123, min(V124) V124, min(V125) V125, min(V126) V126, min(V127) V127, min(V128) V128, min(V129) V129, min(V130) V130, min(V131) V131, min(V132) V132, min(V133) V133, min(V134) V134, min(V135) V135, min(V136) V136, min(V137) V137, min(V138) V138, min(V139) V139, min(V140) V140, min(V141) V141, min(V142) V142, min(V143) V143, min(V144) V144, min(V145) V145, min(V146) V146, min(V147) V147, min(V148) V148, min(V149) V149, min(V150) V150, min(V151) V151, min(V152) V152, min(V153) V153, min(V154) V154, min(V155) V155, min(V156) V156, min(V157) V157, min(V158) V158, min(V159) V159, min(V160) V160, min(V161) V161, min(V162) V162, min(V163) V163, min(V164) V164, min(V165) V165, min(V166) V166, min(V167) V167, min(V168) V168, min(V169) V169, min(V170) V170, min(V171) V171, min(V172) V172, min(V173) V173, min(V174) V174, min(V175) V175, min(V176) V176, min(V177) V177, min(V178) V178, min(V179) V179, min(V180) V180, min(V181) V181, min(V182) V182, min(V183) V183, min(V184) V184, min(V185) V185, min(V186) V186, min(V187) V187, min(V188) V188, min(V189) V189, min(V190) V190, min(V191) V191, min(V192) V192, min(V193) V193, min(V194) V194, min(V195) V195, min(V196) V196, min(V197) V197, min(V198) V198, min(V199) V199, min(V200) V200, min(V201) V201, min(V202) V202, min(V203) V203, min(V204) V204, min(V205) V205, min(V206) V206, min(V207) V207, min(V208) V208, min(V209) V209, min(V210) V210, min(V211) V211, min(V212) V212, min(V213) V213, min(V214) V214, min(V215) V215, min(V216) V216, min(V217) V217, min(V218) V218, min(V219) V219, min(V220) V220, min(V221) V221, min(V222) V222, min(V223) V223, min(V224) V224, min(V225) V225, min(V226) V226, min(V227) V227, min(V228) V228, min(V229) V229, min(V230) V230, min(V231) V231, min(V232) V232, min(V233) V233, min(V234) V234, min(V235) V235, min(V236) V236, min(V237) V237, min(V238) V238, min(V239) V239, min(V240) V240, min(V241) V241, min(V242) V242, min(V243) V243, min(V244) V244, min(V245) V245, min(V246) V246, min(V247) V247, min(V248) V248, min(V249) V249, min(V250) V250, min(V251) V251, min(V252) V252, min(V253) V253, min(V254) V254, min(V255) V255
				FROM #items q INNER JOIN CRC.CQ2_SKETCH_PATH15x256 s
					ON q.concept_path_id = s.concept_path_id
				WHERE q.panel_number = @SketchPanel
				GROUP BY B
			-- Calculate the more accurate sketch size estimate
			SELECT @SketchPanelE = HIVE.fnSketchEstimate(sV15, N15, N15, 32768, 1), @SketchPanelN = N15
				FROM (
					SELECT SUM(sV15) sV15, SUM(N15) N15
					FROM (
						SELECT
							cast(0 as float)+isnull(V0,0)+isnull(V1,0)+isnull(V2,0)+isnull(V3,0)+isnull(V4,0)+isnull(V5,0)+isnull(V6,0)+isnull(V7,0)+isnull(V8,0)+isnull(V9,0)+isnull(V10,0)+isnull(V11,0)+isnull(V12,0)+isnull(V13,0)+isnull(V14,0)+isnull(V15,0)+isnull(V16,0)+isnull(V17,0)+isnull(V18,0)+isnull(V19,0)+isnull(V20,0)+isnull(V21,0)+isnull(V22,0)+isnull(V23,0)+isnull(V24,0)+isnull(V25,0)+isnull(V26,0)+isnull(V27,0)+isnull(V28,0)+isnull(V29,0)+isnull(V30,0)+isnull(V31,0)+isnull(V32,0)+isnull(V33,0)+isnull(V34,0)+isnull(V35,0)+isnull(V36,0)+isnull(V37,0)+isnull(V38,0)+isnull(V39,0)+isnull(V40,0)+isnull(V41,0)+isnull(V42,0)+isnull(V43,0)+isnull(V44,0)+isnull(V45,0)+isnull(V46,0)+isnull(V47,0)+isnull(V48,0)+isnull(V49,0)+isnull(V50,0)+isnull(V51,0)+isnull(V52,0)+isnull(V53,0)+isnull(V54,0)+isnull(V55,0)+isnull(V56,0)+isnull(V57,0)+isnull(V58,0)+isnull(V59,0)+isnull(V60,0)+isnull(V61,0)+isnull(V62,0)+isnull(V63,0)+isnull(V64,0)+isnull(V65,0)+isnull(V66,0)+isnull(V67,0)+isnull(V68,0)+isnull(V69,0)+isnull(V70,0)+isnull(V71,0)+isnull(V72,0)+isnull(V73,0)+isnull(V74,0)+isnull(V75,0)+isnull(V76,0)+isnull(V77,0)+isnull(V78,0)+isnull(V79,0)+isnull(V80,0)+isnull(V81,0)+isnull(V82,0)+isnull(V83,0)+isnull(V84,0)+isnull(V85,0)+isnull(V86,0)+isnull(V87,0)+isnull(V88,0)+isnull(V89,0)+isnull(V90,0)+isnull(V91,0)+isnull(V92,0)+isnull(V93,0)+isnull(V94,0)+isnull(V95,0)+isnull(V96,0)+isnull(V97,0)+isnull(V98,0)+isnull(V99,0)+isnull(V100,0)+isnull(V101,0)+isnull(V102,0)+isnull(V103,0)+isnull(V104,0)+isnull(V105,0)+isnull(V106,0)+isnull(V107,0)+isnull(V108,0)+isnull(V109,0)+isnull(V110,0)+isnull(V111,0)+isnull(V112,0)+isnull(V113,0)+isnull(V114,0)+isnull(V115,0)+isnull(V116,0)+isnull(V117,0)+isnull(V118,0)+isnull(V119,0)+isnull(V120,0)+isnull(V121,0)+isnull(V122,0)+isnull(V123,0)+isnull(V124,0)+isnull(V125,0)+isnull(V126,0)+isnull(V127,0)+isnull(V128,0)+isnull(V129,0)+isnull(V130,0)+isnull(V131,0)+isnull(V132,0)+isnull(V133,0)+isnull(V134,0)+isnull(V135,0)+isnull(V136,0)+isnull(V137,0)+isnull(V138,0)+isnull(V139,0)+isnull(V140,0)+isnull(V141,0)+isnull(V142,0)+isnull(V143,0)+isnull(V144,0)+isnull(V145,0)+isnull(V146,0)+isnull(V147,0)+isnull(V148,0)+isnull(V149,0)+isnull(V150,0)+isnull(V151,0)+isnull(V152,0)+isnull(V153,0)+isnull(V154,0)+isnull(V155,0)+isnull(V156,0)+isnull(V157,0)+isnull(V158,0)+isnull(V159,0)+isnull(V160,0)+isnull(V161,0)+isnull(V162,0)+isnull(V163,0)+isnull(V164,0)+isnull(V165,0)+isnull(V166,0)+isnull(V167,0)+isnull(V168,0)+isnull(V169,0)+isnull(V170,0)+isnull(V171,0)+isnull(V172,0)+isnull(V173,0)+isnull(V174,0)+isnull(V175,0)+isnull(V176,0)+isnull(V177,0)+isnull(V178,0)+isnull(V179,0)+isnull(V180,0)+isnull(V181,0)+isnull(V182,0)+isnull(V183,0)+isnull(V184,0)+isnull(V185,0)+isnull(V186,0)+isnull(V187,0)+isnull(V188,0)+isnull(V189,0)+isnull(V190,0)+isnull(V191,0)+isnull(V192,0)+isnull(V193,0)+isnull(V194,0)+isnull(V195,0)+isnull(V196,0)+isnull(V197,0)+isnull(V198,0)+isnull(V199,0)+isnull(V200,0)+isnull(V201,0)+isnull(V202,0)+isnull(V203,0)+isnull(V204,0)+isnull(V205,0)+isnull(V206,0)+isnull(V207,0)+isnull(V208,0)+isnull(V209,0)+isnull(V210,0)+isnull(V211,0)+isnull(V212,0)+isnull(V213,0)+isnull(V214,0)+isnull(V215,0)+isnull(V216,0)+isnull(V217,0)+isnull(V218,0)+isnull(V219,0)+isnull(V220,0)+isnull(V221,0)+isnull(V222,0)+isnull(V223,0)+isnull(V224,0)+isnull(V225,0)+isnull(V226,0)+isnull(V227,0)+isnull(V228,0)+isnull(V229,0)+isnull(V230,0)+isnull(V231,0)+isnull(V232,0)+isnull(V233,0)+isnull(V234,0)+isnull(V235,0)+isnull(V236,0)+isnull(V237,0)+isnull(V238,0)+isnull(V239,0)+isnull(V240,0)+isnull(V241,0)+isnull(V242,0)+isnull(V243,0)+isnull(V244,0)+isnull(V245,0)+isnull(V246,0)+isnull(V247,0)+isnull(V248,0)+isnull(V249,0)+isnull(V250,0)+isnull(V251,0)+isnull(V252,0)+isnull(V253,0)+isnull(V254,0)+isnull(V255,0) sV15,
							(case when V0 is null then 0 else 1 end)+(case when V1 is null then 0 else 1 end)+(case when V2 is null then 0 else 1 end)+(case when V3 is null then 0 else 1 end)+(case when V4 is null then 0 else 1 end)+(case when V5 is null then 0 else 1 end)+(case when V6 is null then 0 else 1 end)+(case when V7 is null then 0 else 1 end)+(case when V8 is null then 0 else 1 end)+(case when V9 is null then 0 else 1 end)+(case when V10 is null then 0 else 1 end)+(case when V11 is null then 0 else 1 end)+(case when V12 is null then 0 else 1 end)+(case when V13 is null then 0 else 1 end)+(case when V14 is null then 0 else 1 end)+(case when V15 is null then 0 else 1 end)+(case when V16 is null then 0 else 1 end)+(case when V17 is null then 0 else 1 end)+(case when V18 is null then 0 else 1 end)+(case when V19 is null then 0 else 1 end)+(case when V20 is null then 0 else 1 end)+(case when V21 is null then 0 else 1 end)+(case when V22 is null then 0 else 1 end)+(case when V23 is null then 0 else 1 end)+(case when V24 is null then 0 else 1 end)+(case when V25 is null then 0 else 1 end)+(case when V26 is null then 0 else 1 end)+(case when V27 is null then 0 else 1 end)+(case when V28 is null then 0 else 1 end)+(case when V29 is null then 0 else 1 end)+(case when V30 is null then 0 else 1 end)+(case when V31 is null then 0 else 1 end)+(case when V32 is null then 0 else 1 end)+(case when V33 is null then 0 else 1 end)+(case when V34 is null then 0 else 1 end)+(case when V35 is null then 0 else 1 end)+(case when V36 is null then 0 else 1 end)+(case when V37 is null then 0 else 1 end)+(case when V38 is null then 0 else 1 end)+(case when V39 is null then 0 else 1 end)+(case when V40 is null then 0 else 1 end)+(case when V41 is null then 0 else 1 end)+(case when V42 is null then 0 else 1 end)+(case when V43 is null then 0 else 1 end)+(case when V44 is null then 0 else 1 end)+(case when V45 is null then 0 else 1 end)+(case when V46 is null then 0 else 1 end)+(case when V47 is null then 0 else 1 end)+(case when V48 is null then 0 else 1 end)+(case when V49 is null then 0 else 1 end)+(case when V50 is null then 0 else 1 end)+(case when V51 is null then 0 else 1 end)+(case when V52 is null then 0 else 1 end)+(case when V53 is null then 0 else 1 end)+(case when V54 is null then 0 else 1 end)+(case when V55 is null then 0 else 1 end)+(case when V56 is null then 0 else 1 end)+(case when V57 is null then 0 else 1 end)+(case when V58 is null then 0 else 1 end)+(case when V59 is null then 0 else 1 end)+(case when V60 is null then 0 else 1 end)+(case when V61 is null then 0 else 1 end)+(case when V62 is null then 0 else 1 end)+(case when V63 is null then 0 else 1 end)+(case when V64 is null then 0 else 1 end)+(case when V65 is null then 0 else 1 end)+(case when V66 is null then 0 else 1 end)+(case when V67 is null then 0 else 1 end)+(case when V68 is null then 0 else 1 end)+(case when V69 is null then 0 else 1 end)+(case when V70 is null then 0 else 1 end)+(case when V71 is null then 0 else 1 end)+(case when V72 is null then 0 else 1 end)+(case when V73 is null then 0 else 1 end)+(case when V74 is null then 0 else 1 end)+(case when V75 is null then 0 else 1 end)+(case when V76 is null then 0 else 1 end)+(case when V77 is null then 0 else 1 end)+(case when V78 is null then 0 else 1 end)+(case when V79 is null then 0 else 1 end)+(case when V80 is null then 0 else 1 end)+(case when V81 is null then 0 else 1 end)+(case when V82 is null then 0 else 1 end)+(case when V83 is null then 0 else 1 end)+(case when V84 is null then 0 else 1 end)+(case when V85 is null then 0 else 1 end)+(case when V86 is null then 0 else 1 end)+(case when V87 is null then 0 else 1 end)+(case when V88 is null then 0 else 1 end)+(case when V89 is null then 0 else 1 end)+(case when V90 is null then 0 else 1 end)+(case when V91 is null then 0 else 1 end)+(case when V92 is null then 0 else 1 end)+(case when V93 is null then 0 else 1 end)+(case when V94 is null then 0 else 1 end)+(case when V95 is null then 0 else 1 end)+(case when V96 is null then 0 else 1 end)+(case when V97 is null then 0 else 1 end)+(case when V98 is null then 0 else 1 end)+(case when V99 is null then 0 else 1 end)+(case when V100 is null then 0 else 1 end)+(case when V101 is null then 0 else 1 end)+(case when V102 is null then 0 else 1 end)+(case when V103 is null then 0 else 1 end)+(case when V104 is null then 0 else 1 end)+(case when V105 is null then 0 else 1 end)+(case when V106 is null then 0 else 1 end)+(case when V107 is null then 0 else 1 end)+(case when V108 is null then 0 else 1 end)+(case when V109 is null then 0 else 1 end)+(case when V110 is null then 0 else 1 end)+(case when V111 is null then 0 else 1 end)+(case when V112 is null then 0 else 1 end)+(case when V113 is null then 0 else 1 end)+(case when V114 is null then 0 else 1 end)+(case when V115 is null then 0 else 1 end)+(case when V116 is null then 0 else 1 end)+(case when V117 is null then 0 else 1 end)+(case when V118 is null then 0 else 1 end)+(case when V119 is null then 0 else 1 end)+(case when V120 is null then 0 else 1 end)+(case when V121 is null then 0 else 1 end)+(case when V122 is null then 0 else 1 end)+(case when V123 is null then 0 else 1 end)+(case when V124 is null then 0 else 1 end)+(case when V125 is null then 0 else 1 end)+(case when V126 is null then 0 else 1 end)+(case when V127 is null then 0 else 1 end)+(case when V128 is null then 0 else 1 end)+(case when V129 is null then 0 else 1 end)+(case when V130 is null then 0 else 1 end)+(case when V131 is null then 0 else 1 end)+(case when V132 is null then 0 else 1 end)+(case when V133 is null then 0 else 1 end)+(case when V134 is null then 0 else 1 end)+(case when V135 is null then 0 else 1 end)+(case when V136 is null then 0 else 1 end)+(case when V137 is null then 0 else 1 end)+(case when V138 is null then 0 else 1 end)+(case when V139 is null then 0 else 1 end)+(case when V140 is null then 0 else 1 end)+(case when V141 is null then 0 else 1 end)+(case when V142 is null then 0 else 1 end)+(case when V143 is null then 0 else 1 end)+(case when V144 is null then 0 else 1 end)+(case when V145 is null then 0 else 1 end)+(case when V146 is null then 0 else 1 end)+(case when V147 is null then 0 else 1 end)+(case when V148 is null then 0 else 1 end)+(case when V149 is null then 0 else 1 end)+(case when V150 is null then 0 else 1 end)+(case when V151 is null then 0 else 1 end)+(case when V152 is null then 0 else 1 end)+(case when V153 is null then 0 else 1 end)+(case when V154 is null then 0 else 1 end)+(case when V155 is null then 0 else 1 end)+(case when V156 is null then 0 else 1 end)+(case when V157 is null then 0 else 1 end)+(case when V158 is null then 0 else 1 end)+(case when V159 is null then 0 else 1 end)+(case when V160 is null then 0 else 1 end)+(case when V161 is null then 0 else 1 end)+(case when V162 is null then 0 else 1 end)+(case when V163 is null then 0 else 1 end)+(case when V164 is null then 0 else 1 end)+(case when V165 is null then 0 else 1 end)+(case when V166 is null then 0 else 1 end)+(case when V167 is null then 0 else 1 end)+(case when V168 is null then 0 else 1 end)+(case when V169 is null then 0 else 1 end)+(case when V170 is null then 0 else 1 end)+(case when V171 is null then 0 else 1 end)+(case when V172 is null then 0 else 1 end)+(case when V173 is null then 0 else 1 end)+(case when V174 is null then 0 else 1 end)+(case when V175 is null then 0 else 1 end)+(case when V176 is null then 0 else 1 end)+(case when V177 is null then 0 else 1 end)+(case when V178 is null then 0 else 1 end)+(case when V179 is null then 0 else 1 end)+(case when V180 is null then 0 else 1 end)+(case when V181 is null then 0 else 1 end)+(case when V182 is null then 0 else 1 end)+(case when V183 is null then 0 else 1 end)+(case when V184 is null then 0 else 1 end)+(case when V185 is null then 0 else 1 end)+(case when V186 is null then 0 else 1 end)+(case when V187 is null then 0 else 1 end)+(case when V188 is null then 0 else 1 end)+(case when V189 is null then 0 else 1 end)+(case when V190 is null then 0 else 1 end)+(case when V191 is null then 0 else 1 end)+(case when V192 is null then 0 else 1 end)+(case when V193 is null then 0 else 1 end)+(case when V194 is null then 0 else 1 end)+(case when V195 is null then 0 else 1 end)+(case when V196 is null then 0 else 1 end)+(case when V197 is null then 0 else 1 end)+(case when V198 is null then 0 else 1 end)+(case when V199 is null then 0 else 1 end)+(case when V200 is null then 0 else 1 end)+(case when V201 is null then 0 else 1 end)+(case when V202 is null then 0 else 1 end)+(case when V203 is null then 0 else 1 end)+(case when V204 is null then 0 else 1 end)+(case when V205 is null then 0 else 1 end)+(case when V206 is null then 0 else 1 end)+(case when V207 is null then 0 else 1 end)+(case when V208 is null then 0 else 1 end)+(case when V209 is null then 0 else 1 end)+(case when V210 is null then 0 else 1 end)+(case when V211 is null then 0 else 1 end)+(case when V212 is null then 0 else 1 end)+(case when V213 is null then 0 else 1 end)+(case when V214 is null then 0 else 1 end)+(case when V215 is null then 0 else 1 end)+(case when V216 is null then 0 else 1 end)+(case when V217 is null then 0 else 1 end)+(case when V218 is null then 0 else 1 end)+(case when V219 is null then 0 else 1 end)+(case when V220 is null then 0 else 1 end)+(case when V221 is null then 0 else 1 end)+(case when V222 is null then 0 else 1 end)+(case when V223 is null then 0 else 1 end)+(case when V224 is null then 0 else 1 end)+(case when V225 is null then 0 else 1 end)+(case when V226 is null then 0 else 1 end)+(case when V227 is null then 0 else 1 end)+(case when V228 is null then 0 else 1 end)+(case when V229 is null then 0 else 1 end)+(case when V230 is null then 0 else 1 end)+(case when V231 is null then 0 else 1 end)+(case when V232 is null then 0 else 1 end)+(case when V233 is null then 0 else 1 end)+(case when V234 is null then 0 else 1 end)+(case when V235 is null then 0 else 1 end)+(case when V236 is null then 0 else 1 end)+(case when V237 is null then 0 else 1 end)+(case when V238 is null then 0 else 1 end)+(case when V239 is null then 0 else 1 end)+(case when V240 is null then 0 else 1 end)+(case when V241 is null then 0 else 1 end)+(case when V242 is null then 0 else 1 end)+(case when V243 is null then 0 else 1 end)+(case when V244 is null then 0 else 1 end)+(case when V245 is null then 0 else 1 end)+(case when V246 is null then 0 else 1 end)+(case when V247 is null then 0 else 1 end)+(case when V248 is null then 0 else 1 end)+(case when V249 is null then 0 else 1 end)+(case when V250 is null then 0 else 1 end)+(case when V251 is null then 0 else 1 end)+(case when V252 is null then 0 else 1 end)+(case when V253 is null then 0 else 1 end)+(case when V254 is null then 0 else 1 end)+(case when V255 is null then 0 else 1 end) N15
						FROM #PanelSketch
					) t
				) t
		END

		-- Convert the sketch values into a list of patient_nums
		SELECT patient_num
			INTO #SamplePatientList
			FROM CRC.CQ2_SKETCH_PATIENT
			WHERE v IN (
				SELECT v
				FROM #PanelSketch
					CROSS APPLY (
						select 0 b, v0 v
						union all select 1 b, v1 union all select 2 b, v2 union all select 3 b, v3 union all select 4 b, v4 union all select 5 b, v5 union all select 6 b, v6 union all select 7 b, v7 union all select 8 b, v8 union all select 9 b, v9 union all select 10 b, v10 union all select 11 b, v11 union all select 12 b, v12 union all select 13 b, v13 union all select 14 b, v14 union all select 15 b, v15 union all select 16 b, v16 union all select 17 b, v17 union all select 18 b, v18 union all select 19 b, v19 union all select 20 b, v20 union all select 21 b, v21 union all select 22 b, v22 union all select 23 b, v23 union all select 24 b, v24 union all select 25 b, v25 union all select 26 b, v26 union all select 27 b, v27 union all select 28 b, v28 union all select 29 b, v29 union all select 30 b, v30 union all select 31 b, v31 union all select 32 b, v32 union all select 33 b, v33 union all select 34 b, v34 union all select 35 b, v35 union all select 36 b, v36 union all select 37 b, v37 union all select 38 b, v38 union all select 39 b, v39 union all select 40 b, v40 union all select 41 b, v41 union all select 42 b, v42 union all select 43 b, v43 union all select 44 b, v44 union all select 45 b, v45 union all select 46 b, v46 union all select 47 b, v47 union all select 48 b, v48 union all select 49 b, v49 union all select 50 b, v50 union all select 51 b, v51 union all select 52 b, v52 union all select 53 b, v53 union all select 54 b, v54 union all select 55 b, v55 union all select 56 b, v56 union all select 57 b, v57 union all select 58 b, v58 union all select 59 b, v59 union all select 60 b, v60 union all select 61 b, v61 union all select 62 b, v62 union all select 63 b, v63 union all select 64 b, v64 union all select 65 b, v65 union all select 66 b, v66 union all select 67 b, v67 union all select 68 b, v68 union all select 69 b, v69 union all select 70 b, v70 union all select 71 b, v71 union all select 72 b, v72 union all select 73 b, v73 union all select 74 b, v74 union all select 75 b, v75 union all select 76 b, v76 union all select 77 b, v77 union all select 78 b, v78 union all select 79 b, v79 union all select 80 b, v80 union all select 81 b, v81 union all select 82 b, v82 union all select 83 b, v83 union all select 84 b, v84 union all select 85 b, v85 union all select 86 b, v86 union all select 87 b, v87 union all select 88 b, v88 union all select 89 b, v89 union all select 90 b, v90 union all select 91 b, v91 union all select 92 b, v92 union all select 93 b, v93 union all select 94 b, v94 union all select 95 b, v95 union all select 96 b, v96 union all select 97 b, v97 union all select 98 b, v98 union all select 99 b, v99 union all select 100 b, v100 union all select 101 b, v101 union all select 102 b, v102 union all select 103 b, v103 union all select 104 b, v104 union all select 105 b, v105 union all select 106 b, v106 union all select 107 b, v107 union all select 108 b, v108 union all select 109 b, v109 union all select 110 b, v110 union all select 111 b, v111 union all select 112 b, v112 union all select 113 b, v113 union all select 114 b, v114 union all select 115 b, v115 union all select 116 b, v116 union all select 117 b, v117 union all select 118 b, v118 union all select 119 b, v119 union all select 120 b, v120 union all select 121 b, v121 union all select 122 b, v122 union all select 123 b, v123 union all select 124 b, v124 union all select 125 b, v125 union all select 126 b, v126 union all select 127 b, v127 union all select 128 b, v128 union all select 129 b, v129 union all select 130 b, v130 union all select 131 b, v131 union all select 132 b, v132 union all select 133 b, v133 union all select 134 b, v134 union all select 135 b, v135 union all select 136 b, v136 union all select 137 b, v137 union all select 138 b, v138 union all select 139 b, v139 union all select 140 b, v140 union all select 141 b, v141 union all select 142 b, v142 union all select 143 b, v143 union all select 144 b, v144 union all select 145 b, v145 union all select 146 b, v146 union all select 147 b, v147 union all select 148 b, v148 union all select 149 b, v149 union all select 150 b, v150 union all select 151 b, v151 union all select 152 b, v152 union all select 153 b, v153 union all select 154 b, v154 union all select 155 b, v155 union all select 156 b, v156 union all select 157 b, v157 union all select 158 b, v158 union all select 159 b, v159 union all select 160 b, v160 union all select 161 b, v161 union all select 162 b, v162 union all select 163 b, v163 union all select 164 b, v164 union all select 165 b, v165 union all select 166 b, v166 union all select 167 b, v167 union all select 168 b, v168 union all select 169 b, v169 union all select 170 b, v170 union all select 171 b, v171 union all select 172 b, v172 union all select 173 b, v173 union all select 174 b, v174 union all select 175 b, v175 union all select 176 b, v176 union all select 177 b, v177 union all select 178 b, v178 union all select 179 b, v179 union all select 180 b, v180 union all select 181 b, v181 union all select 182 b, v182 union all select 183 b, v183 union all select 184 b, v184 union all select 185 b, v185 union all select 186 b, v186 union all select 187 b, v187 union all select 188 b, v188 union all select 189 b, v189 union all select 190 b, v190 union all select 191 b, v191 union all select 192 b, v192 union all select 193 b, v193 union all select 194 b, v194 union all select 195 b, v195 union all select 196 b, v196 union all select 197 b, v197 union all select 198 b, v198 union all select 199 b, v199 union all select 200 b, v200 union all select 201 b, v201 union all select 202 b, v202 union all select 203 b, v203 union all select 204 b, v204 union all select 205 b, v205 union all select 206 b, v206 union all select 207 b, v207 union all select 208 b, v208 union all select 209 b, v209 union all select 210 b, v210 union all select 211 b, v211 union all select 212 b, v212 union all select 213 b, v213 union all select 214 b, v214 union all select 215 b, v215 union all select 216 b, v216 union all select 217 b, v217 union all select 218 b, v218 union all select 219 b, v219 union all select 220 b, v220 union all select 221 b, v221 union all select 222 b, v222 union all select 223 b, v223 union all select 224 b, v224 union all select 225 b, v225 union all select 226 b, v226 union all select 227 b, v227 union all select 228 b, v228 union all select 229 b, v229 union all select 230 b, v230 union all select 231 b, v231 union all select 232 b, v232 union all select 233 b, v233 union all select 234 b, v234 union all select 235 b, v235 union all select 236 b, v236 union all select 237 b, v237 union all select 238 b, v238 union all select 239 b, v239 union all select 240 b, v240 union all select 241 b, v241 union all select 242 b, v242 union all select 243 b, v243 union all select 244 b, v244 union all select 245 b, v245 union all select 246 b, v246 union all select 247 b, v247 union all select 248 b, v248 union all select 249 b, v249 union all select 250 b, v250 union all select 251 b, v251 union all select 252 b, v252 union all select 253 b, v253 union all select 254 b, v254 union all select 255 b, v255
					) v
				WHERE v.v IS NOT NULL
			)
		ALTER TABLE #SamplePatientList ADD PRIMARY KEY (patient_num)

		--select * from #SamplePatientList
		--select count(*) from #SamplePatientList

		-- Create a new panel containing the sampled patients, and set its estimated count to 1 to force it to be processed first
		INSERT INTO #panels (panel_number, panel_accuracy_scale, invert, panel_timing, total_item_occurrences, estimated_count, has_multiple_occurrences, has_date_constraint, has_date_range_constraint, has_modifier_constraint, has_value_constraint, has_complex_value_constraint, all_concept_paths, number_of_items, panel_table)
			SELECT max(panel_number)+1, 100 panel_accuracy_scale, 0 invert, 'ANY' panel_timing, 1 total_item_occurrences, 1 estimated_count, 0 has_multiple_occurrences, 0 has_date_constraint, 0 has_date_range_constraint, 0 has_modifier_constraint, 0 has_value_constraint, 0 has_complex_value_constraint, 0 all_concept_paths, 1 number_of_items, 'patient_dimension' panel_table
				FROM #panels
		-- Create an item in the new panel that points to the saved list of sampled patients
		INSERT INTO #items (panel_number, item_key, item_type, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, c_totalnum, valid)
			SELECT max(panel_number), 'sample', 'sample', 'patient_num', 'patient_dimension', 'patient_num', 'N', 'IN', '(SELECT patient_num FROM #SamplePatientList)', 1, 1
				FROM #panels

		--create table dbo.SketchList (patient_num int primary key)
		--delete from dbo.SketchList; insert into dbo.SketchList select * from #SamplePatientList

		--select * from #panels;
		--select * from #items;

		--return;

	END

	------------------------------------------------------------------------------
	-- Determine if CQ2 table alternatives can be used
	------------------------------------------------------------------------------

	IF @UseCQ2Tables = 1
	BEGIN
		UPDATE #Panels
			--SET panel_table = 'cq2_fact_counts_concept_patient'
			SET panel_table = 'cq2_fact_counts_path_patient'
			WHERE panel_timing = 'ANY'
				AND all_concept_paths = 1
				AND has_complex_value_constraint = 0
				AND has_date_range_constraint = 0
				AND has_modifier_constraint = 0
				AND (has_multiple_occurrences = 0 OR number_of_items = 1)
				AND (has_date_constraint + has_multiple_occurrences + has_value_constraint <= 1)
				AND panel_table = 'concept_dimension'
				AND @DebugEnableCQ2PathTables = 1
		UPDATE #Items
			SET c_tablename = 'CQ2_CONCEPT_PATH_CODE', c_columnname = 'CONCEPT_PATH_ID', c_operator = '=', c_dimcode = CAST(concept_path_id AS VARCHAR(50))
			WHERE concept_path_id IS NOT NULL AND c_facttablecolumn = 'concept_cd'
	END

	------------------------------------------------------------------------------
	-- Prepare to run the query
	------------------------------------------------------------------------------

	-- Determine if a temp table is needed
	SELECT @UseTempListTables = 1
	SELECT @UseTempListTables = 0
		WHERE (@ReturnPatientList = 0 AND @ReturnEncounterList = 0)
			AND ((SELECT COUNT(*) FROM #Panels) = 1)
			AND @DebugEnableAvoidTempListTables = 1

	-- Determine panel process order
	;WITH a AS (
		SELECT panel_number, estimated_count,
			ROW_NUMBER() OVER (ORDER BY	(CASE panel_timing WHEN 'ANY' THEN 1 WHEN 'SAMEVISIT' THEN 2 ELSE 3 END),
										invert,
										(CASE WHEN @DebugEnablePanelReorder = 1 THEN estimated_count ELSE 0 END)
										) k1,
			ROW_NUMBER() OVER (ORDER BY	(CASE panel_timing WHEN 'ANY' THEN 3 WHEN 'SAMEVISIT' THEN 2 ELSE 1 END),
										invert,
										(CASE WHEN @DebugEnablePanelReorder = 1 THEN estimated_count ELSE 0 END)
										) k2
		FROM #Panels
	), b AS (
		SELECT (SELECT estimated_count FROM a WHERE k1 = 1) e1, (SELECT estimated_count FROM a WHERE k2 = 1) e2
	)
	UPDATE p
		SET p.process_order = (CASE WHEN e1 <= e2 THEN k1 ELSE k2 END)
		FROM #Panels p, a, b
		WHERE p.panel_number = a.panel_number

	-- Get the panel timing for the last panel that was processed (important for join type)
	UPDATE p
		SET p.previous_panel_timing = q.panel_timing
		FROM #Panels p, #Panels q
		WHERE p.process_order = q.process_order + 1

	--SELECT 'P', * FROM #Panels
	--SELECT 'I', * FROM #Items
	--SELECT 'QueryTiming', @query_timing
	--return;

	/*
	UPDATE #Items
		SET c_tablename = 'CQ2_CONCEPT_PATH_CODE', c_columnname = 'CONCEPT_PATH_ID', c_operator = '=', c_dimcode = CAST(concept_path_id AS VARCHAR(50))
		WHERE concept_path_id IS NOT NULL AND c_facttablecolumn = 'concept_cd'
	*/
	--SELECT 'I2', * FROM #Items

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Run the query
	-- ***************************************************************************
	-- ***************************************************************************

	SELECT @p = 1, @MaxP = IsNull((SELECT MAX(process_order) FROM #Panels),0)
	WHILE @p <= @MaxP
	BEGIN
		------------------------------------------------------------
		-- Setup
		------------------------------------------------------------
		-- Initialize the timer
		SELECT @ProcessStartTime = GETDATE()
		-- Get panel variables
		SELECT	@panel_date_from = panel_date_from,
				@panel_date_to = panel_date_to,
				@panel_accuracy_scale = panel_accuracy_scale,
				@invert = invert,
				@panel_timing = panel_timing,
				@total_item_occurrences = total_item_occurrences,
				@has_date_constraint = has_date_constraint,
				@has_date_range_constraint = has_date_range_constraint,
				@has_modifier_constraint = has_modifier_constraint,
				@has_value_constraint = has_value_constraint,
				@number_of_items = number_of_items,
				@panel_table = panel_table,
				@previous_panel_timing = previous_panel_timing
			FROM #Panels
			WHERE process_order = @p

		SELECT @panel_temp_table = (CASE
										WHEN (ISNULL(@previous_panel_temp_table,'') = '#InstanceList') OR (@panel_timing = 'SAMEINSTANCENUM')
											THEN '#InstanceList'
										WHEN (ISNULL(@previous_panel_temp_table,'') = '#EncounterList') OR (@panel_timing = 'SAMEVISIT')
											THEN '#EncounterList'
										ELSE '#PatientList'
										END)

		SELECT @panel_temp_table_columns = (CASE @panel_temp_table
										WHEN '#InstanceList' THEN 'patient_num, encounter_num, concept_cd, start_date, instance_num, provider_id'
										WHEN '#EncounterList' THEN 'patient_num, encounter_num'
										ELSE 'patient_num' END)

		SELECT @join_to_temp = (CASE
									WHEN @previous_panel_temp_table IS NULL
										THEN ''
									ELSE ' INNER JOIN '+@previous_panel_temp_table+' p
												ON p.panels = '+CAST((@p-1) AS VARCHAR(50))+'
												AND f.patient_num = p.patient_num '
										+(CASE WHEN @panel_timing IN ('SAMEVISIT','SAMEINSTANCENUM')
													AND @previous_panel_temp_table IN ('#EncounterList','#InstanceList')
											THEN ' AND f.encounter_num = p.encounter_num '
											ELSE '' END)
										+(CASE WHEN @panel_timing = 'SAMEINSTANCENUM' AND @previous_panel_temp_table = '#InstanceList'
											THEN '
												AND f.concept_cd = p.concept_cd
												AND f.provider_id = p.provider_id
												AND f.start_date = p.start_date
												AND f.instance_num = p.instance_num
												'
											ELSE '' END)
									END)

		-- Initialize panel SQL
		SELECT @sql = ''
		------------------------------------------------------------
		-- Select the correct facts within the panel
		------------------------------------------------------------
		-- Select the query table
		IF (@panel_table = 'patient_dimension') AND (@panel_timing = 'ANY')
		BEGIN
			-- Handle item constraints
			SELECT @sql = @sql +' OR (f.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode+')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number
			-- Select patients
			SELECT @sql = 'SELECT f.patient_num
								FROM '+@Schema+'.patient_dimension f '+@join_to_temp+'
								WHERE 1=0 ' + @sql
		END
		ELSE IF (@panel_table = 'visit_dimension') AND (@panel_timing IN ('ANY','SAMEVISIT'))
		BEGIN
			-- Handle item constraints
			SELECT @sql = @sql +' OR ('
							+'f.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode
							+(CASE	WHEN p.panel_date_from IS NOT NULL
										THEN ' AND f.start_date >= ''' + CAST(p.panel_date_from AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN p.panel_date_to IS NOT NULL
										THEN ' AND f.start_date <= ''' + CAST(p.panel_date_to AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN i.date_from IS NOT NULL
										THEN ' AND f.start_date >= ''' + CAST(i.date_from AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN i.date_to IS NOT NULL
										THEN ' AND f.start_date <= ''' + CAST(i.date_to AS VARCHAR(50)) + ''''
									ELSE '' END)
							+')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number
			-- Select patients
			SELECT @sql = 'SELECT DISTINCT f.patient_num '
									+(CASE	WHEN @panel_timing = 'SAMEVISIT' 
												THEN ', f.encounter_num'
											ELSE '' END)+'
								FROM '+@Schema+'.visit_dimension f '+@join_to_temp+'
								WHERE 1=0 ' + @sql
		END
		ELSE IF (@panel_table = 'cq2_fact_counts_path_patient')
		BEGIN
			SELECT @sqlTemp1='', @sqlTemp2=''
			-- Handle item constraints (paths)
			SELECT @sqlTemp1 = @sqlTemp1 + ' OR ('
							+'f.concept_path_id = ' + CAST(i.concept_path_id AS NVARCHAR(50))
							+(CASE	WHEN i.value_type='NUMBER' AND i.value_operator IN ('<','<=')
									THEN ' AND f.min_nval_num '+i.value_operator+' '+i.value_constraint
									WHEN i.value_type='NUMBER' AND i.value_operator IN ('>','>=')
									THEN ' AND f.max_nval_num '+i.value_operator+' '+i.value_constraint
									ELSE '' END)
							+(CASE	WHEN i.date_from IS NOT NULL
									THEN ' AND f.last_start >= ''' + CAST(i.date_from AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN i.date_to IS NOT NULL
									THEN ' AND f.first_start <= ''' + CAST(i.date_to AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN @panel_date_from IS NOT NULL
									THEN ' AND f.last_start >= ''' + CAST(@panel_date_from AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN @panel_date_to IS NOT NULL
									THEN ' AND f.first_start <= ''' + CAST(@panel_date_to AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN @total_item_occurrences > 1
									THEN ' AND f.num_instances >= ' + CAST(@total_item_occurrences AS VARCHAR(50))
									ELSE '' END)
							+ ')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number AND i.concept_cd = ''
			-- Handle item constraints (concepts)
			SELECT @sqlTemp2 = @sqlTemp2 + ' OR ('
							+'f.concept_cd = ''' + REPLACE(i.concept_cd,'''','''''') + ''''
							+(CASE	WHEN i.value_type='NUMBER' AND i.value_operator IN ('<','<=')
									THEN ' AND f.min_nval_num '+i.value_operator+' '+i.value_constraint
									WHEN i.value_type='NUMBER' AND i.value_operator IN ('>','>=')
									THEN ' AND f.max_nval_num '+i.value_operator+' '+i.value_constraint
									ELSE '' END)
							+(CASE	WHEN i.date_from IS NOT NULL
									THEN ' AND f.last_start >= ''' + CAST(i.date_from AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN i.date_to IS NOT NULL
									THEN ' AND f.first_start <= ''' + CAST(i.date_to AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN @panel_date_from IS NOT NULL
									THEN ' AND f.last_start >= ''' + CAST(@panel_date_from AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN @panel_date_to IS NOT NULL
									THEN ' AND f.first_start <= ''' + CAST(@panel_date_to AS VARCHAR(50)) + ''''
									ELSE '' END)
							+(CASE	WHEN @total_item_occurrences > 1
									THEN ' AND f.num_instances >= ' + CAST(@total_item_occurrences AS VARCHAR(50))
									ELSE '' END)
							+ ')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number AND i.concept_cd <> ''
			-- Select patients
			SELECT @sql = 'SELECT DISTINCT f.patient_num
								FROM (
									SELECT f.patient_num
										FROM '+@Schema+'.cq2_fact_counts_path_patient f '+@join_to_temp+'
										WHERE (1=0 ' + @sqlTemp1 + ')
									UNION ALL
									SELECT f.patient_num
										FROM '+@Schema+'.cq2_fact_counts_concept_patient f '+@join_to_temp+'
										WHERE (1=0 ' + @sqlTemp2 + ')
								) f '
		END
		ELSE IF (@panel_table = 'cq2_fact_counts_concept_patient')  --TODO: This isn't fully implemented!
		BEGIN
			-- Handle item constraints
			SELECT @sql = @sql 
				+' OR ('
				+'	f.'+i.c_facttablecolumn+' IN ('
				+'	SELECT '+i.c_facttablecolumn
				+'		FROM '+@Schema+'.'+i.c_tablename+' t'
				+'		WHERE t.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode
				+'	)'
				+')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number
			-- Select patients
			SELECT @sql = 'SELECT DISTINCT f.patient_num
								FROM '+@Schema+'.cq2_fact_counts_concept_patient f '+@join_to_temp+'
								WHERE 1=0 ' + @sql
		END
		ELSE
		BEGIN
			-- Handle item constraints
			SELECT @sql = @sql 
				+' OR ('
				+'	f.'+i.c_facttablecolumn+' IN ('
				+'	SELECT '+i.c_facttablecolumn
				+'		FROM '+@Schema+'.'+i.c_tablename+' t'
				+'		WHERE t.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode
				+'	)'
				+(CASE	WHEN IsNull(i.modifier_path,'') <> ''
							THEN ' AND f.'+i.m_facttablecolumn+' IN ('
									+'	SELECT '+i.m_facttablecolumn
									+'		FROM '+@Schema+'.'+i.m_tablename+' t'
									+'		WHERE t.'+i.m_columnname+' '+i.m_operator+' '+i.m_dimcode
									+')'
						ELSE '' END)
				+(CASE	WHEN (i.value_operator IS NULL) OR (i.value_constraint IS NULL)
							THEN ''
						WHEN i.value_type='TEXT'
							THEN ' AND f.tval_char '+i.value_operator+' '+i.value_constraint
						WHEN i.value_type='NUMBER'
							THEN ' AND f.nval_num '+i.value_operator+' '+i.value_constraint
						WHEN i.value_type='FLAG'
							THEN ' AND IsNull(f.valueflag_cd,''@'') '+i.value_operator+' '+i.value_constraint
						ELSE '' END)
				+(CASE	WHEN i.date_from IS NOT NULL
							THEN ' AND f.start_date >= ''' + CAST(i.date_from AS VARCHAR(50)) + ''''
						ELSE '' END)
				+(CASE	WHEN i.date_to IS NOT NULL
							THEN ' AND f.start_date <= ''' + CAST(i.date_to AS VARCHAR(50)) + ''''
						ELSE '' END)
				+(CASE	WHEN p.panel_date_from IS NOT NULL
							THEN ' AND f.start_date >= ''' + CAST(p.panel_date_from AS VARCHAR(50)) + ''''
						ELSE '' END)
				+(CASE	WHEN p.panel_date_to IS NOT NULL
							THEN ' AND f.start_date <= ''' + CAST(p.panel_date_to AS VARCHAR(50)) + ''''
						ELSE '' END)
				+')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number
			-- Handle total_item_occurrences
			IF (@total_item_occurrences > 1) AND (@panel_timing = 'ANY')
				-- Multiple occurrences, ANY timing
				SELECT @sql = 'SELECT patient_num
									FROM (
										SELECT DISTINCT f.encounter_num, f.patient_num, f.concept_cd, f.provider_id, f.start_date, f.instance_num
											FROM '+@Schema+'.observation_fact f '+@join_to_temp+'
											WHERE 1=0 ' + @sql + '
									) t
									GROUP BY patient_num
									HAVING COUNT(*) >= '+CAST(@total_item_occurrences AS VARCHAR(50))
			ELSE IF (@total_item_occurrences > 1)
				-- Multiple occurrences, not ANY timing
				SELECT @sql = 'SELECT DISTINCT patient_num '
									+(CASE	WHEN @panel_timing = 'SAMEVISIT' 
												THEN ', encounter_num'
											WHEN @panel_timing = 'SAMEINSTANCENUM'
												THEN ', encounter_num, concept_cd, provider_id, start_date, instance_num'
											ELSE '' END)+'
									FROM (
										SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num ORDER BY patient_num) k
											FROM (
												SELECT DISTINCT f.encounter_num, f.patient_num, f.concept_cd, f.provider_id, f.start_date, f.instance_num
													FROM '+@Schema+'.observation_fact f '+@join_to_temp+'
													WHERE 1=0 ' + @sql + '
											) t
									) t
									WHERE k = '+CAST(@total_item_occurrences AS VARCHAR(50))
			ELSE
				-- Single occurrence
				SELECT @sql = 'SELECT DISTINCT f.patient_num '
									+(CASE	WHEN @panel_timing = 'SAMEVISIT' 
												THEN ', f.encounter_num'
											WHEN @panel_timing = 'SAMEINSTANCENUM'
												THEN ', f.encounter_num, f.concept_cd, f.provider_id, f.start_date, f.instance_num'
											ELSE '' END)+'
									FROM '+@Schema+'.observation_fact f '+@join_to_temp+'
									WHERE 1=0 ' + @sql
		END
		------------------------------------------------------------
		-- Combine panel with other panels
		------------------------------------------------------------
		IF @QueryMethod IN ('MINHASH8') -- AND (1=0)
			SELECT @PanelMaxdop = ' OPTION (MAXDOP 1) '
		ELSE
			SELECT @PanelMaxdop = ''

		SELECT @sql = (CASE WHEN @UseTempListTables = 0
							THEN 'INSERT INTO #QueryCounts (num_patients)
										SELECT COUNT(DISTINCT patient_num)
											FROM ('+@sql+') t' + @PanelMaxdop
								+'; UPDATE #Panels SET actual_count = (SELECT TOP 1 num_patients FROM #QueryCounts)'
							WHEN (@invert = 0) AND (ISNULL(@previous_panel_temp_table,'') <> @panel_temp_table)
							THEN 'INSERT INTO '+@panel_temp_table+' (panels, '+@panel_temp_table_columns+')'
								--+' SELECT 1, '+@panel_temp_table_columns
								+' SELECT '+CAST(@p AS VARCHAR(50))+', '+@panel_temp_table_columns
								+' FROM ('+@sql+') t' + @PanelMaxdop
								+'; UPDATE #Panels SET actual_count = @@ROWCOUNT WHERE process_order = '+CAST(@p AS VARCHAR(50))
								+(CASE	WHEN (@MaxP > @p)
										THEN '; ALTER TABLE '+@panel_temp_table+' ADD PRIMARY KEY (panels, '+@panel_temp_table_columns+')'
										ELSE ''
										END)
							ELSE 'SELECT * INTO #TempList FROM ('+@sql+') t ' + @PanelMaxdop + '; '
								+'UPDATE p '
								+' SET p.panels = '+CAST(@p AS VARCHAR(50))+' '
								+' FROM '+@previous_panel_temp_table+' p'
								+(CASE	WHEN @invert = 1
										THEN ' LEFT OUTER JOIN #TempList t '
										ELSE ' INNER JOIN #TempList t '
										END)
								+' ON p.patient_num = t.patient_num '
								+(CASE	WHEN @panel_timing IN ('SAMEVISIT','SAMEINSTANCENUM')
													AND @previous_panel_temp_table IN ('#EncounterList','#InstanceList')
										THEN ' AND p.encounter_num = t.encounter_num '
										ELSE ''
										END)
								+(CASE	WHEN @panel_timing = 'SAMEINSTANCENUM' AND @previous_panel_temp_table = '#InstanceList'
										THEN ' AND p.concept_cd = t.concept_cd 
												AND p.start_date = t.start_date 
												AND p.instance_num = t.instance_num 
												AND p.provider_id = t.provider_id '
										ELSE ''
										END)
								+'WHERE p.panels = '+CAST((@p-1) AS VARCHAR(50))+' '
								+(CASE	WHEN @invert = 1
										THEN 'AND t.patient_num IS NULL '
										ELSE ''
										END)
								+'; DROP TABLE #TempList'
								+'; UPDATE #Panels SET actual_count = @@ROWCOUNT WHERE process_order = '+CAST(@p AS VARCHAR(50))
							END)

		------------------------------------------------------------
		-- Process the SQL
		------------------------------------------------------------
		-- Run the panel sql
		--insert into dbo.x(s) select @sql
		UPDATE #Panels SET panel_sql = @sql WHERE process_order = @p
		EXEC sp_executesql @sql
		UPDATE #Panels SET run_time_ms = DATEDIFF(ms,@ProcessStartTime,GETDATE()) WHERE process_order = @p
		-- Move to the next panel
		SELECT @p = @p + 1
		SELECT @previous_panel_temp_table = @panel_temp_table
	END

	--insert into dbo.x(x) select 'RT = '+cast(run_time_ms as varchar(50)) from #Panels
	--SELECT 'PL', * FROM #PatientList
	--SELECT 'PP', * FROM #Panels
	--SELECT 'II', * FROM #Items
	--SELECT 'GG', patient_num FROM #GlobalPatientList WHERE query_master_id = 1

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Return the results
	-- ***************************************************************************
	-- ***************************************************************************

	IF (@ReturnPatientCount = 1 OR @ReturnEncounterCount = 1)
	BEGIN
		-- Declare the count variables
		DECLARE @NumPatients INT
		DECLARE @NumEncounters BIGINT
		DECLARE @NumInstances BIGINT
		DECLARE @NumFacts BIGINT
		-- Get values from the #QueryCounts table
		SELECT @NumPatients = num_patients, @NumEncounters = num_encounters, @NumInstances = num_instances, @NumFacts = num_facts
			FROM #QueryCounts
		-- Get number of patients
		IF (@ReturnPatientCount = 1) AND (@NumPatients IS NULL)
		BEGIN
			--insert into dbo.x(x) select 'PTT = '+@panel_temp_table;
			SELECT @NumPatients = (CASE @panel_temp_table
									WHEN '#InstanceList' THEN
										(SELECT COUNT(DISTINCT patient_num) FROM #InstanceList WHERE panels = @MaxP)
									WHEN '#EncounterList' THEN
										(SELECT COUNT(DISTINCT patient_num) FROM #EncounterList WHERE panels = @MaxP)
									ELSE
										(SELECT COUNT(*) FROM #PatientList WHERE panels = @MaxP)
									END)
		END
		-- Get number of encounters
		IF (@ReturnEncounterCount = 1) AND (@NumEncounters IS NULL)
		BEGIN
			SELECT @NumEncounters = (CASE @panel_temp_table
									WHEN '#InstanceList' THEN
										(SELECT COUNT_BIG(*) FROM (SELECT DISTINCT patient_num, encounter_num FROM #InstanceList WHERE panels = @MaxP) t)
									WHEN '#EncounterList' THEN
										(SELECT COUNT_BIG(*) FROM #EncounterList WHERE panels = @MaxP)
									ELSE
										(SELECT COUNT_BIG(*) FROM #PatientList p INNER JOIN ..VISIT_DIMENSION v ON p.patient_num = v.patient_num WHERE panels = @MaxP)
									END)
		END
		-- Adjust counts for sampling
		IF @QueryMethod in ('MINHASH8','MINHASH15')
		BEGIN
			SELECT @SketchPanelQ = @NumPatients
			SELECT @NumPatients = (CASE WHEN @SketchPanelN=0 THEN 0 ELSE floor(@SketchPanelE*(@NumPatients/cast(@SketchPanelN as float))+0.5) END)
			SELECT @SketchPanelM = (CASE WHEN @QueryMethod='MINHASH8' THEN 256 ELSE 32768 END)
		END
		-- Return counts
		INSERT INTO #GlobalQueryCounts (query_master_id, num_patients, num_encounters, num_instances, num_facts, sketch_e, sketch_n, sketch_q, sketch_m)
			SELECT @QueryMasterID, @NumPatients, @NumEncounters, @NumInstances, @NumFacts, @SketchPanelE, @SketchPanelN, @SketchPanelQ, @SketchPanelM

	END

	IF @ReturnPatientList = 1
	BEGIN
		IF @panel_temp_table = '#InstanceList'
			INSERT INTO #GlobalPatientList (query_master_id, patient_num)
				SELECT DISTINCT @QueryMasterID, patient_num FROM #InstanceList WHERE panels = @MaxP
		IF @panel_temp_table = '#EncounterList'
			INSERT INTO #GlobalPatientList (query_master_id, patient_num)
				SELECT DISTINCT @QueryMasterID, patient_num FROM #EncounterList WHERE panels = @MaxP
		IF @panel_temp_table = '#PatientList'
			INSERT INTO #GlobalPatientList (query_master_id, patient_num)
				SELECT @QueryMasterID, patient_num FROM #PatientList WHERE panels = @MaxP
	END

	IF @ReturnEncounterList = 1
	BEGIN
		IF @panel_temp_table = '#InstanceList'
			INSERT INTO #GlobalEncounterList (query_master_id, encounter_num, patient_num)
				SELECT DISTINCT @QueryMasterID, encounter_num, patient_num FROM #InstanceList WHERE panels = @MaxP
		IF @panel_temp_table = '#EncounterList'
			INSERT INTO #GlobalEncounterList (query_master_id, encounter_num, patient_num)
				SELECT @QueryMasterID, encounter_num, patient_num FROM #EncounterList WHERE panels = @MaxP
		IF @panel_temp_table = '#PatientList'
			INSERT INTO #GlobalEncounterList (query_master_id, encounter_num, patient_num)
				SELECT @QueryMasterID, v.encounter_num, v.patient_num 
					FROM #PatientList p INNER JOIN ..VISIT_DIMENSION v 
						ON p.patient_num = v.patient_num 
					WHERE panels = @MaxP
	END

	IF @QueryMasterID < 0
	BEGIN
		SELECT @SQL = 'SELECT f.*
						FROM '+@Schema+'.observation_fact f
							INNER JOIN '+@panel_temp_table+' t
								ON f.patient_num = t.patient_num '
					+(CASE @panel_temp_table
						WHEN '#EncounterList'
							THEN ' AND f.encounter_num = t.encounter_num '
						WHEN '#InstanceList'
							THEN ' AND f.encounter_num = t.encounter_num
								AND f.concept_cd = t.concept_cd 
								AND f.start_date = t.start_date 
								AND f.instance_num = t.instance_num 
								AND f.provider_id = t.provider_id '
						ELSE '' END)
		IF (@panel_temp_table = '#InstanceList') AND (@ReturnTemporalListEnd IS NULL)
			SELECT @SQL = 'SELECT * FROM #InstanceList'
		SELECT @SQL = ';WITH t AS ('+@SQL+') '
			+'INSERT INTO #GlobalTemporalList (subquery_id, patient_num, is_start, the_date) '
			+' SELECT 0, 0, 0, ''1/1/1900'' WHERE 1=0'
			+(CASE @ReturnTemporalListStart
				WHEN 'FIRST'	THEN ' UNION ALL SELECT '+CAST(@QueryMasterID AS VARCHAR(50))+', patient_num, 1, MIN(start_date) FROM t GROUP BY patient_num'
				WHEN 'LAST'		THEN ' UNION ALL SELECT '+CAST(@QueryMasterID AS VARCHAR(50))+', patient_num, 1, MAX(start_date) FROM t GROUP BY patient_num'
				WHEN 'ANY'		THEN ' UNION ALL SELECT DISTINCT '+CAST(@QueryMasterID AS VARCHAR(50))+', patient_num, 1, start_date FROM t'
				ELSE '' END)
			+(CASE @ReturnTemporalListEnd
				WHEN 'FIRST'	THEN ' UNION ALL SELECT '+CAST(@QueryMasterID AS VARCHAR(50))+', patient_num, 0, MIN(end_date) FROM t WHERE end_date IS NOT NULL GROUP BY patient_num'
				WHEN 'LAST'		THEN ' UNION ALL SELECT '+CAST(@QueryMasterID AS VARCHAR(50))+', patient_num, 0, MAX(end_date) FROM t WHERE end_date IS NOT NULL GROUP BY patient_num'
				WHEN 'ANY'		THEN ' UNION ALL SELECT DISTINCT '+CAST(@QueryMasterID AS VARCHAR(50))+', patient_num, 0, end_date FROM t WHERE end_date IS NOT NULL'
				ELSE '' END)
			+'; UPDATE #GlobalSubqueryList SET num_patients = @@ROWCOUNT WHERE subquery_id = '+CAST(@QueryMasterID AS VARCHAR(50))

		EXEC sp_executesql @sql
	END

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Display debugging information
	-- ***************************************************************************
	-- ***************************************************************************

	IF @DebugShowDetails = 1
	BEGIN
		SELECT 'Panels', * FROM #Panels
		SELECT 'Items', * FROM #Items
		SELECT	DateDiff(ms,@QueryStartTime,GetDate()) QueryTimeMS,
				@UseCQ2Tables UseCQ2Tables, 
				@UseCQ2SketchTables UseCQ2SketchTables, 
				@query_timing QueryTiming, 
				@UseTempListTables UseTempListTables,
				@UseEstimatedCountAsActual UseEstimatedCountAsActual,
				@DebugEnablePanelReorder DebugEnablePanelReorder,
				@DebugEnableCQ2Tables DebugEnableCQ2Tables,
				@DebugEnableCQ2PathTables DebugEnableCQ2PathTables,
				@DebugEnableAvoidTempListTables DebugEnableAvoidTempListTables,
				@DebugEnableEstimatedCountAsActual DebugEnableEstimatedCountAsActual
	END

END
GO
