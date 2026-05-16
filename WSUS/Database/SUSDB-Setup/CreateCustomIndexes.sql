-- guidance from https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide#create-custom-indexes
--only needs to be run on the primary or upstream server

USE SUSDB

IF EXISTS (
		SELECT *
		FROM sys.indexes AS si
		INNER JOIN sys.objects AS so ON si.object_id = so.object_id
		INNER JOIN sys.schemas AS sc ON so.schema_id = sc.schema_id
		WHERE (
				so.name = 'tbLocalizedPropertyForRevision' /* Table */
				AND si.name = 'nclLocalizedPropertyID' /* Index */
				)
		)
	PRINT 'nclLocalizedPropertyID index exists'
ELSE
	-- Create custom index in tbLocalizedPropertyForRevision
	CREATE NONCLUSTERED INDEX [nclLocalizedPropertyID] ON [dbo].[tbLocalizedPropertyForRevision] ([LocalizedPropertyID] ASC
		)
		WITH (
				PAD_INDEX = OFF
				,STATISTICS_NORECOMPUTE = OFF
				,SORT_IN_TEMPDB = OFF
				,DROP_EXISTING = OFF
				,ONLINE = OFF
				,ALLOW_ROW_LOCKS = ON
				,ALLOW_PAGE_LOCKS = ON
				) ON [PRIMARY];
GO

IF EXISTS (
		SELECT *
		FROM sys.indexes AS si
		INNER JOIN sys.objects AS so ON si.object_id = so.object_id
		INNER JOIN sys.schemas AS sc ON so.schema_id = sc.schema_id
		WHERE (
				so.name = 'tbRevisionSupersedesUpdate' /* Table */
				AND si.name = 'nclSupercededUpdateID' /* Index */
				)
		)
	PRINT 'nclSupercededUpdateID index exists'
ELSE
	-- Create custom index in tbRevisionSupersedesUpdate
	CREATE NONCLUSTERED INDEX [nclSupercededUpdateID] ON [dbo].[tbRevisionSupersedesUpdate] ([SupersededUpdateID] ASC
		)
		WITH (
				PAD_INDEX = OFF
				,STATISTICS_NORECOMPUTE = OFF
				,SORT_IN_TEMPDB = OFF
				,DROP_EXISTING = OFF
				,ONLINE = OFF
				,ALLOW_ROW_LOCKS = ON
				,ALLOW_PAGE_LOCKS = ON
				) ON [PRIMARY];