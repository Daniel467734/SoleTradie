# 🔴 NUCLEAR RESET - Complete Data Wipe & Restore Guide

## What This Does

This is a **complete reset** of your entire application data:

### ❌ DELETES (Everything Gone)
- **Firestore Cloud**: All `jobs`, `contacts`, `pricebook` collections
- **Local Device**: All app data, cache, preferences
- **Clean slate**: Start fresh with zero data

### ✅ RESTORES (Fresh Import)
- **92 jobs** from `jobs.json`
- **Contacts** from `customers.json`
- **Price book** from `price_book.json`
- All synced to device on first app restart

---

## Pre-Reset Checklist

Before running the script, verify:

- [ ] Device is plugged in and connected via ADB
  ```bash
  adb devices
  ```
  Should show: `device_name    device`

- [ ] Backup files exist locally:
  - [ ] `~/SOLE TRADER APP VERSIONS/Version 2.2/jobs.json` (860K)
  - [ ] `~/SOLE TRADER APP VERSIONS/Version 2.2/customers.json` (183K)
  - [ ] `~/SOLE TRADER APP VERSIONS/Version 2.2/price_book.json` (263K)

- [ ] All three code fixes are applied and app is built
  - [ ] Fix #1: `firestore_service.dart` line 202
  - [ ] Fix #2: `job_details_screen.dart` lines 584, 611, 628
  - [ ] Fix #3: `firestore_service.dart` line 133

- [ ] App is closed on device (not running)

---

## Step-by-Step Execution

### 1. Make Script Executable

```bash
chmod +x ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/NUCLEAR_RESET_AND_RESTORE.sh
```

### 2. Run the Reset Script

```bash
zsh ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/NUCLEAR_RESET_AND_RESTORE.sh
```

The script will:
- ✅ Verify all backup files exist
- ✅ Confirm ADB device connection
- ✅ Create pre-reset backups (safety)
- ✅ Delete local app data on device
- ✅ Clear all caches and preferences
- ⏸️ **PAUSE** - Manual step required (see below)

### 3. Delete Firestore Collections (MANUAL)

The script will pause and ask you to manually delete Firestore collections:

**Go to Firebase Console:**

1. Open: https://console.firebase.google.com
2. Select your project
3. Click: **Firestore Database** (left sidebar)
4. You'll see these collections:
   - `jobs`
   - `contacts`
   - `pricebook`
   - (and others - leave those alone)

**For each collection (`jobs`, `contacts`, `pricebook`):**

1. Click the three dots `⋮` next to the collection name
2. Select **"Delete collection"**
3. Confirm the deletion (type collection name if prompted)
4. Wait for deletion to complete (usually 10-30 seconds)

**Visual Guide:**
```
Firestore Database
├── jobs           ⋮ → Delete collection
├── contacts       ⋮ → Delete collection
├── pricebook      ⋮ → Delete collection
├── users          ⋮ (leave this alone)
└── ...            ⋮ (leave others alone)
```

After deleting all three, return to terminal and press ENTER.

### 4. App Restart & Sync

The script will tell you the final steps:

1. **Close the app** on device (swipe away or force stop)
2. **Restart the app**
3. **Wait 30-60 seconds** for initial sync
4. **Watch logs** for sync completion:
   ```bash
   adb logcat | grep flutter
   ```
   Look for:
   ```
   ✅ Loaded 92 jobs from Firestore
   ✅ Saved 92 jobs to local storage
   ✅ Synced 92 jobs from Firebase
   ```

---

## Expected Results

After completion, you should see:

✅ App displays ~92 jobs  
✅ Jobs list shows all contacts  
✅ Price book is populated  
✅ No sync errors in logs  
✅ App runs smoothly  

### Testing

1. **Open a few jobs** - verify they have data
2. **Generate a new invoice** - make sure it stays after sync
3. **Check contacts** - should see all customer data
4. **Check price book** - should load quickly

---

## If Something Goes Wrong

### Issue: App shows 0 jobs after restart
**Solution:**
1. Close app completely
2. Restart app
3. Wait another 30-60 seconds
4. Check logs for errors

### Issue: "Failed to sync" errors
**Solution:**
1. Verify internet connection on device
2. Verify Firestore collections are truly empty
3. Check Firebase is accessible (open website)
4. Try restarting app again

### Issue: App crashes on startup
**Solution:**
1. Check logs: `adb logcat | grep ERROR`
2. Ensure all three code fixes are applied
3. Rebuild app: `flutter clean && flutter pub get && flutter run --release`

### Restore from Backup

If you need to undo this entire operation:

```bash
# Backup was created at:
~/SOLE TRADER APP VERSIONS/Version 2.2/backup/pre_nuclear_reset_YYYYMMDD_HHMMSS/

# Restore local files:
cp backup/pre_nuclear_reset_*/jobs.json ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/
cp backup/pre_nuclear_reset_*/customers.json ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/
cp backup/pre_nuclear_reset_*/price_book.json ~/SOLE\ TRADER\ APP\ VERSIONS/Version\ 2.2/

# Then use the normal restore script
```

---

## FAQ

**Q: Will this delete my PDFs/invoices?**  
A: No. PDFs are stored separately in Firebase Storage. This only deletes database records. Invoices will be restored with job data.

**Q: Can I undo this?**  
A: Yes! The script creates backups before doing anything. See "Restore from Backup" above.

**Q: How long does this take?**  
A: Usually 5-10 minutes total:
- Script execution: 2-3 minutes
- Manual Firestore deletion: 2-3 minutes
- App sync on restart: 1-2 minutes

**Q: What if I close the app during initial sync?**  
A: Just restart it. The sync will resume.

**Q: Do I need to rebuild the app?**  
A: No, just restart it. The fixes are already in the code.

---

## Support

If you need help:
1. Check the logs: `adb logcat | grep flutter`
2. Screenshot any error messages
3. Note the timestamp of when it failed
4. Share the relevant log section

Good luck! 🚀
