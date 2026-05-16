USE [FileSizes]
GO
/****** Object:  Table [dbo].[BatchSummary]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[BatchSummary](
	[BatchId] [uniqueidentifier] NOT NULL,
	[TotalUsedBytes] [bigint] NULL,
	[TotalFreeBytes] [bigint] NULL,
	[TotalFiles] [bigint] NULL,
	[TotalDirectories] [bigint] NULL,
	[StaleFilesCount] [bigint] NULL,
	[StaleFilesBytes] [bigint] NULL,
	[DuplicateCandidatesCount] [bigint] NULL,
	[DuplicateCandidatesWastedBytes] [bigint] NULL,
	[TempCacheFilesCount] [bigint] NULL,
	[TempCacheFilesBytes] [bigint] NULL,
	[ComputedAtUtc] [datetime2](0) NULL,
PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
