USE [FileSizes]
GO
/****** Object:  Table [dbo].[FileEntry]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[FileEntry](
	[FileEntryId] [bigint] IDENTITY(1,1) NOT NULL,
	[BatchId] [uniqueidentifier] NOT NULL,
	[Volume] [nvarchar](512) NOT NULL,
	[FullPath] [nvarchar](4000) NOT NULL,
	[FileName] [nvarchar](512) NOT NULL,
	[FileSize] [bigint] NULL,
	[CreatedTime] [datetime2](0) NULL,
	[ModifiedTime] [datetime2](0) NULL,
	[AccessedTime] [datetime2](0) NULL,
	[IsDirectory] [bit] NOT NULL,
	[Attributes] [bigint] NOT NULL,
	[IsTempCache] [bit] NOT NULL,
 CONSTRAINT [PK_FileEntry] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC,
	[FileEntryId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Index [IX_FileEntry_BatchId_FileSize]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_BatchId_FileSize] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[FileSize] DESC
)
INCLUDE([IsDirectory],[FileName],[FullPath],[ModifiedTime],[Volume]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_FileEntry_Extension]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_Extension] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[IsDirectory] ASC
)
INCLUDE([FileName],[FileSize]) 
WHERE ([IsDirectory]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_FileEntry_Modified]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_Modified] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[ModifiedTime] ASC
)
WHERE ([IsDirectory]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_FileEntry_Path]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_Path] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[FullPath] ASC
)
INCLUDE([FileName],[FileSize],[ModifiedTime]) 
WHERE ([IsDirectory]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_FileEntry_Size]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_Size] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[FileSize] DESC
)
WHERE ([IsDirectory]=(0) AND [FileSize] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_FileEntry_StaleFiles]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_StaleFiles] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[ModifiedTime] ASC,
	[FileSize] ASC
)
WHERE ([IsDirectory]=(0) AND [FileSize]>=(104857600))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
/****** Object:  Index [IX_FileEntry_TempCache]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_TempCache] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[FileSize] DESC
)
WHERE ([IsTempCache]=(1) AND [IsDirectory]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_FileEntry_Volume]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_FileEntry_Volume] ON [dbo].[FileEntry]
(
	[BatchId] ASC,
	[Volume] ASC,
	[IsDirectory] ASC
)
INCLUDE([FileSize]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
ALTER TABLE [dbo].[FileEntry] ADD  DEFAULT ((0)) FOR [IsTempCache]
GO
ALTER TABLE [dbo].[FileEntry]  WITH CHECK ADD  CONSTRAINT [FK_FileEntry_Batch] FOREIGN KEY([BatchId])
REFERENCES [dbo].[ScanBatch] ([BatchId])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[FileEntry] CHECK CONSTRAINT [FK_FileEntry_Batch]
GO
