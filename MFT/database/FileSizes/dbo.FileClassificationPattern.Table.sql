USE [FileSizes]
GO
/****** Object:  Table [dbo].[FileClassificationPattern]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[FileClassificationPattern](
	[PatternId] [int] IDENTITY(1,1) NOT NULL,
	[TargetColumn] [nvarchar](50) NOT NULL,
	[Pattern] [nvarchar](255) NOT NULL,
	[Label] [nvarchar](100) NULL,
	[IsEnabled] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[PatternId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[FileClassificationPattern] ADD  DEFAULT ((1)) FOR [IsEnabled]
GO
