SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [WORK].[uspGetResponse]
	@Service VARCHAR(100) = NULL,
	@Operation VARCHAR(100) = NULL,
	@RequestXML XML = NULL,
	@UserID VARCHAR(50) = NULL,
	@RequestType VARCHAR(100) = NULL OUTPUT,
	@ResponseXML XML = NULL OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-- Determine the procedure that will process the operation
	DECLARE @opProc VARCHAR(100)
	SELECT @opProc = OBJECT_SCHEMA_NAME(@@PROCID) + '.'
						+ (CASE WHEN @Operation IN ('annotateChild','getFoldersByProject','deleteChild','getChildren','addChild','renameChild','moveChild','getFoldersByUserId')
								THEN 'uspRunOperation'
							ELSE NULL END)

	-- Generate the ResponseXML using the standard method
	EXEC HIVE.uspGetStandardResponse
			@RequestXML = @RequestXML,
			@SendingAppName = 'Workplace Cell',
			@SendingAppVersion = '1.6',
			@ReceivingAppName = 'i2b2 Ontology',
			@ReceivingAppVersion = '1.6',
			@Operation = @Operation,
			@OperationProcedure = @opProc,
			@MessageTag = 'ns3:response',
			@MessageNamespaces = 'xmlns:ns2="http://www.i2b2.org/xsd/cell/crc/psm/1.1/" xmlns:ns4="http://www.i2b2.org/xsd/cell/work/1.1/" xmlns:ns3="http://www.i2b2.org/xsd/hive/msg/1.1/" xmlns:tns="http://ws.workplace.i2b2.harvard.edu" xmlns:ns5="http://www.i2b2.org/xsd/cell/crc/psm/querydefinition/1.1/" xmlns:ns6="http://www.i2b2.org/xsd/cell/crc/psm/analysisdefinition/1.1/" xmlns:ns7="http://www.i2b2.org/xsd/cell/pm/1.1/"',
			@RequestType = @RequestType OUTPUT,
			@ResponseXML = @ResponseXML OUTPUT

END
GO
