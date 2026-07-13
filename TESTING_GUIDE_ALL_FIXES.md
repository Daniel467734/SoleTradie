# 🧪 Testing Guide - After All Fixes

## Quick Test (5 minutes)

### Step 1: Install APK
```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Step 2: Clear Previous App Data
```bash
adb shell pm clear com.example.soltrader  # Adjust package name as needed
```

### Step 3: Watch Logcat
```bash
adb logcat | grep -E "✅|⚠️|OutOfMemory|FormatException|WaitForGcToComplete"
```

### Step 4: Launch App
- Should load in **3-4 seconds** (not 5-6s)
- Should show jobs list
- Watch logcat for corruption warnings (shouldn't see any)

### Step 5: Basic Operations
- Create a new job
- Edit an existing job
- Change job status
- Close app and restart

**Expected**: App responsive, no crashes, no lag

---

## Full Test (15 minutes)

### Test 1: Clean Load
```bash
adb shell pm clear com.example.soltrader
adb shell rm /data/data/com.example.soltrader/files/jobs.json*
```
- Launch app
- Should load quickly
- Jobs should sync from Firebase
- **Logcat**: `✅ Fetched metadata-only updates`

### Test 2: Repeated Operations
1. Create 5 new jobs
2. Edit each one to have different statuses
3. Delete 2 of them
4. Close app
5. Reopen app

**Expected**: All changes persisted, no lag, no crashes

### Test 3: Performance Check
```bash
adb logcat | grep -i "gc\|alloc\|memory"
```
Should NOT see:
```
OutOfMemoryError
WaitForGcToComplete blocked Alloc
Failed to allocate 37MB
```

### Test 4: Background Sync
1. Open app
2. Look at job count
3. Close app
4. Manually add a job in Firestore (using Firebase Console)
5. Open app again
6. **Expected**: New job appears automatically

### Test 5: Corruption Recovery (Advanced)
This tests the backup file mechanism:

```bash
# Stop app
adb shell am force-stop com.example.soltrader

# Corrupt the jobs file
adb shell
  # In adb shell:
  echo "truncated json" > /data/data/com.example.soltrader/files/jobs.json
  exit

# Reopen app
adb shell am start com.example.soltrader

# Check logcat
adb logcat | grep -E "corrupted|Backed up|Recovered"
```

**Expected logcat output**:
```
⚠️ WARNING: jobs.json is corrupted
💾 Backed up corrupted jobs.json to jobs.json.corrupt
✅ Recovered X jobs from backup
```

**Expected behavior**: App still loads previous jobs from backup

---

## Memory Profiling

### Before Fix Baseline
- Startup memory: 100-150MB
- Peak during sync: 150-200MB+ (OOM at 37MB codec buffer)
- GC stalls: 500-700ms
- Crashes: Yes

### After Fix Expected
- Startup memory: 60-80MB
- Peak during sync: 80-100MB
- GC stalls: <100ms
- Crashes: No

### How to Check
```bash
adb shell dumpsys meminfo com.example.soltrader | head -20
```

Look at "Native Heap Allocated Size" - should be stable around 80-100MB.

---

## Logcat Indicators

### ✅ Everything Working
```
I  FirebaseIntegration: ✅ Loaded 103 jobs from local storage (valid JSON)
I  FirestoreService: ✅ Fetched metadata-only updates from Firestore (206 bytes)
I  FirebaseIntegration: ✅ Saved 103 jobs to local storage (atomic write)
```

### ⚠️ Minor Issues (Handled)
```
⚠️ WARNING: jobs.json is corrupted
💾 Backed up corrupted jobs.json to jobs.json.corrupt
✅ Recovered 103 jobs from backup
```

### ❌ Critical Issues (Should NOT See)
```
OutOfMemoryError: Failed to allocate 37748752 bytes
OutOfMemoryError in MapFieldLite.putAll()
FormatException: Unexpected end of input (at character 126977)
WaitForGcToComplete blocked Alloc for 700ms
```

---

## Problem? Check This

### Symptom: App Still Crashes on Load
1. Check logcat for specific error
2. If corruption error → backup recovery should trigger
3. If OutOfMemory → might need to increase JVM heap
4. If other error → share full logcat

### Symptom: App is Still Laggy
1. Check if `✅ Loaded X jobs` appears quickly
2. Check if GC stalls appear in logcat
3. Might need to increase JVM memory settings

### Symptom: Jobs Keep Disappearing
1. Check if atomic write is completing: `✅ Saved X jobs`
2. Check if backup file exists: `adb shell ls -la /data/data/.../files/jobs.json*`
3. Might indicate file system permission issue

### Symptom: Corrupted File Keep Reappearing
1. This shouldn't happen with atomic writes
2. Check if temp file (`jobs.json.tmp`) is left behind
3. Manually delete: `adb shell rm /data/data/.../files/jobs.json.tmp`

---

## File System Check

To see what files exist after running:
```bash
adb shell ls -la /data/data/com.example.soltrader/files/ | grep jobs
```

**Expected after normal operation**:
```
-rw-rw----  jobs.json           (current, valid JSON)
-rw-rw----  jobs.json.backup    (previous known-good)
```

**After corruption was detected**:
```
-rw-rw----  jobs.json           (restored from backup)
-rw-rw----  jobs.json.backup    (previous known-good)
-rw-rw----  jobs.json.corrupt   (the corrupted file that was backed up)
```

**Never should see**:
```
-rw-rw----  jobs.json.tmp       (temp file not cleaned up - indicates write failed)
```

---

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| App crashes on load | Corrupted file | Should auto-recover from backup |
| App crashes during save | Write interrupt | Atomic writes should prevent this |
| Jobs missing after restart | Backup not created | Check `jobs.json.backup` exists |
| Lag when loading jobs | Metadata-only not working | Check logcat for "Fetched metadata-only" |
| OOM crash still happens | Old code still running | Clear app data and reinstall APK |
| No backup recovery | Backup file corrupted too | Contact support with logcat |

---

## Success Checklist

After running all tests above, you should be able to check:

- [ ] App launches in 3-4 seconds (not 5-6s)
- [ ] Jobs load without lag
- [ ] Can create, edit, delete jobs smoothly
- [ ] No crashes in logcat
- [ ] No OutOfMemoryError in logcat
- [ ] No "Unexpected end of input" errors
- [ ] No "WaitForGcToComplete" stalls >100ms
- [ ] Jobs persist after app restart
- [ ] Backup recovery works (if triggered)
- [ ] Normal usage is smooth and responsive

## If Everything Passes ✅

Great! All fixes are working. You can:
1. Build release APK: `flutter build apk --release`
2. Deploy to production
3. Monitor logcat for any issues on real devices

## If Something Fails ❌

Please capture:
1. Full logcat: `adb logcat > logcat_full.txt`
2. File listing: `adb shell ls -la /data/data/.../files/`
3. Describe what you were doing when crash happened
4. Share this information for debugging

---

**Last Updated**: 2026-07-13
**All Fixes**: Deployed and ready to test
**Expected Outcome**: Stable, fast, crash-free app
