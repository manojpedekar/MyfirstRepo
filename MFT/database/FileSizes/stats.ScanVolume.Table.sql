USE [FileSizes]
GO
/****** Object:  Table [stats].[ScanVolume]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [stats].[ScanVolume](
	[ScanVolumeId] [int] NOT NULL,
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
 CONSTRAINT [PK_stats_ScanVolume] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC,
	[ScanVolumeId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [stats].[ScanVolume]  WITH CHECK ADD  CONSTRAINT [FK_stats_ScanVolume_Batch] FOREIGN KEY([BatchId])
REFERENCES [stats].[ScanBatch] ([BatchId])
ON DELETE CASCADE
GO
ALTER TABLE [stats].[ScanVolume] CHECK CONSTRAINT [FK_stats_ScanVolume_Batch]
GO
