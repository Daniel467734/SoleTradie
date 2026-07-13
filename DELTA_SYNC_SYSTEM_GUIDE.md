# Delta Sync System - Complete Guide

## Overview

The **Delta Sync System** is an intelligent sync mechanism that ensures all local changes (jobs, customers, PDFs, and metadata) are efficiently backed up to Firebase Cloud Storage and Firestore. Instead of uploading/downloading everything every time, it only syncs what has changed.

### Key Benefits

✅ **Bandwidth Efficient** - Only uploads changed PDFs, not the entire job  
✅ **Memory Efficient** - Doesn't load all cloud data at once (avoids OutOfMemoryError)  
✅ **Fast Sync** - Incremental updates instead of full replacements  
✅ **Smart Conflict Resolution** - Local changes always sync, cloud doesn't overwrite local  
✅ **Offline-First** - Works perfectly without internet (queues for sync later)  
✅ **PDF Tracking** - Monitors file changes by hash/timestamp  

---

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     APP LOCAL STORAGE                    │
│  ┌──────────────────────────────────────────────────┐   │
│  │  jobs.json, customers.json, price_book.json     │   │
│  │  PDF files: Invoice_123.pdf, Quote_456.pdf      │   │
│  │  Sync metadata: jobs_sync_meta.json              │   │
│  └──────────────────────────────────────────────────┘   │
└──────────┬────────────────────────────────────────────────┘
           │
           │  DeltaSyncService monitors for changes
           │  (hash comparison, timestamp tracking)
           │
           ▼
┌─────────────────────────────────────────────────────────┐
│           DELTA SYNC SERVICE                            │
│  ┌──────────────────────────────────────────────────┐   │
│  │ 1. Detect: What changed since last sync?        │   │
│  │ 2. Compare: Hash of current vs stored metadata  │   │
│  │ 3. Queue: Build list of changes to sync        │   │
│  │ 4. Sync: Push only deltas to cloud             │   │
│  │ 5. Update: Save new metadata locally           │   │
│  └──────────────────────────────────────────────────┘   │
└──────────┬────────────────────────────────────────────────┘
           │
           │  Syncs changes to:
           │  - Firestore (job metadata)
           │  - Cloud Storage (PDF files)
           │
           ▼
┌─────────────────────────────────────────────────────────┐
│              FIREBASE CLOUD                             │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Firestore: jobs/, customers/, metadata/       │   │
│  │  Cloud Storage: invoices/{userId}/{jobId}/      │   │
│  │  File metadata: file_sync_meta/{userId}/        │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## How It Works

### 1. **Local Change Detection**

When you save a job, estimate, or invoice locally:

```dart
// User saves invoice locally
_persistJobToDisk(job);

// App automatically:
// ✓ Saves invoice PDF to device: /Invoice_123.pdf
// ✓ Saves job metadata to jobs.json
// ✓ Records timestamp locally
```

### 2. **Sync Metadata Tracking**

The system maintains `jobs_sync_meta.json` that tracks:

```json
{
  "lastSyncTime": "2024-07-13T10:30:00.000Z",
  "dataHash": "abc123def456...",
  "entityTimestamps": {
    "job-001": "2024-07-13T10:30:00.000Z",
    "job-002": "2024-07-12T14:22:00.000Z"
  }
}
```

### 3. **Delta Comparison**

When sync runs (automatic or manual):

```
Firestore: "job-001 last updated 2024-07-13 09:00 AM"
Local: "job-001 last updated 2024-07-13 10:30 AM"
                                          ↑ Newer!
Result: SYNC THIS JOB
```

### 4. **Smart Upload Strategy**

#### For **Jobs & Metadata**:
- Only upload jobs where `local.lastModified > cloud.lastModified`
- Skip unchanged jobs entirely
- Batch operations for efficiency

#### For **PDFs**:
- Calculate file hash (MD5) to detect changes
- Compare with cloud metadata
- Only upload if hash differs
- Skip if cloud copy is identical

```dart
// Example: Invoice PDF changed?
local_hash = MD5("Invoice_123.pdf contents")
cloud_hash = "abc123def456..." (from metadata)

if (local_hash != cloud_hash) {
  // Changed! Upload it
  upload_to_cloud(file)
} else {
  // Unchanged, skip
  print("✓ PDF unchanged, skipping upload")
}
```

### 5. **Sync Completion**

After successful sync:
- Update `jobs_sync_meta.json` with new timestamps
- Record new data hashes
- Clear pending change queue
- Ready for next sync cycle

---

## PDF Intelligent Sync

### Why PDFs Need Special Handling

PDFs are large binary files that change whenever:
- Invoice is regenerated with new amounts
- Payment status changes
- Invoice is marked as paid
- Customer edits existing invoice

### PDF Sync Strategy

**1. File Hash Comparison**
```dart
// Calculate hash when file is saved
fileHash = md5(file.readAsBytes())

// Store in sync metadata
sync_meta.pdfHashes[jobId][fileName] = fileHash

// Next sync: compare
if (storedHash != currentHash) {
  // File changed, upload
}
```

