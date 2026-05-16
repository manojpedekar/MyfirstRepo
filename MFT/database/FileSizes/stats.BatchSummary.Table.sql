USE [FileSizes]
GO
/****** Object:  Table [stats].[BatchSummary]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [stats].[BatchSummary](
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
	[SystemManagedFilesCount] [bigint] NULL,
	[SystemManagedFilesBytes] [bigint] NULL,
	[TopExtensionsJson] [nvarchar](max) NULL,
	[ComputedAtUtc] [datetime2](0) NOT NULL,
 CONSTRAINT [PK_stats_BatchSummary] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
ALTER TABLE [stats].[BatchSummary] ADD  DEFAULT (sysutcdatetime()) FOR [ComputedAtUtc]
GO
ALTER TABLE [stats].[BatchSummary]  WITH CHECK ADD  CONSTRAINT [FK_stats_BatchSummary_Batch] FOREIGN KEY([BatchId])
REFERENCES [stats].[ScanBatch] ([BatchId])
ON DELETE CASCADE
GO
ALTER TABLE [stats].[BatchSummary] CHECK CONSTRAINT [FK_stats_BatchSummary_Batch]
GO
