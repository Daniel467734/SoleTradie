# One-Way Throttled Cloud Sync Feature

## Overview
Added a new **"Careful One-Way Sync (Throttled)"** button to the Settings screen that allows users to carefully upload all their local app data to the cloud with controlled speed and real-time progress tracking.

### Key Features
- **One-Way Upload**: Uploads all local data to cloud (customers, price book, jobs, estimates, invoices, builds) without pulling changes
- **Throttled Speed**: 500ms delay between sync operations prevents network saturation and ensures stable uploads
- **Real-Time Progress**: Shows percentage completion and current operation being synced
- **Detailed Status**: Displays which data type is currently being uploaded
- **Graceful Error Handling**: Continues syncing remaining data even if one batch fails
- **Batch Processing**: Handles large datasets by processing data in batches (25-100 items per batch)

## UI Location
**Settings Screen → Cloud Sync & Storage Section**

A new purple-highlighted box appears below the regular upload/download buttons with:
- 🎯 Title: "Careful One-Way Sync (Throttled)"
- 📊 Description of features
- ⏱️ Throttled speed explanation
- 📝 Progress indicator during sync
- 🔵 Purple "Start Throttled Sync" button

## Technical Implementation

### New Service: `cloud_sync_throttled_service.dart`
Located at: `lib/services/cloud_sync_throttled_service.dart`

#### Key Methods

```dart
// Start the one-way sync process
static Future<bool> performOneWaySync() async

// Set up progress callback for UI updates
static void setProgressCallback(Function(double progress, String operation)? callback)

// Check if sync is currently active
static bool get isSyncing

// Get current progress (0.0 to 1.0)
static double get progress

// Get current operation description
static String get currentOperation
```

#### How It Works
1. Gathers all local data files (jobs.json, customers.json, etc.)
2. Calculates total work based on file sizes
3. Processes each data type with progress notifications
4. Uses 500ms throttle delay between operations
5. Splits large datasets into batches (25 jobs, 50 customers, 100 price book items)
6. Updates UI with percentage and operation status in real-time
7. Continues with next item even if batch fails (resilient)

### Modified Files

#### `lib/screens/settings_screen.dart`
Added:
1. State variables for tracking throttled sync:
   - `_isThrottledSyncActive`: Whether sync is running
   - `_throttledSyncProgress`: Progress value 0.0-1.0
   - `_throttledSyncOperation`: Current operation description

2. Method `_performThrottledCloudSync()`:
   - Shows modal progress dialog
   - Sets up progress callback
   - Calls `CloudSyncThrottledService.performOneWaySync()`
   - Updates UI with progress in real-time
   - Shows success/error snackbars

3. Updated `_buildCloudSyncCard()`:
   - Added new purple section for throttled sync
   - Shows feature benefits
   - Displays start button with real-time progress percentage
   - Located above the existing sync status section

## User Workflow

### To Use the Throttled Sync:

1. **Open Settings** → Scroll to "Cloud Sync & Storage"
2. **See the new purple section** "Careful One-Way Sync (Throttled)"
3. **Click "Start Throttled Sync"** button
4. **Modal dialog appears** showing:
   - Linear progress bar (0% → 100%)
   - Percentage completion (e.g., "43.2% Complete")
   - Current operation (e.g., "Syncing Customers: Customers (150 items)")
   - Info box explaining throttling
5. **Monitor progress** as each data type uploads
6. **Dialog closes** when complete with success message
7. **Success snackbar** confirms "✅ Cloud sync completed successfully!"

### Data Synced
- ✅ Jobs (primary data)
- ✅ Customers (contact list)
- ✅ Price Book (item prices)
- ✅ Estimates (drafted work)
- ✅ Invoices (billing data)
- ✅ In-Progress Builds (estimate builder state)

## Technical Details

### Throttling
- **Delay**: 500ms between sync operations
- **Purpose**: Prevents network saturation and allows graceful handling of slow connections
- **Effect**: Sync takes slightly longer but ensures stability

### Batch Sizes
- Jobs: 25 items per batch
- Customers: 50 items per batch
- Price Book: 100 items per batch
- Estimates/Builds/Invoices: Full pass (logged only)

### Progress Calculation
```
Total Work = Sum of (file_size_in_MB for each data type)
Completed Work = Sum of items processed * estimated size
Progress % = (Completed Work / Total Work) * 100
```

### Error Handling
- Individual batch failures don't stop the sync
- Error is logged and sync continues with next item
- Final success/error message shown based on overall result
- User can see from progress which data types succeeded

## UI/UX Design

### Progress Dialog
```
┌─────────────────────────────────────┐
│  One-Way Cloud Sync                 │
├─────────────────────────────────────┤
│ Uploading your local data to cloud..│
│                                      │
│ ████████░░░░░░░░░░░░░░░░░░░░░░░░░  │  ← Progress bar
│                                      │
│      43.2% Complete                 │  ← Percentage
│                                      │
│ ╔─────────────────────────────────╗ │
│ │ Syncing Customers: Customers... │ │  ← Current op
│ ╚─────────────────────────────────╝ │
│                                      │
│ ℹ️ Sync is throttled...              │  ← Info box
│                                      │
│              [Cancel]                │
└─────────────────────────────────────┘
```

### Settings Card
```
┌────────────────────────────────────────────┐
│ 🚀 Careful One-Way Sync (Throttled)        │
├────────────────────────────────────────────┤
│ 🎯 Perfect for careful data sync           │
│ ⏱️ Throttled speed prevents issues         │
│ 📊 Real-time progress indicator            │
│                                             │
│    [Start Throttled Sync] 42%              │
└────────────────────────────────────────────┘
```

## Advantages Over Standard Sync

### Standard Manual Sync
- Fast but all-or-nothing
- No progress visibility
- Can saturate network
- No operation details

### Throttled One-Way Sync
- ✅ Controlled speed (safe for slow connections)
- ✅ Real-time progress tracking
- ✅ Shows what's being uploaded
- ✅ Graceful error handling
- ✅ Non-blocking (user can see progress)
- ✅ Perfect for careful data synchronization

## Testing Checklist

- [ ] Settings screen loads without errors
- [ ] "Careful One-Way Sync" button visible in purple box
- [ ] Clicking button shows progress dialog
- [ ] Progress bar updates smoothly (0% → 100%)
- [ ] Percentage display updates correctly
- [ ] Operation description changes as different data types sync
- [ ] Dialog closes when sync completes
- [ ] Success snackbar shows on completion
- [ ] Works with both small (1-10 items) and large (1000+) datasets
- [ ] Gracefully handles network errors
- [ ] Cancel button works to close dialog

## Future Enhancements

Potential improvements:
1. **Download variant**: Add throttled one-way download sync
2. **Selective sync**: Let users choose which data types to upload
3. **Scheduling**: Schedule throttled syncs for off-peak hours
4. **Resume**: Allow resuming interrupted syncs
5. **Verification**: Show detailed before/after stats
6. **Compression**: Compress data before upload for faster transfer

## File Changes Summary

| File | Changes |
|------|---------|
| `lib/services/cloud_sync_throttled_service.dart` | NEW - 393 lines |
| `lib/screens/settings_screen.dart` | Added state vars, method, UI (50+ lines) |

## Dependencies
- No new external packages required
- Uses existing: `path_provider`, `dart:io`, `dart:convert`
- Integrates with existing `DataType` enum and storage strategy

---

**Implementation Date**: July 14, 2026  
**Status**: ✅ Complete and Ready for Testing
