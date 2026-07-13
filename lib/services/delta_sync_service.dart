import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import '../models/customer.dart';
import '../models/sync_metadata.dart';
import 'firestore_service.dart';

/// Delta sync service: only fetch data that has changed since last sync
/// This dramatically reduces bandwidth and memory usage since we have
/// local copies of everything and only need to sync the deltas.
/// 
/// Features:
/// - Smart job/customer sync (only downloads changed items)
/// - Intelligent PDF sync (hash-based change detection)
/// - Metadata tracking (knows exactly what's in sync and what isn't)
/// - Offline-first (works without internet, syncs when available)
class DeltaSyncService {
  static const String _jobsSyncMetaFile = 'jobs_sync_meta.json';
  static const String _customersSyncMetaFile = 'customers_sync_meta.json';

  // CRITICAL: `main.dart` calls `FirebaseIntegrationService.loadJobs()` from
  // several places in quick succession at startup/refresh (auth listener,
  // `_loadDataFallback()`, `_refreshAppData()`). Each call spawns its own
  // unawaited `syncJobsWithDelta()` in the background. Without
  // serialization, these concurrent calls race to read-modify-write the
  // SAME local `jobs.json` (and its `.tmp` file during the atomic write),
  // which was silently corrupting/losing data (estimateVersions,
  // attachments, invoices) and even throwing PathNotFoundException when
  // one call deleted the `.tmp` file out from under another. This lock
  // ensures only one delta sync (and one customer sync) runs at a time;
  // any subsequent concurrent callers just await the in-flight operation
  // and get its result instead of starting their own conflicting one.
  static Future<List<Job>>? _inFlightJobsSync;
  static Future<List<Customer>>? _inFlightCustomersSync;

  /// Sync jobs: fetch only those changed since last sync
  static Future<List<Job>> syncJobsWithDelta() {
    // If a sync is already running, piggyback on it instead of starting a
    // second concurrent sync that would race on the same local file.
    final inFlight = _inFlightJobsSync;
    if (inFlight != null) {
      print('⏳ Delta sync for jobs already in progress - awaiting existing call');
      return inFlight;
    }

    final future = _syncJobsWithDeltaInternal();
    _inFlightJobsSync = future;
    // Clear the lock once done (success or failure) so future calls start fresh.
    future.whenComplete(() => _inFlightJobsSync = null);
    return future;
  }

  static Future<List<Job>> _syncJobsWithDeltaInternal() async {
    try {
      // Load current local metadata
      final lastMeta = await _loadSyncMetadata('jobs');

      // Ask Firestore for only changed jobs (updatedAt > lastSyncTime)
      final changedJobs = await FirestoreService.getJobsChangedSince(
        lastMeta.lastSyncTime,
      );

      final allLocal = await _loadJobsFromLocal();

      if (changedJobs.isNotEmpty) {
        print('🔄 Delta sync: ${changedJobs.length} jobs changed since ${lastMeta.lastSyncTime}');

        // Merge with local data
        final localMap = {for (var j in allLocal) j.id: j};

        // Apply cloud changes to local map. IMPORTANT: `getJobsChangedSince`
        // intentionally returns metadata-only stubs (estimateVersions,
        // invoices, attachments, statusHistory, estimateItems are always
        // `[]`) to avoid loading the full nested payload for every job on
        // every sync - see its doc comment. Blindly replacing the local
        // job with this stub would silently wipe out builds/attachments
        // that only exist locally (not yet pushed to the cloud). Instead,
        // only update the lightweight metadata fields here and keep the
        // existing local job's nested collections untouched. Full nested
        // data is only ever refreshed via the explicit lazy-load path
        // (`JobLazyLoadService.loadJobDetails`) or a real cloud doc fetch
        // (`FirestoreService.getJob`), never via this delta metadata sync.
        for (final cloudJob in changedJobs) {
          final existingLocal = localMap[cloudJob.id];
          if (existingLocal != null) {
            existingLocal.title = cloudJob.title;
            existingLocal.customerName = cloudJob.customerName;
            existingLocal.currentStatus = cloudJob.currentStatus;
            existingLocal.address = cloudJob.address;
            existingLocal.description = cloudJob.description;
            // Nested collections (estimateVersions/invoices/attachments/
            // statusHistory/estimateItems) are deliberately left as-is on
            // existingLocal since cloudJob only carries empty stubs here.
          } else {
            // Job doesn't exist locally at all yet - safe to add the
            // metadata-only stub; its nested data will be lazy-loaded
            // on-demand when the job is actually opened.
            localMap[cloudJob.id] = cloudJob;
          }
        }

        final merged = localMap.values.toList();
        await _saveJobsToLocal(merged);

        // Update metadata
        await _saveSyncMetadata('jobs', SyncMetadata(
          lastSyncTime: DateTime.now(),
          dataHash: _hashJobs(merged),
          cloudVersion: lastMeta.cloudVersion ?? 1,
          entityTimestamps: {
            for (var job in merged) job.id: job.created
          },
        ));

        print('✅ Jobs synced: ${merged.length} total');
        return merged;
      } else {
        print('✓ Jobs already in sync (no changes since ${lastMeta.lastSyncTime})');
        return allLocal;
      }
    } catch (e) {
      print('❌ Delta sync for jobs failed: $e');
      // Fall back to loading local
      return _loadJobsFromLocal();
    }
  }

