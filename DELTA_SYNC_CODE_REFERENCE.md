# Delta Sync Implementation Guide - Code Reference

## Quick Integration Guide

The delta sync system is **already integrated** into your app! No additional setup needed.

---

## How It's Connected

### 1. **When You Save a Job**

```dart
// In estimate_builder_screen.dart or any job save flow
await _persistJobToDisk(job);

// This automatically triggers:
// 1. Local save to jobs.json ✓
// 2. Cloud save to Firestore via FirestoreService ✓
// 3. Intelligent PDF sync via DeltaSyncService ✓
```

### 2. **The Sync Chain**

```
User saves job
    ↓
_persistJobToDisk(job)
    ↓
FirestoreService.saveJob(job)
    ↓
FirebaseIntegrationService.saveJob(job)
    ↓
DeltaSyncService.syncPdfsWithDelta(job)
    ↓
✓ Only changed PDFs uploaded
✓ Metadata updated
✓ Sync complete
```

---

## Code Examples

### Example 1: Automatic Sync (Default)

```dart
// This just works - no special code needed!
void savingJob() {
  _persistJobToDisk(job);
  // Internally:
  // ✓ Saves to local storage
  // ✓ Calls FirestoreService
  // ✓ Triggers DeltaSyncService
  // ✓ Only uploads changed PDFs
  // Done!
}
```

### Example 2: Manual Full Sync (If Needed)

```dart
// Force re-upload all PDFs for a job (rare case)
import 'services/delta_sync_service.dart';

void forceFullSync() {
  await DeltaSyncService.forcePdfFullSync(job);
  // Clears stored hashes
  // Re-uploads all PDFs regardless of changes
}
```

### Example 3: Check What Needs Syncing

```dart
// See which PDFs are pending upload
import 'services/delta_sync_service.dart';

void checkPendingPdfs() {
  final pending = await DeltaSyncService.getPdfsNeedingSync(job);
  
  for (final fileName in pending) {
    print('Pending: $fileName');
  }
}
```

### Example 4: Clear Sync Metadata (Debugging)

```dart
// Force a full resync (clears all metadata)
// Use this if sync data gets corrupted
import 'services/delta_sync_service.dart';

void resetSyncSystem() {
  await DeltaSyncService.clearSyncMetadata();
  print('Sync data cleared - will do full resync next time');
}
```

---

## File Locations

### Where Data is Stored

```
📁 App Storage Directory: /data/user/0/com.example.app/app_flutter/

Files created by delta sync:
├── jobs.json                    (job metadata)
├── customers.json               (customer data)
├── price_book.json             (pricing)
├── Invoice_*.pdf               (PDF files)
├── Quote_*.pdf
├── Estimate_*.pdf
├── jobs_sync_meta.json          (sync tracking)
├── customers_sync_meta.json     (sync tracking)
├── pdf_meta_job-001.json       (PDF hashes)
├── pdf_meta_job-002.json
└── ...more job metadata
```

### Firebase Storage Structure

```
Cloud Storage: soletradie-ab850.firebasestorage.app

📁 invoices/
   └── {userId}/                (your user ID)
       ├── job-001/
       │   ├── Invoice_ABC.pdf
       │   └── Invoice_DEF.pdf
       ├── job-002/
       │   └── Quote_GHI.pdf
       └── ...more jobs
```

---

## Logging & Debugging

### Enable Logs (Automatically On)

The system automatically logs important events:

```
✓ PDF unchanged, skipping: Invoice_123.pdf
☁️ Uploaded PDF (changed): Invoice_ABC.pdf
✅ PDF delta sync complete: 2 uploaded, 1 skipped
❌ Error uploading PDF: network timeout (retry later)
```

### Grep for Sync Messages

```bash
# On device/emulator logs:
flutter logs | grep "delta sync"
flutter logs | grep "Uploaded PDF"
flutter logs | grep "PDF unchanged"
```

### Check Local Metadata Files

```dart
// View what's stored locally
void debugMetadata() async {
  final directory = await getApplicationDocumentsDirectory();
  final metaFile = File('${directory.path}/pdf_meta_job-123.json');
  
  if (await metaFile.exists()) {
    final content = await metaFile.readAsString();
    print('PDF Metadata:');
    print(content);
  }
}
```

