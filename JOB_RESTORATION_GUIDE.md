# 📋 Job Restoration Guide

## Objective
Delete local jobs.json and restore your 91 jobs from Firestore cloud backup.

## Status
- ✅ Bug fixes applied (3 critical fixes total)
- ⏳ Ready to restore jobs

## Steps

### Step 1: Export Current Firestore Jobs (Backup First!)

You should have ~91 jobs in Firestore that we need to preserve. These are your "source of truth" after the recent syncs.

**Option A: Via Firebase Console (Recommended)**
1. Go to Firebase Console → Firestore Database
2. Select `jobs` collection
3. Export to JSON (if available)
4. Save as `/Users/dan/SOLE TRADER APP VERSIONS/Version 2.2/backup/jobs_backup_before_restore.json`

**Option B: Via App Debug Export**
If you have a debug endpoint in the app, export jobs from the app settings.

### Step 2: Delete Local jobs.json

**Location**: App Documents folder
- iOS: `/Users/{username}/Library/Developer/CoreSimulator/Devices/{UUID}/data/Containers/Data/Application/{APP_ID}/Documents/jobs.json`
- Android: `/data/data/com.example.app/app_flutter/jobs.json`

**Via Flutter Commands**:
```bash
# For Android emulator/device
adb shell "rm /data/data/com.example.app/app_flutter/jobs.json"

# For iOS simulator (find your app documents)
# Or delete via app's debug menu if available
```

### Step 3: Clear App Cache

This ensures the app reloads from Firestore fresh:

**Via Settings**:
1. Open app
2. Settings → Storage → Clear Cache/Local Data
3. Or uninstall and reinstall app

### Step 4: Force Cloud Sync

Once app restarts with cleared local storage:

1. **App will detect missing local data**
2. **Triggers immediate Firestore sync** 
3. **Downloads all 91 jobs from cloud**
4. **Saves fresh copy to local storage**

This syncs will include:
- ✅ All job metadata
- ✅ All attachments (now that we fixed the deletion bug!)
- ✅ All estimates/invoices (if stored in estimateVersions subcollection)

## Key Fixes That Enable This

1. **Fix #1**: Added `attachments` field to `saveJob()` Firestore save
2. **Fix #2**: Changed local reload to **merge** attachments instead of replace
3. **Fix #3** (Critical): REMOVED `attachments` from cleanup deletion list

## Expected Outcome

✅ Local storage has fresh 91 jobs from cloud
✅ All invoices preserved (now that we fixed the deletion)
✅ App ready for testing with clean data

## Testing Checklist

After restoration:
- [ ] App loads with 77-91 jobs showing
- [ ] Each job shows all previously generated invoices
- [ ] Can generate new invoices without disappearing
- [ ] Navigate away and back - invoices still there
- [ ] Cloud sync occurs - invoices still there

## Rollback Plan

If something goes wrong:
1. Restore from your backup JSON
2. Or Firestore automatically keeps 30 days of deleted data (Firebase retention)

## Important Notes

- ⚠️ Do NOT delete from Firestore console directly (can't be undone)
- ⚠️ Only delete local storage, cloud is the backup
- ⚠️ Keep backup of jobs_backup_before_restore.json safe

---

**Next**: Are you ready to proceed? I can guide you through the exact `adb` commands if using Android, or help with iOS simulator if needed.
