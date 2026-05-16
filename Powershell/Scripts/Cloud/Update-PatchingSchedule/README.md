# Update-PatchingSchedule

A quick PowerShell script to set patching schedules on cloud instances

## Requirements

### Cloud API Key

The \$APIKey variable should be updated in the script using an API key generated in the SS&C Cloud portal for your account.

### CloudNeedPatchSched.csv

The script uses a CSV input file. The CSV has the following fields:

| **vm_name**                            | **Environemnt** | **CloudValue**  | **DesiredSched**                      | **SetResult**   | **request**     |
|----------------------------------------|-----------------|-----------------|---------------------------------------|-----------------|-----------------|
| i-3129e897-2673-479b-8e69-4405b862283c | \<Leave Blank\> | \<Leave Blank\> | \<Leave Blank\> or \<Valid Schedule\> | \<Leave Blank\> | \<Leave Blank\> |

### Updating \$DefaultSchedules

The environment variable on the subproject is used to set a default schedule on the compute instance

| **environment** | **schedule**      |
|-----------------|-------------------|
| dev             | 3rd-tues-10pm-4am |
| devtest         | 3rd-tues-10pm-4am |
| nonprod         | 3rd-tues-10pm-4am |
| prod            | 4th-sun-2am-5am   |
| qa              | 3rd-tues-10pm-4am |
| sandbox         | 3rd-tues-10pm-4am |
| uat             | 3rd-tues-10pm-4am |

### Valid Schedules

At the time of writing, the valid schedules are

-   1st-sun-3am-5am
-   1st-sun-12am-4am
-   1st-sun-2am-5am
-   2nd-sun-12am-4am
-   2nd-sun-2am-5am
-   3rd-tues-6pm-10pm
-   3rd-tues-10pm-4am
-   3rd-thurs-6pm-10pm
-   3rd-thurs-10pm-4am
-   3rd-sat-10pm-4am
-   3rd-sun-2am-5am
-   4th-sun-2am-5am
-   self-managed
