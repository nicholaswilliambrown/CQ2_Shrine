SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [HIVE].[MessageLog](
	[MessageID] [bigint] IDENTITY(0,1) NOT NULL,
	[UserID] [varchar](50) NULL,
	[DomainID] [varchar](50) NULL,
	[ProjectID] [varchar](50) NULL,
	[Cell] [varchar](100) NULL,
	[CellSchema] [varchar](100) NULL,
	[Service] [varchar](100) NULL,
	[Operation] [varchar](100) NULL,
	[RequestType] [varchar](100) NULL,
	[RequestDate] [datetime] NULL,
	[ResponseDate] [datetime] NULL,
	[DurationMS] [int] NULL,
	[ErrorNumber] [int] NULL,
	[ErrorSeverity] [int] NULL,
	[ErrorState] [int] NULL,
	[ErrorProcedure] [varchar](1000) NULL,
	[ErrorLine] [int] NULL,
	[ErrorMessage] [varchar](4000) NULL,
	[IPAddress] [varchar](50) NULL,
	[RequestXML] [varchar](max) NULL,
	[ResponseXML] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[MessageID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
