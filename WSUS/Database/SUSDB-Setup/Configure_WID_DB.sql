USE [master]
GO

EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE;
EXEC sys.sp_configure N'max server memory (MB)', N'16384';
RECONFIGURE WITH OVERRIDE
EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE;

EXEC sp_addserver 'your_server_name', 'local'

USE [SUSDB]

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_GetSummarizationState] (@ActionID INT)
RETURNS NVARCHAR(50)
AS
BEGIN
    DECLARE @ActionName NVARCHAR(50)

    SELECT @ActionName = CASE @ActionID
        WHEN 0 THEN 'No Status'
        WHEN 1 THEN 'Not Applicable'
        WHEN 2 THEN 'Not Installed'
        WHEN 3 THEN 'Downloaded'
        WHEN 4 THEN 'Installed'
WHEN 5 THEN 'Failed'
WHEN 6 THEN 'Requires Reboot'
        ELSE 'Unknown'
    END

    RETURN @ActionName
END

GO


CREATE VIEW [dbo].[vw_GetWSUSEvents]
AS
SELECT EI.[EventInstanceID]
,EI.[EventID]
,EMT.MessageTemplate
,vU.DefaultTitle
,vCT.Name AS [Client]
,@@SERVERNAME as WSUSServer
,ES.DisplayNameString AS [Source]
,EI.[TimeAtTarget]
,EI.[TimeAtServer]
,EI.[Win32HResult]
,EI.[AppName]
,EI.[MiscData]
,EI.[ReplacementStrings]
,EI.[RevisionNumber]
,EI.[EventOrdinalNumber]
,E.[StateID]
,E.[SeverityID]
,E.[LogLevel]
,EN.DisplayNameString AS [EventNameSpace]
,EI.ComputerID
,EI.UpdateID
,CASE 
WHEN EI.ComputerID IS NULL OR EI.UpdateID IS NULL THEN NULL
ELSE [dbo].[fn_GetSummarizationState](vUIIB.State) 
END as State
FROM [SUSDB].[dbo].[tbEventInstance] AS EI
LEFT JOIN [SUSDB].[dbo].[tbEventMessageTemplate] AS EMT ON EI.EventID = EMT.EventID
LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vComputerTarget] AS vCT ON EI.ComputerID = vCT.ComputerTargetId
LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdate] AS vU ON EI.UpdateID = vU.UpdateID
LEFT JOIN [SUSDB].[dbo].[tbEventSource] AS ES ON EI.[EventNamespaceID] = ES.EventNamespaceID AND EI.[EventSourceID] = ES.EventSourceID
LEFT JOIN [SUSDB].[dbo].[tbEvent] AS E ON EI.[EventNamespaceID] = E.EventNamespaceID AND EI.[EventID] = E.[EventID]
LEFT JOIN [SUSDB].[dbo].[tbEventNamespace] AS EN ON EI.[EventNamespaceID] = EN.[EventNamespaceID]
LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdateInstallationInfoBasic] vUIIB ON EI.ComputerID = vUIIB.ComputerTargetId AND EI.UpdateID = vUIIB.UpdateId;
GO



