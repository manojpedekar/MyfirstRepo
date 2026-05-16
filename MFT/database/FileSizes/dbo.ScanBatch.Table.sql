USE [FileSizes]
GO
/****** Object:  Table [dbo].[ScanBatch]    Script Date: 2/11/2026 3:51:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[ScanBatch](
	[BatchId] [uniqueidentifier] NOT NULL,
	[ServerName] [nvarchar](256) NOT NULL,
	[CollectedAtUtc] [datetime2](0) NOT NULL,
	[CollectedBy] [nvarchar](128) NULL,
	[ToolName] [nvarchar](64) NOT NULL,
	[ToolVersion] [nvarchar](32) NULL,
	[DurationSec] [decimal](10, 1) NULL,
	[Notes] [nvarchar](1000) NULL,
 CONSTRAINT [PK_ScanBatch] PRIMARY KEY CLUSTERED 
(
	[BatchId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_ScanBatch_Server]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE NONCLUSTERED INDEX [IX_ScanBatch_Server] ON [dbo].[ScanBatch]
(
	[ServerName] ASC,
	[CollectedAtUtc] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ScanBatch] ADD  DEFAULT (newid()) FOR [BatchId]
GO
ALTER TABLE [dbo].[ScanBatch] ADD  DEFAULT (sysutcdatetime()) FOR [CollectedAtUtc]
GO
