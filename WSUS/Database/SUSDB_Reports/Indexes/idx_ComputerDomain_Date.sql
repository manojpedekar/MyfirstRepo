USE [SUSDB_Reports]
GO

SET ANSI_PADDING ON
GO

/****** Object:  Index [idx_ComputerDomain_Date]    Script Date: 4/10/2024 11:22:39 AM ******/
CREATE NONCLUSTERED INDEX [idx_ComputerDomain_Date] ON [dbo].[tb_UpdatesNeededByComputerHistory]
(
	[ComputerDomain] ASC,
	[DATE] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO


