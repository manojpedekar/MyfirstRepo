> **FROZEN HISTORICAL RECORD.** The Newkirk tech.newkirk.com SOC audit
> workflow has been retired. This folder is preserved as a reference for
> any future "quarterly audit of a decommissioning legacy domain" effort.
>
> The original V1 procedure (described below) was a three-script manual
> ETL: gather local admins, gather group members, combine into the final
> audit report. V2/Collect-AuditInfo.ps1 is a single-script consolidation
> that runs the whole pipeline and emails the result.

# MANUALLY COMPILING NT_DOMAIN DATA

Created by: Bill Moxim Created On: 07/21/2021

Due to an authentication issue with the scripts that gather all other domain data for the SOC audit, this is a temporary process to gather the required data for "NT_DOMAIN" (tech.newkirk.com) until proper credentials can be added to the standard scripts.

## SCRIPTS USED:

- **get-localadmins.ps1**
  - **input**: Get-LocalAdmins-NTDOMAIN.txt

- **GetGroupMembersNT.ps1**
  - **input**: GetGroupMembers_NT.txt

- **Write_NT_Output.ps1**
  - **input**: NT_All_Users.csv
  - **input**: NT_Group_Users.csv

## STEPS:
Create a text file listing all the required servers for NT_DOMAIN from the "WINDOWS_SOC1_NONEMP" report and save it as "Get-LocalAdmins-NTDOMAIN.txt".

Logon to the following servers to run the "Get-LocalAdmins.ps1" script

- DSKCRSFILE01WC
- DSKCRSAPP06WC

The file "Get-LocalAdmins-NTDOMAIN.txt" lists all the servers to check

- Command: ".\\get-localadmins.ps1 -Computername (Get-Content .\\Get-LocalAdmins-NTDOMAIN.txt)"
- OutputFile: "LocalGroupMembers.csv"

Run this from each server

- Copy the results to a sheet "NT_DOMAIN_yyyyQ\#.xlsx" (year+quarter)
- Put results from FILE01 into a tab "FILE01", and APP06 to a tab "APP06"

Combine the output from both to a new sheet\\tab changing the header as below:

- Change column 'A' "ComputerName" to "ATTESTATION_DESCRIPTION"
- Add column 'G' and call it "SOURCE"
- When combining data, list the SOURCE as "APP06" or "FILE01"
- Sort on "STATUS" column 'C' and remove all "FailedToQuery"

This will cover all required servers in 'tech.newkirk.com'

From the new combined sheet\\tab:

- Filter on "MemberType" = "DomainGroup"
- Select all names in the column "MemberName" (F) and paste it to a new tab
- Remove duplicates
- Save the list to a text file "GetGroupMembers_NT.txt" - this will be copied to the server used below

Next, from the combined sheet\\tab:

- Clear all filters
  - Copy the tab to a new sheet "AllUsers"
- Export the "AllUsers" tab to a csv file by doing the following:
- Save (copy/paste) the tab to a new spreadsheet
- On the new sheet, Save As "NT_All_Users.csv" (select .csv as file type)

Copy the file "GetGroupMembers_NT.txt" to the server you will use in the next step (I used 'DSKCRSFILE01WC').

This file contains all the groups that need to be checked.

Run PS script "GetGroupMembersNT.ps1" from an NT_DOMAIN server.

- Command: ".\\GetGroupMembersNT.ps1" \<-- note the filename, no parameter needed
- OutputFile: "GetGroupMembers_NT_yyyymmdd-hhmmss.csv" time stamp is appended to the file name)

This will provide the user content of all domain groups listed in the text file.

Rename the column header "SAM Account Name" to "SAM_Account_Name".

Copy the csv file above to "NT_Group_Users.csv"

Put all files in a single location. Edit the below script so \$WorkFolder is pointing to your files directory.

Required input files:

- NT_All_Users.csv
- NT_Group_Users.csv

Run PS script "Write_NT_Output.ps1" to combine Server users with domain group users.

The output file will be "NT_Final_Output_yyyymmdd-hhmmss.csv"

Generate xlsx spreadsheet from the csv file then send to Gary to complete remaining data.
