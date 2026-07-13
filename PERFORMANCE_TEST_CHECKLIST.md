# Quick Performance Test Checklist

## Before You Start
- Device has the latest APK installed
- Good internet connection (for Firebase sync)
- Device has 50%+ battery

---

## Test 1: App Startup (30 seconds)
```
✓ Tap app icon
✓ Watch splash screen
✓ Dashboard appears within 2-3 seconds
✓ "✅ Synced X jobs from Firebase (delta sync)" appears in logs
✓ No "Zone mismatch" errors in logcat
```

**Expected**: App is responsive immediately, no lag

---

## Test 2: Jobs List (15 seconds)
```
✓ Tap "Jobs" tab
✓ List loads instantly from 104 jobs
✓ Scroll through list smoothly
✓ No stuttering or UI freezing
✓ Search field responds immediately as you type
✓ Status filter dropdown opens quickly
```

**Expected**: Buttery smooth scrolling, no frame drops

---

## Test 3: Open Job Details (10 seconds)
```
✓ Tap any job in the list
✓ Details screen opens within 1 second
✓ All job information loads quickly
✓ Scroll through estimates/invoices smoothly
✓ No memory warnings in logcat
```

**Expected**: Instant navigation, smooth scrolling

---

## Test 4: Edit & Save Job (20 seconds)
```
✓ Edit an invoice detail
✓ Change a line item
✓ Tap "Save"
✓ Wait for "✅ Job saved successfully" or "☁️ Job synced to Firebase"
✓ Check logcat for NO "Throwing OutOfMemoryError"
✓ Check logcat for NO "Unterminated string" errors
```

**Expected**: Save completes in <2 seconds, no errors

---

## Test 5: Price Book Load (10 seconds)
```
✓ Open a job's line items section
✓ Price book loads with 52,444 items
✓ Search for an item: "power", "outlet", "labour" etc
✓ Results appear instantly
✓ No "Could not load price book" errors
```

**Expected**: Instant search through 52K items

---

## Test 6: Memory Check (20 seconds)
```
✓ Open "Settings" → "Developer Options"
✓ Check "Memory Usage" or use Android Profiler
✓ Memory should be 150-250MB (not 400MB+)
✓ No "Background GC" freezes in logcat
✓ App stays responsive while syncing
```

**Expected**: Low memory usage, smooth GC cycles

---

## Test 7: Logcat Verification (5 seconds)
Run this command:
```bash
adb logcat -s flutter | grep -E "Zone mismatch|Unterminated string|OutOfMemory|Price book|corruption"
```

**Expected Output**:
```
✅ Price book saved: 52444 items, 21387683 bytes
✅ Synced 104 jobs from Firebase (delta sync)
(NO "Zone mismatch" errors)
(NO "Unterminated string" errors)
(NO "OutOfMemoryError" anywhere)
```

**UNEXPECTED** (should NOT see):
```
❌ Zone mismatch
❌ Unterminated string
❌ OutOfMemoryError
❌ Failed to allocate
```

---

## Summary Scoring

| Test | Pass? | Notes |
|------|-------|-------|
| 1. Startup | ☐ | Should be 2-3s |
| 2. Jobs List | ☐ | Smooth scrolling? |
| 3. Job Details | ☐ | Quick navigation? |
| 4. Edit & Save | ☐ | Any errors? |
| 5. Price Book | ☐ | Instant search? |
| 6. Memory | ☐ | <250MB usage? |
| 7. Logcat | ☐ | Clean logs? |

---

## If You See Issues

### "Zone mismatch" still appears?
- The fix is in place but may show once during old cache cleanup
- Should only appear once, then never again

### "Unterminated string" in price book?
- The fix will back up the corrupted file to `price_book.json.corrupt`
- App uses default pricebook and syncs fresh data
- Check: `adb logcat -s flutter | grep "Backed up"`

### App still sluggish?
- Make sure you have the NEW APK (from today's build)
- Do: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- Check: `adb logcat -s flutter | grep "Built\|running"`

### OutOfMemoryError still occurring?
- This should be completely gone (fixed in previous session)
- If it appears, enable crash logs: `adb logcat | grep -i "memory"`

---

## Performance Expectations

### After All Fixes
- **App Startup**: 2-3 seconds (was ~5-6s with OOM)
- **Jobs List Load**: <500ms (was hanging)
- **Job Details**: <1 second (was 2-3s)
- **Price Book Search**: Instant (was laggy)
- **Memory Usage**: 150-250MB (was 400MB+ crashing)
- **Crashes**: 0 OutOfMemory errors (was frequent)

---

## How to Capture Logs for Analysis
```bash
# Full startup logs
adb logcat > startup_$(date +%s).log &
# Tap app icon
# Let it fully load
# Ctrl+C to stop

# Or live monitoring
adb logcat -s flutter | tee live_$(date +%s).log
```

---

Generated: 2026-07-13
Use this to verify all improvements are working!
