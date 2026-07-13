# 🚀 ACTION PLAN: Delete Local Jobs & Restore from Firestore

## Step-by-Step Instructions

### Step 1: Verify You Have 91+ Jobs in Firestore ✅
Before we delete anything locally, confirm your cloud backup is safe:

```bash
# Check Firebase Console or run in app debug console:
# Should show ~91 jobs
```

**DO NOT PROCEED until confirmed!**

### Step 2: Build & Deploy the Fixed App

Make sure your app has all three fixes:

```bash
# In VS Code, rebuild Flutter app
flutter clean
flutter pub get
flutter run --release

# Or in your build tool
```

### Step 3: Delete Local jobs.json

**For Android Emulator/Device:**
```bash
# Connect your device/emulator, then:
adb shell rm /data/data/com.example.app/app_flutter/jobs.json

# Verify it's deleted:
adb shell ls -la /data/data/com.example.app/app_flutter/ | grep jobs
```

**For iOS Simulator:**
```bash
# Find your simulator device UUID
xcrun simctl list devices

# Delete from simulator Documents
rm ~/Library/Developer/CoreSimulator/Devices/{UUID}/data/Containers/Data/Application/{APP_ID}/Documents/jobs.json
```

**Via App UI (Easiest):**
1. Open app Settings
2. Look for "Storage" or "Debug" menu
3. Find "Clear Local Jobs" or "Reset Local Data" button
4. Tap to delete

### Step 4: Clear App Cache

```bash
# Android
adb shell pm clear com.example.app

# Or uninstall & reinstall (will lose all local temp data)
adb uninstall com.example.app
adb install app.apk
```

### Step 5: Restart App - Force Cloud Sync

1. **Close and reopen app**
2. **App will detect missing local jobs.json**
3. **Triggers automatic Firestore sync**
4. **Downloads all 91 jobs**
5. **Saves fresh copy locally**

### Step 6: Verify Restoration

**Check logs should show:**
```
✅ Loaded 91 jobs from Firestore
✅ Saved 91 jobs to local storage (atomic write)
✅ Synced 91 jobs from Firebase (delta sync)
```

**Then check app UI:**
- [ ] Jobs list shows ~91 jobs
- [ ] Each job displays
- [ ] Can tap to view job details
- [ ] Invoices are visible in each job

### Step 7: Test New Invoice Generation

1. Open any job
2. Generate new invoice PDF
3. Sync to cloud
4. Navigate away and back to job
5. **✅ Invoice should still be there (NOT disappearing)**

---

## Safety Checks

- ✅ Don't delete from Firestore directly (can't undo)
- ✅ Only delete local storage (cloud is the backup)
- ✅ Keep backup of jobs_before_restore.json just in case
- ✅ Have the fixed app built before deleting

---

## Troubleshooting

**Problem**: App still shows 0 jobs after restart
- **Solution**: Check app logs, ensure network connected, wait 30 seconds for sync to complete

**Problem**: Some jobs missing after sync
- **Solution**: Jobs may still be syncing, check logs for: "Synced X jobs from Firebase"

**Problem**: Invoices still disappearing
- **Solution**: Ensure all three fixes are in the deployed app, not just in your code

---

## Exact Commands (Copy-Paste Ready)

### Android:
```bash
# Delete local jobs
adb shell rm /data/data/com.example.app/app_flutter/jobs.json

# Clear cache
adb shell pm clear com.example.app

# Then restart app
```

### Firebase Verification (Console):
```
1. Open Firebase Console
2. Go to Firestore → jobs collection
3. Count documents (should be ~91)
4. Spot check a few jobs - verify "attachments" field exists
```

---

## Expected Timeline

- **Restart app**: 5 seconds
- **App detects missing local**: 2 seconds  
- **Cloud sync starts**: 1 second
- **Download 91 jobs**: 10-30 seconds (depends on network)
- **Save locally**: 5 seconds
- **UI updates with jobs**: 2 seconds

**Total**: ~1-2 minutes

---

## What Gets Restored

✅ All 91 jobs with metadata  
✅ Job attachments (invoice PDF paths) - NOW FIXED!  
✅ All customer data linked to jobs  
✅ Job status, dates, pricing  

❌ Things NOT automatically restored:
- In-progress builds (saved separately)
- Temporary app settings (non-critical)

---

## Ready?

When you're ready to proceed, just say the word!

I can:
1. Guide you through exact Android/iOS commands
2. Monitor the logs to ensure proper sync
3. Verify all jobs restored correctly
4. Test invoice generation

**Next**: Confirm you want to proceed and what platform you're using (Android/iOS)

---

**Estimated completion time**: 5-10 minutes
**Risk level**: 🟢 LOW (Cloud backup intact, fixes in place)
**Rollback**: Easy (Restore from Firebase console if needed)