**2. Timestamp-Based Changes**
```dart
// When invoice status changes:
invoice.isPaid = true  // Changed!
invoice.lastModified = DateTime.now()

// Next sync detects this and uploads new PDF
```

**3. Batch PDF Operations**
```dart
// Collect all changed PDFs first
changedPDFs = [
  "Invoice_123.pdf" (hash changed),
  "Quote_456.pdf" (new file),
  "Estimate_789.pdf" (unchanged - skip)
]

// Upload in parallel
await Future.wait([
  storage.ref(path1).putFile(file1),
  storage.ref(path2).putFile(file2),
]);
```

---

## Sync Flow Examples

### Example 1: User Creates Invoice

```
Step 1: User in app generates invoice
        ↓
Step 2: PDF saved locally: /data/.../Invoice_ABC123.pdf
        ↓
Step 3: Job data saved to jobs.json
        ↓
Step 4: DeltaSyncService detects new job + PDF
        ↓
Step 5: Calculates file hash: md5(Invoice_ABC123.pdf)
        ↓
Step 6: Uploads to Firestore:
        - Job metadata to: jobs/{jobId}
        - PDF metadata to: file_sync_meta/{jobId}
        ↓
Step 7: Uploads PDF to Cloud Storage:
        - invoices/{userId}/{jobId}/Invoice_ABC123.pdf
        ↓
Step 8: Updates local sync metadata:
        - jobs_sync_meta.json: lastSyncTime = now
        - Records: jobId -> timestamp
        ↓
Step 9: ✅ Sync complete, ready for next change
```

### Example 2: User Edits Invoice (Marks as Paid)

```
Step 1: User marks invoice as paid in app
        ↓
Step 2: invoice.isPaid = true
        ↓
Step 3: Job saved locally to jobs.json
        ↓
Step 4: New PDF generated: /Invoice_ABC123.pdf (new hash!)
        ↓
Step 5: DeltaSyncService wakes up:
        
        Check: job-ABC123 in metadata?
        YES → lastSyncTime = 2024-07-13 09:00
              current job.lastModified = 2024-07-13 10:30
              NEWER! → Include in sync
        
        Check: Invoice_ABC123.pdf unchanged?
        currentHash = md5("...new PDF bytes...")
        storedHash = "abc123def456" (from last sync)
        DIFFERENT! → Include PDF in sync
        
Step 6: Upload changed job + PDF to cloud
        ↓
Step 7: Update metadata:
        - Job timestamp: 2024-07-13 10:30
        - PDF hash: new hash value
        ↓
Step 8: ✅ Sync complete
```

### Example 3: Multi-Device Sync

```
Device A (Primary - Sole Trader with App):
  - Creates Invoice #ABC123
  - Marks as Paid
  - Syncs to cloud ✓
  
            ↓↓↓ Data flows through Firebase ↓↓↓
  
Device B (Admin Dashboard or Web):
  - Signed in as same user
  - Refreshes job list
  - DeltaSyncService compares:
    - Cloud: Invoice #ABC123 (latest version)
    - Local: (older or missing)
  - Downloads cloud version
  - Merges with local
  - ✓ Device B now has latest invoice
  
Result: Both devices have identical data!
```

---

## Key Data Structures

### SyncMetadata (Track what's been synced)
```dart
class SyncMetadata {
  DateTime lastSyncTime;           // When was last sync?
  String dataHash;                 // Hash of all data
  int cloudVersion;                // Cloud schema version
  Map<String, DateTime> entityTimestamps; // Per-job timestamps
  Map<String, String> pdfHashes;   // Per-PDF file hashes
}
```

### PDF Sync Record
```dart
{
  "jobId": "job-123",
  "fileName": "Invoice_ABC.pdf",
  "fileHash": "d41d8cd98f00b204e9800998ecf8427e",
  "fileSize": 51234,
  "lastModified": "2024-07-13T10:30:00Z",
  "uploadedToCloud": true
}
```

---

## API Reference

### DeltaSyncService Methods

#### `syncJobsWithDelta()`
Fetches only jobs changed since last sync
```dart
final jobs = await DeltaSyncService.syncJobsWithDelta();
// Returns only changed jobs, updates local cache
```

#### `syncCustomersWithDelta()`
Fetches only customers changed since last sync
```dart
final customers = await DeltaSyncService.syncCustomersWithDelta();
```

#### `syncPdfsWithDelta(jobId)`
Sync only PDFs that changed for a specific job
```dart
await DeltaSyncService.syncPdfsWithDelta(jobId);
// Only uploads PDFs where hash differs
```

#### `forcedFullSync()`
Force re-sync of everything (clears metadata)
```dart
await DeltaSyncService.forcedFullSync();
// Use after major app updates
```

#### `clearSyncMetadata()`
Clear all sync tracking (forced full resync next time)
```dart
await DeltaSyncService.clearSyncMetadata();
```

---

## Configuration

### Sync Schedule

**Automatic Sync**:
- On app launch (after user signs in)
- Every 5 minutes while app is running
- When app pauses/resumes
- When network reconnects (offline detection)

