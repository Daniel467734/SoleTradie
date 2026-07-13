# Jobs Not Showing - Root Cause & Fix

## The Problem

Jobs exist in `jobs.json` **in the project root** on your computer, but the Flutter app on your phone looks for them in a **different location** - the phone's application documents directory.

### File Location Mismatch:
- **Project Root:** `/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2/jobs.json`
  - This is YOUR computer's file
  - Used for development/testing only
  
- **Phone Storage:** `/data/user/0/com.example.app/documents/jobs.json`
  - This is where the app actually reads/writes data
  - App looks here at runtime

## Why Jobs Aren't Showing

1. ✅ jobs.json exists in project root (91 jobs, fully valid)
2. ❌ But jobs.json does NOT exist on phone's local storage yet
3. ❌ App launches, checks phone storage, finds nothing
4. ❌ App shows empty jobs list
5. ❌ Cloud sync tries to happen but fails (timing issue)

## The Solution: Push jobs.json to Phone

### Option 1: Via ADB Push (Fastest - Recommended)

```bash
# 1. Connect phone via USB with developer mode enabled

# 2. Push the jobs.json file to phone storage
adb push "/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2/jobs.json" \
  "/data/user/0/com.example.app/documents/jobs.json"

# 3. Verify it was pushed
adb shell ls -lh /data/user/0/com.example.app/documents/jobs.json

# 4. Do the same for customers and pricebook
adb push "/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2/customers.json" \
  "/data/user/0/com.example.app/documents/customers.json"

adb push "/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2/price_book.json" \
  "/data/user/0/com.example.app/documents/price_book.json"

# 5. Close and reopen the app on your phone
# Jobs should now appear!
```

### Option 2: Via Firebase Console (If ADB not working)

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to Firestore Database
4. Create collection `users` (or navigate to it)
5. Create document with your user ID
6. Create collection `jobs` under that document
7. Manually add your jobs (tedious for 91 jobs - not recommended)

### Option 3: Via App's Import Feature

If your app has a built-in import feature, you could:
1. Email yourself the `jobs.json` file
2. Open it on phone
3. Use app's import dialog
4. Select the file
5. Import all jobs

## Step-by-Step (Option 1 - Recommended)

```bash
# Full command sequence to push all 3 files

cd "/Users/dan/SOLE TRADER APP VERSIONS/Version 11 Settings need sfixing copy 2"

echo "📱 Pushing jobs.json..."
adb push jobs.json /data/user/0/com.example.app/documents/jobs.json

echo "👥 Pushing customers.json..."
adb push customers.json /data/user/0/com.example.app/documents/customers.json

echo "📚 Pushing price_book.json..."
adb push price_book.json /data/user/0/com.example.app/documents/price_book.json

echo "✅ All files pushed! Now close and reopen the app on your phone."
```

## After Pushing Files

1. **Close the app completely** on your phone (swipe from recent apps)
2. **Wait 2 seconds**
3. **Reopen the app**
4. **Wait 10 seconds for sync** (may see loading spinner)

You should now see:
- ✅ **Dashboard:** Job count showing 91
- ✅ **Jobs Screen:** Full list of all jobs
- ✅ **Customers:** 680 customers available
- ✅ **Price Book:** 500 items loaded

## Verify Files Were Pushed

```bash
# Check each file exists and has the right size
adb shell ls -lh /data/user/0/com.example.app/documents/

# Expected output:
# -rw------- 1 u0_a123 u0_a123    183K 2026-07-13 13:10 customers.json
# -rw------- 1 u0_a123 u0_a123    860K 2026-07-13 13:10 jobs.json
# -rw------- 1 u0_a123 u0_a123    263K 2026-07-13 13:10 price_book.json
```

## Troubleshooting

### "adb: command not found"
- Install Android SDK: `brew install android-sdk`
- Or add to PATH: `export PATH=$PATH:~/Android/sdk/platform-tools`

### "device not found"
- Enable USB Debugging on phone: Settings > Developer Options > USB Debugging
- Connect phone with USB cable
- Run: `adb devices` (should show your phone)

### Files still not appearing
1. Check files were actually pushed: `adb shell ls -l /data/user/0/com.example.app/documents/`
2. Check file sizes are correct (should be ~180KB, ~860KB, ~260KB)
3. Force close app: `adb shell am force-stop com.example.app`
4. Clear app cache: `adb shell pm clear com.example.app`
5. Reopen app

### "Permission denied" when pushing
- Your user account doesn't have write permission to phone storage
- Try: `adb root` (requires phone to allow it)
- Or use: `adb push` with sudo: `sudo adb push ...`

## Why This Happens

The recovered `jobs.json` file:
- ✅ Is in the correct JSON format
- ✅ Contains all 91 jobs with full details
- ✅ Has all customer names and addresses
- ✅ Includes estimates, invoices, and status history

But it's **on your computer**, not **on your phone**. The Flutter app is running **on your phone**, so it can only read files from the phone's filesystem.

The app WILL eventually sync to Firebase, but it needs an initial seed of data on the phone to display immediately, and to avoid an incomplete sync that might miss old jobs.

## Next Step After Restore

Once jobs appear on phone:
1. Keep phone connected and give it 5 minutes
2. App will auto-sync all data to Firebase in background
3. Data becomes cloud-backed and syncs across devices
4. You'll no longer lose data if app crashes

---

**Bottom Line:** Push the 3 JSON files to phone → Reopen app → Jobs appear immediately ✅

