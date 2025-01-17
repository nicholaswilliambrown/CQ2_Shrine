SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspRunPDO]
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


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Declare Variables
	-- ***************************************************************************
	-- ***************************************************************************

	-- Declare schema variables
	DECLARE @Schema VARCHAR(100)
	DECLARE @OntSchema VARCHAR(100)

	-- Declare request variables
	DECLARE @DomainID VARCHAR(50)
	DECLARE @Username VARCHAR(50)
	DECLARE @ProjectID VARCHAR(50)
	DECLARE @ResultWaittimeMS BIGINT

	DECLARE @EstimatedTime INT
	DECLARE @PatientSetLimit INT

	-- Request XML wrappers

	DECLARE @PDORequest XML
	DECLARE @InputList XML
	DECLARE @FilterList XML
	--DECLARE @OutputOption XML

	DECLARE @FactPrimaryKey XML
	DECLARE @FactOutputOption XML

	DECLARE @PatientPrimaryKey XML
	DECLARE @PatientOutputOption XML

	-- Input list variables

	DECLARE @InputPatientListMin INT
	DECLARE @InputPatientListMax INT
	DECLARE @InputPatientListSet INT
	DECLARE @InputPatientListAll BIT
	DECLARE @InputPidListMin INT
	DECLARE @InputPidListMax INT

	DECLARE @InputEncounterListMin INT
	DECLARE @InputEncounterListMax INT
	DECLARE @InputEncounterListSet INT
	DECLARE @InputEncounterListAll BIT
	DECLARE @InputEidListMin INT
	DECLARE @InputEidListMax INT

	DECLARE @InputPatientListSize INT
	DECLARE @InputPidListSize INT
	DECLARE @InputEncounterListSize INT
	DECLARE @InputEidListSize INT

	-- Output option variables

	DECLARE @OutputName VARCHAR(50)
	DECLARE @OutputObservationWithModifiers BIT
	DECLARE @OutputObservationFilter VARCHAR(50)
	DECLARE @OutputObservationFilterN INT

	-- Observation key variables

	DECLARE @PrimaryKeyPatientID VARCHAR(200)
	DECLARE @PrimaryKeyPatientNum INT
	DECLARE @PrimaryKeyEventID VARCHAR(200)
	DECLARE @PrimaryKeyEventNum INT

	-- Declare response variables
	DECLARE @Response VARCHAR(MAX)
	DECLARE @ConditionType VARCHAR(100)
	DECLARE @ConditionText VARCHAR(1000)
	
	-- Declare processing variables
	DECLARE @ProcName VARCHAR(100)
	DECLARE @HaltTime DATETIME
	DECLARE @DelayMS FLOAT
	DECLARE @DelayTime VARCHAR(20)

	-- User roles
	DECLARE @HasProtectedAccess BIT
	DECLARE @HasDeidAccess BIT

	-- Additional variables for loops
	DECLARE @p INT
	DECLARE @i INT
	DECLARE @MaxP INT
	DECLARE @MaxI INT

	DECLARE @SQL NVARCHAR(MAX)

	-- Temp tables for input lists

	CREATE TABLE #InputPatientList (
		patient_num INT NOT NULL,
		sort_index INT
	)
	
	CREATE TABLE #InputPidList (
		patient_ide VARCHAR(200) NOT NULL,
		patient_ide_source VARCHAR(50) NOT NULL,
		sort_index INT
	)

	CREATE TABLE #InputEncounterList (
		encounter_num INT NOT NULL,
		sort_index INT
	)

	CREATE TABLE #InputEidList (
		encounter_ide VARCHAR(200) NOT NULL,
		encounter_ide_source VARCHAR(50) NOT NULL,
		sort_index INT
	)

	-- Temp tables for output observation sets

	CREATE TABLE #PanelNames (
		PanelID INT IDENTITY(1,1) PRIMARY KEY,
		PanelName VARCHAR(255),
		PanelXML XML
	)

	CREATE TABLE #ObservationSet (
		PanelID INT NOT NULL,
		encounter_num INT NOT NULL,
		patient_num INT NOT NULL,
		concept_cd VARCHAR(50) NOT NULL,
		provider_id VARCHAR(50) NOT NULL,
		start_date DATETIME NOT NULL,
		modifier_cd VARCHAR(100) NOT NULL,
		instance_num INT NOT NULL
	)

	-- Temp tables for filters

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
		all_concept_paths TINYINT,
		number_of_items INT,
		panel_table VARCHAR(200),
		process_order INT,
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
		modifier_key VARCHAR(900),
		modifier_path VARCHAR(700),
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
		c_totalnum INT,
		valid TINYINT,
		ont_table VARCHAR(255)
	)

	-- Temp tables for output options

	CREATE TABLE #ColumnList (
		PDOSet VARCHAR(100) NOT NULL,
		ColumnName VARCHAR(100) NOT NULL,
		DataTable VARCHAR(100),
		DataColumn VARCHAR(100),
		DataType VARCHAR(50),
		UseExactXML INT,
		IsTechData INT,
		IsBlob INT,
		IsKey INT,
		IsParam INT,
		CodeNameColumn VARCHAR(100),
		SourceColumn VARCHAR(100),
		StatusColumn VARCHAR(100),
		ColumnDescriptor VARCHAR(200),
		SortOrder INT
	)
	ALTER TABLE #ColumnList ADD PRIMARY KEY (PDOSet, ColumnName)

	CREATE TABLE #OutputSetSQL (
		SetID INT IDENTITY(1,1) PRIMARY KEY,
		PDOSet VARCHAR(100),
		selecttype VARCHAR(50),
		onlykeys BIT,
		blob BIT,
		techdata BIT,
		withmodifiers BIT,
		ColumnListSQL NVARCHAR(MAX),
		DataTableSQL NVARCHAR(MAX),
		SetSQL NVARCHAR(MAX),
		SetStr VARCHAR(MAX),
	)

	-- Get the schema
	SELECT @Schema = OBJECT_SCHEMA_NAME(@@PROCID)


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Parse Request Message
	-- ***************************************************************************
	-- ***************************************************************************

	-- Extract variables from the request message
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as ns6,
		'http://www.i2b2.org/xsd/cell/crc/pdo/1.1/' as ns3
	), Wrappers AS (
		SELECT	
			x.query('message_header[1]/*') MessageHeader,
			x.query('request_header[1]/*') RequestHeader,
			x.query('message_body[1]/ns3:pdoheader[1]/*') PDOHeader,
			x.query('message_body[1]/ns3:request[1]/*') PDORequest,
			x.query('message_body[1]/ns3:request[1]/input_list[1]/*') InputList
		FROM @RequestXML.nodes('ns6:request[1]') AS R(x)
	)
	SELECT	-- message_header
			@DomainID = MessageHeader.value('security[1]/domain[1]','varchar(50)'),
			@Username = MessageHeader.value('security[1]/username[1]','VARCHAR(50)'),
			@ProjectID = MessageHeader.value('project_id[1]','VARCHAR(50)'),
			-- request_header
			@ResultWaittimeMS = RequestHeader.value('result_waittime_ms[1]','INT'),
			-- message_body - pdoheader
			@RequestType = PDOHeader.value('request_type[1]','VARCHAR(100)'),
			@EstimatedTime = PDOHeader.value('estimated_time[1]','INT'),
			@PatientSetLimit = PDOHeader.value('patient_set_limit[1]','INT'),
			-- message_body - request
			@PDORequest = PDORequest,
			@InputList = InputList,
			@FilterList = PDORequest.query('filter_list[1]'),
			-- Input List
			@InputPatientListMin = InputList.value('patient_list[1]/@min[1]','INT'),
			@InputPatientListMax = InputList.value('patient_list[1]/@max[1]','INT'),
			@InputPatientListSet = InputList.value('patient_list[1]/patient_set_coll_id[1]','INT'),
			@InputPatientListAll = HIVE.fnStr2Bit(InputList.value('patient_list[1]/entire_patient_set[1]','VARCHAR(10)')),
			@InputPidListMin = InputList.value('pid_list[1]/@min[1]','INT'),
			@InputPidListMax = InputList.value('pid_list[1]/@max[1]','INT'),
			@InputEncounterListMin = InputList.value('event_list[1]/@min[1]','INT'),
			@InputEncounterListMax = InputList.value('event_list[1]/@max[1]','INT'),
			@InputEncounterListSet = InputList.value('event_list[1]/patient_event_coll_id[1]','INT'),
			@InputEncounterListAll = HIVE.fnStr2Bit(InputList.value('input_list[1]/entire_encounter_set[1]','VARCHAR(10)')),
			@InputEidListMin = InputList.value('eid_list[1]/@min[1]','INT'),
			@InputEidListMax = InputList.value('eid_list[1]/@max[1]','INT'),
			-- Output List
			@OutputName = ISNULL(PDORequest.value('output_option[1]/@name[1]','VARCHAR(50)'),'asattributes'),
			@OutputObservationWithModifiers = HIVE.fnStr2BitDefault(PDORequest.value('output_option[1]/observation_set[1]/@withmodifiers[1]','VARCHAR(10)'),1),
			@OutputObservationFilter = PDORequest.value('output_option[1]/observation_set[1]/@selectionfilter[1]','VARCHAR(50)'),
			-- Primary Key
			@PrimaryKeyPatientID = (CASE WHEN @RequestType = 'get_patient_by_primary_key'
											THEN PDORequest.value('patient_primary_key[1]/patient_id[1]','VARCHAR(200)')
										ELSE PDORequest.value('fact_primary_key[1]/patient_id[1]','VARCHAR(200)')
										END),
			@PrimaryKeyEventID = PDORequest.value('fact_primary_key[1]/event_id[1]','VARCHAR(200)')
		FROM Wrappers

	IF @PrimaryKeyPatientID IS NOT NULL
	BEGIN
		SELECT @PrimaryKeyPatientNum = (
			SELECT TOP 1 patient_num
			FROM ..PATIENT_MAPPING
			WHERE patient_ide = @PrimaryKeyPatientID
				AND patient_ide_source = 'HIVE'
				AND project_id = @ProjectID
		)
	END

	IF @PrimaryKeyEventID IS NOT NULL
	BEGIN
		SELECT @PrimaryKeyEventNum = (
			SELECT TOP 1 encounter_num
			FROM ..ENCOUNTER_MAPPING
			WHERE encounter_ide = @PrimaryKeyEventID
				AND encounter_ide_source = 'HIVE'
				AND project_id = @ProjectID
		)
	END

	-- Set default values
 	SELECT	@ResultWaittimeMS = IsNull(@ResultWaittimeMS,180000),
 			@HaltTime = DateAdd(ms,@ResultWaittimeMS,GetDate()),
 			@DelayMS = 100,
			@ConditionType = 'DONE',
 			@ConditionText = 'DONE',
 			@StatusType = 'DONE',
 			@StatusText = 'DONE'


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Security
	-- ***************************************************************************
	-- ***************************************************************************

	IF (IsNull(@Username,'') = '')
	BEGIN
		RETURN;
	END
	
	-- Check for security
	IF HIVE.fnHasUserRole(@ProjectID,@Username,'DATA_LDS')=0
	BEGIN
		-- TODO: Add error handling
		RETURN
	END
	SELECT @HasProtectedAccess = HIVE.fnHasUserRole(@ProjectID,@Username,'DATA_PROT')
	SELECT @HasDeidAccess = HIVE.fnHasUserRole(@ProjectID,@Username,'DATA_DEID')


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Get Input Lists
	-- ***************************************************************************
	-- ***************************************************************************

	IF @RequestType = 'get_patient_by_primary_key'
	BEGIN
		INSERT INTO #InputPatientList (patient_num, sort_index)
			SELECT @PrimaryKeyPatientNum, 1
			WHERE @PrimaryKeyPatientNum IS NOT NULL
	END

	IF @RequestType = 'getPDO_fromInputList'
	BEGIN

		------------------------------------------------------------------------------
		-- Get lists from request message
		------------------------------------------------------------------------------

		-- patient_list
		INSERT INTO #InputPatientList (patient_num, sort_index)
			SELECT p.z.value('.','VARCHAR(200)'), p.z.value('@index[1]','INT')
			FROM @InputList.nodes('patient_list/patient_id') as p(z)
		SELECT @InputPatientListSize = @@ROWCOUNT

		-- pid_list
		INSERT INTO #InputPidList (patient_ide, patient_ide_source, sort_index)
			SELECT p.z.value('.','VARCHAR(200)'), p.z.value('@source[1]','VARCHAR(50)'), p.z.value('@index[1]','INT')
			FROM @InputList.nodes('pid_list/pid') as p(z)
		SELECT @InputPidListSize = @@ROWCOUNT
		ALTER TABLE #InputPidList ADD PRIMARY KEY (patient_ide, patient_ide_source)

		-- encounter_list
		INSERT INTO #InputEncounterList (encounter_num, sort_index)
			SELECT p.z.value('.','VARCHAR(200)'), p.z.value('@index[1]','INT')
			FROM @InputList.nodes('event_list/event_id') as p(z)
		SELECT @InputEncounterListSize = @@ROWCOUNT

		-- eid_list
		INSERT INTO #InputEidList (encounter_ide, encounter_ide_source, sort_index)
			SELECT p.z.value('.','VARCHAR(200)'), p.z.value('@source[1]','VARCHAR(50)'), p.z.value('@index[1]','INT')
			FROM @InputList.nodes('eid_list/eid') as p(z)
		SELECT @InputEidListSize = @@ROWCOUNT
		ALTER TABLE #InputEidList ADD PRIMARY KEY (encounter_ide, encounter_ide_source)

		------------------------------------------------------------------------------
		-- Get the final input patient list
		------------------------------------------------------------------------------

		IF (@InputPatientListSize = 0) AND (@InputPatientListSet IS NOT NULL)
		BEGIN
			INSERT INTO #InputPatientList (patient_num, sort_index)
				SELECT patient_num, ROW_NUMBER() OVER (ORDER BY set_index, patient_num) sort_index
				FROM ..QT_PATIENT_SET_COLLECTION
				WHERE result_instance_id = @InputPatientListSet
			SELECT @InputPatientListSize = @@ROWCOUNT
		END

		IF (@InputPatientListSize = 0) AND (@InputPatientListAll = 1)
		BEGIN
			INSERT INTO #InputPatientList (patient_num, sort_index)
				SELECT patient_num, sort_index
				FROM (
					SELECT patient_num, ROW_NUMBER() OVER (ORDER BY patient_num) sort_index
					FROM ..PATIENT_DIMENSION
				) t
			SELECT @InputPatientListSize = @@ROWCOUNT
		END
	
		IF @InputPatientListMin IS NOT NULL
			DELETE FROM #InputPatientList WHERE sort_index < @InputPatientListMin
		IF @InputPatientListMax IS NOT NULL
			DELETE FROM #InputPatientList WHERE sort_index > @InputPatientListMax

		IF (@InputPatientListSize = 0) AND (@InputPidListSize IS NOT NULL)
		BEGIN
			INSERT INTO #InputPatientList (patient_num, sort_index)
				SELECT patient_num, sort_index
				FROM (
					SELECT patient_num, ROW_NUMBER() OVER (ORDER BY sort_index) sort_index
					FROM (
						SELECT m.patient_num, MIN(i.sort_index) sort_index
						FROM ..PATIENT_MAPPING m
							INNER JOIN #InputPidList i
								ON m.patient_ide = i.patient_ide AND m.patient_ide_source = i.patient_ide_source
						GROUP BY m.patient_num
					) t
				) i
				WHERE i.sort_index >= ISNULL(@InputPidListMin,i.sort_index)
					AND i.sort_index <= ISNULL(@InputPidListMax,i.sort_index)
		END

		------------------------------------------------------------------------------
		-- Get the final input encounter list
		------------------------------------------------------------------------------

		IF (@InputEncounterListSize = 0) AND (@InputEncounterListSet IS NOT NULL)
		BEGIN
			INSERT INTO #InputEncounterList (encounter_num, sort_index)
				SELECT encounter_num, ROW_NUMBER() OVER (ORDER BY set_index, encounter_num) sort_index
				FROM ..QT_PATIENT_ENC_COLLECTION
				WHERE result_instance_id = @InputEncounterListSet
			SELECT @InputEncounterListSize = @@ROWCOUNT
		END

		IF (@InputEncounterListSize = 0) AND (@InputEncounterListAll = 1)
		BEGIN
			INSERT INTO #InputEncounterList (encounter_num, sort_index)
				SELECT encounter_num, sort_index
				FROM (
					SELECT encounter_num, ROW_NUMBER() OVER (ORDER BY encounter_num) sort_index
					FROM ..VISIT_DIMENSION
				) t
			SELECT @InputEncounterListSize = @@ROWCOUNT
		END
	
		IF @InputEncounterListMin IS NOT NULL
			DELETE FROM #InputEncounterList WHERE sort_index < @InputEncounterListMin
		IF @InputEncounterListMax IS NOT NULL
			DELETE FROM #InputEncounterList WHERE sort_index > @InputEncounterListMax

		IF (@InputEncounterListSize = 0) AND (@InputEidListSize IS NOT NULL)
		BEGIN
			INSERT INTO #InputEncounterList (encounter_num, sort_index)
				SELECT encounter_num, sort_index
				FROM (
					SELECT encounter_num, ROW_NUMBER() OVER (ORDER BY sort_index) sort_index
					FROM (
						SELECT m.encounter_num, MIN(i.sort_index) sort_index
						FROM ..ENCOUNTER_MAPPING m
							INNER JOIN #InputEidList i
								ON m.encounter_ide = i.encounter_ide AND m.encounter_ide_source = i.encounter_ide_source
						GROUP BY m.encounter_num
					) t
				) i
				WHERE i.sort_index >= ISNULL(@InputEidListMin,i.sort_index)
					AND i.sort_index <= ISNULL(@InputEidListMax,i.sort_index)
		END

	END -- @RequestType = 'getPDO_fromInputList'

	ALTER TABLE #InputPatientList ADD PRIMARY KEY (patient_num)
	SELECT @InputPatientListSize = (SELECT COUNT(*) FROM #InputPatientList)

	ALTER TABLE #InputEncounterList ADD PRIMARY KEY (encounter_num)
	SELECT @InputEncounterListSize = (SELECT COUNT(*) FROM #InputEncounterList)

	--insert into dbo.x(x) select 'IELSet = '+isnull(cast(@InputEncounterListSet as varchar(50)),'')
	--insert into dbo.x(x) select 'IELSize = '+isnull(cast(@InputEncounterListSize as varchar(50)),'')

	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Get Observation Sets
	-- ***************************************************************************
	-- ***************************************************************************

	IF @RequestType = 'get_observationfact_by_primary_key'
	BEGIN
		INSERT INTO #PanelNames (PanelName)
			SELECT NULL PanelName

		SELECT @SQL = '
			INSERT INTO #ObservationSet (PanelID,encounter_num,patient_num,concept_cd,provider_id,start_date,modifier_cd,instance_num)
				SELECT TOP(1) 1 PanelID,encounter_num,patient_num,concept_cd,provider_id,start_date,modifier_cd,instance_num
				FROM '+@Schema+'.OBSERVATION_FACT
				WHERE 1=1
			'
			+ ISNULL(' AND encounter_num = '+CAST(@PrimaryKeyEventNum AS VARCHAR(50)), '')
			+ ISNULL(' AND patient_num = '+CAST(@PrimaryKeyPatientNum AS VARCHAR(50)), '')
			+ ISNULL(' AND concept_cd = '''+REPLACE(x.value('fact_primary_key[1]/concept_cd[1]','VARCHAR(50)'),'''','''''')+'''', '')
			+ ISNULL(' AND provider_id = '''+REPLACE(x.value('fact_primary_key[1]/observer_id[1]','VARCHAR(50)'),'''','''''')+'''', '')
			+ ISNULL(' AND start_date = '''+CAST(x.value('fact_primary_key[1]/start_date[1]','DATETIME') AS VARCHAR(50))+'''', '')
			+ ISNULL(' AND modifier_cd = '''+REPLACE(x.value('fact_primary_key[1]/modifier_cd[1]','VARCHAR(100)'),'''','''''')+'''', '')
			+ ISNULL(' AND instance_num = '+CAST(x.value('fact_primary_key[1]/instance_num[1]','INT') AS VARCHAR(50)), '')
			+ ' ORDER BY encounter_num, concept_cd, provider_id, start_date, instance_num, (CASE WHEN modifier_cd = ''@'' THEN 0 ELSE 1 END), modifier_cd'
			FROM (SELECT @PDORequest.query('patient_primary_key[1]') x) t

		EXEC sp_executesql @SQL
	END

	IF @RequestType = 'getPDO_fromInputList'
	BEGIN

		-- Get panels from filter list
		INSERT INTO #PanelNames (PanelName, PanelXML)
			SELECT P.x.value('@name','VARCHAR(255)') PanelName, P.x.query('.') PanelXML
			FROM @FilterList.nodes('filter_list[1]/panel') as P(x)

		-- Get panel-level information
		INSERT INTO #Panels (panel_number, panel_date_from, panel_date_to, panel_accuracy_scale, invert, panel_timing, total_item_occurrences, items,
								estimated_count, has_date_constraint, has_value_constraint)
			SELECT	P.PanelID,
					P.x.value('panel_date_from[1]','DATETIME'),
					P.x.value('panel_date_to[1]','DATETIME'),
					P.x.value('panel_accuracy_scale[1]','INT'),
					P.x.value('invert[1]','TINYINT'),
					P.x.value('panel_timing[1]','VARCHAR(100)'),
					P.x.value('total_item_occurrences[1]','INT'),
					P.x.query('item'),
					0, 0, 0
			FROM (SELECT PanelID, PanelXML.query('panel[1]/*') x FROM #PanelNames) P

		-- Get item-level information
		INSERT INTO #Items (panel_number, item_key, modifier_key, value_constraint, value_operator, value_unit_of_measure, value_type, valid)
			SELECT	p.panel_number,
					I.x.value('item_key[1]','VARCHAR(900)'),
					I.x.value('constrain_by_modifier[1]/modifier_key[1]','VARCHAR(900)'),
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
		UPDATE #Items
			SET item_type = (CASE WHEN item_key LIKE '\\%\%' THEN 'concept'
								WHEN item_key LIKE 'masterid:%' THEN 'masterid'
								WHEN item_key LIKE 'patient_set_coll_id:%' THEN 'patient_set_coll_id'
								ELSE NULL END)
		UPDATE #Items
			SET item_key_id = SUBSTRING(item_key,LEN(item_type)+2,LEN(item_key))
			WHERE (item_type IS NOT NULL) AND (item_type <> 'concept')
		UPDATE #Items
			SET	item_table = SUBSTRING(item_key,3,CHARINDEX('\',item_key,3)-3),
				item_path = SUBSTRING(item_key,CHARINDEX('\',item_key,3),700),
				modifier_path = SUBSTRING(modifier_key,CHARINDEX('\',modifier_key,3),700)
			WHERE item_type = 'concept'

		-- Get the ontology cell schema
		EXEC [HIVE].[uspGetCellSchema]	@Service = 'OntologyService',
										@DomainID = @DomainID,
										@UserID = @Username,
										@ProjectID = @ProjectID,
										@CellSchema = @OntSchema OUTPUT

		-- Get item details from ontology tables
		SELECT @i = 1, @MaxI = IsNull((SELECT MAX(item_id) FROM #Items),0)
		WHILE @i <= @MaxI
		BEGIN
			IF EXISTS (SELECT * FROM #Items WHERE item_id = @i AND item_type = 'concept')
			BEGIN
				SELECT @sql = 'UPDATE i
								SET i.ont_table = '''+REPLACE(@OntSchema,'''','''''')+'.''+t.c_table_name
								FROM #Items i, '+@OntSchema+'.TABLE_ACCESS t
								WHERE i.item_id = '+CAST(@i AS VARCHAR(50))+' 
									AND i.item_table = t.c_table_cd
								'
								+(CASE WHEN @HasProtectedAccess=1 THEN '' ELSE 'AND ISNULL(C_PROTECTED_ACCESS,''N'') <> ''Y''' END)
				EXEC sp_executesql @sql
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
			END
			SELECT @i = @i + 1
		END

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

		-- Only concepts are handled by a PDO query
		DELETE
			FROM #Items
			WHERE ISNULL(item_type,'')<>'concept'

		-- Confirm user has permissions to access items
		IF EXISTS (SELECT * FROM #Items WHERE IsNull(valid,0) = 0)
		BEGIN
			SELECT 'ERROR' Error, * FROM #Items WHERE IsNull(valid,0) = 0
			--ToDo: Set error status
			RETURN
		END

		-- Only concepts from the concept dimension are handled by a PDO query
		DELETE
			FROM #Items
			WHERE c_tablename<>'CONCEPT_DIMENSION'

		-- Run the panels in order
		UPDATE #Panels SET process_order = panel_number

		-- Parse the selection filter
		IF @OutputObservationFilter LIKE 'last_%_values'
		BEGIN
			SELECT @OutputObservationFilter = 'last_n_values', @OutputObservationFilterN = N
			FROM (
				SELECT CAST(N AS INT) N
				FROM (SELECT SUBSTRING(@OutputObservationFilter,6,LEN(@OutputObservationFilter)-12) N) t
				WHERE ISNUMERIC(N)=1
			) t
		END

		-- Run each panel
		SELECT @p = 1, @MaxP = IsNull((SELECT MAX(process_order) FROM #Panels),0)
		WHILE @p <= @MaxP
		BEGIN
			-- Initialize panel SQL
			SELECT @sql = ''
			-- Handle item constraints
			SELECT @sql = @sql 
				+' OR ('
				+'	f.'+i.c_facttablecolumn+' IN ('
				+'	SELECT '+i.c_facttablecolumn
				+'		FROM '+@Schema+'.'+i.c_tablename+' t'
				+'		WHERE t.'+i.c_columnname+' '+i.c_operator+' '+i.c_dimcode
				+'	)'
				+(CASE	WHEN IsNull(i.modifier_path,'') <> ''
							THEN ' AND f.modifier_cd IN (
										SELECT modifier_cd 
										FROM '+@Schema+'.modifier_dimension 
										WHERE modifier_path LIKE '''+REPLACE(i.modifier_path,'''','''''')+'%''
									)'
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
				+(CASE	WHEN p.panel_date_from IS NOT NULL
							THEN ' AND f.start_date >= ''' + CAST(p.panel_date_from AS VARCHAR(50)) + ''''
						ELSE '' END)
				+(CASE	WHEN p.panel_date_to IS NOT NULL
							THEN ' AND f.start_date <= ''' + CAST(p.panel_date_to AS VARCHAR(50)) + ''''
						ELSE '' END)
				+')'
				FROM #Panels p, #Items i
				WHERE p.process_order = @p AND p.panel_number = i.panel_number
			-- Join to the input lists
			SELECT @sql =
				'SELECT f.*'
				+' FROM '+@Schema+'.OBSERVATION_FACT f'
				+(CASE WHEN @InputPatientListSize > 0 THEN ' INNER JOIN #InputPatientList i ON f.patient_num = i.patient_num' ELSE '' END)
				+(CASE WHEN @InputPatientListSize = 0 AND @InputEncounterListSize > 0 THEN ' INNER JOIN #InputEncounterList i ON f.encounter_num = i.encounter_num' ELSE '' END)
				+' WHERE 1=0'
				+@sql
			-- Restrict to observations with modifiers
			IF @OutputObservationWithModifiers = 0
				SELECT @sql = 'SELECT * FROM ('+@sql+') t WHERE modifier_cd = ''@'''
			-- Handle the selection filter
			SELECT @sql = (
				CASE @OutputObservationFilter
					WHEN 'min_value' THEN 'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num, concept_cd ORDER BY (CASE WHEN modifier_cd=''@'' THEN 0 ELSE 1 END), nval_num) k FROM ('+@sql+') t) t WHERE k = 1'
					WHEN 'max_value' THEN 'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num, concept_cd ORDER BY (CASE WHEN modifier_cd=''@'' THEN 0 ELSE 1 END), nval_num DESC) k FROM ('+@sql+') t) t WHERE k = 1'
					WHEN 'first_value' THEN 'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num, concept_cd ORDER BY (CASE WHEN modifier_cd=''@'' THEN 0 ELSE 1 END), start_date) k FROM ('+@sql+') t) t WHERE k = 1'
					WHEN 'last_value' THEN 'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num, concept_cd ORDER BY (CASE WHEN modifier_cd=''@'' THEN 0 ELSE 1 END), start_date DESC) k FROM ('+@sql+') t) t WHERE k = 1'
					WHEN 'single_observation' THEN 'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num, concept_cd ORDER BY (CASE WHEN modifier_cd=''@'' THEN 0 ELSE 1 END), start_date) k FROM ('+@sql+') t) t WHERE k = 1'
					WHEN 'last_n_values' THEN 'SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY patient_num, concept_cd ORDER BY (CASE WHEN modifier_cd=''@'' THEN 0 ELSE 1 END), start_date DESC) k FROM ('+@sql+') t) t WHERE k <= ' + CAST(@OutputObservationFilterN AS VARCHAR(50))
					ELSE @sql END
				)
			-- Save the results to the observation set temp table
			SELECT @sql =
				'INSERT INTO #ObservationSet (PanelID,encounter_num,patient_num,concept_cd,provider_id,start_date,modifier_cd,instance_num)'
				+' SELECT '+CAST(@p AS VARCHAR(50))+', encounter_num,patient_num,concept_cd,provider_id,start_date,modifier_cd,instance_num'
				+' FROM ('+@sql+') t'

			-- Run the panel sql
			--insert into dbo.x(x) select 'SQL = '+@sql
			UPDATE #Panels SET panel_sql = @sql WHERE process_order = @p
			EXEC sp_executesql @sql

			-- Move to the next panel
			SELECT @p = @p + 1
		END

	END

	ALTER TABLE #ObservationSet ADD PRIMARY KEY (PanelID, encounter_num, concept_cd, provider_id, start_date, modifier_cd, instance_num)


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Generate Output XML Sets
	-- ***************************************************************************
	-- ***************************************************************************

	-- Get all the output options
	;WITH XMLNAMESPACES (
		'http://www.i2b2.org/xsd/hive/msg/1.1/' as ns6,
		'http://www.i2b2.org/xsd/cell/crc/pdo/1.1/' as ns3
	), Options AS (
		SELECT 'patient' PDOSet, 'using_patient_list' selecttype, 0 onlykeysdefault, x.query('.') x
			FROM @RequestXML.nodes('ns6:request[1]/message_body[1]/ns3:request[1]/patient_output_option[1]') AS R(x)
			WHERE @RequestType = 'get_patient_by_primary_key'
		UNION ALL
		SELECT 'observation' PDOSet, 'using_filter_list' selecttype, 0 onlykeysdefault, x.query('.') x
			FROM @RequestXML.nodes('ns6:request[1]/message_body[1]/ns3:request[1]/fact_output_option[1]') AS R(x)
			WHERE @RequestType = 'get_observationfact_by_primary_key'
		UNION ALL
		SELECT	LEFT(PDOTag,CHARINDEX('_set',PDOTag)-1) PDOSet,
				ISNULL(x.value('@select','varchar(50)'),'using_filter_list') selecttype,
				1 onlykeysdefault, 
				x.query('.') x
			FROM @RequestXML.nodes('ns6:request[1]/message_body[1]/ns3:request[1]/output_option[1]/*') AS R(x)
				CROSS APPLY (SELECT R.x.value('local-name(.[1])','varchar(100)') PDOTag) AS S
			WHERE @RequestType = 'getPDO_fromInputList'
	)
	INSERT INTO #OutputSetSQL (PDOSet, selecttype, onlykeys, blob, techdata, withmodifiers)
		SELECT PDOSet, selecttype,
			ISNULL(HIVE.fnStr2Bit(x.value('*[1]/@onlykeys','varchar(10)')),onlykeysdefault) onlykeys,
			(@HasDeidAccess & HIVE.fnStr2Bit(x.value('*[1]/@blob','varchar(10)'))) blob,
			(@HasDeidAccess & HIVE.fnStr2Bit(x.value('*[1]/@techdata','varchar(10)'))) techdata,
			HIVE.fnStr2Bit(x.value('*[1]/@withmodifiers','varchar(10)')) withmodifiers
		FROM Options

	-- Create a list of all output columns and attributes
	;WITH PDOSets AS (
		SELECT '' PDOSet, '' DataTable WHERE 1=0
		UNION ALL SELECT 'concept', 'CONCEPT_DIMENSION'
		UNION ALL SELECT 'eid', 'ENCOUNTER_MAPPING'
		UNION ALL SELECT 'event', 'VISIT_DIMENSION'
		UNION ALL SELECT 'modifier', 'MODIFIER_DIMENSION'
		UNION ALL SELECT 'observation', 'OBSERVATION_FACT'
		UNION ALL SELECT 'observer', 'PROVIDER_DIMENSION'
		UNION ALL SELECT 'patient', 'PATIENT_DIMENSION'
		UNION ALL SELECT 'pid', 'PATIENT_MAPPING'
	), ColumnNames AS (
		SELECT '' PDOSet, '' DataColumn, '' ColumnName WHERE 1=0
		UNION ALL SELECT 'eid','ENCOUNTER_IDE','event_id'
		UNION ALL SELECT 'event','ENCOUNTER_NUM','event_id'
		UNION ALL SELECT 'event','PATIENT_NUM','patient_id'
		UNION ALL SELECT 'observation','ENCOUNTER_NUM','event_id'
		UNION ALL SELECT 'observation','PATIENT_NUM','patient_id'
		UNION ALL SELECT 'observation','PROVIDER_ID','observer_cd'
		UNION ALL SELECT 'observer','PROVIDER_ID','observer_cd'
		UNION ALL SELECT 'observer','PROVIDER_PATH','observer_path'
		UNION ALL SELECT 'patient','PATIENT_NUM','patient_id'
		UNION ALL SELECT 'pid','PATIENT_IDE','patient_id'
	), ColumnDescriptors AS (
		SELECT '' PDOSet, '' ColumnName, '' ColumnDescriptor WHERE 1=0
		UNION ALL SELECT 'event','active_status_cd','Date accuracy code'
		UNION ALL SELECT 'event','start_date','Start Date'
		UNION ALL SELECT 'event','end_date','End Date'
		UNION ALL SELECT 'event','inout_cd','Inpatient/Outpatient code'
		UNION ALL SELECT 'event','location_cd','Location'
		UNION ALL SELECT 'event','location_path','Location hierarchy'
		UNION ALL SELECT 'event','length_of_stay','Length of Stay'
		UNION ALL SELECT 'event','visit_blob','Visit Blob'
		UNION ALL SELECT 'patient','vital_status_cd','Date Accuracy Code'
		UNION ALL SELECT 'patient','birth_date','Birth Date'
		UNION ALL SELECT 'patient','death_date','Death Date'
		UNION ALL SELECT 'patient','sex_cd','Gender'
		UNION ALL SELECT 'patient','age_in_years_num','Age'
		UNION ALL SELECT 'patient','language_cd','Language'
		UNION ALL SELECT 'patient','race_cd','Race'
		UNION ALL SELECT 'patient','marital_status_cd','Marital Status'
		UNION ALL SELECT 'patient','religion_cd','Religion'
		UNION ALL SELECT 'patient','zip_cd','Zip Code'
		UNION ALL SELECT 'patient','statecityzip_path','Zip Code Hierarchy'
		UNION ALL SELECT 'patient','income_cd','Income'
		UNION ALL SELECT 'patient','patient_blob','Patient Blob'
	), ColumnList1 AS (
		SELECT p.PDOSet, ISNULL(CAST(n.ColumnName AS VARCHAR(50)),LOWER(c.column_name)) ColumnName, 
			p.DataTable, c.column_name DataColumn, c.ordinal_position, c.data_type
		FROM INFORMATION_SCHEMA.COLUMNS c
			INNER JOIN PDOSets p
				ON c.TABLE_NAME = p.DataTable AND c.TABLE_SCHEMA = @Schema 
			LEFT OUTER JOIN ColumnNames n
				ON p.PDOSet = n.PDOSet AND c.column_Name = n.DataColumn
		-- exclude columns
		WHERE
			NOT (	(p.PDOSet = 'eid' AND c.column_name IN ('ENCOUNTER_NUM','ENCOUNTER_IDE_SOURCE','ENCOUNTER_IDE_STATUS','PATIENT_IDE','PATIENT_IDE_SOURCE','PROJECT_ID'))
				OR	(p.PDOSet = 'pid' AND c.column_name IN ('PATIENT_NUM','PATIENT_IDE_SOURCE','PATIENT_IDE_STATUS','PROJECT_ID'))
			)
		-- add columns
		UNION ALL SELECT 'eid', 'event_map_id', NULL, 'event_map_id', 100, 'varchar'
		UNION ALL SELECT 'pid', 'patient_map_id', NULL, 'patient_map_id', 100, 'varchar'
	), ColumnList2 AS (
		SELECT PDOSet, ColumnName, DataTable, DataColumn, ordinal_position,
			(CASE	WHEN data_type IN ('date','datetime') THEN 'dateTime'
					WHEN data_type IN ('int','bigint','tinyint') THEN 'int'
					WHEN data_type IN ('decimal','numeric','float','real') THEN 'decimal'
					ELSE 'string' END) DataType,
			(CASE	WHEN PDOSet = 'eid' AND ColumnName IN ('event_map_id') THEN 1
					WHEN PDOSet = 'pid' AND ColumnName IN ('patient_map_id') THEN 1
					ELSE 0 END) UseExactXML,
			(CASE	WHEN ColumnName IN ('download_date','import_date','sourcesystem_cd','update_date','upload_date','upload_id') THEN 1
					ELSE 0 END) IsTechData,
			(CASE	WHEN ColumnName LIKE '%BLOB' THEN 1 ELSE 0 END) IsBlob,
			(CASE	WHEN PDOSet = 'concept' AND ColumnName IN ('concept_cd','concept_path') THEN 1
					WHEN PDOSet = 'eid' AND ColumnName IN ('encounter_ide') THEN 1
					WHEN PDOSet = 'event' AND ColumnName IN ('event_id','patient_id') THEN 1
					WHEN PDOSet = 'modifier' AND ColumnName IN ('modifier_cd','modifier_path') THEN 1
					WHEN PDOSet = 'observation' AND ColumnName IN ('event_id','patient_id','concept_cd','observer_cd','start_date','modifier_cd','instance_num') THEN 1
					WHEN PDOSet = 'observer' AND ColumnName IN ('provider_id','provider_path') THEN 1
					WHEN PDOSet = 'patient' AND ColumnName IN ('patient_id') THEN 1
					WHEN PDOSet = 'pid' AND ColumnName IN ('patient_ide') THEN 1
					ELSE 0 END) IsKey,
			(CASE	WHEN PDOSet = 'observation' AND ColumnName = 'concept_cd' THEN 'concept_name_char'
					WHEN PDOSet = 'observation' AND ColumnName = 'modifier_cd' THEN 'modifier_name_char'
					WHEN PDOSet = 'observation' AND ColumnName = 'observer_cd' THEN 'provider_name_char'
					ELSE NULL END) CodeNameColumn
		FROM ColumnList1
	)
	INSERT INTO #ColumnList (PDOSet, ColumnName, DataTable, DataColumn, DataType, 
					UseExactXML, IsTechData, IsBlob, IsKey, IsParam, CodeNameColumn,
					ColumnDescriptor, SortOrder)
		SELECT c.PDOSet, c.ColumnName, DataTable, DataColumn, DataType, 
			UseExactXML, IsTechData, IsBlob, IsKey, IsParam, CodeNameColumn,
			ISNULL(l.name_char,d.ColumnDescriptor) ColumnDescriptor,
			ROW_NUMBER() OVER (PARTITION BY c.PDOSet ORDER BY (CASE WHEN IsParam=1 THEN 1 WHEN IsTechData=1 THEN 2 ELSE 0 END), ordinal_position) SortOrder
		FROM ColumnList2 c
			LEFT OUTER JOIN ColumnDescriptors d ON c.PDOSet = d.PDOSet AND c.ColumnName = d.ColumnName
			LEFT OUTER JOIN ..CODE_LOOKUP l
				ON c.DataTable = l.table_cd AND c.DataColumn = l.column_cd AND l.code_cd = 'crc_column_descriptor'
			CROSS APPLY (
				SELECT (CASE	WHEN (c.PDOSet = 'patient') AND (IsTechData+IsKey = 0) THEN 1
								WHEN (c.PDOSet = 'event') AND (IsTechData+IsKey = 0) AND (c.ColumnName NOT IN ('patient_id','start_date','end_date')) THEN 1
								ELSE 0 END) IsParam
				) p

	-- Testing
	-- SELECT * FROM #ColumnList

	-- Generate the SQL for each output set [Part 1]
	UPDATE o
		SET o.ColumnListSQL =
			(CASE WHEN (o.PDOSet NOT IN ('eid','pid')) AND (o.TechData=1) THEN 
					'update_date "@update_date", '
					+'download_date "@download_date", '
					+'import_date "@import_date", '
					+'sourcesystem_cd "@sourcesystem_cd", '
					+'upload_id "@upload_id", '
				ELSE '' END)
			+(SELECT (CASE WHEN (m.IsKey=1 OR o.OnlyKeys=0)
							AND (m.IsBlob=0 OR o.Blob=1)
							AND (m.IsTechData=0 OR o.TechData=1)
						THEN
							(CASE 
								WHEN m.UseExactXML = 1 THEN ''
									+m.DataColumn+'.query(''*''), '
								WHEN m.IsParam = 1 THEN ''
									+''''+m.DataType+''' "param/@type", '
									+ISNULL(''''+m.ColumnDescriptor+''' "param/@column_descriptor", ','')
									+ISNULL(''''+m.ColumnName+''' "param/@column", ','')
									+m.DataColumn+' "param", '
								WHEN m.ColumnName IN ('event_id','patient_id') THEN ''
									+(CASE m.PDOSet
										WHEN 'event' THEN '''i2b2'' "'+m.ColumnName+'/@source", '
										WHEN 'observation' THEN '''HIVE'' "'+m.ColumnName+'/@source", '
										WHEN 'patient' THEN '''i2b2'' "'+m.ColumnName+'/@source", '
										WHEN 'eid' THEN
											'patient_ide_source "event_id/@patient_id_source", '
											+'patient_ide "event_id/@patient_id", '
											+'encounter_ide_source "event_id/@source", '
										WHEN 'pid' THEN
											(CASE WHEN o.TechData=1 THEN 
												'upload_date "patient_id/@upload_date", '
												+'update_date "patient_id/@update_date", '
												+'download_date "patient_id/@download_date", '
												+'import_date "patient_id/@import_date", '
												+'sourcesystem_cd "patient_id/@sourcesystem_cd", '
												+'upload_id "patient_id/@upload_id", '
											ELSE '' END)
											+'patient_ide_status "patient_id/@status", '
											+'patient_ide_source "patient_id/@source", '
										ELSE '' END)
									+m.DataColumn+' "'+m.ColumnName+'", '
								ELSE '' 
									+(CASE WHEN @OutputName<>'none' THEN ISNULL(m.CodeNameColumn+' "'+m.ColumnName+'/@name", ','') ELSE '' END)
									+m.DataColumn+' "'+m.ColumnName+'", '
								END)
							+''''','
						ELSE '' END)
				FROM #ColumnList m
				WHERE m.PDOSet = o.PDOSet AND m.IsTechData = 0
				ORDER BY m.SortOrder
				FOR XML PATH(''), TYPE
			).value('.','VARCHAR(MAX)')+'''''',
		DataTableSQL = 
			(CASE selecttype
				WHEN 'using_input_list'
					THEN (CASE PDOSet
						WHEN 'patient' THEN 'SELECT patient_num, sort_index FROM #InputPatientList'
						WHEN 'event' THEN 'SELECT encounter_num, sort_index FROM #InputEncounterList'
						WHEN 'pid' THEN 'SELECT patient_num, sort_index FROM #InputPatientList'
						WHEN 'eid' THEN 'SELECT encounter_num, sort_index FROM #InputEncounterList'
						ELSE NULL END)
				WHEN 'using_filter_list'
					THEN (CASE PDOSet
						WHEN 'patient' THEN 'SELECT DISTINCT patient_num, NULL sort_index FROM #ObservationSet'
						WHEN 'event' THEN 'SELECT DISTINCT encounter_num, NULL sort_index FROM #ObservationSet'
						WHEN 'observer' THEN 'SELECT DISTINCT provider_id, NULL sort_index FROM #ObservationSet'
						WHEN 'concept' THEN 'SELECT DISTINCT concept_cd, NULL sort_index FROM #ObservationSet'
						WHEN 'modifier' THEN 'SELECT DISTINCT modifier_cd, NULL sort_index FROM #ObservationSet'
						WHEN 'pid' THEN 'SELECT DISTINCT patient_num, NULL sort_index FROM #ObservationSet'
						WHEN 'eid' THEN 'SELECT DISTINCT encounter_num, NULL sort_index FROM #ObservationSet'
						WHEN 'observation' THEN 'SELECT * FROM #ObservationSet'
						ELSE NULL END)
				ELSE NULL END)
		FROM #OutputSetSQL o

	-- Generate the SQL for each output set [Part 2]
	UPDATE o
		SET o.SetSQL =
			'UPDATE x '
			+'SET x.SetStr = '
			+(CASE WHEN PDOSet = 'observation' THEN
				'REPLACE(CAST(
				(SELECT PanelName "@panel_name",
					(SELECT '+ColumnListSQL+'
						FROM
							(SELECT f.*,
									c.name_char concept_name_char,
									v.name_char provider_name_char,
									m.name_char modifier_name_char
								FROM #ObservationSet o
									INNER JOIN '+@Schema+'.OBSERVATION_FACT f
										ON o.encounter_num = f.encounter_num
											AND o.concept_cd = f.concept_cd
											AND o.provider_id = f.provider_id
											AND o.start_date = f.start_date
											AND o.modifier_cd = f.modifier_cd
											AND o.instance_num = f.instance_num
									LEFT OUTER JOIN '+@Schema+'.CONCEPT_DIMENSION c
										ON f.concept_cd = c.concept_cd
									LEFT OUTER JOIN '+@Schema+'.PROVIDER_DIMENSION v
										ON f.provider_id = v.provider_id
									LEFT OUTER JOIN '+@Schema+'.MODIFIER_DIMENSION m
										ON f.modifier_cd = m.modifier_cd
								WHERE o.PanelID = n.PanelID
							) t						
						FOR XML PATH(''observation''), TYPE
					)
					FROM #PanelNames n
					ORDER BY n.PanelID
					FOR XML PATH(''ns2observation_set''), TYPE
				) AS VARCHAR(MAX)),''ns2observation_set'',''ns2:observation_set'')
				'
			ELSE
				'''<ns2:'+PDOSet+'_set>''+CAST(('
				+'SELECT '
				+ColumnListSQL
				+' FROM ('
				+(CASE PDOSet
					WHEN 'patient' THEN 
						'SELECT p.*, l.sort_index
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.PATIENT_DIMENSION p ON l.patient_num = p.patient_num'
					WHEN 'event' THEN 
						'SELECT e.*, l.sort_index
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.VISIT_DIMENSION e ON l.encounter_num = e.encounter_num'
					WHEN 'observer' THEN 
						'SELECT p.*
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.PROVIDER_DIMENSION p ON l.provider_id = p.provider_id'
					WHEN 'concept' THEN 
						'SELECT c.*
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.CONCEPT_DIMENSION c ON l.concept_cd = c.concept_cd'
					WHEN 'modifier' THEN 
						'SELECT m.*
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.MODIFIER_DIMENSION m ON l.modifier_cd = m.modifier_cd'
					WHEN 'pid' THEN 
						'SELECT m.*, l.sort_index,
								(SELECT
									'+(CASE WHEN o.TechData = 1 THEN
												'q.upload_date "patient_map_id/@upload_date", '
												+'q.update_date "patient_map_id/@update_date", '
												+'q.download_date "patient_map_id/@download_date", '
												+'q.import_date "patient_map_id/@import_date", '
												+'q.sourcesystem_cd "patient_map_id/@sourcesystem_cd", '
												+'q.upload_id "patient_map_id/@upload_id", '
											ELSE '' END)+'
									q.patient_ide_status "patient_map_id/@status",
									q.patient_ide_source "patient_map_id/@source",
									q.patient_ide "patient_map_id"
									FROM '+@Schema+'.PATIENT_MAPPING q
									WHERE q.patient_num = m.patient_num
										AND q.project_id = m.project_id
										AND (q.patient_ide <> m.patient_ide
											OR q.patient_ide_source <> m.patient_ide_source)
									ORDER BY q.patient_ide, q.patient_ide_source
									FOR XML PATH(''''), TYPE
								) patient_map_id
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.PATIENT_MAPPING m ON l.patient_num = m.patient_num 
									AND m.project_id = '''+REPLACE(@ProjectID,'''','''''')+'''
									AND m.patient_ide_source = ''HIVE'''
					WHEN 'eid' THEN 
						'SELECT m.*, l.sort_index,
								(SELECT
									q.encounter_ide_status "event_map_id/@status",
									q.encounter_ide_source "event_map_id/@source",
									q.encounter_ide "event_map_id"
									FROM '+@Schema+'.ENCOUNTER_MAPPING q
									WHERE q.encounter_num = m.encounter_num
										AND q.project_id = m.project_id
										AND (q.encounter_ide <> m.encounter_ide
											OR q.encounter_ide_source <> m.encounter_ide_source)
									ORDER BY q.encounter_ide, q.encounter_ide_source
									FOR XML PATH(''''), TYPE
								) event_map_id
							FROM ('+DataTableSQL+') l 
								INNER JOIN '+@Schema+'.ENCOUNTER_MAPPING m ON l.encounter_num = m.encounter_num 
									AND m.project_id = '''+REPLACE(@ProjectID,'''','''''')+'''
									AND m.encounter_ide_source = ''HIVE'''
					ELSE NULL END)
				+') T'
				+' ORDER BY '
				+(CASE PDOSet
					WHEN 'patient' THEN 'sort_index, patient_num'
					WHEN 'event' THEN 'sort_index, encounter_num'
					WHEN 'observer' THEN 'provider_id, provider_path'
					WHEN 'concept' THEN 'concept_cd, concept_path'
					WHEN 'modifier' THEN 'modifier_cd, modifier_path'
					WHEN 'pid' THEN 'sort_index, patient_ide, patient_ide_source'
					WHEN 'eid' THEN 'sort_index, encounter_ide, encounter_ide_source'
					ELSE NULL END)
				+' FOR XML PATH('''+PDOSet+'''), TYPE'
				+') AS VARCHAR(MAX))+''</ns2:'+PDOSet+'_set>'''
			END)
			+' FROM #OutputSetSQL x' 
			+' WHERE PDOSet = '''+PDOSet+''''
		FROM #OutputSetSQL o

	-- Run the SQL for each output set
	SELECT @i = 1, @MaxI = (SELECT ISNULL(MAX(SetID),0) FROM #OutputSetSQL)
	WHILE (@i <= @MaxI)
	BEGIN
		SELECT @sql = SetSQL
			FROM #OutputSetSQL
			WHERE SetID = @i
		SELECT @i = @i + 1
		EXEC sp_executesql @sql	
	END

	-- Testing
	--SELECT * FROM #OutputSetSQL


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Perform Actions
	-- ***************************************************************************
	-- ***************************************************************************

	-- Form MessageBody
	SELECT	@StatusType = 'DONE',
			@StatusText = 'DONE',
			@MessageBody = 
				'<message_body>'
				+ '<ns3:response xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="ns3:patient_data_responseType">'
				+ '<ns2:patient_data>'
				+ ISNULL(REPLACE(REPLACE(CAST((SELECT REPLACE(REPLACE(SetStr,'<','_TAGLT_'),'>','_TAGGT_')+'' 
					FROM #OutputSetSQL 
					WHERE SetStr IS NOT NULL 
					ORDER BY SetID 
					FOR XML PATH(''), TYPE
				) AS VARCHAR(MAX)),'_TAGLT_','<'),'_TAGGT_','>'),'')
				+ '</ns2:patient_data>'
				+ '</ns3:response>'
				+ '</message_body>'

END
GO
