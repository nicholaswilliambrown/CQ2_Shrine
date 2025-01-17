SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ONT].[uspRunOperation]
	@Operation VARCHAR(100),
	@RequestXML XML,
	@RequestType VARCHAR(100) OUTPUT,
	@StatusType NVARCHAR(100) OUTPUT,
	@StatusText NVARCHAR(MAX) OUTPUT,
	@MessageBody NVARCHAR(MAX) OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Declare variables
	DECLARE @Schema VARCHAR(100)
	DECLARE @Username VARCHAR(MAX)
	DECLARE @ProjectID VARCHAR(50)
	DECLARE @OpBody XML

	DECLARE @Type VARCHAR(10)
	DECLARE @Blob BIT
	DECLARE @Synonyms BIT
	DECLARE @Hiddens BIT
	DECLARE @Max INT
	DECLARE @Key VARCHAR(1000)
	DECLARE @Pos INT
	DECLARE @Table VARCHAR(50)
	DECLARE @Path VARCHAR(1000)
	DECLARE @TableName VARCHAR(255)
	DECLARE @TableFullName VARCHAR(1000)
	DECLARE @TableDisplayName VARCHAR(2000)
	DECLARE @AppliedPath VARCHAR(1000)
	DECLARE @AppliedConcept VARCHAR(1000)
	DECLARE @AppliedConceptTable VARCHAR(50)
	DECLARE @AppliedConceptPath VARCHAR(1000)
	DECLARE @HLevel INT
	DECLARE @Strategy VARCHAR(100)
	DECLARE @MatchStr VARCHAR(MAX)

	DECLARE @Items XML

	DECLARE @SQL NVARCHAR(MAX)

	CREATE TABLE #T (
		C_HLEVEL int,
		C_FULLNAME varchar(700),
		C_NAME varchar(2000),
		C_SYNONYM_CD char(1),
		C_VISUALATTRIBUTES char(3),
		C_TOTALNUM int,
		C_BASECODE varchar(50),
		C_METADATAXML text,
		C_FACTTABLECOLUMN varchar(50),
		C_TABLENAME varchar(50),
		C_COLUMNNAME varchar(50),
		C_COLUMNDATATYPE varchar(50),
		C_OPERATOR varchar(10),
		C_DIMCODE varchar(700),
		C_COMMENT text,
		C_TOOLTIP varchar(900),
		M_APPLIED_PATH varchar(700),
		UPDATE_DATE datetime,
		DOWNLOAD_DATE datetime,
		IMPORT_DATE datetime,
		SOURCESYSTEM_CD varchar(50),
		VALUETYPE_CD varchar(50),
		M_EXCLUSION_CD varchar(25),
		C_PATH varchar(700),
		C_SYMBOL varchar(50),
		C_KEY varchar(1000),
		C_KEY_PATH varchar(700),
		C_KEY_NAME varchar(max)
	)

	-- Get the schema
	SELECT @Schema = OBJECT_SCHEMA_NAME(@@PROCID)


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Extract variables from the RequestXML
	-- ***************************************************************************
	-- ***************************************************************************

	-- Extract variables
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as ns3,
		'http://www.i2b2.org/xsd/cell/ont/1.1/' as ns4
	), x AS (
		SELECT	@RequestXML.query('ns3:request[1]/message_header[1]/*') h,
				@RequestXML.query('ns3:request[1]/message_body[1]/*') b
	), y AS (
		SELECT	h,
				(CASE @Operation
					WHEN 'getCategories' THEN b.query('ns4:get_categories[1]')
					WHEN 'getModifiers' THEN b.query('ns4:get_modifiers[1]')
					WHEN 'getChildren' THEN b.query('ns4:get_children[1]')
					WHEN 'getModifierChildren' THEN b.query('ns4:get_modifier_children[1]')
					WHEN 'getTermInfo' THEN b.query('ns4:get_term_info[1]')
					WHEN 'getModifierInfo' THEN b.query('ns4:get_modifier_info[1]')
					WHEN 'getNameInfo' THEN b.query('ns4:get_name_info[1]')
					WHEN 'getModifierNameInfo' THEN b.query('ns4:get_modifier_name_info[1]')
					WHEN 'getCodeInfo' THEN b.query('ns4:get_code_info[1]')
					WHEN 'getModifierCodeInfo' THEN b.query('ns4:get_modifier_code_info[1]')
					WHEN 'getSchemes' THEN b.query('ns4:get_schemes[1]')
					ELSE NULL END) b
		FROM x
	)
	SELECT	@Username =			h.value('security[1]/username[1]','VARCHAR(MAX)'),
			@ProjectID =		h.value('project_id[1]','VARCHAR(50)'),
			@Type =				b.value('*[1]/@type[1]','VARCHAR(10)'),
			@Blob =				HIVE.fnStr2Bit(b.value('*[1]/@blob[1]','VARCHAR(10)')),
			@Synonyms =			HIVE.fnStr2Bit(b.value('*[1]/@synonyms[1]','VARCHAR(10)')),
			@Hiddens =			HIVE.fnStr2Bit(b.value('*[1]/@hiddens[1]','VARCHAR(10)')),
			@Max =				b.value('*[1]/@max[1]','INT'),
			@Key =				(CASE WHEN @Operation IN ('getChildren','getModifierChildren')
										THEN b.value('*[1]/parent[1]','VARCHAR(1000)')
									ELSE b.value('*[1]/self[1]','VARCHAR(1000)') END),
			@AppliedPath =		b.value('*[1]/applied_path[1]','VARCHAR(1000)'),
			@AppliedConcept =	b.value('*[1]/applied_concept[1]','VARCHAR(1000)'),
			@Table =			b.value('*[1]/@category[1]','VARCHAR(100)'),
			@Strategy =			b.value('*[1]/match_str[1]/@strategy[1]','VARCHAR(100)'),
			@MatchStr =			b.value('*[1]/match_str[1]','VARCHAR(MAX)'),
			@OpBody =		b.query('*[1]/*')
	FROM y

	-- Parse the key
	IF @Key IS NOT NULL
	BEGIN
		SELECT @Pos = CHARINDEX('\',@Key,3)
		IF @Pos > 1
			SELECT @Table = SUBSTRING(@Key,3,@Pos-3), @Path = SUBSTRING(@Key,@Pos,LEN(@Key))
	END

	-- Parse the applied concept
	IF @AppliedConcept IS NOT NULL
	BEGIN
		SELECT @Pos = CHARINDEX('\',@AppliedConcept,3)
		IF @Pos > 1
			SELECT @AppliedConceptTable = SUBSTRING(@AppliedConcept,3,@Pos-3), @AppliedConceptPath = SUBSTRING(@AppliedConcept,@Pos,LEN(@AppliedConcept))
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Validate variables
	-- ***************************************************************************
	-- ***************************************************************************

	-- Set default return values
 	SELECT	@StatusType = 'DONE',
 			@StatusText = 'Ontology processing completed'

	-- Validate key
	IF @Operation IN ('getModifiers','getChildren','getModifierChildren','getTermInfo','getModifierInfo','getModifierNameInfo','getModifierCodeInfo')
	BEGIN
		-- Check that a key was provided
		IF @Key IS NULL
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = (CASE WHEN @Operation IN ('getChildren','getModifierChildren')
											THEN 'No parent was provided'
										ELSE 'No self was provided'
										END),
					@MessageBody = NULL
			RETURN
		END

		-- Check that the key was valid
		IF (@Table IS NULL) OR (@Path IS NULL)
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = (CASE WHEN @Operation IN ('getChildren','getModifierChildren')
											THEN 'Invalid parent key'
										ELSE 'Invalid self key'
										END),
					@MessageBody = NULL
			RETURN
		END
	END

	-- Get table name and check table access
	IF @Operation IN ('getModifiers','getChildren','getModifierChildren','getTermInfo','getModifierInfo','getNameInfo','getModifierNameInfo','getModifierCodeInfo')
	BEGIN

		-- Check that a table code is explicitly provided if required for the operation
		IF @Operation IN ('getNameInfo')
			AND @Table IS NULL
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = 'Missing table',
					@MessageBody = NULL
			RETURN
		END

		-- Get table name from the table code
		SELECT @TableName = C_TABLE_NAME, @TableFullName = C_FULLNAME, @TableDisplayName = C_NAME
			FROM ..TABLE_ACCESS 
			WHERE C_TABLE_CD = @Table
				AND (ISNULL(C_PROTECTED_ACCESS,'N') <> 'Y'
					OR HIVE.fnHasUserRole(@ProjectID,@Username,'USER_PROT') = 1)

		-- Confirm the user has access to the table
		IF @TableName IS NULL
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = 'TABLE_ACCESS_DENIED',
					@MessageBody = NULL
			RETURN
		END

	END

	-- Check for the match string
	IF @Operation IN ('getNameInfo','getCodeInfo','getModifierNameInfo','getModifierCodeInfo')
	BEGIN
		IF @MatchStr IS NULL
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = 'Missing match string',
					@MessageBody = NULL
			RETURN
		END
		SELECT @MatchStr = Replace(@MatchStr,'''','''''')
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getCategories [Part 1] (root nodes)
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'getCategories'
	BEGIN
	
		INSERT INTO #T (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_TOOLTIP, C_KEY)
			SELECT C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_FACTTABLECOLUMN, C_TABLE_NAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_TOOLTIP, '\\' + C_TABLE_CD + C_FULLNAME
				FROM ..TABLE_ACCESS
				WHERE (ISNULL(C_PROTECTED_ACCESS,'N') <> 'Y'
					OR HIVE.fnHasUserRole(@ProjectID,@Username,'USER_PROT') = 1)

	END



	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getModifiers [Part 1] (modifiers that apply to terms)
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getModifiers')
	BEGIN
		
		-- Load children into a temp table	
		SELECT @SQL = '
				SELECT C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL
				FROM '+@Schema+'.'+@TableName+'
				WHERE '''+REPLACE(@Path,'''','''''')+''' LIKE M_APPLIED_PATH
					AND C_HLEVEL = 1 
					AND ISNULL(M_EXCLUSION_CD,'''')<>''X''
					AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''I''
					'+(CASE WHEN @Hiddens = 0 THEN 'AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''H''' ELSE '' END)+'
					'+(CASE WHEN @Synonyms = 0 THEN 'AND C_SYNONYM_CD = ''N''' ELSE '' END)+'
					AND C_FULLNAME NOT IN (
						SELECT C_FULLNAME
						FROM '+@Schema+'.'+@TableName+'
						WHERE '''+REPLACE(@Path,'''','''''')+''' LIKE M_APPLIED_PATH
							AND C_HLEVEL = 1 AND ISNULL(M_EXCLUSION_CD,'''')=''X''
					)
			'

		INSERT INTO #T (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
			EXEC sp_executesql @SQL

		UPDATE #T SET C_KEY = '\\' + @Table + C_FULLNAME

	END



	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getChildren [Part 1]
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getChildren','getModifierChildren')
	BEGIN

		-- Load children into a temp table	
		SELECT @SQL = '
				SELECT T.C_HLEVEL, T.C_FULLNAME, T.C_NAME, T.C_SYNONYM_CD, T.C_VISUALATTRIBUTES, T.C_TOTALNUM, T.C_BASECODE, T.C_METADATAXML, T.C_FACTTABLECOLUMN, T.C_TABLENAME, T.C_COLUMNNAME, T.C_COLUMNDATATYPE, T.C_OPERATOR, T.C_DIMCODE, T.C_COMMENT, T.C_TOOLTIP, T.M_APPLIED_PATH, T.UPDATE_DATE, T.DOWNLOAD_DATE, T.IMPORT_DATE, T.SOURCESYSTEM_CD, T.VALUETYPE_CD, T.M_EXCLUSION_CD, T.C_PATH, T.C_SYMBOL
				FROM '+@Schema+'.'+@TableName+' T, (
					SELECT TOP 1 C_HLEVEL, C_FULLNAME
					FROM '+@Schema+'.'+@TableName+'
					WHERE C_FULLNAME = '''+REPLACE(@Path,'''','''''')+'''
				) F
				WHERE T.C_HLEVEL = F.C_HLEVEL+1
					AND T.C_FULLNAME LIKE F.C_FULLNAME+''%''
					AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''I''
					'+(CASE WHEN @Hiddens = 0 THEN 'AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''H''' ELSE '' END)+'
					'+(CASE WHEN @Synonyms = 0 THEN 'AND C_SYNONYM_CD = ''N''' ELSE '' END)+'
					'+(CASE WHEN @Operation = 'getModifierChildren' AND @AppliedPath IS NOT NULL THEN 'AND M_APPLIED_PATH = '''+REPLACE(@AppliedPath,'''','''''')+'''' ELSE '' END)+'
			'

		INSERT INTO #T (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
			EXEC sp_executesql @SQL

		-- Create the key
		UPDATE #T SET C_KEY = '\\' + @Table + C_FULLNAME

		-- Convert leaf nodes to folders if they have modifiers
		SELECT @SQL = '
			UPDATE t
			SET t.C_VISUALATTRIBUTES = ''F''+SUBSTRING(t.C_VISUALATTRIBUTES,2,2)
			FROM #T t
			WHERE LEFT(t.C_VISUALATTRIBUTES,1)=''L''
				AND EXISTS (
					SELECT *
					FROM '+@Schema+'.'+@TableName+' m
					WHERE t.C_FULLNAME LIKE m.M_APPLIED_PATH
						AND m.C_HLEVEL = 1
						AND ISNULL(m.M_EXCLUSION_CD,'''')<>''X''
				)
			'

		EXEC sp_executesql @SQL

	END




	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getTermInfo, getModifierInfo [Part 1] (get details about an item)
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getTermInfo','getModifierInfo')
	BEGIN

		-- Load children into a temp table	
		SELECT @SQL = '
				SELECT C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL
				FROM '+@Schema+'.'+@TableName+'
				WHERE C_FULLNAME = ''' + Replace(@Path,'''','''''') + '''
					AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''I''
					'+(CASE WHEN @Hiddens = 0 THEN 'AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''H''' ELSE '' END)+'
					'+(CASE WHEN @Synonyms = 0 THEN 'AND C_SYNONYM_CD = ''N''' ELSE '' END)+'
					'+(CASE WHEN @Operation = 'getModifierInfo' AND @AppliedPath IS NOT NULL THEN 'AND M_APPLIED_PATH = '''+REPLACE(@AppliedPath,'''','''''')+''' AND ISNULL(M_EXCLUSION_CD,'''')<>''X'' ' ELSE '' END)+'
			'

		INSERT INTO #T (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
			EXEC sp_executesql @SQL

		UPDATE #T SET C_KEY = '\\' + @Table + C_FULLNAME

	END



	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getNameInfo, getModifierNameInfo [Part 1] (search for items by name)
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getNameInfo','getModifierNameInfo')
	BEGIN

		-- Load children into a temp table	
		SELECT @SQL = '
				SELECT C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL
				FROM '+@Schema+'.'+@TableName+'
				WHERE C_FULLNAME LIKE '''+Replace(@TableFullName,'''','''''')+'%''
					AND C_NAME LIKE '+(CASE @Strategy	WHEN 'contains' THEN '''%'+@MatchStr+'%''' 
														WHEN 'exact' THEN ''''+@MatchStr+''''
														WHEN 'right' THEN '''%'+@MatchStr+''''
														ELSE ''''+@MatchStr+'%''' END)+'
					AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''I''
					'+(CASE WHEN @Hiddens = 0 THEN 'AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''H''' ELSE '' END)+'
					'+(CASE WHEN @Synonyms = 0 THEN 'AND C_SYNONYM_CD = ''N''' ELSE '' END)+'
					'+(CASE WHEN @Operation = 'getModifierNameInfo' THEN 'AND '''+REPLACE(@Path,'''','''''')+''' LIKE M_APPLIED_PATH AND ISNULL(M_EXCLUSION_CD,'''')<>''X'' ' ELSE '' END)+'
			'

		INSERT INTO #T (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
			EXEC sp_executesql @SQL

		UPDATE #T 
			SET C_KEY = '\\' + @Table + C_FULLNAME,
				C_KEY_PATH = C_FULLNAME,
				C_KEY_NAME = (CASE WHEN @Operation = 'getNameInfo' THEN '\'+REPLACE(C_NAME,'\','|')+'\' ELSE NULL END)


		IF @Operation = 'getNameInfo'
		BEGIN
			-- Add the parent path names to the front of the key name
			DECLARE @LoopNum INT
			SELECT @LoopNum=0
			WHILE (@LoopNum<20)
			BEGIN
				UPDATE #t
					SET C_KEY_PATH = LEFT(C_KEY_PATH,LEN(C_KEY_PATH)-CHARINDEX('\',REVERSE(C_KEY_PATH),2)+1)
					WHERE C_KEY_PATH LIKE @TableFullName+'_%'
				IF (@@ROWCOUNT=0)
					SELECT @LoopNum=100
				SELECT @SQL = '
					UPDATE t
					SET t.C_KEY_NAME = ''\''+REPLACE(o.C_NAME,''\'',''|'')+t.C_KEY_NAME
					FROM #t t
						INNER JOIN '+@Schema+'.'+@TableName+' o
							ON t.C_KEY_PATH = o.C_FULLNAME
								AND o.M_APPLIED_PATH=''@'' AND o.C_SYNONYM_CD=''N''
					WHERE t.C_KEY_PATH LIKE '''+REPLACE(@TableFullName,'''','''''')+'_%'''
				EXEC sp_executesql @SQL
				SELECT @LoopNum=@LoopNum+1
			END
			-- Add the table display name to the front of the key name
			UPDATE #T
				SET C_KEY_NAME = '\'+REPLACE(@TableDisplayName,'\','|')+C_KEY_NAME
				WHERE C_KEY_PATH = @TableFullName
		END

	END



	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getCodeInfo, getModifierCodeInfo [Part 1] (search for items by code)
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getCodeInfo','getModifierCodeInfo')
	BEGIN

		-- Load matching nodes into a temp table
		SELECT @SQL = ''
		SELECT @SQL = @SQL + (CASE WHEN @SQL = '' THEN '' ELSE ' UNION ALL ' END)
			+ '	SELECT C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL, 
						''\\'+C_TABLE_CD+''' + C_FULLNAME C_KEY
					FROM '+@Schema+'.'+C_TABLE_NAME+'
					WHERE C_BASECODE LIKE '+(CASE @Strategy	WHEN 'contains' THEN '''%'+@MatchStr+'%''' 
															WHEN 'exact' THEN ''''+@MatchStr+''''
															WHEN 'right' THEN '''%'+@MatchStr+''''
															ELSE ''''+@MatchStr+'%''' END)+'
						AND C_FULLNAME LIKE '''+REPLACE(C_FULLNAME,'''','''''')+'%''
						AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''I''
						'+(CASE WHEN @Hiddens = 0 THEN 'AND SUBSTRING(C_VISUALATTRIBUTES,2,1) <> ''H''' ELSE '' END)+'
						'+(CASE WHEN @Synonyms = 0 THEN 'AND C_SYNONYM_CD = ''N''' ELSE '' END)+'
						'+(CASE WHEN @Operation = 'getModifierCodeInfo' THEN 'AND '''+REPLACE(@Path,'''','''''')+''' LIKE M_APPLIED_PATH AND ISNULL(M_EXCLUSION_CD,'''')<>''X'' ' ELSE '' END)+'
				'
			FROM (
				SELECT C_TABLE_CD, C_TABLE_NAME, C_FULLNAME
				FROM ..TABLE_ACCESS
				WHERE C_TABLE_CD = (CASE WHEN @Operation = 'getModifierCodeInfo' THEN @Table ELSE C_TABLE_CD END)
					AND (ISNULL(C_PROTECTED_ACCESS,'N') <> 'Y'
						OR HIVE.fnHasUserRole(@ProjectID,@Username,'USER_PROT') = 1)

			) T

		INSERT INTO #T (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL, C_KEY)
			EXEC sp_executesql @SQL

	END



	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getSchemes
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'getSchemes'
	BEGIN
	
		-- Form MessageBody
		SELECT	@StatusType = 'DONE',
				@StatusText = 'Ontology processing completed',
				@MessageBody = 
					'<message_body>'
					+ '<ns6:concepts>'
					+ ISNULL(CAST((
						SELECT	0 "level",
								C_KEY "key",
								C_NAME "name",
								CAST('<totalnum xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true" />' AS XML),
								(CASE WHEN @Type='core' THEN C_DESCRIPTION ELSE NULL END) "description"
						FROM ..SCHEMES
						ORDER BY C_NAME, C_KEY
						FOR XML PATH('concept'), TYPE
					) AS NVARCHAR(MAX)),'')
					+ '</ns6:concepts>'
					+ '</message_body>'
	END




	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getCategories, getModifiers, getChildren, getModifierChildren,
	-- **** getTermInfo, getModifierInfo, getNameInfo, getModifierNameInfo,
	-- **** getCodeInfo, getModifierCodeInfo [Part 2]
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getCategories', 'getModifiers', 'getChildren', 'getModifierChildren',
						'getTermInfo', 'getModifierInfo', 'getNameInfo', 'getModifierNameInfo', 
						'getCodeInfo', 'getModifierCodeInfo')
	BEGIN

		-- Check that there are not too many children
		IF @Max IS NOT NULL
			IF @Max < (SELECT COUNT(*) FROM #T)
			BEGIN
				SELECT	@StatusType = 'ERROR',
						@StatusText = 'MAX_EXCEEDED',
						@MessageBody = NULL
				RETURN
			END
		

		-- Get each item XML
		SELECT @Items = (
				SELECT	C_HLEVEL "level",
						(CASE WHEN @Operation IN ('getModifiers','getModifierChildren') THEN M_APPLIED_PATH ELSE NULL END) "applied_path",
						REPLACE(REPLACE(REPLACE(C_KEY,'&','&amp;'),'<','&lt;'),'>','&gt;') "key",
						REPLACE(REPLACE(REPLACE(C_KEY_NAME,'&','&amp;'),'<','&lt;'),'>','&gt;') "key_name",
						(CASE WHEN @Operation IN ('getModifiers','getModifierChildren') THEN C_FULLNAME ELSE NULL END) "fullname",
						REPLACE(REPLACE(REPLACE(C_NAME,'&','&amp;'),'<','&lt;'),'>','&gt;') "name",
						C_SYNONYM_CD "synonym_cd",
						C_VISUALATTRIBUTES "visualattributes",
						CASE	WHEN C_TOTALNUM IS NULL
								THEN CAST('<totalnum xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true" />' AS XML)
								ELSE CAST('<totalnum>'+CAST(C_TOTALNUM AS VARCHAR(10))+'</totalnum>' AS XML)
								END,
						REPLACE(REPLACE(REPLACE(C_BASECODE,'&','&amp;'),'<','&lt;'),'>','&gt;') "basecode",
						(CASE WHEN @Blob = 1 THEN REPLACE(CAST(C_METADATAXML AS VARCHAR(MAX)),'<?xml version="1.0"?>','') ELSE NULL END) "metadataxml",
						C_FACTTABLECOLUMN "facttablecolumn",
						C_TABLENAME "tablename",
						C_COLUMNNAME "columnname",
						C_COLUMNDATATYPE "columndatatype",
						REPLACE(REPLACE(REPLACE(C_OPERATOR,'&','&amp;'),'<','&lt;'),'>','&gt;') "operator",
						REPLACE(REPLACE(REPLACE(C_DIMCODE,'&','&amp;'),'<','&lt;'),'>','&gt;') "dimcode",
						(CASE WHEN @Blob = 1 THEN C_COMMENT ELSE NULL END) "comment",
						REPLACE(REPLACE(REPLACE(C_TOOLTIP,'&','&amp;'),'<','&lt;'),'>','&gt;') "tooltip",
						(CASE WHEN @Type = 'all' THEN UPDATE_DATE ELSE NULL END) "update_date",
						(CASE WHEN @Type = 'all' THEN DOWNLOAD_DATE ELSE NULL END)  "download_date",
						(CASE WHEN @Type = 'all' THEN IMPORT_DATE ELSE NULL END)  "import_date",
						(CASE WHEN @Type = 'all' THEN SOURCESYSTEM_CD ELSE NULL END)  "sourcesystem_cd"
				FROM #T
				ORDER BY C_NAME, C_FULLNAME
				FOR XML PATH('concept'), TYPE
			)

		--insert into x(x) select cast(@Items as varchar(max)) from #T

		-- Convert "concept" tag to "modifier" for modifiers
		IF @Operation in ('getModifiers', 'getModifierChildren','getModifierInfo','getModifierNameInfo','getModifierCodeInfo')
		BEGIN
			SELECT @Items = (
				SELECT m.x.query('*')
				FROM @Items.nodes('concept') AS m(x)
				FOR XML PATH('modifier'), TYPE
			)
		END

		-- Form MessageBody
		SELECT	@StatusType = 'DONE',
				@StatusText = 'Ontology processing completed',
				@MessageBody = 
					'<message_body>'
					+ (CASE WHEN @Operation in ('getModifiers', 'getModifierChildren') THEN '<ns6:modifiers>' ELSE '<ns6:concepts>' END)
					+ ISNULL(CAST(@Items AS NVARCHAR(MAX)),'')
					+ (CASE WHEN @Operation in ('getModifiers', 'getModifierChildren') THEN '</ns6:modifiers>' ELSE '</ns6:concepts>' END)
					+ '</message_body>'

	END



END
GO
