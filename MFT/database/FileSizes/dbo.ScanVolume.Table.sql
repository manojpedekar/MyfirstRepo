USE [FileSizes]
GO
/****** Object:  Table [dbo].[ScanVolume]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[ScanVolume](
	[ScanVolumeId] [int] IDENTITY(1,1) NOT NULL,
	[BatchId] [uniqueidentifier] NOT NULL,
	[VolumeName] [nvarchar](512) NOT NULL,
	[VolumeLabel] [nvarchar](256) NULL,
	[FileSystemType] [nvarchar](32) NULL,
	[TotalSizeBytes] [bigint] NULL,
	[FreeSizeBytes] [bigint] NULL,
	[EntryCount] [bigint] NULL,
	[DirectoryCount] [bigint] NULL,
	[FileCount] [bigint] NULL,
	[ErrorCount] [bigint] NULL,
	[ScanDurationSec] [decimal](10, 1) NULL,
 CONSTRAINT [PK_ScanVolume] PRIMARY KEY CLUSTERED 
(
	[ScanVolumeId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Index [IX_ScanVolume_Batch]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_ScanVolume_Batch] ON [dbo].[ScanVolume]
(
	[BatchId] ASC
)
INCLUDE([VolumeName],[TotalSizeBytes],[FreeSizeBytes]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ScanVolume]  WITH CHECK ADD  CONSTRAINT [FK_ScanVolume_Batch] FOREIGN KEY([BatchId])
REFERENCES [dbo].[ScanBatch] ([BatchId])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[ScanVolume] CHECK CONSTRAINT [FK_ScanVolume_Batch]
GO
