# Cloud Sync Diagnostic Guide ☁️🔍

## Quick Access

1. Open your **Sole Tradie** app at https://soletradie-app.web.app/
2. Navigate to **Settings** ⚙️
3. Scroll down to find the button: **☁️ Cloud Status Debug** (purple outlined button)
4. Click it to run diagnostics

## What the Debug Screen Checks

### 1. **Authentication Status** 🔐
- ✅ Your login status
- ✅ Your Firebase UID
- ✅ Your email address
- **If Red**: You're not logged in - log in first

### 2. **Firestore Connection** 🔗
- ✅ Connectivity to Firebase
- ✅ Network/permissions to cloud database
- **If Red**: Firebase connection failed - check internet or Firebase rules

### 3. **Data Counts** 📊
Shows how many records exist in the cloud:
- **Jobs**: Number of job documents in Firestore
- **Customers**: Number of customer records in Firestore
- **Price Book**: Number of price book items in Firestore

### 4. **Errors List** ❌
If any errors occur during diagnosis, they'll be listed here with details

## Common Issues & Solutions

### Issue 1: "NOT authenticated"
**Problem**: Red box says "❌ NOT authenticated"

**Solutions**:
1. Log out and log in again:
   - Settings → Account Settings → [Logout button]
   - Log back in with your credentials
2. Clear browser cache and refresh
3. Check if Firebase project has users enabled

### Issue 2: "Firestore error"
**Problem**: Red box says "❌ Firestore connection error"

**Solutions**:
1. ✅ Check your internet connection
2. ✅ Make sure you're logged in (see Issue 1)
3. ✅ In Firebase Console, verify Firestore rules allow your user ID:
   ```
   match /users/{userId}/{document=**} {
     allow read, write: if request.auth.uid == userId;
   }
   ```
4. ✅ Check if Firestore is in read-only mode (maintenance)

### Issue 3: "0 Jobs" / "0 Customers" / "0 Price Book"
**Problem**: All data counts show 0, but you uploaded data before

**Solutions**:
1. **Data might be in local storage only**:
   - Use the "Throttled Cloud Sync" feature in settings
   - Click "Start Throttled Sync" to push local data to cloud
   - Wait for 100% completion ✅

2. **Data might be on wrong user account**:
   - Log out and log back in with the correct account
   - Run diagnostic again

3. **Data might not have been synced**:
   - In Settings, under "Cloud Sync & Storage"
   - Click "Upload" or "Start Throttled Sync"
   - Check back after upload completes

### Issue 4: "FirebaseIntegrationService error"
**Problem**: Error loading data through the service

**Solutions**:
1. Try refreshing the app (F5)
2. Wait 30 seconds and try again (cloud connection might be initializing)
3. Check the error message for more details

## How to Interpret Results

### ✅ All Green = Everything OK
```
✅ Authentication Status
  ✅ Authenticated
  UID: abc123xyz
  Email: you@example.com

✅ Firestore Connection
  ✅ Connected to Firestore

📊 Cloud Data Counts
  Jobs: 42
  Customers: 15
  Price Book: 200

✅ No errors detected
```

### ⚠️ Mixed Results = Partial Connectivity
- Auth works, Firestore works, but 0 data
- → Use "Throttled Sync" to upload data

### ❌ Red Items = Blocking Issues
- Fix authentication issues first
- Then fix connection issues
- Then check why data counts are 0

## Advanced Debugging

### Check Console Logs
1. Open browser developer tools (**F12**)
2. Click "Console" tab
3. Look for messages starting with 📍, ✅, ❌, ⚠️
4. These show exactly what's happening during sync

### Common Log Messages
```
✅ FirestoreService initialized for user: your@email.com
  → Login worked

📍 DIAGNOSTIC: Checking authentication...
  → Debug screen is running

❌ Firestore connection error: [error details]
  → Connection failed, see error for why

✅ Loaded 42 jobs via service
  → Data loaded successfully
```

### Re-run Diagnostics
1. After any fixes, click **"Re-check"** button
2. Wait for it to complete
3. Check if issues are resolved

## Next Steps After Diagnosis

### If Data Counts Are 0:
1. Go to **Settings**
2. Find **"Cloud Sync & Storage"** section
3. Click **"Start Throttled Sync"** button
4. Wait for progress to reach 100% ✅
5. Go back to debug screen and **Re-check**
6. Counts should now show data

### If Data Still Doesn't Show:
1. Make sure **all features** synced:
   - Jobs ✅
   - Customers ✅
   - Price Book ✅
   - Estimates ✅
   - Invoices ✅
2. Check if data exists locally first:
   - Create a test customer or job
   - Sync it up
   - Check debug screen again

### If Connection Issues Persist:
1. Try a different browser
2. Try incognito/private window
3. Check Firefox/Chrome settings for cookies/cache
4. Restart your device
5. Contact support with:
   - Your email address
   - UID from debug screen
   - Error messages from debug screen
   - Any errors from browser console

## Important Notes

📝 **This is a diagnostic tool** - it doesn't fix issues, just identifies them

📝 **No data is modified** - the debug screen only reads/checks, never writes

📝 **Safe to run multiple times** - use "Re-check" button as often as needed

📝 **Helps troubleshooting** - share debug results with support if needed

---

**Last Updated**: Version 2.2  
**If you need help**: Use this debug screen first, then share results in a support request!
