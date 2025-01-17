SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [HIVE].[fnHasUserRole] 
(
	@ProjectID VARCHAR(50),
	@UserID VARCHAR(50),
	@Role VARCHAR(50)
)
RETURNS BIT
AS
BEGIN
	DECLARE @HasRole BIT
	SELECT @HasRole = 0

	SELECT @HasRole = 1
		FROM PM.PM_PROJECT_USER_ROLES
		WHERE project_id = @ProjectID AND [user_id] = @UserID
			AND (user_role_cd = @Role
				OR (user_role_cd = 'ADMIN' AND @Role IN ('DATA_OBFSC','DATA_AGG','DATA_LDS','DATA_DEID','DATA_PROT','USER','MANAGER'))
				OR (user_role_cd = 'MANAGER' AND @Role IN ('DATA_OBFSC','DATA_AGG','DATA_LDS','DATA_DEID','USER'))
				OR (user_role_cd = 'USER' AND @Role IN ('DATA_OBFSC','DATA_AGG','DATA_LDS','DATA_DEID'))
				OR (user_role_cd = 'DATA_PROT' AND @Role IN ('DATA_OBFSC','DATA_AGG','DATA_LDS','DATA_DEID','USER'))
				OR (user_role_cd = 'DATA_DEID' AND @Role IN ('DATA_OBFSC','DATA_AGG','DATA_LDS','USER'))
				OR (user_role_cd = 'DATA_LDS' AND @Role IN ('DATA_OBFSC','DATA_AGG'))
				OR (user_role_cd = 'DATA_AGG' AND @Role IN ('DATA_OBFSC'))
			)

	RETURN @HasRole
END
GO
