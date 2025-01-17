SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspUpdateAllSteps]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	EXEC [CRC].[uspUpdateStep1CreateDataTables];
	EXEC [CRC].[uspUpdateStep2LoadDataTables];
	EXEC [CRC].[uspUpdateStep3IndexDataTables];
	EXEC [CRC].[uspUpdateStep4CreateCQ2Tables];
	EXEC [CRC].[uspUpdateStep5SwapTables];
	EXEC [CRC].[uspUpdateStep6DropOldTables];

END
GO
