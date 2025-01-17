SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [WORK].[uspRunOperation]
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

	DECLARE @Blob BIT
	DECLARE @Category VARCHAR(1000)
	DECLARE @Max INT
	DECLARE @Node VARCHAR(255)
	DECLARE @Type VARCHAR(10)

	DECLARE @Path VARCHAR(1000)
	DECLARE @Pos INT
	DECLARE @PathTable VARCHAR(255)
	DECLARE @PathIndex VARCHAR(255)
	DECLARE @TableName VARCHAR(255)

	DECLARE @SQL NVARCHAR(MAX)

	CREATE TABLE #T (
		C_NAME varchar(255),
		C_USER_ID varchar(255),
		C_GROUP_ID varchar(255),
		C_SHARE_ID varchar(255),
		C_INDEX varchar(255),
		C_PARENT_INDEX varchar(255),
		C_VISUALATTRIBUTES char(3),
		C_PROTECTED_ACCESS char(1),
		C_TOOLTIP varchar(900),
		C_WORK_XML varchar(max),
		C_WORK_XML_SCHEMA varchar(max),
		C_WORK_XML_I2B2_TYPE varchar(255),
		C_ENTRY_DATE datetime,
		C_CHANGE_DATE datetime,
		C_STATUS_CD char(1)
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
		'http://www.i2b2.org/xsd/cell/work/1.1/' as ns4
	), x AS (
		SELECT	@RequestXML.query('ns3:request[1]/message_header[1]/*') h,
				@RequestXML.query('ns3:request[1]/message_body[1]/*') b
	), y AS (
		SELECT	h,
				(CASE @Operation
					WHEN 'addChild' THEN b.query('ns4:add_child[1]')
					WHEN 'annotateChild' THEN b.query('ns4:annotate_child[1]')
					WHEN 'deleteChild' THEN b.query('ns4:delete_child[1]')
					WHEN 'moveChild' THEN b.query('ns4:move_child[1]')
					WHEN 'renameChild' THEN b.query('ns4:rename_child[1]')
					WHEN 'getFoldersByUserId' THEN b.query('ns4:get_folders_by_userId[1]')
					WHEN 'getFoldersByProject' THEN b.query('ns4:get_folders_by_project[1]')
					WHEN 'getChildren' THEN b.query('ns4:get_children[1]')
					ELSE NULL END) b
		FROM x
	)
	SELECT	@Username =		h.value('security[1]/username[1]','VARCHAR(MAX)'),
			@ProjectID =	h.value('project_id[1]','VARCHAR(50)'),
			@Blob =			HIVE.fnStr2Bit(b.value('*[1]/@blob[1]','VARCHAR(MAX)')),
			@Category =		b.value('*[1]/@category[1]','VARCHAR(MAX)'),
			@Max =			b.value('*[1]/@max[1]','VARCHAR(MAX)'),
			@Node =			b.value('*[1]/@node[1]','VARCHAR(MAX)'),
			@Type =			b.value('*[1]/@type[1]','VARCHAR(MAX)'),
			@Path =			(CASE @Operation
								WHEN 'addChild' THEN b.value('*[1]/parent_index[1]','VARCHAR(MAX)')
								WHEN 'setProtectedAccess' THEN b.value('*[1]/index[1]','VARCHAR(MAX)')
								WHEN 'getChildren' THEN b.value('*[1]/parent[1]','VARCHAR(MAX)')
								ELSE b.value('*[1]/node[1]','VARCHAR(MAX)') END),
			@OpBody =		b.query('*[1]/*')
	FROM y

	-- Parse the path
	SELECT @Pos = CHARINDEX('\',@Path,3)
	IF @Pos > 1
		SELECT @PathTable = SUBSTRING(@Path,3,@Pos-3), @PathIndex = SUBSTRING(@Path,@Pos+1,LEN(@Path))


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** Validate variables
	-- ***************************************************************************
	-- ***************************************************************************

	-- Set default return values
 	SELECT	@StatusType = 'DONE',
 			@StatusText = 'Workplace processing completed'

	-- Validate Path
	IF @Operation IN ('addChild','annotateChild','deleteChild','moveChild','renameChild','setProtectedAccess','getChildren')
	BEGIN
		-- Check if a Path was provided
		IF @Path IS NULL
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = (CASE @Operation
									WHEN 'addChild' THEN 'No parent_index was provided'
									WHEN 'setProtectedAccess' THEN 'No index was provided'
									WHEN 'getChildren' THEN 'No parent was provided'
									ELSE 'No node was provided' END),
					@MessageBody = NULL
			RETURN
		END

		-- Check that the path was valid
		IF (@PathTable IS NULL) OR (@PathIndex IS NULL)
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = (CASE @Operation
									WHEN 'addChild' THEN 'Invalid parent_index key'
									WHEN 'setProtectedAccess' THEN 'Invalid index key'
									WHEN 'getChildren' THEN 'Invalid parent key'
									ELSE 'Invalid node key' END),
					@MessageBody = NULL
			RETURN
		END

		-- Confirm that the user has access to the table
		SELECT @TableName = C_TABLE_NAME
			FROM ..WORKPLACE_ACCESS 
			WHERE C_TABLE_CD = @PathTable
				AND ISNULL(C_PROTECTED_ACCESS,'N') <> 'Y'
				AND (C_GROUP_ID = '@' OR C_GROUP_ID = @ProjectID)
				AND (C_SHARE_ID = 'Y' OR C_USER_ID = '@' OR C_USER_ID = @Username)

		IF @TableName IS NULL
		BEGIN
			SELECT	@StatusType = 'ERROR',
					@StatusText = 'TABLE_ACCESS_DENIED',
					@MessageBody = NULL
			RETURN
		END

	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** addChild
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'addChild'
	BEGIN	
		-- Extract variables from request message_body
		INSERT INTO #T (C_NAME, C_USER_ID, C_GROUP_ID, C_SHARE_ID, C_INDEX, C_PARENT_INDEX, C_VISUALATTRIBUTES, C_PROTECTED_ACCESS, C_TOOLTIP, C_WORK_XML, C_WORK_XML_SCHEMA, C_WORK_XML_I2B2_TYPE, C_ENTRY_DATE, C_CHANGE_DATE, C_STATUS_CD)
		SELECT	IsNull(x.value('name[1]','VARCHAR(255)'),'@') C_NAME,
				IsNull(x.value('user_id[1]','VARCHAR(255)'),@Username) C_USER_ID,
				IsNull(x.value('group_id[1]','VARCHAR(255)'),@ProjectID) C_GROUP_ID,
				x.value('share_id[1]','VARCHAR(255)') C_SHARE_ID,
				IsNull(x.value('index[1]','VARCHAR(255)'),CAST(NEWID() AS VARCHAR(50))) C_INDEX,
				@PathIndex C_PARENT_INDEX,
				IsNull(x.value('visual_attributes[1]','VARCHAR(3)'),'LA ') C_VISUALATTRIBUTES,
				NULL C_PROTECTED_ACCESS,
				IsNull(x.value('tooltip[1]','VARCHAR(255)'),x.value('name[1]','VARCHAR(255)')) C_TOOLTIP,
				CAST(x.query('work_xml[1]/*') AS VARCHAR(MAX)) C_WORK_XML,
				NULL C_WORK_XML_SCHEMA,
				x.value('work_xml_i2b2_type[1]','VARCHAR(255)') C_WORK_XML_I2B2_TYPE,
				GetDate() C_ENTRY_DATE,
				GetDate() C_CHANGE_DATE,
				'A' C_STATUS_CD
			FROM (SELECT @OpBody AS x) T

		-- Insert the child record
		SELECT @SQL = 'INSERT INTO '+@Schema+'.'+@TableName+' SELECT * FROM #T'
		EXEC sp_executesql @SQL
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** annotateChild
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'annotateChild'
	BEGIN
		SELECT @SQL = '
				UPDATE '+@Schema+'.'+@TableName+'
				SET C_TOOLTIP = '''+REPLACE(Tooltip,'''','''''')+'''
				WHERE C_INDEX = '''+REPLACE(@PathIndex,'''','''''')+'''
			'
		FROM (
			SELECT (CASE WHEN IsNull(Tooltip,'') = '' THEN '' ELSE Tooltip END) Tooltip
			FROM (SELECT @OpBody.value('tooltip[1]','VARCHAR(255)') Tooltip) T
		) T

		EXEC sp_executesql @SQL
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** renameChild
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'renameChild'
	BEGIN
		SELECT @SQL = '
				UPDATE '+@Schema+'.'+@TableName+'
				SET C_NAME = '''+REPLACE(Name,'''','''''')+'''
				WHERE C_INDEX = '''+REPLACE(@PathIndex,'''','''''')+'''
			'
		FROM (
			SELECT (CASE WHEN IsNull(Name,'') = '' THEN '@' ELSE Name END) Name
			FROM (SELECT @OpBody.value('name[1]','VARCHAR(255)') Name) T
		) T

		EXEC sp_executesql @SQL
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** deleteChild
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'deleteChild'
	BEGIN
		SELECT @SQL = '
				UPDATE '+@Schema+'.'+@TableName+'
				SET C_STATUS_CD = ''I''
				WHERE C_INDEX = '''+REPLACE(@PathIndex,'''','''''')+'''
			'

		EXEC sp_executesql @SQL
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** moveChild
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'moveChild'
	BEGIN
		SELECT @SQL = '
				UPDATE '+@Schema+'.'+@TableName+'
				SET C_PARENT_INDEX = '''+REPLACE(Parent,'''','''''')+'''
				WHERE C_INDEX = '''+REPLACE(@PathIndex,'''','''''')+'''
			'
		FROM (SELECT @OpBody.value('parent[1]','VARCHAR(255)') Parent) T
		WHERE IsNull(Parent,'')<>''

		EXEC sp_executesql @SQL
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getFoldersByUserId [Part 1]
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'getFoldersByUserId'
	BEGIN
		INSERT INTO #T (C_NAME, C_USER_ID, C_GROUP_ID, C_SHARE_ID, C_INDEX, C_PARENT_INDEX, C_VISUALATTRIBUTES, C_PROTECTED_ACCESS, C_TOOLTIP, C_WORK_XML, C_WORK_XML_SCHEMA, C_WORK_XML_I2B2_TYPE, C_ENTRY_DATE, C_CHANGE_DATE, C_STATUS_CD)
			SELECT C_NAME, C_USER_ID, C_GROUP_ID, C_SHARE_ID, '\\'+C_TABLE_CD+'\'+C_INDEX, C_PARENT_INDEX, C_VISUALATTRIBUTES, C_PROTECTED_ACCESS, C_TOOLTIP, NULL, NULL, NULL, C_ENTRY_DATE, C_CHANGE_DATE, C_STATUS_CD
				FROM ..WORKPLACE_ACCESS
				WHERE ISNULL(C_PROTECTED_ACCESS,'N') <> 'Y'
					AND C_STATUS_CD = 'A'
					AND (C_GROUP_ID = '@' OR C_GROUP_ID = @ProjectID)
					AND (C_SHARE_ID = 'Y' OR C_USER_ID = '@' OR C_USER_ID = @Username)
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getChildren [Part 1]
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation = 'getChildren'
	BEGIN
		-- Load children into a temp table	
		SELECT @SQL = '
				SELECT T.*
				FROM '+@Schema+'.'+@TableName+' T
				WHERE T.C_PARENT_INDEX = '''+REPLACE(@PathIndex,'''','''''')+'''
					AND C_STATUS_CD = ''A''
					AND SUBSTRING(C_VISUALATTRIBUTES,2,1) = ''A''
					AND ISNULL(C_PROTECTED_ACCESS,''N'') <> ''Y''
					AND (C_GROUP_ID = ''@'' OR C_GROUP_ID = '''+REPLACE(@ProjectID,'''','''''')+''')
					AND (C_SHARE_ID = ''Y'' OR C_USER_ID = ''@'' OR C_USER_ID = '''+REPLACE(@Username,'''','''''')+''')
			'

		INSERT INTO #T (C_NAME, C_USER_ID, C_GROUP_ID, C_SHARE_ID, C_INDEX, C_PARENT_INDEX, C_VISUALATTRIBUTES, C_PROTECTED_ACCESS, C_TOOLTIP, C_WORK_XML, C_WORK_XML_SCHEMA, C_WORK_XML_I2B2_TYPE, C_ENTRY_DATE, C_CHANGE_DATE, C_STATUS_CD)
			EXEC sp_executesql @SQL

		UPDATE #T SET C_INDEX = '\\' + @PathTable + '\' + C_INDEX
	END


	-- ***************************************************************************
	-- ***************************************************************************
	-- **** getFoldersByUserId, getChildren [Part 2]
	-- ***************************************************************************
	-- ***************************************************************************

	IF @Operation IN ('getFoldersByUserId','getChildren')
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
			
		-- Form MessageBody
		SELECT	@MessageBody = 
					'<message_body>'
					+ '<ns4:folders>'
					+ ISNULL(CAST((
						SELECT	REPLACE(REPLACE(REPLACE(C_NAME,'&','&amp;'),'<','&lt;'),'>','&gt;') "name",
								C_USER_ID "user_id",
								C_GROUP_ID "group_id",
								C_PROTECTED_ACCESS "protected_access",
								C_SHARE_ID "share_id",
								REPLACE(REPLACE(REPLACE(C_INDEX,'&','&amp;'),'<','&lt;'),'>','&gt;') "index",
								C_PARENT_INDEX "parent_index",
								C_VISUALATTRIBUTES "visual_attributes",
								REPLACE(REPLACE(REPLACE(C_TOOLTIP,'&','&amp;'),'<','&lt;'),'>','&gt;') "tooltip",
								(CASE WHEN IsNull(@Blob,1) = 1 THEN REPLACE(CAST(C_WORK_XML AS VARCHAR(MAX)),'<?xml version="1.0"?>','') ELSE NULL END) "work_xml",
								C_WORK_XML_SCHEMA "work_xml_schema",
								C_WORK_XML_I2B2_TYPE "work_xml_i2b2_type",
								(CASE WHEN @Type = 'all' THEN C_ENTRY_DATE ELSE NULL END) "entry_date",
								(CASE WHEN @Type = 'all' THEN C_CHANGE_DATE ELSE NULL END)  "change_date"
						FROM #T
						ORDER BY CAST(C_NAME AS VARBINARY(MAX)), C_INDEX
						FOR XML PATH('folder'), TYPE
					) AS NVARCHAR(MAX)),'')
					+ '</ns4:folders>'
					+ '</message_body>'
	END

END
GO
