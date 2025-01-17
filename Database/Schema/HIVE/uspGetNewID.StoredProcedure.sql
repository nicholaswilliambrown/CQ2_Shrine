SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [HIVE].[uspGetNewID]
	@Length INT,
	@NewID VARCHAR(MAX) OUTPUT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @str NVARCHAR(62)
	DECLARE @i INT
	SELECT	@NewID = '',
			@i = 0,
			@str = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
	WHILE @i < @Length
	BEGIN
		SELECT @i = @i + 1
		SELECT @NewID = @NewID + SUBSTRING(@str,CAST(rand()*62 AS INT)+1,1)
	END

END
GO
