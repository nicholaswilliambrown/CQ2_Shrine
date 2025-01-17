SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [CRC].[PATIENT_DIMENSION_NEW](
	[PATIENT_NUM] [int] NOT NULL,
	[VITAL_STATUS_CD] [varchar](50) NULL,
	[BIRTH_DATE] [datetime] NULL,
	[DEATH_DATE] [datetime] NULL,
	[SEX_CD] [varchar](50) NULL,
	[AGE_IN_YEARS_NUM] [int] NULL,
	[LANGUAGE_CD] [varchar](50) NULL,
	[RACE_CD] [varchar](50) NULL,
	[MARITAL_STATUS_CD] [varchar](50) NULL,
	[RELIGION_CD] [varchar](50) NULL,
	[ZIP_CD] [varchar](10) NULL,
	[STATECITYZIP_PATH] [varchar](700) NULL,
	[INCOME_CD] [varchar](50) NULL,
	[PATIENT_BLOB] [varchar](max) NULL,
	[UPDATE_DATE] [datetime] NULL,
	[DOWNLOAD_DATE] [datetime] NULL,
	[IMPORT_DATE] [datetime] NULL,
	[SOURCESYSTEM_CD] [varchar](50) NULL,
	[UPLOAD_ID] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