Output would look like:
```json
{
  "Invoice_123.pdf": {
    "hash": "d41d8cd98f00b204e9800998ecf8427e",
    "size": 51234,
    "lastModified": "2024-07-13T10:30:00Z",
    "uploadedAt": "2024-07-13T10:31:00Z"
  }
}
```

---

## Configuration Options

### Adjust Hash Calculation (if needed)

```dart
// In DeltaSyncService, can modify:

// Use SHA256 instead of MD5 (more secure but slower)
static Future<String> _calculateFileHash(File file) async {
  final bytes = await file.readAsBytes();
  return sha256.convert(bytes).toString();
  // But MD5 is fine for our use case
}
```

### Adjust Sync Frequency (optional)

```dart
// In firebase_integration_service.dart:

// Default is 5 minutes, can change to:
const syncInterval = Duration(minutes: 1);  // More frequent
const syncInterval = Duration(minutes: 10); // Less frequent
```

### Limit Maximum File Size (optional)

```dart
// Add this check before uploading:
const maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB limit

if (await file.length() > maxFileSizeBytes) {
  print('⚠️ File too large, skipping');
  continue;
}
```

---

## Testing Your Implementation

### Unit Test: Hash Consistency

```dart
import 'package:test/test.dart';
import 'services/delta_sync_service.dart';

void main() {
  test('File hashes are consistent', () async {
    final file = File('test_invoice.pdf');
    
    final hash1 = await DeltaSyncService._calculateFileHash(file);
    final hash2 = await DeltaSyncService._calculateFileHash(file);
    
    expect(hash1, hash2, reason: 'Same file should have same hash');
  });

  test('Different files have different hashes', () async {
    final file1 = File('test_invoice_1.pdf');
    final file2 = File('test_invoice_2.pdf');
    
    final hash1 = await DeltaSyncService._calculateFileHash(file1);
    final hash2 = await DeltaSyncService._calculateFileHash(file2);
    
    expect(hash1, isNot(hash2), 
           reason: 'Different files should have different hashes');
  });
}
```

### Integration Test: PDF Skip Detection

```dart
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PDF unchanged, sync skips upload', (tester) async {
    // 1. Create a job with PDF
    final job = createTestJob();
    
    // 2. Initial sync (uploads)
    await DeltaSyncService.syncPdfsWithDelta(job);
    
    // 3. Sync again without changes
    await DeltaSyncService.syncPdfsWithDelta(job);
    
    // Verify: No new uploads (check Firebase)
    expect(findUploadsSince(Duration(seconds: 5)), isEmpty);
  });
}
```

---

## Performance Tuning

### Monitor Upload Speed

```dart
// Add timing to track performance
Future<void> _syncPdfIfChanged(...) async {
  final stopwatch = Stopwatch()..start();
  
  try {
    await storage.ref(cloudPath).putFile(file);
    stopwatch.stop();
    
    print('⏱️ Upload time: ${stopwatch.elapsedMilliseconds} ms');
  } catch (e) {
    print('❌ Upload failed: $e');
  }
}
```

### Optimize for Slow Networks

```dart
// Add timeout for slow connections
Future<void> _syncPdfIfChanged(...) async {
  try {
    await storage.ref(cloudPath).putFile(file)
        .timeout(Duration(seconds: 30), onTimeout: () {
      throw Exception('Upload timeout');
    });
  } catch (e) {
    print('⚠️ Upload timeout or failed: $e');
    // File remains in metadata, will retry next sync
  }
}
```

---

## Error Handling Best Practices

### Handle Upload Failures Gracefully

```dart
// Current implementation (already handles this):

try {
  await storage.ref(cloudPath).putFile(file);
  // Success - update metadata
  pdfMetadata[fileName] = { 'hash': currentHash, ... };
} catch (e) {
  print('⚠️ Failed to upload PDF $fileName: $e');
  // Don't update metadata - file remains "pending"
  // Next sync will retry
  // Local file is always safe
}
```

### Queue Failed Uploads

```dart
// Track what failed (for manual retry)
List<String> failedPdfs = [];

try {
  await storage.ref(cloudPath).putFile(file);
} catch (e) {
  failedPdfs.add(fileName);
}

// Later: User can manually retry
void retryFailedUploads() {
  for (final fileName in failedPdfs) {
    // Retry upload
  }
}
```

---

## Multi-Device Sync Example

### Device A (Primary)

