USE [SUSDB_Reports]
GO

/****** Object:  Index [PK_tbDownstreamFriendlyName]    Script Date: 4/10/2024 11:22:33 AM ******/
ALTER TABLE [dbo].[tb_DownstreamFriendlyName] ADD  CONSTRAINT [PK_tbDownstreamFriendlyName] PRIMARY KEY CLUSTERED 
(
	[AccountServerID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO


