USE [FileSizes]
GO
/****** Object:  Table [stats].[FileEntry]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [stats].[FileEntry](
	[FileEntryId] [bigint] IDENTITY(1,1) NOT NULL,
	[BatchId] [uniqueidentifier] NOT NULL,
	[DirectoryId] [int] NOT NULL,
	[FileName] [nvarchar](256) NOT NULL,
	[Extension] [nvarchar](32) NULL,
	[FileSize] [bigint] NULL,
	[CreatedTime] [datetime2](0) NULL,
	[ModifiedTime] [datetime2](0) NULL,
	[AccessedTime] [datetime2](0) NULL,
	[Attributes] [int] NOT NULL,
 CONSTRAINT [PK_stats_FileEntry] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC,
	[FileEntryId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Index [IX_stats_FileEntry_Directory]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_FileEntry_Directory] ON [stats].[FileEntry]
(
	[BatchId] ASC,
	[DirectoryId] ASC
)
INCLUDE([FileName],[FileSize],[Extension]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_stats_FileEntry_Duplicates]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_FileEntry_Duplicates] ON [stats].[FileEntry]
(
	[BatchId] ASC,
	[FileName] ASC,
	[FileSize] ASC
)
INCLUDE([DirectoryId]) 
WHERE ([FileSize]>=(10485760))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_stats_FileEntry_Extension]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_FileEntry_Extension] ON [stats].[FileEntry]
(
	[BatchId] ASC,
	[Extension] ASC
)
INCLUDE([FileSize]) 
WHERE ([Extension] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_stats_FileEntry_Modified]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_FileEntry_Modified] ON [stats].[FileEntry]
(
	[BatchId] ASC,
	[ModifiedTime] ASC
)
INCLUDE([DirectoryId],[FileName],[FileSize]) 
WHERE ([FileSize] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_stats_FileEntry_Size]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_FileEntry_Size] ON [stats].[FileEntry]
(
	[BatchId] ASC,
	[FileSize] DESC
)
INCLUDE([DirectoryId],[FileName],[Extension],[ModifiedTime]) 
WHERE ([FileSize] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
ALTER TABLE [stats].[FileEntry]  WITH CHECK ADD  CONSTRAINT [FK_stats_FileEntry_Batch] FOREIGN KEY([BatchId])
REFERENCES [stats].[ScanBatch] ([BatchId])
ON DELETE CASCADE
GO
ALTER TABLE [stats].[FileEntry] CHECK CONSTRAINT [FK_stats_FileEntry_Batch]
GO
