# ✅ Pre-Restoration Verification Checklist

Before running the delete/restore scripts, verify everything is ready:

## Code Fixes Applied ✅

- [x] **Fix #1**: `firestore_service.dart` line 202 - Added `'attachments': job.attachments ?? []`
- [x] **Fix #2**: `job_details_screen.dart` lines 584, 611, 628 - Merge strategy for attachments
- [x] **Fix #3**: `firestore_service.dart` line 133 - Commented out `'attachments': FieldValue.delete()`

**Verification**: All three fixes are in the code and app builds without errors ✅

## Firestore Cloud Backup Ready

- [ ] **Count jobs in Firestore**: Should be ~92 jobs
  - Go to: Firebase Console → Firestore Database → `jobs` collection
  - Count documents (should show ~92)
  
- [ ] **Spot check a few jobs**: Verify they have data
  - Open 2-3 random job documents
  - Verify each has: `customerName`, `address`, `attachments` (array field)
  - Verify some jobs have attachments (invoice PDF paths)

- [ ] **Note any jobs with invoices/attachments**:
  - These should be visible in the Firestore documents
  - Example: `attachments: ["Invoice (1).pdf", "Quote (1).pdf"]`

## Local Backup Created

- [ ] **Have a local backup of jobs.json**:
  - Location: `~/SOLE TRADER APP VERSIONS/Version 2.2/backup/jobs_backup_*.json`
  - File size: Should be several MB (if you have 92 jobs)
  - Keep this file safe until restoration is verified!

## App Build & Device Ready

- [ ] **App rebuilt with all three fixes**:
  ```bash
  flutter clean
  flutter pub get
  flutter run --release
  ```

- [ ] **Device/Emulator connected**:
  ```bash
  adb devices
  # Should show one device with status "device"
  ```

- [ ] **App version updated** (if desired):
  - Optional: Update version in `pubspec.yaml`
  - Currently: Check `pubspec.yaml` for version

## Network Connectivity

- [ ] **Device has internet connection**:
  - WiFi or mobile data enabled
  - Can reach Firebase (test: open any web page)

- [ ] **Firebase connectivity verified**:
  - App can reach Firebase services
  - Check: Open app, look for "✅ FirestoreService initialized" in logs

## Ready to Execute?

If all boxes are checked ✅, you're ready to run:

```bash
# Step 1: Make scripts executable
chmod +x ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/delete_and_restore_jobs.sh

# Step 2: Run restoration script
zsh ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/delete_and_restore_jobs.sh

# Step 3: Follow the manual steps in the script output
```

## Post-Restoration Verification

After running the script and restarting the app:

- [ ] **App shows ~92 jobs** in the jobs list
- [ ] **Jobs load quickly** (should be instant from local storage)
- [ ] **Sample jobs have invoices visible**:
  - Open a few jobs
  - Check that attachments/invoices are listed
- [ ] **Can generate new invoices**:
  - Create a new invoice
  - Navigate away and back
  - Invoice should still be there ✅
- [ ] **Cloud sync works**:
  - Watch logs for "✅ Synced X jobs from Firebase"
  - New invoices should appear in Firestore

## Troubleshooting

**Problem**: After restart, app shows 0 jobs
- **Solution**: Check logs for sync errors, wait 30 seconds, restart again

**Problem**: Some jobs missing after restore
- **Solution**: Check Firestore console, jobs may still be syncing

**Problem**: Invoices still disappearing
- **Solution**: Ensure all THREE fixes are in the deployed app, rebuild if needed

---

**Status**: Ready to execute the restoration! 🚀
