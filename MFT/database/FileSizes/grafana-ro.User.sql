USE [FileSizes]
GO
/****** Object:  User [grafana-ro]    Script Date: 2/11/2026 3:51:31 PM ******/
CREATE USER [grafana-ro] FOR LOGIN [grafana-ro] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_datareader] ADD MEMBER [grafana-ro]
GO
