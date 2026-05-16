USE [SUSDB_Reports]
GO

SET ANSI_PADDING ON
GO

/****** Object:  Index [idx_MsrcSeverity_ComputerID]    Script Date: 4/10/2024 11:22:50 AM ******/
CREATE NONCLUSTERED INDEX [idx_MsrcSeverity_ComputerID] ON [dbo].[tb_UpdatesNeededByComputerHistory]
(
	[MsrcSeverity] ASC,
	[ComputerID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
GO


