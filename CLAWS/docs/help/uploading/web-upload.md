# Web Interface Upload

Upload your collections through the web browser interface.

## Prerequisites

- Valid user account with upload permissions
- .zip file from NTFS or AD Inventory collector
- File size within configured limits

## Step-by-Step Guide

### Step 1: Log In

1. Navigate to the NTFSPermsUploader web application
2. Log in with your credentials
3. Verify you can see the **Upload** option in the navigation

### Step 2: Navigate to Upload

Click **Upload** in the top navigation bar.

### Step 3: Select Your File

1. Click **Choose File** or drag-and-drop your .zip file
2. Verify the correct file is selected
3. The file type (NTFS or AD Inventory) will be auto-detected

### Step 4: Upload

1. Click the **Upload** button
2. Watch the progress bar as the file uploads
3. Do not close the browser during upload

### Step 5: Monitor Processing

After upload completes, processing begins automatically:

1. **Validation** - File integrity checks
2. **Import** - Data loaded into database
3. **Migration** - Data moved to production

Progress updates appear in real-time.

### Step 6: Verify Completion

When processing completes:

1. Status shows **Completed**
2. Import statistics are displayed
3. Data is available for analysis

## Upload Page Features

### File Selection

- Drag-and-drop support
- Click to browse
- File type validation (only .zip)

### Progress Display

- Upload percentage
- Processing stage
- Estimated time remaining
- Real-time log updates

### Status Indicators

| Icon | Meaning |
|------|---------|
| Spinner | Processing in progress |
| Green check | Completed successfully |
| Red X | Error occurred |
| Yellow warning | Completed with warnings |

## After Upload

### View Results

- Click on the upload row to see details
- Review import statistics
- Check for any warnings or errors

### Re-upload

If needed, you can upload a new collection:
- New collections replace older data from the same source
- Historical data is maintained for comparison

## Troubleshooting

### Upload Stalls

- Check your network connection
- Try a smaller file first
- Contact support if issue persists

### "Access Denied"

- Verify you have upload permissions
- Contact your administrator

### Processing Fails

- Review the error message
- Check [Troubleshooting](../troubleshooting/upload-failures.md)
- Verify your collection completed successfully

## Tips

| Tip | Benefit |
|-----|---------|
| Use wired network | Faster, more reliable uploads |
| Close other browser tabs | More resources for upload |
| Don't navigate away | Prevents upload interruption |
| Check collection first | Avoids uploading corrupt files |

---

*Need help? Contact GlobalWindowsServers@sscinc.com*
