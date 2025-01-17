SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [HIVE].[uspGetCellSchema]
	@Service VARCHAR(100),
	@DomainID VARCHAR(50),
	@UserID VARCHAR(50),
	@ProjectID VARCHAR(50),
	@Cell VARCHAR(100) = NULL OUTPUT,
	@CellSchema VARCHAR(100) OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @DBLookupTable VARCHAR(100)
	DECLARE @ProjectPath VARCHAR(255)
	DECLARE @sql NVARCHAR(MAX)

	-- Get the cell
	SELECT @Cell = CELL, @DBLookupTable = DB_LOOKUP_TABLE
		FROM HIVE.SERVICE_LOOKUP
		WHERE [SERVICE] = @Service

	-- Get the cell schema
	IF (@DBLookupTable IS NULL)
	BEGIN
		SELECT @CellSchema = @Cell
	END
	ELSE
	BEGIN
		SELECT	@ProjectPath = PROJECT_PATH
			FROM PM.PM_PROJECT_DATA
			WHERE PROJECT_ID = @ProjectID
		IF (@DomainID IS NOT NULL) AND (@ProjectPath IS NOT NULL)
		BEGIN
			SELECT @sql = 'SELECT @CellSchemaOUT = C_DB_FULLSCHEMA 
							FROM '+@DBLookupTable+' 
							WHERE C_DOMAIN_ID = '''+REPLACE(@DomainID,'''','''''')+''' 
								AND C_PROJECT_PATH = '''+REPLACE(@ProjectPath,'''','''''')+'''
								AND C_OWNER_ID IN (''@'','''+REPLACE(@UserID,'''','''''')+''')
							ORDER BY (CASE WHEN C_OWNER_ID = ''@'' THEN 1 ELSE 0 END)'
			EXEC sp_executesql @sql,
								N'@CellSchemaOUT VARCHAR(100) OUTPUT',
								@CellSchemaOUT = @CellSchema OUTPUT
		END
	END

END
GO