```dart
// Create invoice on Device A
void createInvoice() {
  final invoice = Invoice(...);
  final job = Job(...invoices: [invoice]);
  
  _persistJobToDisk(job);  // Saves locally
  // ↓
  // DeltaSyncService automatically:
  // ✓ Calculates PDF hash
  // ✓ Uploads to Cloud Storage
  // ✓ Updates Firestore
  // ✓ Saves metadata
}
```

### Device B (Secondary)

```dart
// Open same job on Device B
void loadJobs() {
  final jobs = FirebaseIntegrationService.loadJobs(
    onCloudUpdate: (cloudJobs) {
      // Cloud data received
      for (final job in cloudJobs) {
        // Download PDF from Cloud Storage if needed
        final pdf = await downloadPdfFromCloud(job);
        print('✓ Downloaded: ${pdf.fileName}');
      }
      setState(() {
        _jobs = cloudJobs;
      });
    },
  );
}
```

---

## Advanced: Custom Sync Logic

### Create Custom Metadata

```dart
// If you need to track additional metadata:
void saveCustomMetadata(String jobId, Map<String, dynamic> data) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/custom_meta_$jobId.json');
  
  await file.writeAsString(jsonEncode(data));
}

Future<Map<String, dynamic>> loadCustomMetadata(String jobId) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/custom_meta_$jobId.json');
  
  if (await file.exists()) {
    return jsonDecode(await file.readAsString());
  }
  return {};
}
```

### Implement Compression (Future Enhancement)

```dart
// Compress PDFs before upload (saves ~40% bandwidth)
import 'dart:compress'; // Hypothetical package

Future<void> uploadCompressed(File file) async {
  final compressed = await compressFile(file);
  
  // Upload compressed version
  await storage.ref(cloudPath).putFile(compressed);
  
  // Store original hash for detection
  final hash = await _calculateFileHash(file);
}
```

---

## Troubleshooting Guide

### Issue: PDF Not Uploading

```dart
// Debug checklist:

// 1. Check authentication
final user = FirebaseAuth.instance.currentUser;
if (user == null) {
  print('❌ Not signed in!');
  return;
}

// 2. Check file exists
final file = File(filePath);
if (!await file.exists()) {
  print('❌ File doesn\'t exist: $filePath');
  return;
}

// 3. Check Firebase permissions
// Go to Firebase Console > Storage > Rules
// Verify rule allows user to write

// 4. Check file size
final size = await file.length();
if (size == 0) {
  print('⚠️ File is empty!');
}

// 5. Check network
// Enable logging in Firebase SDK
```

### Issue: Hash Mismatch

```dart
// Why would a hash mismatch occur?

// 1. Different PDF generation (timestamps, metadata)
// Solution: Regenerate to ensure consistency

// 2. Partial file read
// Solution: File size changed during read

// 3. Encoding issues
// Solution: Use bytes instead of strings

// Debug:
final file = File(filePath);
final hash1 = await _calculateFileHash(file);
final hash2 = await _calculateFileHash(file);
if (hash1 != hash2) {
  print('⚠️ Hash changed between reads!');
  print('File size: ${await file.length()} bytes');
}
```

### Issue: Storage Quota Exceeded

```dart
// Check storage usage
// Firebase Console > Storage > Files

// Solutions:
// 1. Delete old/archived jobs
// 2. Increase Firebase plan
// 3. Archive PDFs separately

// Monitor usage:
void checkStorageUsage() {
  final config = FirebaseStorage.instance;
  // No direct API, check Firebase Console
}
```

---

## Summary of Key Methods

| Method | Purpose | Returns |
|--------|---------|---------|
| `syncPdfsWithDelta(job)` | Smart sync only changed PDFs | `Future<void>` |
| `_calculateFileHash(file)` | Calculate MD5 hash | `Future<String>` |
| `_loadPdfMetadata(jobId)` | Load stored hashes | `Future<Map>` |
| `_savePdfMetadata(jobId, meta)` | Save updated hashes | `Future<void>` |
| `getPdfsNeedingSync(job)` | List pending files | `Future<List<String>>` |
| `forcePdfFullSync(job)` | Force re-upload all | `Future<void>` |
| `clearSyncMetadata()` | Reset all tracking | `Future<void>` |

---

## Conclusion

The delta sync system is **fully integrated** and working automatically. You don't need to change any existing code - it just works!

For testing and verification, use the examples above to:
- ✅ Monitor sync operations
- ✅ Debug any issues
- ✅ Verify cross-device sync
- ✅ Check cloud storage uploads

Happy syncing! 🚀

