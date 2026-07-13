# ✅ TESTING CHECKLIST - Firestore Metadata-Only Query Fix

## Status
- ✅ Code compiled successfully
- ✅ APK built: `build/app/outputs/flutter-apk/app-debug.apk` (223MB)
- ✅ APK installed on device via ADB

## Immediate Actions

### 1. Launch App
- [ ] Cold start app
- [ ] Observe startup time (should be ~3-4 seconds, not 5-6)
- [ ] No crashes during startup
- [ ] No "Zone mismatch" warnings in logcat

### 2. Monitor Logcat During Startup
Run this in terminal while app launches:
```bash
adb logcat | grep -E "flutter|OutOfMemory|Zone|GC|Firestore"
```

Look for these messages (in order):
1. `📱 Loaded 103 jobs from local storage`
2. `📊 Found X metadata jobs changed since ... (batched loading)`
3. `✅ Synced 103 jobs from Firebase (delta sync)`
4. `✓ Jobs already in sync (no changes since ...)`

### 3. Verify No OOM Errors
```bash
adb logcat | grep -i "outofmemory"
```
Should return **NOTHING**. If it shows anything, we have a problem.

### 4. Verify No GC Stalls
```bash
adb logcat | grep "WaitForGcToComplete"
```
Should show values like:
- ✅ Good: `WaitForGcToComplete for 50ms`
- ✅ Good: `WaitForGcToComplete for 100ms`
- ❌ Bad: `WaitForGcToComplete for 700ms` (indicates problem)
- ❌ Bad: `WaitForGcToComplete blocked Alloc` (indicates problem)

## Full Testing Sequence

### Phase 1: Startup & Loading (2 min)
- [ ] App launches without crash
- [ ] Jobs list displays 103 jobs smoothly
- [ ] No stuttering or freezing during load
- [ ] Logcat shows "metadata jobs changed" (not "full jobs")
- [ ] Estimated load time: <3 seconds

### Phase 2: Navigation (3 min)
- [ ] Tap on a job to open details
- [ ] Full job data loads smoothly (should see estimates, invoices, etc.)
- [ ] Switch between multiple jobs
- [ ] Go back to jobs list - should still show all 103
- [ ] No crashes during navigation

### Phase 3: Status Changes (2 min)
- [ ] Open a job's popup menu
- [ ] Select "Update Status"
- [ ] Change status to "Archived"
- [ ] Check logcat for: `✅ Job J#### synced to cloud`
- [ ] Close job, return to list
- [ ] Verify job no longer shows in "Active" filter
- [ ] Switch to "Archived" filter - job should appear there

### Phase 4: Persistence (3 min)
- [ ] Restart app completely
- [ ] Jobs list should still show all 103 jobs
- [ ] The job you archived should still be archived (not in Active list)
- [ ] Change another job's status
- [ ] Restart again - new status should persist

### Phase 5: Price Book (2 min)
- [ ] Navigate to price book section
- [ ] Verify all ~52K items load smoothly
- [ ] Search for an item - should find quickly
- [ ] No "Unterminated string" errors in logcat

### Phase 6: General Responsiveness (3 min)
- [ ] Scroll through jobs list quickly - should be smooth
- [ ] Try creating a new job - should respond quickly
- [ ] Try editing customer info - should respond quickly
- [ ] Overall UI should feel responsive, no 1+ second delays

### Phase 7: Stress Test (5 min)
- [ ] Rapidly toggle between different sections (Jobs, Customers, Price Book)
- [ ] Open and close 5-10 different jobs in quick succession
- [ ] Restart app 3 times quickly
- [ ] Watch for any crashes or anomalies

## Expected Results

### ✅ SUCCESS (All these should be true)
```
Startup time: 3-4 seconds (not 5-6)
Jobs load time: 1-2 seconds (not 10-15)
GC stalls: <100ms (not 700ms+)
Crashes: NONE (no OutOfMemoryError)
Logcat: Shows "metadata jobs changed" (not "full jobs")
UI: Smooth and responsive throughout
Data: Persists across app restarts
Price book: Loads all 52K items without corruption
```

### ❌ FAILURE (Any of these = problem remains)
```
OutOfMemoryError appears in logcat
WaitForGcToComplete blocked Alloc for 700ms+
App crashes when loading jobs
App crashes when switching to price book
Logcat shows "java.lang.OutOfMemoryError"
Jobs list takes >5 seconds to load
UI freezes for >1 second at any point
Price book shows "Unterminated string" error
```

## Detailed Logcat Analysis

### What to Look For

**Good signs**:
```
I/flutter: 📱 Loaded 103 jobs from local storage
I/flutter: 📊 Found 15 metadata jobs changed since 2026-07-13 11:00:00 (batched loading)
I/flutter: ✅ Synced 103 jobs from Firebase (delta sync)
I/flutter: ✓ Jobs already in sync (no changes since 2026-07-13 11:43:53.131647)
I/com.example.app: Alloc concurrent mark compact GC freed 6MB AllocSpace bytes, 2% free, 490MB/512MB
I/flutter: ✅ Job J2834 synced to cloud (status: archived)
```

**Bad signs**:
```
W/com.example.app: Throwing OutOfMemoryError "Failed to allocate a 37748752 byte"
I/com.example.app: WaitForGcToComplete blocked Alloc on Alloc for 700ms
I/com.example.app: Clamp target GC heap from 545MB to 512MB
E/AndroidRuntime: FATAL EXCEPTION
D/flutter: Zone mismatch
E/flutter: Unterminated string in JSON
```

## If Problems Occur

### OutOfMemoryError Still Shows
1. Check exact stack trace - should NOT mention Firebase codec anymore
2. Could be elsewhere in app
3. Run: `adb shell dumpsys meminfo com.example.app`
4. Report the full stack trace

### App Crashes During Jobs Load
1. Capture full logcat: `adb logcat > crash.log`
2. Look for "FATAL EXCEPTION"
3. Send the stack trace to development team

### Jobs Taking >5 Seconds to Load
1. Check network - WiFi or mobile?
2. Check Firebase connection status
3. Verify local storage isn't corrupted: `adb shell ls -la /data/data/com.example.app/files/`
4. Check if jobs.json or price_book.json are present and accessible

### GC Still Stalling at 700ms
1. Run: `adb shell getprop ro.product.model` (check device model)
2. Run: `adb shell getprop | grep ro.build.version.sdk` (check Android version)
3. This could be device-specific, not our code
4. Try: `adb shell pm clear com.example.app` (clear cache) then restart

---

## Quick Start Testing

The minimum viable test:
1. `adb logcat | grep flutter` (open terminal 1)
2. Launch app (in terminal 2: `adb shell am start -n com.example.app/.MainActivity`)
3. Wait for jobs to load (~2 seconds)
4. Check that logcat shows "metadata jobs changed" NOT "OutOfMemoryError"
5. Open a job, verify it loads completely
6. Return to list, verify smooth
7. **Result**: If no crashes, fix is working ✅

---

**Ready?** Plug in device and start testing!
