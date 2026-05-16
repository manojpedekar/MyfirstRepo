SELECT U.DefaultTitle
	, U.[KnowledgebaseArticle]
	, U.[MsrcSeverity]
FROM PUBLIC_VIEWS.vUpdateApproval UA
LEFT JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdate] U ON UA.UpdateId = U.UpdateId
WHERE UA.CreationDate BETWEEN Convert(DATETIME, '2022-7-01') AND Convert(DATETIME, '2022-12-31')
	AND Action = 'Install'
	AND U.[MsrcSeverity] <> 'Unspecified'
	AND U.DefaultTitle NOT LIKE '%Itanium%'
	AND U.DefaultTitle LIKE '%2012%'
GROUP BY U.[KnowledgebaseArticle]
	, U.DefaultTitle
	, [MsrcSeverity]
