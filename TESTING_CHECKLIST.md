# Testing Checklist - Firebase Query Optimization

## Pre-Deployment Verification ✅

### Build & Deployment
- [x] Flutter build web --release completes without errors
- [x] Web app deployed to Firebase Hosting successfully
- [x] No compilation errors in new services/models
- [x] Imports and dependencies resolved correctly

### Code Quality
- [x] No unused imports (removed cloud_firestore from job_lazy_load_service.dart)
- [x] All compilation errors resolved
- [x] Type safety verified (no unsafe casts)
- [x] Null safety enforced throughout

---

## Post-Deployment Testing 🧪

### Test 1: App Startup Performance
**Goal**: Verify app loads instantly without OutOfMemoryError

**Steps**:
1. Clear app cache and app data
2. Launch app fresh on device with 100+ jobs
3. Time how long until jobs list appears

**Expected**:
- Jobs list appears instantly (< 2 seconds) ✅
- No "Device memory low" warnings
- No OutOfMemoryError crashes
- Logcat shows: "📱 Loaded {N} job summaries from local storage"

**Regression**:
- If blank screen for > 3 seconds → Check if loadJobs() is blocking
- If crash on startup → Check local storage corruption

---

### Test 2: Mark Invoice as Paid
**Goal**: Verify invoice status updates instantly

**Steps**:
1. Open a job with unpaid invoices
2. Tap invoice → Mark as Paid
3. Observe success message timing

**Expected**:
- Success message appears instantly (< 500ms) ✅
- Invoice status changes immediately in UI
- Logcat shows non-blocking Firebase sync:
  - "💾 Saved to local cache immediately"
  - "☁️ Syncing to Firebase (background)" (after message appears)
  - "✅ Saved to Firebase"

**Regression**:
- If message takes 3+ seconds → saveJob() is still awaiting Firebase
- If invoice reverts after 1 second → Firebase sync not implemented

---

### Test 3: Offline Functionality
**Goal**: Verify jobs list loads from cache when offline

**Steps**:
1. Open app (connected)
2. Verify jobs load
3. Enable Airplane Mode
4. Kill app completely
5. Relaunch app
6. Verify jobs list still appears (from cache)

**Expected**:
- Jobs list appears instantly even offline ✅
- Logcat shows: "📱 Loaded X job summaries from local storage"
- No Firebase errors in logs
- "Sync pending" or similar indicator (optional)

**Regression**:
- If blank screen when offline → Local cache not working

---

### Test 4: Memory Usage
**Goal**: Verify memory stays under control with 100+ jobs

