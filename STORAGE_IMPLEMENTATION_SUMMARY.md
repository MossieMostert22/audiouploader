# Google Drive Storage Management - Complete Implementation

## Overview
Your audiouploader app now has a comprehensive Google Drive storage management system that displays real-time storage usage across the platform and individual listeners, with intelligent validation to prevent exceeding the 15GB Drive limit.

## Features Implemented

### 1. Storage Metrics Display

#### Total Drive Usage (Settings Dialog)
- Shows total Google Drive usage vs. total available space
- Displays percentage of Drive utilization
- Visual progress bar with custom styling
- Updates dynamically during app runtime

#### Per-Listener Storage (Management Dialog)
- Each listener folder's storage usage displayed at top
- Individual storage metrics relative to total Drive quota
- Accurate size calculation including nested folders
- Synchronized with uploaded/deleted files

### 2. Pre-Upload File Size Validation

#### Hard Limit: 15GB Drive Capacity
- Blocks uploads if: `totalUsedBytes + fileSize > 15GB`
- Shows clear red error: `"Upload blocked: File is XXmb but only XXmb available"`
- Prevents exceeding Google Drive's free storage allocation

#### Soft Warning: 500MB Available Threshold
- Alerts users when: `availableBytes < 500MB`
- Shows orange warning: `"Low storage: Only XXmb available after uploading XXmb file"`
- Allows upload to proceed (doesn't block)
- Gives users time to clean up before hitting hard limit

### 3. Storage Synchronization

#### During Initialization
- `_loadListenersFromDrive()` calculates:
  - Total Drive used/available bytes
  - Each listener's folder size
  - Stores metrics in `listener['folderBytes']`

#### After File Upload
- Recalculates listener folder size
- Refreshes total storage quota
- Updates state immediately
- Storage bars reflect new totals

#### After File Deletion
- Syncs deleted files to Google Drive
- Recalculates listener folder size
- Refreshes total storage quota
- Updates state for immediate UI refresh

### 4. Backend Storage Methods

#### `getStorageQuota()`
```dart
Future<Map<String, int>> getStorageQuota()
```
- Fetches Drive storage quota via Google Drive API
- Returns: `{'usedBytes': int, 'limitBytes': int, 'availableBytes': int}`
- Called during initialization and after upload/deletion

#### `calculateFolderSize(String folderId)`
```dart
Future<int> calculateFolderSize(String folderId)
```
- Recursively calculates total folder size
- Handles pagination for large folders
- Traverses nested folder structures
- Returns total size in bytes

#### `getListenerFolderId(String listenerDirectory)`
```dart
Future<String?> getListenerFolderId(String listenerDirectory)
```
- Public wrapper for accessing listener folder IDs
- Used for storage calculation in management screen
- Returns folder ID string

## Code Architecture

### State Variables
```dart
int _totalDriveUsedBytes = 0;
int _totalDriveAvailableBytes = 0;
```
Tracks total Drive usage and available space, refreshed at:
- App initialization
- After each file upload
- After deleting files

### Storage Bar Widget
```dart
Widget _buildStorageBar({
  required String label,
  required int usedBytes,
  required int totalBytes,
})
```
Displays storage usage as:
- Label with formatted size (e.g., "Total (3.25GB)")
- Percentage on right (e.g., "32%")
- Visual progress bar below

### Upload Prevention
Located in `_pickAndUploadFile()`:
- Reads file size before upload
- Validates against 15GB limit
- Shows 500MB warning if needed
- Only calls `_uploadFile()` if validation passes

### Deletion Sync & Refresh
Located in Management dialog close handler:
- Syncs deleted files to Google Drive
- Recalculates affected listener folder
- Refreshes total storage quota
- Triggers setState() for UI update

## Testing Checklist

### Test 1: Initial Load
- [ ] App opens and calculates storage metrics
- [ ] Settings dialog shows accurate total usage
- [ ] Progress bars show correct percentages

### Test 2: Upload Within Limits
- [ ] Upload small file (< 100MB)
- [ ] No warnings appear
- [ ] Storage bars update after upload completes
- [ ] Listener folder size increases

### Test 3: Low Storage Warning (500MB)
- [ ] Free up space to less than 500MB remaining
- [ ] Try uploading any file
- [ ] Orange "Low storage" warning appears
- [ ] Upload still proceeds

### Test 4: Upload Exceeds Limit
- [ ] Try uploading file that would exceed 15GB
- [ ] Red "Upload blocked" error appears
- [ ] Upload does NOT execute
- [ ] Storage metrics stay unchanged

### Test 5: Delete and Refresh
- [ ] Open Management dialog for a listener
- [ ] Note the folder size shown
- [ ] Delete some files
- [ ] Close dialog (background sync runs)
- [ ] Wait 2-3 seconds
- [ ] Reopen Management dialog
- [ ] Folder size should have decreased
- [ ] Total storage should have decreased

### Test 6: Multiple Listeners
- [ ] Create 3+ listeners with files
- [ ] Settings should show total of all listener folders
- [ ] Each Management dialog shows individual listener size
- [ ] Sum should approximately equal Settings total

## Performance Notes

- **Initialization**: First load calculates all folder sizes (~2-3 seconds depending on folder count)
- **Storage Refresh**: After upload/delete takes ~1-2 seconds
- **UI Response**: Storage bars update immediately after API calls complete
- **Caching**: Metrics stay in memory; recalculated on major operations

## Files Modified

1. **main.dart**
   - Added storage state variables
   - Added storage calculation in `_loadListenersFromDrive()`
   - Added `_formatBytes()` helper
   - Added `_buildStorageBar()` widget
   - Added upload validation logic
   - Added storage refresh after uploads
   - Added storage refresh after deletions
   - Integrated storage bars into Settings and Management dialogs

2. **google_drive_service.dart**
   - Added `getStorageQuota()` method
   - Added `calculateFolderSize()` method
   - Exposed `getListenerFolderId()` publicly

## API Calls Summary

The implementation uses these Google Drive API calls:
- `about.get($fields: 'storageQuota')` - Get Drive storage quota
- `files.list(q: ..., $fields: ...)` - List folder contents for size calculation

These are efficient and only called when needed (init, upload complete, deletion complete).

## Error Handling

- **Auth failure**: Gracefully handled with error message
- **Network timeout**: Wrapped in try-catch with debug output
- **Missing folders**: Returns 0 bytes instead of crashing
- **API rate limit**: Operations queue and retry with exponential backoff

## Future Enhancements

Possible future additions:
- Automatic cleanup reminder when space below 500MB
- Per-listener storage quota limits
- Archive old files to free space
- Storage usage analytics/history
- Auto-pause uploads when below 100MB remaining
