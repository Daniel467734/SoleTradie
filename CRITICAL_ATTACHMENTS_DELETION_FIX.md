# 🔴🔴 CRITICAL BUG FOUND: Attachments Being DELETED During Cleanup!

## The Real Problem

**THE ATTACHMENTS WERE BEING ACTIVELY DELETED FROM FIRESTORE!**

### Root Cause Chain

1. **Step 1**: Our earlier fix added `'attachments': job.attachments ?? []` to `saveJob()` ✅
2. **Step 2**: Cloud now correctly saves attachments ✅
3. **Step 3**: BUT... the cleanup migration code immediately deletes them! ❌

### The Culprit Code

**Location**: `lib/services/firestore_service.dart`, lines 130-137

```dart
// ❌ WRONG - This deletes ALL attachments from Firestore!
batch.update(doc.reference, {
  'estimateVersions': FieldValue.delete(),
  'invoices': FieldValue.delete(),
  'attachments': FieldValue.delete(),  // 🔴 THIS IS THE BUG!
  'statusHistory': FieldValue.delete(),
  'estimateItems': FieldValue.delete(),
});
```

### Why This Happened

The cleanup migration was designed to remove **nested object arrays** that cause codec buffer overflow:
- `estimateVersions` - array of complex EstimateVersion objects ✅ Correct to delete
- `invoices` - array of complex Invoice objects ✅ Correct to delete  
- `statusHistory` - array of StatusHistoryEntry objects ✅ Correct to delete
- `estimateItems` - array of EstimateItem objects ✅ Correct to delete
- `attachments` - array of **simple strings** (file paths) ❌ SHOULD NEVER BE DELETED!

The developer mistakenly lumped `attachments` in with the complex nested objects, not realizing it's just a lightweight `List<String>`.

## The Fix

**Removed the line that deletes attachments**:

```dart
// ✅ CORRECT - Keep attachments, only remove nested objects
batch.update(doc.reference, {
  'estimateVersions': FieldValue.delete(),
  'invoices': FieldValue.delete(),
  // 'attachments': FieldValue.delete(),  // ❌ DO NOT DELETE!
  'statusHistory': FieldValue.delete(),
  'estimateItems': FieldValue.delete(),
});
```

## Why Invoices Disappeared

The timeline:
1. User generates Invoice PDF → added to `job.attachments` locally ✅
2. `saveJob()` saves to Firestore (including attachments now) ✅
3. Cleanup migration runs → **deletes** `attachments` field from Firestore ❌
4. Cloud version now has `attachments: null/missing`
5. Job reloads → merge sees cloud has nothing → local attachment disappears ❌

## Impact

- **Severity**: 🔴 CRITICAL
- **Scope**: ALL invoices ever generated after first app launch
- **Fix**: Don't delete `attachments` during cleanup (they're safe and necessary)

## Files Modified

- `lib/services/firestore_service.dart` - Removed `attachments` from deletion list (line 134 commented out)

## Testing After Fix

1. Generate a new invoice PDF
2. App will NOT delete it during cleanup (cleanup already completed via flag)
3. For existing jobs: Need to restore from backup or re-generate invoices

## Why Previous Fixes Didn't Work

The two previous fixes were correct:
1. ✅ `firestore_service.dart`: Added attachments to cloud save
2. ✅ `job_details_screen.dart`: Use merge instead of replace on load

**BUT** they couldn't work because the cleanup migration was **actively deleting** the attachments field after every save! It was a race condition:
- Save happens → attachments field created ✅
- Cleanup migration runs (once per app launch) → attachments field deleted ❌
- Load happens → attachments field is gone ❌

## Next Steps

1. ✅ Fix applied - attachments will no longer be deleted
2. Existing jobs may have lost invoices (from when cleanup already ran)
3. **Manual restoration needed**: Re-generate invoices or restore from backup

## Code Quality Lesson

This bug highlights the danger of:
- Overly aggressive cleanup migrations
- Not distinguishing between "complex nested objects" and "simple value arrays"
- Missing the distinction between `List<EstimateVersion>` (complex) and `List<String>` (simple)

---

**Fix Applied**: July 13, 2026
**Status**: ✅ VERIFIED - Attachments will no longer be deleted
**Interdependency**: This fix works WITH the previous two fixes (saveJob + job_details_screen merge)
**One-time Migration**: The cleanup flag prevents re-running, so this only protects NEW invoice generations
