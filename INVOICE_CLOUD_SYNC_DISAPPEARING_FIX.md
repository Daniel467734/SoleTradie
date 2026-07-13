# 🔴 CRITICAL FIX: Invoices Disappearing After Cloud Sync

## Problem Summary

**Invoices were disappearing from job attachments AFTER syncing to the cloud.**

Flow of the bug:
1. ✅ Generate Invoice PDF → added to `job.attachments` locally
2. ✅ Save to cloud via `FirestoreService.saveJob()`
3. ❌ Cloud sync completes → attachment disappears
4. ❌ Any subsequent PDFs get duplicate names (no sequence number)

## Root Cause Analysis

**TWO-PART BUG** (Both must be fixed):

### Part 1: Missing Attachments in Cloud Save ❌
**Location**: `lib/services/firestore_service.dart`, lines 174-202

The `saveJob()` method was saving job metadata to Firestore but **NOT including `attachments`**:

```dart
// ❌ WRONG - attachments field missing from cloud save
await jobsCollection.doc(job.id).set({
  'id': job.id,
  'title': job.title,
  'description': job.description,
  'customerName': job.customerName,
  // ... other fields ...
  'notes': job.notes,
  'scheduleDates': job.scheduleDates?.map(...).toList(),
  'isFlexibleDayJob': job.isFlexibleDayJob,
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
// ⚠️ NOTE: `attachments` not in this set!
```

### Part 2: Job Reload Overwrites with Blank Cloud Data ❌
**Location**: `lib/screens/job_details_screen.dart`, lines 575-630 (already fixed in previous commit)

When reloading job from cloud, the code was **completely replacing** local attachments with cloud data (which had blank/null attachments):

```dart
// ❌ OLD - replaces entire attachments with cloud version
widget.job.attachments = cloudJob.attachments;
// If cloud version is null, local attachments lost!
```

## The Two-Part Fix

### Fix Part 1: Include Attachments in Cloud Save
**File**: `lib/services/firestore_service.dart` (line 202)

```dart
// ✅ FIXED - now includes attachments in cloud save
await jobsCollection.doc(job.id).set({
  'id': job.id,
  'title': job.title,
  // ... other fields ...
  'notes': job.notes,
  'attachments': job.attachments ?? [],  // 🔧 NEW: Include attachments
  'scheduleDates': job.scheduleDates?.map(...).toList(),
  'isFlexibleDayJob': job.isFlexibleDayJob,
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
```

### Fix Part 2: Merge Instead of Replace on Reload ✅ 
**File**: `lib/screens/job_details_screen.dart` (already applied)

```dart
// ✅ FIXED - merges cloud + local attachments (no overwrite)
final cloudAttachments = cloudJob.attachments ?? [];
final localAttachments = widget.job.attachments ?? [];
final merged = <String>{...cloudAttachments, ...localAttachments}.toList();
widget.job.attachments = merged.isEmpty ? null : merged;
```

## Why This Happened

1. **Lazy Loading Architecture**: To prevent OutOfMemoryError, the app was designed to save only "metadata" fields to cloud (not nested arrays like invoices/estimates)

2. **Attachments Not in "Metadata" List**: Someone added `notes`, `scheduleDates`, `isFlexibleDayJob` to the metadata save, but forgot `attachments`

3. **Cloud Becomes "Source of Truth"**: When app reloaded the job from Firestore, it treated the cloud version as the authoritative copy (because `merge: true` was used). Since cloud had no attachments data, it sent `null`

4. **Perfect Storm**: The reload code replaced attachments with cloud's `null`, losing all local references to generated PDFs

## Impact

### Severity: 🔴 CRITICAL
- **Visibility**: User loses access to generated invoices
- **Functionality**: PDF naming system breaks (duplicate names)
- **Data Loss**: Not permanent (files still on disk) but invisible to user
- **Trust**: User thinks invoices are deleted/lost

### Timeline
- Generate Invoice #1 → PDF created and saved ✅
- Save to cloud → attachments field NOT synced ❌
- Cloud reload happens → attachments overwritten with cloud's null ❌
- Generate Invoice #2 → System thinks no prior invoices exist → gives same name ❌
- Confusion: User sees only one invoice in list (newest one) ❌

## Testing Scenarios

### Scenario 1: Generate Invoice, Force Cloud Sync
1. Create new job
2. Generate Invoice PDF
3. **Verify in Firestore Console**: Navigate to `jobs/{id}` collection
4. Check that `attachments` field now contains the PDF path ✅
5. (Previously: `attachments` field would be missing or null)

### Scenario 2: Multiple Invoices with Cloud Sync
1. Generate Invoice #1 → local attachment added
2. Force cloud sync (app auto-syncs or manual trigger)
3. Generate Invoice #2 → should get unique name like "Invoice (2)"
4. Navigate away and back to job
5. ✅ Both invoices should still be visible
6. ✅ No duplicates in attachment list

### Scenario 3: Slow Network Sync
1. Generate Invoice PDF
2. Immediately go to cloud (Firestore console)
3. Wait for Firebase sync to complete
4. Refresh cloud view → `attachments` should now show PDF path ✅
5. (Previously: `attachments` would remain empty/missing)

## Files Modified

### 1. `lib/services/firestore_service.dart`
- **Line**: 202 (added `attachments` field)
- **Change**: Added `'attachments': job.attachments ?? []` to the `.set()` call
- **Impact**: Cloud now saves attachment data
- **Status**: ✅ VERIFIED - Compiles without errors

### 2. `lib/screens/job_details_screen.dart` (from previous fix)
- **Lines**: 584, 611, 628
- **Change**: Changed from replace to merge strategy
- **Impact**: Local attachments no longer overwritten by cloud on reload
- **Status**: ✅ VERIFIED - Compiles without errors

## Deployment Checklist

- [ ] Deploy both fixes together (they're interdependent)
- [ ] Test with slow network conditions
- [ ] Monitor cloud → local sync behavior
- [ ] Verify invoices persist across app restart
- [ ] Check Firestore console that `attachments` field is saved
- [ ] Verify no duplicate invoice names are generated

## Related Code

**Key interaction chain**:
```
EstimateBuilderScreen
  └─> Generates PDF
  └─> Adds to job.attachments ✅ (already fixed in previous commit)
  └─> Calls FirestoreService.saveJob()
      └─> Should save attachments to cloud ✅ (NOW FIXED)
  └─> Job reloads from cloud
      └─> Should merge attachments, not replace ✅ (already fixed)
```

## Future Improvements

1. **Attachment Sync Auditing**: Periodically verify cloud `attachments` matches local
2. **Firestore Rules**: Add validation to ensure `attachments` array is never cleared
3. **Attachment Verification**: Check that referenced files actually exist on disk
4. **Change Tracking**: Only reload if cloud version actually changed (use timestamps)
5. **Selective Merge**: Keep latest timestamp version instead of set union

## Historical Context

This bug emerged from the **lazy-loading architecture** designed to prevent OutOfMemoryError. The fix preserves that architecture while ensuring `attachments` (a lightweight metadata field) is always synced.

---

**Fixes Applied**: July 13, 2026
**Status**: ✅ VERIFIED - Both parts compiling and logically sound
**Interdependency**: MUST deploy both firestore_service.dart AND job_details_screen.dart fixes together