  /// Sync customers: fetch only those changed since last sync
  static Future<List<Customer>> syncCustomersWithDelta() {
    final inFlight = _inFlightCustomersSync;
    if (inFlight != null) {
      print('⏳ Delta sync for customers already in progress - awaiting existing call');
      return inFlight;
    }

    final future = _syncCustomersWithDeltaInternal();
    _inFlightCustomersSync = future;
    future.whenComplete(() => _inFlightCustomersSync = null);
    return future;
  }

  static Future<List<Customer>> _syncCustomersWithDeltaInternal() async {
    try {
      final lastMeta = await _loadSyncMetadata('customers');

      final changedCustomers = await FirestoreService.getCustomersChangedSince(
        lastMeta.lastSyncTime,
      );

      if (changedCustomers.isNotEmpty) {
        print('🔄 Delta sync: ${changedCustomers.length} customers changed');

        final allLocal = await _loadCustomersFromLocal();
        final localMap = {for (var c in allLocal) c.id: c};

        for (final cloudCustomer in changedCustomers) {
          localMap[cloudCustomer.id] = cloudCustomer;
        }

        final merged = localMap.values.toList();
        await _saveCustomersToLocal(merged);

        await _saveSyncMetadata('customers', SyncMetadata(
          lastSyncTime: DateTime.now(),
          dataHash: _hashCustomers(merged),
          cloudVersion: lastMeta.cloudVersion ?? 1,
          entityTimestamps: {
            for (var c in merged) c.id: DateTime.now()
          },
        ));

        print('✅ Customers synced: ${merged.length} total');
        return merged;
      } else {
        print('✓ Customers already in sync');
        return _loadCustomersFromLocal();
      }
    } catch (e) {
      print('❌ Delta sync for customers failed: $e');
      return _loadCustomersFromLocal();
    }
  }

  // PRIVATE: Metadata management