**Steps**:
1. Install Android Profiler or equivalent
2. Launch app
3. Load job list (don't tap into jobs yet)
4. Check memory usage

**Expected**:
- Memory ~200-300MB for 100 job summaries ✅
- No steady memory growth (memory leak indicator)
- If you tap into 20 different jobs sequentially, memory stays ~500MB

**Regression**:
- If memory > 1GB with just summary list → Summaries not lightweight enough
- If memory keeps growing → Memory leak in cache

---

### Test 5: Navigate Into Job Details
**Goal**: Verify full job details load correctly on-demand

**Steps**:
1. Open jobs list
2. Tap into first job
3. Verify all job details display correctly
4. Go back, tap into another job
5. Repeat 5 times
6. Check memory profile

**Expected**:
- Job details load correctly ✅
- No blank/missing fields
- Memory grows slightly (caching latest jobs)
- Logcat shows pattern:
  - "📱 Job {id} loaded from local storage" (if cached)
  - "☁️ Job {id} loaded from Firebase" (if first load)

**Regression**:
- If details missing → JobLazyLoadService.loadJobDetails() not working
- If memory grows unbounded → LRU cache eviction not working

---

### Test 6: Create New Job
**Goal**: Verify new jobs are added to summaries immediately

**Steps**:
1. Create a new job from jobs screen
2. Observe jobs list updates
3. Navigate to new job and verify details

**Expected**:
- New job appears in list instantly ✅
- Summary contains correct metadata
- Full details load correctly when tapped

**Regression**:
- If new job doesn't appear → Summary cache not updated
- If new job appears but missing fields → Metadata not populated

---

### Test 7: Edit & Save Job
**Goal**: Verify job edits sync correctly

**Steps**:
1. Open a job
2. Change job title or add invoice
3. Save changes
4. Check local cache file
5. Go offline and reopen job (verify changes persisted)
6. Go online and check Firestore (verify synced)

**Expected**:
- Changes save instantly (no loading dialog) ✅
- Local file updated immediately
- Firestore updated asynchronously
- All changes persist after app restart

**Regression**:
- If changes take > 2 seconds → Non-blocking sync not implemented
- If changes lost after restart → Local cache not saved

---

### Test 8: Cloud Sync Refresh
**Goal**: Verify background cloud sync updates local cache

**Steps**:
1. Open app and note jobs list
2. Use Firestore Console to manually update a job
3. Return to app or wait 2 seconds
4. Verify update appears in list
5. Check background refresh logs

**Expected**:
- Updated job appears without manual refresh ✅
- Logcat shows: "✅ Synced {N} job summaries from Firebase"
- UI updates automatically via onCloudUpdate callback

**Regression**:
- If changes don't appear → Background refresh not triggering
- If UI doesn't update → onCloudUpdate callback not working

---

### Test 9: Device Memory Pressure
**Goal**: Verify app handles low-memory scenarios gracefully

**Steps**:
1. Open app
2. Tap through 30+ jobs sequentially (triggers cache evictions)
3. Monitor memory profile

**Expected**:
- Memory stays relatively flat (max ~10MB for job details) ✅
- Cache eviction occurs silently without UI impact
- No crashes or OOM errors

**Regression**:
- If memory grows unbounded → LRU cache not evicting old jobs
- If crashes with "Failed to allocate" → Cache size too large

---

### Test 10: Firestore Metadata Fields
**Goal**: Verify precomputed metadata is stored and used

**Steps**:
1. Save a job (add invoice)
2. Check Firestore console for the job document
3. Verify fields present:
   - invoiceCount
   - estimateCount
   - totalAmount
   - hasUnpaidInvoices

**Expected**:
- All metadata fields present ✅
- Values accurate (match actual invoices/estimates)
- Fields update when job is re-saved with changes

**Regression**:
- If fields missing → updateJobMetadata() not called
- If values wrong → Calculation logic error

---

## Regression Test Suite

### Critical Paths (Must Not Break)
1. [ ] App launch → jobs load
2. [ ] Create job → appears in list
3. [ ] Open job → details load
4. [ ] Edit job → changes persist
5. [ ] Delete job → removed from list
6. [ ] Mark invoice paid → syncs
7. [ ] Offline mode → cache works
8. [ ] Re-launch app → state restored

### Performance Benchmarks
- [ ] App startup: < 2 seconds
- [ ] Mark invoice paid: < 500ms UI response
- [ ] Memory with 100 jobs: < 300MB
- [ ] Firebase query: < 1 second
- [ ] Job detail load: < 1 second

### Error Handling
- [ ] Network timeout → graceful fallback to cache
- [ ] Corrupted cache file → re-download from Firebase
- [ ] Device out of storage → handle gracefully
- [ ] Firestore permission error → show user-friendly message

---

## Debug Commands

### Check Local Storage (via adb shell)
```bash
# List cached jobs
adb shell "ls -lah /data/data/com.soletradie.app/app_flutter/"

# View summary cache (if readable)
adb shell "cat /data/data/com.soletradie.app/app_flutter/job_summaries.json"

# Check cache size
adb shell "du -sh /data/data/com.soletradie.app/app_flutter/"
```

### Monitor Firestore Writes
1. Open Firestore Console
2. Go to Rules & Security
3. Verify metadata fields are created when jobs are saved
4. Check write counts (should match save operations)

### Logcat Patterns (Good Signs)
```
✅ Loaded 105 job summaries from local storage
✅ Synced 105 job summaries from Firebase
✅ Job abc123 loaded from local storage
💾 Saved job details to local storage
☁️ Job abc123 synced to Firebase
🗑️ Evicted old_id from job cache
```

### Logcat Patterns (Bad Signs)
```
❌ Error loading job summaries
❌ OutOfMemoryError: failed to allocate
⚠️ Job loading took > 3 seconds
⚠️ Memory pressure detected
```

---

## Issue Resolution Guide

### Issue: OutOfMemoryError Still Occurs
**Investigation**:
1. Check if using old code path (not JobLazyLoadService)
2. Verify cache eviction is working (look for 🗑️ logs)
3. Check if loading multiple jobs simultaneously
4. Monitor memory profile during job navigation

**Solution**:
- Reduce LRU cache size from 20 to 10 in job_lazy_load_service.dart
- Implement more aggressive memory cleanup
- Profile to find memory leaks

---

### Issue: Summaries Not Syncing from Cloud
**Investigation**:
1. Check Firebase authentication status
2. Verify Firestore permissions allow read/write
3. Check if background refresh is triggered
4. Look for network errors in logs

**Solution**:
- Force manual sync via sync button
- Verify Firestore security rules
- Check authentication token expiry

---

### Issue: Invoices Marked Paid Still Revert
**Investigation**:
1. Check if saveJob() is awaiting Firebase (should not be)
2. Verify JobLazyLoadService.saveJobDetails() non-blocking
3. Check if sync is actually reaching Firebase
4. Look for cache invalidation issues

**Solution**:
- Verify non-blocking .then() pattern is used
- Add debug logging to track sync stages
- Check Firestore for actual saved data

---

### Issue: App Still Crashes on Startup
**Investigation**:
1. Check device RAM (if < 1GB, very limited)
2. Verify local cache files not corrupted
3. Check if still loading old jobs.json
4. Monitor memory during startup

**Solution**:
- Clear app cache and restart
- Delete job_summaries.json and re-download
- Check for file system issues
- Reduce initial job load limit

---

## Success Metrics (Post-Deployment)

Track these metrics over time:

1. **Crash Rate** (target: 0%)
   - OutOfMemoryError crashes should be eliminated
   - Monitor in Firebase Crashlytics

2. **User Session Duration** (target: +30%)
   - App should crash less, sessions longer

3. **Performance** (target: all < 2s)
   - App startup time
   - Jobs list load time
   - Firebase query time

4. **User Feedback** (qualitative)
   - "App feels faster"
   - "No more crashing"
   - "Works on my old phone now"

---

## Sign-Off Checklist

- [ ] All critical tests passed
- [ ] No OutOfMemoryError crashes
- [ ] Performance benchmarks met
- [ ] Regression tests clean
- [ ] Memory profiling acceptable
- [ ] Firestore metadata correct
- [ ] Local storage optimized
- [ ] Team aware of changes
- [ ] Monitoring in place
- [ ] Ready for production

