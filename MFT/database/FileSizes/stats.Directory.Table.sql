USE [FileSizes]
GO
/****** Object:  Table [stats].[Directory]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [stats].[Directory](
	[DirectoryId] [int] NOT NULL,
	[BatchId] [uniqueidentifier] NOT NULL,
	[ScanVolumeId] [int] NOT NULL,
	[ParentId] [int] NOT NULL,
	[Depth] [tinyint] NOT NULL,
	[DirectoryName] [nvarchar](256) NOT NULL,
	[FullPath] [nvarchar](4000) NOT NULL,
	[IsTempCache] [bit] NOT NULL,
	[IsSystemManaged] [bit] NOT NULL,
	[FileCount] [int] NULL,
	[TotalFileSize] [bigint] NULL,
	[RecursiveFileCount] [bigint] NULL,
	[RecursiveTotalSize] [bigint] NULL,
 CONSTRAINT [PK_stats_Directory] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC,
	[DirectoryId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Index [IX_stats_Directory_Parent]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_Directory_Parent] ON [stats].[Directory]
(
	[BatchId] ASC,
	[ParentId] ASC
)
INCLUDE([DirectoryName],[Depth]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_stats_Directory_Size]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_Directory_Size] ON [stats].[Directory]
(
	[BatchId] ASC,
	[TotalFileSize] DESC
)
INCLUDE([FullPath],[FileCount],[Depth]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_stats_Directory_TempCache]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_Directory_TempCache] ON [stats].[Directory]
(
	[BatchId] ASC,
	[IsTempCache] ASC
)
INCLUDE([FullPath],[FileCount],[TotalFileSize]) 
WHERE ([IsTempCache]=(1))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
ALTER TABLE [stats].[Directory] ADD  DEFAULT ((0)) FOR [IsTempCache]
GO
ALTER TABLE [stats].[Directory] ADD  DEFAULT ((0)) FOR [IsSystemManaged]
GO
/****** Object:  Index [IX_stats_Directory_SystemManaged]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_Directory_SystemManaged] ON [stats].[Directory]
(
	[BatchId] ASC,
	[IsSystemManaged] ASC
)
INCLUDE([FullPath],[FileCount],[TotalFileSize],[Depth])
WHERE ([IsSystemManaged]=(1))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
ALTER TABLE [stats].[Directory]  WITH CHECK ADD  CONSTRAINT [FK_stats_Directory_Batch] FOREIGN KEY([BatchId])
REFERENCES [stats].[ScanBatch] ([BatchId])
ON DELETE CASCADE
GO
ALTER TABLE [stats].[Directory] CHECK CONSTRAINT [FK_stats_Directory_Batch]
GO
ALTER TABLE [stats].[Directory]  WITH CHECK ADD  CONSTRAINT [FK_stats_Directory_Volume] FOREIGN KEY([BatchId], [ScanVolumeId])
REFERENCES [stats].[ScanVolume] ([BatchId], [ScanVolumeId])
GO
ALTER TABLE [stats].[Directory] CHECK CONSTRAINT [FK_stats_Directory_Volume]
GO
