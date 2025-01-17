SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [WORK].[WORKPLACE](
	[C_NAME] [varchar](255) NOT NULL,
	[C_USER_ID] [varchar](255) NOT NULL,
	[C_GROUP_ID] [varchar](255) NOT NULL,
	[C_SHARE_ID] [varchar](255) NULL,
	[C_INDEX] [varchar](255) NOT NULL,
	[C_PARENT_INDEX] [varchar](255) NULL,
	[C_VISUALATTRIBUTES] [char](3) NOT NULL,
	[C_PROTECTED_ACCESS] [char](1) NULL,
	[C_TOOLTIP] [varchar](255) NULL,
	[C_WORK_XML] [varchar](max) NULL,
	[C_WORK_XML_SCHEMA] [varchar](max) NULL,
	[C_WORK_XML_I2B2_TYPE] [varchar](255) NULL,
	[C_ENTRY_DATE] [datetime] NULL,
	[C_CHANGE_DATE] [datetime] NULL,
	[C_STATUS_CD] [char](1) NULL,
PRIMARY KEY CLUSTERED 
(
	[C_INDEX] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
