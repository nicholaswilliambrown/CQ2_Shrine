SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [CRC].[QT_PDO_QUERY_MASTER](
	[QUERY_MASTER_ID] [int] IDENTITY(1,1) NOT NULL,
	[USER_ID] [varchar](50) NOT NULL,
	[GROUP_ID] [varchar](50) NOT NULL,
	[CREATE_DATE] [datetime] NOT NULL,
	[REQUEST_XML] [varchar](max) NULL,
	[I2B2_REQUEST_XML] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[QUERY_MASTER_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [QT_IDX_PQM_UGID] ON [CRC].[QT_PDO_QUERY_MASTER]
(
	[USER_ID] ASC,
	[GROUP_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
