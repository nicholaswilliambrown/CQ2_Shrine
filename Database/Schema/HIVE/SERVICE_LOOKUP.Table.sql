SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [HIVE].[SERVICE_LOOKUP](
	[SERVICE] [varchar](100) NOT NULL,
	[CELL] [varchar](100) NULL,
	[DB_LOOKUP_TABLE] [varchar](100) NULL,
PRIMARY KEY CLUSTERED 
(
	[SERVICE] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
