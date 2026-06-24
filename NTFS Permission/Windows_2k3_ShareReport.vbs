'==============================================================
' ShareReport.vbs
' Lists all file shares on a Windows Server 2003 file server,
' with the total size and file count of each share.
'
' EXCLUDED (the built-in defaults only):
'   - Default drive shares : C$, D$, E$ ... (single letter + $)
'   - Remote Admin share   : ADMIN$
'   - Remote IPC share     : IPC$
'   - Non-disk shares       : print queues, devices, IPC
'
' INCLUDED:
'   - Every normal share AND every custom hidden share (e.g.
'     Data$, Apps$) -- a "$" in the name does NOT exclude it;
'     only the specific default names above are skipped.
'
' Usage (run ON the file server):
'   cscript //nologo ShareReport.vbs                  (to screen)
'   cscript //nologo ShareReport.vbs > shares.csv     (to file)
'
' Progress / diagnostics are written to StdErr, so they appear
' on screen but do NOT end up inside shares.csv.
'==============================================================

Option Explicit

Dim objWMI, objFSO, colShares, objShare
Dim strComputer, strName
Dim dblBytes, lngFiles
Dim lngTotalShares, lngReported, lngSkipped

strComputer = "."   ' local machine

Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\" & strComputer & "\root\cimv2")

' --- CSV header (goes to StdOut, i.e. the redirected file) -------
WScript.Echo "ShareName,Path,Description,SizeBytes,SizeMB,SizeGB,FileCount"

' Enumerate ALL shares -- no WHERE filter, so nothing is lost to
' inconsistent Type flags. We filter in code below.
Set colShares = objWMI.ExecQuery("SELECT * FROM Win32_Share")

lngTotalShares = 0
lngReported    = 0
lngSkipped     = 0

For Each objShare In colShares
    lngTotalShares = lngTotalShares + 1
    strName = objShare.Name

    If IsDefaultShare(strName) Then
        WScript.StdErr.WriteLine "  [skip default] " & strName
        lngSkipped = lngSkipped + 1

    ElseIf objShare.Path = "" Or Not objFSO.FolderExists(objShare.Path) Then
        ' IPC$, print queues, devices, or a path we cannot see.
        WScript.StdErr.WriteLine "  [skip no path] " & strName & _
                                 "  (path='" & objShare.Path & "')"
        lngSkipped = lngSkipped + 1

    Else
        WScript.StdErr.WriteLine "  [scanning]      " & strName & _
                                 "  -> " & objShare.Path
        dblBytes = 0
        lngFiles = 0
        GetFolderStats objFSO.GetFolder(objShare.Path), dblBytes, lngFiles

        WScript.Echo QuoteIfNeeded(strName) & "," & _
                     QuoteIfNeeded(objShare.Path) & "," & _
                     QuoteIfNeeded(objShare.Description) & "," & _
                     dblBytes & "," & _
                     FormatNumber(dblBytes / 1048576, 2, , , 0) & "," & _
                     FormatNumber(dblBytes / 1073741824, 2, , , 0) & "," & _
                     lngFiles
        lngReported = lngReported + 1
    End If
Next

WScript.StdErr.WriteLine ""
WScript.StdErr.WriteLine "Shares found:    " & lngTotalShares
WScript.StdErr.WriteLine "Shares reported: " & lngReported
WScript.StdErr.WriteLine "Shares skipped:  " & lngSkipped

WScript.Quit 0

'==============================================================
' Returns True only for the built-in default shares:
'   ADMIN$, IPC$, and any single drive-letter share (C$, D$...).
' Custom hidden shares like "Data$" return False (kept).
'==============================================================
Function IsDefaultShare(strShareName)
    Dim s
    s = UCase(strShareName & "")

    If s = "ADMIN$" Or s = "IPC$" Or s = "PRINT$" Or s = "FAX$" Then
        IsDefaultShare = True
    ElseIf Len(s) = 2 And Right(s, 1) = "$" And _
           s >= "A$" And s <= "Z$" Then
        ' Two chars, ends in "$", first char A-Z => drive share.
        IsDefaultShare = True
    Else
        IsDefaultShare = False
    End If
End Function

'==============================================================
' Recursively sum size (bytes) and file count of a folder.
' On Error keeps an unreadable subfolder from aborting the scan.
'==============================================================
Sub GetFolderStats(objFolder, ByRef dblBytes, ByRef lngFiles)
    Dim objFile, objSubFolder

    On Error Resume Next

    For Each objFile In objFolder.Files
        dblBytes = dblBytes + objFile.Size
        lngFiles = lngFiles + 1
    Next

    For Each objSubFolder In objFolder.SubFolders
        GetFolderStats objSubFolder, dblBytes, lngFiles
    Next

    On Error GoTo 0
End Sub

'==============================================================
' CSV-quote a value if it contains a comma or quote.
'==============================================================
Function QuoteIfNeeded(strValue)
    Dim s
    s = strValue & ""
    If InStr(s, ",") > 0 Or InStr(s, """") > 0 Then
        QuoteIfNeeded = """" & Replace(s, """", """""") & """"
    Else
        QuoteIfNeeded = s
    End If
End Function
