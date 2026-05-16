Run above command from the directory where psexe and server.txt file resides.

for /f %i in (servers.txt) do psexec \\%i -accepteula -s cmd /c "winrm quickconfig -q"
