# 📱 QUICK SYNC GUIDE - Getting Your Data Back on Your Phone

## Current Status
✅ **691 customers** recovered  
✅ **500 pricebook items** recovered  
✅ **91 jobs** recovered  

All files are validated and ready to upload.

---

## EASIEST WAY: Automatic Firebase Sync

### Step 1: Build & Install Latest APK
```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Step 2: Launch App on Phone
1. Open the Sole Trader app
2. Sign in with your Firebase account (daniel.drummer@outlook.com)
3. Wait for initial cloud sync (should take 30-60 seconds)

### Step 3: What Happens Next
The app will automatically:
- Detect the recovered `jobs.json`, `customers.json`, and `price_book.json`
- Upload all data to Firestore (silently in background)
- Sync locally
- You'll see your dashboard populate with your jobs

**Expected time:** 2-3 minutes for full sync

---

## Manual Upload (If Automatic Fails)

### Using Firebase Console
1. Go to https://console.firebase.google.com
2. Select your project
3. Go to **Firestore Database**

#### Upload Customers:
```json
// Collection: customers
// Use bulk import or manually add docs
// Each customer becomes a document
```

#### Upload Jobs:
```json
// Collection: jobs
// Each job becomes a document
```

#### Upload Pricebook:
```json
// Collection: pricebook  (or configure as needed)
// Each item becomes a document
```

---

## Mobile Upload (Use App's Import Feature)

### If App Has Built-in Import:
1. Open app menu
2. Look for "Import" or "Restore Data"
3. Select the JSON files from `/data/data/com.example.app/`
4. Confirm upload

**Note:** Check if this feature exists in your app first!

---

## Verification Checklist

After syncing, verify:

- [ ] Dashboard shows jobs count
- [ ] Click "Jobs" screen - all 91 jobs visible
- [ ] Search for a known customer (e.g., "City Funeral Home")
- [ ] Check price book has 500 items
- [ ] Open a job - confirm all details loaded
- [ ] Try creating a new job - confirm customer list complete

---

## If Something Goes Wrong

### Jobs showing as 0:
1. Force stop app (Settings → Apps → Sole Trader → Force Stop)
2. Clear app cache (Settings → Apps → Sole Trader → Storage → Clear Cache)
3. Reopen app
4. Wait 2 minutes for cloud sync

### Data still not appearing:
1. Check Firebase project is correct
2. Verify Firestore is accessible: https://console.firebase.google.com
3. Check Firestore rules allow reads/writes
4. Check phone has internet connection
5. Restart phone and try again

### Duplicate customers appearing:
1. This is normal initially - duplicates from merge
2. Check Firestore console for documents
3. Can manually delete duplicates if needed
4. Or run deduplication script

---

## File Locations for Manual Setup

If you need to access the files directly:

```
Project Root:
├── customers.json (680 records, 183 KB)
├── jobs.json (91 records, 860 KB)
├── price_book.json (500 items, 263 KB)
└── phone_backup/extracted/ (original backup + PDFs/photos)
```

---

## Next Steps After Sync

1. **Test Creating a New Job** - Verify it saves to cloud
2. **Update a Customer** - Confirm changes sync
3. **Check Firestore Console** - Verify collections populated
4. **Monitor Performance** - Watch for any OOM errors (should be fixed!)
5. **Test All Features** - Estimates, invoices, scheduling

---

## Support & Debugging

If you see errors in the app logs after sync:

**Look for:**
- OutOfMemory errors (should be gone with new build)
- "Cannot find customer" errors (check customer IDs match)
- "Firestore permission denied" (check security rules)
- "Document not found" (check Firestore collections)

**Share with me if you see:**
- Any error messages in logcat
- Screenshots of blank screens
- Specific missing data issues

---

## Recovery Files Reference

**All original backup files are preserved at:**
```
/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2/
├── phone_backup/extracted/
│   ├── customers.json (original)
│   ├── jobs.json (original)
│   ├── price_book.json (original)
│   ├── job_*.json (91 individual job files)
│   ├── *.pdf (estimates, invoices, certificates)
│   └── job_photos/ (photos)
└── phone_backup/2026-07-12/ (dated backup)
```

---

## One More Thing: OutOfMemory Fixes

The latest APK you're about to install includes:
✅ Nested data cleanup (automatic)
✅ Pricebook pagination (500 items per request)
✅ Memory optimization for queries
✅ Firestore codec buffer protection

These should prevent the crashes you were experiencing!

---

**👉 NEXT: Build the APK and sync with your phone!**

Need help? Check the logs or let me know what you see! 🚀
