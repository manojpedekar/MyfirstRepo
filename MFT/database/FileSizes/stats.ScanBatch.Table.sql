USE [FileSizes]
GO
/****** Object:  Table [stats].[ScanBatch]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [stats].[ScanBatch](
	[BatchId] [uniqueidentifier] NOT NULL,
	[ServerName] [nvarchar](256) NOT NULL,
	[CollectedAtUtc] [datetime2](0) NOT NULL,
	[CollectedBy] [nvarchar](128) NULL,
	[ToolName] [nvarchar](64) NOT NULL,
	[ToolVersion] [nvarchar](32) NULL,
	[SchemaVersion] [tinyint] NOT NULL,
	[DurationSec] [decimal](10, 1) NULL,
	[LastAccessEnabled] [bit] NOT NULL,
	[LastAccessRegistryValue] [bigint] NULL,
	[LastAccessStatus] [nvarchar](64) NULL,
	[AccessTimeCollected] [bit] NOT NULL,
	[TotalEntries] [bigint] NULL,
	[TotalDirectories] [bigint] NULL,
	[TotalFiles] [bigint] NULL,
	[TotalBytes] [bigint] NULL,
	[Notes] [nvarchar](1000) NULL,
 CONSTRAINT [PK_stats_ScanBatch] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_stats_ScanBatch_Server]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_stats_ScanBatch_Server] ON [stats].[ScanBatch]
(
	[ServerName] ASC,
	[CollectedAtUtc] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
ALTER TABLE [stats].[ScanBatch] ADD  DEFAULT ((2)) FOR [SchemaVersion]
GO
ALTER TABLE [stats].[ScanBatch] ADD  DEFAULT ((0)) FOR [LastAccessEnabled]
GO
ALTER TABLE [stats].[ScanBatch] ADD  DEFAULT ((0)) FOR [AccessTimeCollected]
GO