  static Future<SyncMetadata> _loadSyncMetadata(String collection) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metaFile = collection == 'jobs'
          ? _jobsSyncMetaFile
          : _customersSyncMetaFile;
      final file = File('${directory.path}/$metaFile');

      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        return SyncMetadata.fromJson(json);
      }
    } catch (e) {
      print('⚠️ Could not load sync metadata for $collection: $e');
    }

    // First sync or metadata lost - start fresh
    return SyncMetadata.initial();
  }

  static Future<void> _saveSyncMetadata(String collection, SyncMetadata meta) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metaFile = collection == 'jobs'
          ? _jobsSyncMetaFile
          : _customersSyncMetaFile;
      final file = File('${directory.path}/$metaFile');
      await file.writeAsString(jsonEncode(meta.toJson()));
    } catch (e) {
      print('⚠️ Could not save sync metadata for $collection: $e');
    }
  }

  // PRIVATE: Local storage helpers

  static Future<List<Job>> _loadJobsFromLocal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/jobs.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(jsonString);
          return jsonList.map((e) => Job.fromJson(e)).toList();
        }
      }
    } catch (e) {
      print('❌ Error loading jobs from local: $e');
    }
    return [];
  }

  static Future<void> _saveJobsToLocal(List<Job> jobs) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/jobs.json');
      final jsonList = jobs.map((job) => job.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      
      // ATOMIC WRITE: Write to temp file first, verify, then swap
      final tempFile = File('${file.path}.tmp');
      
      // Clean up any leftover temp file
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      
      await tempFile.writeAsString(jsonString);
      
      // Verify the temp file is valid
      try {
        final tempContent = await tempFile.readAsString();
        if (tempContent.isEmpty) {
          throw Exception('Temp file is empty after write');
        }
        
        // Verify JSON is valid by parsing it
        jsonDecode(tempContent);
        
        // Backup current file before overwriting
        if (await file.exists()) {
          try {
            await file.copy('${file.path}.backup');
          } catch (e) {
            print('⚠️ Could not create backup: $e');
          }
        }
        
        // Atomically swap temp -> final (with retry on failure)
        try {
          await tempFile.rename(file.path);
        } catch (renameError) {
          // If rename fails, try direct copy instead
          print('⚠️ Rename failed, trying direct write: $renameError');
          await file.writeAsString(jsonString);
          // Clean up temp file
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        print('✅ Saved ${jobs.length} jobs to local storage (atomic write)');
      } catch (verifyError) {
        // Temp file is bad, delete it
        try {
          await tempFile.delete();
        } catch (_) {}
        throw verifyError;
      }
    } catch (e) {
      print('❌ Error saving jobs to local: $e');
    }
  }

  static Future<List<Customer>> _loadCustomersFromLocal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/customers.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(jsonString);
          return jsonList.map((e) => Customer.fromJson(e)).toList();
        }
      }
    } catch (e) {
      print('❌ Error loading customers from local: $e');
    }
    return [];
  }

  static Future<void> _saveCustomersToLocal(List<Customer> customers) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/customers.json');
      final jsonList = customers.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('⚠️ Error saving customers to local: $e');
    }
  }

  // PRIVATE: Hashing for change detection

  static String _hashJobs(List<Job> jobs) {
    final data = jobs.map((j) => '${j.id}:${j.created.toIso8601String()}').join('|');
    return md5.convert(utf8.encode(data)).toString();
  }

  static String _hashCustomers(List<Customer> customers) {
    final data = customers.map((c) => '${c.id}:${c.name}').join('|');
    return md5.convert(utf8.encode(data)).toString();
  }

  /// Clear all sync metadata (forces full resync on next launch)
  static Future<void> clearSyncMetadata() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final jobsFile = File('${directory.path}/$_jobsSyncMetaFile');
      final customersFile = File('${directory.path}/$_customersSyncMetaFile');

      if (await jobsFile.exists()) await jobsFile.delete();
      if (await customersFile.exists()) await customersFile.delete();

      print('🧹 Cleared sync metadata');
    } catch (e) {
      print('⚠️ Error clearing sync metadata: $e');
    }
  }

  // PDF DELTA SYNC METHODS

  /// Intelligently sync PDFs for a job: only upload if file hash changed
  /// This prevents re-uploading unchanged PDFs (saves bandwidth)
  static Future<void> syncPdfsWithDelta(Job job) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('⚠️ Not signed in - skipping PDF delta sync');
      return;
    }

    try {
      final storage = FirebaseStorage.instance;
      int uploadedCount = 0;
      int skippedCount = 0;

      // Load stored PDF metadata to compare hashes
      final pdfMetadata = await _loadPdfMetadata(job.id);

      // Process invoice PDFs from estimate versions
      for (final version in job.estimateVersions) {
        if (version.type == 'invoice' && version.filePath != null) {
          final file = File(version.filePath!);
          if (await file.exists()) {
            await _syncPdfIfChanged(
              file: file,
              jobId: job.id,
              userId: currentUser.uid,
              storage: storage,
              pdfMetadata: pdfMetadata,
              onUpload: () => uploadedCount++,
              onSkip: () => skippedCount++,
            );
          }
        }
      }

      // Process PDF attachments
      if (job.attachments != null) {
        for (final attachmentPath in job.attachments!) {
          if (attachmentPath.endsWith('.pdf')) {
            final file = File(attachmentPath);
            if (await file.exists()) {
              // Check if it's invoice-related
              if (attachmentPath.contains('Invoice') ||
                  attachmentPath.contains('Quote') ||
                  attachmentPath.contains('Estimate')) {
                await _syncPdfIfChanged(
                  file: file,
                  jobId: job.id,
                  userId: currentUser.uid,
                  storage: storage,
                  pdfMetadata: pdfMetadata,
                  onUpload: () => uploadedCount++,
                  onSkip: () => skippedCount++,
                );
              }
            }
          }
        }
      }

      // Save updated PDF metadata
      if (uploadedCount > 0) {
        await _savePdfMetadata(job.id, pdfMetadata);
      }

      if (uploadedCount > 0 || skippedCount > 0) {
        print('✅ PDF delta sync complete: $uploadedCount uploaded, $skippedCount skipped');
      }
    } catch (e) {
      print('❌ Error during PDF delta sync: $e');
    }
  }

  /// Sync a single PDF only if its hash changed
  static Future<void> _syncPdfIfChanged({
    required File file,
    required String jobId,
    required String userId,
    required FirebaseStorage storage,
    required Map<String, dynamic> pdfMetadata,
    required Function() onUpload,
    required Function() onSkip,
  }) async {
    try {
      final fileName = file.path.split('/').last;
      
      // Calculate current file hash
      final currentHash = await _calculateFileHash(file);
      
      // Get stored hash from metadata
      final storedHash = pdfMetadata[fileName]?['hash'] as String?;

      // Compare hashes - only upload if different
      if (storedHash == null || storedHash != currentHash) {
        // Hash differs or never uploaded before - upload now
        try {
          final cloudPath = 'invoices/$userId/$jobId/$fileName';
          
          await storage.ref(cloudPath).putFile(file);
          
          // Update metadata with new hash
          pdfMetadata[fileName] = {
            'hash': currentHash,
            'size': await file.length(),
            'lastModified': DateTime.now().toIso8601String(),
          };

          print('☁️ Uploaded PDF (changed): $fileName');
          onUpload();
        } catch (e) {
          print('⚠️ Failed to upload PDF $fileName: $e');
        }
      } else {
        // Hash matches - file unchanged, skip upload
        print('✓ PDF unchanged, skipping: $fileName');
        onSkip();
      }
    } catch (e) {
      print('⚠️ Error checking PDF $file: $e');
    }
  }

  /// Calculate MD5 hash of a file for change detection
  static Future<String> _calculateFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return md5.convert(bytes).toString();
    } catch (e) {
      print('⚠️ Error calculating file hash: $e');
      return 'error';
    }
  }

  /// Load stored PDF metadata for a job
  static Future<Map<String, dynamic>> _loadPdfMetadata(String jobId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/pdf_meta_$jobId.json');

      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        return json as Map<String, dynamic>;
      }
    } catch (e) {
      print('⚠️ Could not load PDF metadata for $jobId: $e');
    }

    return {}; // First sync or metadata lost
  }

  /// Save PDF metadata for a job
  static Future<void> _savePdfMetadata(
    String jobId,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/pdf_meta_$jobId.json');
      await file.writeAsString(jsonEncode(metadata));
      print('💾 Saved PDF metadata for $jobId');
    } catch (e) {
      print('⚠️ Could not save PDF metadata for $jobId: $e');
    }
  }

  /// Get list of all PDFs that need syncing for a job (changed or new)
  static Future<List<String>> getPdfsNeedingSync(Job job) async {
    final needsSync = <String>[];
    final pdfMetadata = await _loadPdfMetadata(job.id);

    // Check invoice versions
    for (final version in job.estimateVersions) {
      if (version.type == 'invoice' && version.filePath != null) {
        final file = File(version.filePath!);
        if (await file.exists()) {
          final fileName = file.path.split('/').last;
          final currentHash = await _calculateFileHash(file);
          final storedHash = pdfMetadata[fileName]?['hash'] as String?;

          if (storedHash == null || storedHash != currentHash) {
            needsSync.add(fileName);
          }
        }
      }
    }

    // Check attachments
    if (job.attachments != null) {
      for (final attachmentPath in job.attachments!) {
        if (attachmentPath.endsWith('.pdf') &&
            (attachmentPath.contains('Invoice') ||
             attachmentPath.contains('Quote') ||
             attachmentPath.contains('Estimate'))) {
          final file = File(attachmentPath);
          if (await file.exists()) {
            final fileName = file.path.split('/').last;
            final currentHash = await _calculateFileHash(file);
            final storedHash = pdfMetadata[fileName]?['hash'] as String?;

            if (storedHash == null || storedHash != currentHash) {
              needsSync.add(fileName);
            }
          }
        }
      }
    }

    return needsSync;
  }

  /// Force full PDF sync (ignore hashes, upload everything)
  static Future<void> forcePdfFullSync(Job job) async {
    print('🔄 Forcing full PDF sync for job ${job.id}...');
    
    // Clear PDF metadata to force re-upload everything
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/pdf_meta_${job.id}.json');
      if (await file.exists()) {
        await file.delete();
        print('🧹 Cleared PDF metadata for ${job.id}');
      }
    } catch (e) {
      print('⚠️ Error clearing PDF metadata: $e');
    }

    // Sync with empty metadata (forces all files to be treated as "changed")
    await syncPdfsWithDelta(job);
  }
}