**Manual Sync**:
- User pulls-to-refresh on jobs screen
- Settings → "Sync Now" button
- After major operations (invoice marked paid, etc.)

### Sync Timeout
```dart
const syncTimeout = Duration(seconds: 30);
// If sync takes longer, aborts gracefully
// Local changes remain, sync retries next cycle
```

---

## Behavior & Edge Cases

### ✓ What Syncs
- New jobs created locally
- Changes to existing jobs (status, fields, etc.)
- New customers added
- Changes to existing customers
- Invoice PDFs (all types)
- Quote PDFs (all types)
- Estimate PDFs (all types)
- Price book updates

### ✗ What Doesn't Sync Automatically
- App settings (local storage only)
- UI state (scroll position, selected filters, etc.)
- Temporary drafts not yet saved to jobs.json

### ⚠️ Conflict Resolution
If same data changed both locally and in cloud:

```
Rule: LAST WRITE WINS (with local priority)

Case 1: Local change newer
  Local:  2024-07-13 10:30 ← WINS
  Cloud:  2024-07-13 09:00
  → Local version sent to cloud

Case 2: Cloud change newer
  Local:  2024-07-13 08:00
  Cloud:  2024-07-13 10:30 ← WINS
  → Cloud version downloaded to local
  
Case 3: Both same timestamp
  → Local version used (local-first philosophy)
```

### 📱 Offline Behavior
1. User makes changes while offline
2. All changes saved to local storage ✓
3. When internet returns:
   - Changes are queued
   - Next sync cycle sends them up ✓
4. User can work indefinitely offline

### 🔄 Retry Logic
```
Upload fails (network error)
  ↓
Wait 5 seconds
  ↓
Retry (attempt 2)
  ↓
Wait 10 seconds
  ↓
Retry (attempt 3)
  ↓
If still failing: Log warning, continue
  (Will retry on next sync cycle)
```

---

## Performance Metrics

### Expected Behavior

**Initial Sync** (first time):
- ~1000 jobs: 8-15 seconds
- ~500 PDFs: 20-40 seconds (depends on file sizes)
- Total: ~30-50 seconds

**Delta Sync** (normal):
- 10 changed jobs: 1-2 seconds
- 2 changed PDFs: 3-5 seconds
- Total: ~2-7 seconds

**Bandwidth**:
- Per invoice PDF: ~50-200 KB
- Per job metadata: ~2-5 KB
- Full job with 10 invoices: ~500 KB - 2 MB

**Storage**:
- Per job (with PDFs): ~500 KB - 2 MB
- 1000 jobs with invoices: ~500 MB - 2 GB

---

## Monitoring & Debugging

### Enable Verbose Logging
```dart
// In main.dart or app startup
const bool enableVerboseSyncLogging = true;

// Then DeltaSyncService prints detailed logs:
// 🔄 Delta sync: 3 jobs changed since 2024-07-13 09:00
// ☁️ Uploading PDF: Invoice_123.pdf (hash: abc123...)
// ✅ Successfully synced 5 jobs
```

### Check Sync Status
```dart
// Get timestamp of last sync
final meta = await DeltaSyncService.getLastSyncMetadata();
print('Last sync: ${meta.lastSyncTime}');
print('Jobs synced: ${meta.entityTimestamps.length}');
```

### Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| "OutOfMemoryError during sync" | Loading all jobs at once | Delta sync already active - should prevent this |
| "PDFs not appearing in cloud" | Upload failed silently | Check Firebase Storage quota/permissions |
| "Sync takes too long" | Network slow | Normal - check bandwidth. Max wait: 30 seconds then aborts |
| "Offline changes not syncing" | No internet | Changes remain local. Will sync when online |
| "Conflicting versions" | Edited on 2 devices simultaneously | Local version wins, cloud overwrites |

---

## Implementation Checklist

- ✅ DeltaSyncService created and active
- ✅ Sync metadata tracking implemented
- ✅ PDF hash comparison working
- ✅ Automatic sync on job save
- ✅ Manual sync available (via settings)
- ✅ Offline-first support
- ✅ Conflict resolution (last-write-wins)
- ⏳ Retry logic for failed uploads
- ⏳ Bandwidth optimization for large PDFs
- ⏳ User-facing sync status indicator

---

## Next Steps

1. **Monitor first sync cycle** - Check logs for any issues
2. **Verify PDF hashes** - Confirm PDFs uploading with delta sync
3. **Test offline scenarios** - Create job offline, sync when online
4. **Check multi-device sync** - Sign in on another device, verify data
5. **Performance tuning** - Adjust sync intervals if needed

---

## Questions & Troubleshooting

**Q: Why is my PDF uploading even though it hasn't changed?**  
A: Timestamps might differ. Check the hash comparison in logs - if hashes match, it should skip.

**Q: Can I disable delta sync and do full syncs?**  
A: Yes - call `clearSyncMetadata()` to force a full resync on next launch.

**Q: What happens if sync fails halfway through?**  
A: No data is lost. Changes remain local. Next sync picks up where it left off.

**Q: How do I know if sync is working?**  
A: Check Firebase Console > Cloud Storage > invoices/ folder. New PDFs should appear within seconds of saving.

