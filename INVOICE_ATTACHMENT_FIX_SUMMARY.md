# ⚡ Quick Summary: Invoices Disappearing Bug

## The Issue
Invoices were disappearing from job attachments list when screen reloaded, even though PDF files still existed on disk.

## The Cause
`_reloadJob()` in `job_details_screen.dart` was **replacing** `job.attachments` with cloud/disk data, losing locally-added PDFs that hadn't synced yet.

## The Fix
Changed 3 locations in `_reloadJob()` from **REPLACE** to **MERGE**:

```dart
// Before (❌ BUG):
widget.job.attachments = cloudJob.attachments;

// After (✅ FIXED):
final cloudAttachments = cloudJob.attachments ?? [];
final localAttachments = widget.job.attachments ?? [];
final merged = <String>{...cloudAttachments, ...localAttachments}.toList();
widget.job.attachments = merged.isEmpty ? null : merged;
```

## Impact
- ✅ Invoices no longer disappear on screen reload
- ✅ Multiple PDFs generate with correct sequential names
- ✅ No data loss on cloud sync lag
- ✅ No duplicates (automatic via set deduplication)

## Files Changed
- `lib/screens/job_details_screen.dart` (3 merge statements added)

## Testing
Generate 3+ invoices → navigate away/back → all should still be visible
