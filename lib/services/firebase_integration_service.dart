import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'job_lazy_load_service.dart';
import 'delta_sync_service.dart';
import '../models/customer.dart';
import '../models/job.dart';
import '../models/price_book_item.dart';
import '../screens/pricebook_extensive_screen.dart' as pb;

/// Enhanced Firebase integration service that provides seamless sync between local and cloud storage
class FirebaseIntegrationService {
  static bool _isInitialized = false;
  
  /// Initialize Firebase integration when user signs in
  static Future<void> initializeForUser() async {
    if (_isInitialized) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found');
    }
    
    try {
      // Initialize Firestore service
      FirestoreService.initialize();
      
      // Initialize user data collections if needed
      await FirestoreService.initializeUserData();
      
      _isInitialized = true;
      print('✅ Firebase integration initialized for user: ${user.email}');
    } catch (e) {
      print('❌ Failed to initialize Firebase integration: $e');
      rethrow;
    }
  }
  
  /// Cleanup when user signs out
  static void cleanup() {
    FirestoreService.cleanup();
    _isInitialized = false;
    print('🧹 Firebase integration cleaned up');
  }
  
  /// Check if Firebase integration is ready
  static bool get isReady => _isInitialized && FirebaseAuth.instance.currentUser != null;

  /// Wait briefly for Firebase integration to become ready before deciding to
  /// fall back to local storage. This avoids a race condition on app startup
  /// where loadJobs()/loadCustomers()/loadPriceBook() run before
  /// initializeForUser() has finished, which previously caused a silent
  /// fallback to a stale local cache even though the user was really signed in
  /// and cloud data was available.
  static Future<bool> _waitUntilReady({Duration timeout = const Duration(seconds: 5)}) async {
    if (isReady) return true;
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (isReady) return true;
    }
    return isReady;
  }
  
  // CUSTOMER SYNC METHODS
  
  // CRITICAL: `main.dart` calls `loadCustomers()` from several places in
  // quick succession at startup/refresh. Serialize the background cloud
  // refresh the same way as jobs to avoid concurrent writes to
  // customers.json.
  static Future<void>? _inFlightCustomersRefresh;

  /// Load customers local-first for an instant UI, then refresh from the
  /// cloud in the background. Pass [onCloudUpdate] to be notified (e.g. to
  /// call setState) once the cloud data has been fetched and merged.
  /// This avoids the old cloud-first behaviour which could block the UI
  /// for 30-40+ seconds on a cold Firestore connection.
  static Future<List<Customer>> loadCustomers({
    void Function(List<Customer> cloudCustomers)? onCloudUpdate,
  }) async {
    final localCustomers = await _loadCustomersFromLocal();
    print('📱 Loaded ${localCustomers.length} customers from local storage');

    if (_inFlightCustomersRefresh != null) {
      print('⏳ Cloud customers refresh already in progress - not starting another');
      return localCustomers;
    }

    // Kick off the cloud refresh in the background - do not block on it.
    final refreshFuture = _refreshCustomersFromCloud(
      localCustomers: localCustomers,
      onCloudUpdate: onCloudUpdate,
    );
    _inFlightCustomersRefresh = refreshFuture;
    unawaited(refreshFuture.whenComplete(() => _inFlightCustomersRefresh = null));

    return localCustomers;
  }

  /// Fetches customers from Firestore in the background, merges with local
  /// storage, and notifies [onCloudUpdate] if the cloud has data.
  static Future<void> _refreshCustomersFromCloud({
    required List<Customer> localCustomers,
    void Function(List<Customer> cloudCustomers)? onCloudUpdate,
  }) async {
    try {
      final ready = await _waitUntilReady();
      if (!ready) {
        // Not signed in / not ready - if we have local data, try to push
        // it up once we do become ready is handled elsewhere; nothing more
        // to do right now.
        return;
      }

      final cloudCustomers = await FirestoreService.getCustomers();
      if (cloudCustomers.isNotEmpty) {
        await _saveCustomersToLocal(cloudCustomers);
        print('✅ Synced ${cloudCustomers.length} customers from Firebase');
        onCloudUpdate?.call(cloudCustomers);
      } else if (localCustomers.isNotEmpty) {
        // Cloud is empty but we have local data - push it up so the
        // cloud becomes the source of truth for next time.
        await syncCustomersToCloud(localCustomers);
      }
    } catch (e) {
      print('❌ Error refreshing customers from Firebase: $e');
    }
  }
  
  /// Save customer with automatic cloud sync
  static Future<void> saveCustomer(Customer customer) async {
    try {
      // Save to local storage first (faster)
      await _saveCustomerToLocal(customer);
      
      // Sync to cloud if authenticated
      if (isReady) {
        await FirestoreService.saveCustomer(customer);
        print('☁️ Customer ${customer.name} synced to Firebase');
      }
    } catch (e) {
      print('❌ Error saving customer: $e');
      rethrow;
    }
  }
  
  /// Sync local customers to cloud
  static Future<void> syncCustomersToCloud(List<Customer> customers) async {
    if (!isReady || customers.isEmpty) return;
    
    try {
      await FirestoreService.batchSaveCustomers(customers);
      print('☁️ Synced ${customers.length} customers to Firebase');
    } catch (e) {
      print('❌ Failed to sync customers to Firebase: $e');
    }
  }

  /// Delete a customer both locally and from the cloud. Previously
  /// main.dart's _removeCustomer() only removed the customer from the
  /// in-memory list and (by mistake) re-saved the price book instead of
  /// persisting the customer removal anywhere - meaning deleted customers
  /// (including duplicates) would reappear after the next cloud sync since
  /// they were never actually deleted from customers.json or Firestore.
  static Future<void> deleteCustomer(String customerId) async {
    try {
      final customers = await _loadCustomersFromLocal();
      customers.removeWhere((c) => c.id == customerId);
      await _saveCustomersToLocal(customers);

      if (isReady) {
        await FirestoreService.deleteCustomer(customerId);
        print('☁️ Customer $customerId deleted from Firebase');
      }
    } catch (e) {
      print('❌ Error deleting customer: $e');
      rethrow;
    }
  }
  
  // JOB SYNC METHODS

  // CRITICAL: `main.dart` calls `loadJobs()` from several places in quick
  // succession at startup/refresh (auth listener, `_loadDataFallback()`,
  // `_refreshAppData()`). Each call spawns its own unawaited
  // `_refreshJobsFromCloud()` in the background. Without serialization,
  // these raced to read-modify-write the same local `jobs.json`, silently
  // corrupting/losing builds, attachments and invoices. This lock ensures
  // only one cloud refresh runs at a time.
  static Future<void>? _inFlightJobsRefresh;

  /// Load jobs local-first for an instant UI, then refresh from the cloud
  /// in the background. Pass [onCloudUpdate] to be notified (e.g. to call
  /// setState) once the cloud data has been fetched and merged.
  static Future<List<Job>> loadJobs({
    void Function(List<Job> cloudJobs)? onCloudUpdate,
  }) async {
    final localJobs = await _loadJobsFromLocal();
    print('📱 Loaded ${localJobs.length} jobs from local storage');

    final inFlight = _inFlightJobsRefresh;
    if (inFlight != null) {
      print('⏳ Cloud jobs refresh already in progress - not starting another');
      return localJobs;
    }

    final refreshFuture = _refreshJobsFromCloud(
      localJobs: localJobs,
      onCloudUpdate: onCloudUpdate,
    );
    _inFlightJobsRefresh = refreshFuture;
    unawaited(refreshFuture.whenComplete(() => _inFlightJobsRefresh = null));

    return localJobs;
  }

  /// Fetches jobs from Firestore in the background using delta sync (only changed jobs),
  /// merges with local storage, and notifies [onCloudUpdate] if the cloud has data.
  /// This avoids the OutOfMemoryError by only loading jobs that changed since last sync.
  static Future<void> _refreshJobsFromCloud({
    required List<Job> localJobs,
    void Function(List<Job> cloudJobs)? onCloudUpdate,
  }) async {
    try {
      final ready = await _waitUntilReady();
      if (!ready) return;

      // Use delta sync to only fetch changed jobs (not all jobs)
      // This prevents OutOfMemoryError by avoiding loading all nested data at once.
      // NOTE: DeltaSyncService.syncJobsWithDelta() already persists the
      // merged result to jobs.json internally - do NOT save again here,
      // that would be a redundant duplicate write that can race with the
      // next refresh cycle and corrupt the file.
      final cloudJobs = await DeltaSyncService.syncJobsWithDelta();
      if (cloudJobs.isNotEmpty) {
        print('✅ Synced ${cloudJobs.length} jobs from Firebase (delta sync)');
        onCloudUpdate?.call(cloudJobs);
      } else if (localJobs.isNotEmpty) {
        await syncJobsToCloud(localJobs);
      }
    } catch (e) {
      print('❌ Error refreshing jobs from Firebase: $e');
    }
  }
  
  /// Save job with automatic cloud sync (using lazy-load service)
  static Future<void> saveJob(Job job) async {
    try {
      // Use the lazy-load service which handles both local + cloud sync
      await JobLazyLoadService.saveJobDetails(job);
      
      // Sync invoice PDFs to Firebase Storage using intelligent delta sync
      // (only uploads PDFs that changed, skips unchanged ones)
      _syncJobPdfsWithDelta(job).catchError((e) {
        print('⚠️ Warning: Failed to sync invoice PDFs: $e');
      });
    } catch (e) {
      print('❌ Error saving job: $e');
      rethrow;
    }
  }
  
  /// Intelligently sync invoice PDFs - only uploads if file changed (hash-based)
  static Future<void> _syncJobPdfsWithDelta(Job job) async {
    // Check if user is authenticated
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('⚠️ Not signed in - skipping PDF sync');
      return;
    }

    try {
      // Use DeltaSyncService for intelligent PDF sync
      // This calculates file hashes and only uploads changed PDFs
      await DeltaSyncService.syncPdfsWithDelta(job);
    } catch (e) {
      print('❌ Error syncing invoice PDFs: $e');
    }
  }
  
  /// Sync local jobs to cloud
  static Future<void> syncJobsToCloud(List<Job> jobs) async {
    if (!isReady || jobs.isEmpty) return;
    
    try {
      await FirestoreService.batchSaveJobs(jobs);
      print('☁️ Synced ${jobs.length} jobs to Firebase');
    } catch (e) {
      print('❌ Failed to sync jobs to Firebase: $e');
    }
  }

  /// Delete a job both locally and from the cloud.
  static Future<void> deleteJob(String jobId) async {
    try {
      final jobs = await _loadJobsFromLocal();
      jobs.removeWhere((j) => j.id == jobId);
      await _saveJobsToLocal(jobs);

      if (isReady) {
        await FirestoreService.deleteJob(jobId);
        print('☁️ Job $jobId deleted from Firebase');
      }
    } catch (e) {
      print('❌ Error deleting job: $e');
      rethrow;
    }
  }
  
  // PRICE BOOK SYNC METHODS
  
  /// Load price book local-first for an instant UI, then refresh from the
  /// cloud in the background. Pass [onCloudUpdate] to be notified (e.g. to
  /// call setState) once the cloud data has been fetched and merged.
  static Future<List<pb.PriceBookItem>> loadPriceBook({
    void Function(List<pb.PriceBookItem> cloudItems)? onCloudUpdate,
  }) async {
    final localItems = await _loadPriceBookFromLocal();
    print('📱 Loaded ${localItems.length} price book items from local storage');

    unawaited(_refreshPriceBookFromCloud(
      localItems: localItems,
      onCloudUpdate: onCloudUpdate,
    ));

    if (localItems.isEmpty) {
      // No local data at all yet (e.g. very first run) - fall back to a
      // sample price book so the UI isn't completely empty while we wait
      // for the background cloud refresh to complete.
      return _createSamplePriceBook();
    }
    return localItems;
  }

  /// Fetches the price book from Firestore in the background, merges with
  /// local storage, and notifies [onCloudUpdate] if the cloud has data.
  static Future<void> _refreshPriceBookFromCloud({
    required List<pb.PriceBookItem> localItems,
    void Function(List<pb.PriceBookItem> cloudItems)? onCloudUpdate,
  }) async {
    try {
      final ready = await _waitUntilReady();
      if (!ready) return;

      final cloudItems = await FirestoreService.getPriceBookItems();
      if (cloudItems.isNotEmpty) {
        final pbItems = cloudItems.map((item) => pb.PriceBookItem.fromJson(item.toJson())).toList();
        await _savePriceBookToLocal(pbItems);
        print('✅ Synced ${pbItems.length} price book items from Firebase');
        onCloudUpdate?.call(pbItems);
      } else if (localItems.isNotEmpty) {
        await syncPriceBookToCloud(localItems);
      }
    } catch (e) {
      print('❌ Error refreshing price book from Firebase: $e');
    }
  }
  
  /// Save price book with automatic cloud sync
  static Future<void> savePriceBook(List<pb.PriceBookItem> items) async {
    try {
      // Save to local storage first (faster)
      await _savePriceBookToLocal(items);
      
      // Sync to cloud if authenticated
      if (isReady) {
        await syncPriceBookToCloud(items);
      }
    } catch (e) {
      print('❌ Error saving price book: $e');
      rethrow;
    }
  }
  
  /// Sync local price book to cloud
  static Future<void> syncPriceBookToCloud(List<pb.PriceBookItem> items) async {
    if (!isReady || items.isEmpty) return;
    
    try {
      // Convert pb.PriceBookItem to models/PriceBookItem for Firestore
      final firestoreItems = items.map((pbItem) {
        return PriceBookItem(
          code: pbItem.code,
          name: pbItem.name,
          category: pbItem.groupCode,
          purchasePrice: pbItem.purchasePrice,
          salePrice: pbItem.price,
          unit: pbItem.unit,
          description: '',
        );
      }).toList();
      
      await FirestoreService.batchSavePriceBookItems(firestoreItems);
      print('☁️ Synced ${items.length} price book items to Firebase');
    } catch (e) {
      print('❌ Failed to sync price book to Firebase: $e');
    }
  }
  
  // PRIVATE LOCAL STORAGE METHODS
  
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
      print('❌ Error saving customers to local: $e');
    }
  }
  
  static Future<void> _saveCustomerToLocal(Customer customer) async {
    try {
      final customers = await _loadCustomersFromLocal();
      final index = customers.indexWhere((c) => c.id == customer.id);
      if (index >= 0) {
        customers[index] = customer;
      } else {
        customers.add(customer);
      }
      await _saveCustomersToLocal(customers);
    } catch (e) {
      print('❌ Error saving customer to local: $e');
    }
  }
  
  static Future<List<Job>> _loadJobsFromLocal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/jobs.json');
      
      if (await file.exists()) {
        try {
          final jsonString = await file.readAsString();
          if (jsonString.trim().isNotEmpty) {
            // Try to parse JSON - this will catch truncation errors
            final List<dynamic> jsonList = jsonDecode(jsonString);
            final jobs = jsonList.map((e) => Job.fromJson(e)).toList();
            
            // Sync invoices for loaded jobs
            for (final job in jobs) {
              job.syncInvoices();
            }
            
            print('✅ Loaded ${jobs.length} jobs from local storage (valid JSON)');
            return jobs;
          }
        } catch (parseError) {
          // JSON parse error indicates corruption
          print('⚠️ WARNING: jobs.json is corrupted: $parseError');
          
          // Backup corrupted file
          try {
            final corruptFile = File('${file.path}.corrupt');
            await file.copy(corruptFile.path);
            print('💾 Backed up corrupted jobs.json to jobs.json.corrupt');
          } catch (backupError) {
            print('⚠️ Could not backup corrupted file: $backupError');
          }
          
          // Try to load from backup if it exists
          try {
            final backupFile = File('${file.path}.backup');
            if (await backupFile.exists()) {
              final backupJson = await backupFile.readAsString();
              if (backupJson.trim().isNotEmpty) {
                final List<dynamic> jsonList = jsonDecode(backupJson);
                final jobs = jsonList.map((e) => Job.fromJson(e)).toList();
                for (final job in jobs) {
                  job.syncInvoices();
                }
                print('✅ Recovered ${jobs.length} jobs from backup');
                return jobs;
              }
            }
          } catch (backupError) {
            print('⚠️ Could not load from backup: $backupError');
          }
        }
      }
    } catch (e) {
      print('❌ Error accessing jobs file: $e');
    }
    
    print('⚠️ No valid local jobs found, will sync from Firebase');
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
        
        // Atomically swap temp -> final
        await tempFile.rename(file.path);
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
  
  static Future<List<pb.PriceBookItem>> _loadPriceBookFromLocal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(jsonString);
            final List<dynamic> jsonList;
            if (decoded is Map<String, dynamic> && decoded.containsKey('items')) {
              jsonList = decoded['items'] as List<dynamic>;
            } else if (decoded is List<dynamic>) {
              jsonList = decoded;
            } else {
              throw Exception('Unexpected pricebook JSON structure');
            }
            
            // Validate we got valid items
            if (jsonList.isEmpty) {
              print('⚠️ Price book file is empty, using default');
              return _createSamplePriceBook();
            }
            
            return jsonList.map((e) => pb.PriceBookItem.fromJson(e)).toList();
          } catch (parseError) {
            print('⚠️ Price book JSON corrupted: $parseError');
            // Try to delete the corrupted file and use default
            try {
              // Back it up first
              final backup = File('${directory.path}/price_book.json.corrupt');
              if (await file.exists()) {
                await file.rename(backup.path);
                print('📋 Backed up corrupted price book to: ${backup.path}');
              }
            } catch (backupError) {
              print('⚠️ Could not backup corrupted price book: $backupError');
            }
            return _createSamplePriceBook();
          }
        }
      }
    } catch (e) {
      print('⚠️ Error loading price book from local: $e');
    }
    return _createSamplePriceBook();
  }
  
  static Future<void> _savePriceBookToLocal(List<pb.PriceBookItem> items) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/price_book.json';
      final file = File(filePath);
      final tempFile = File('${filePath}.tmp');
      
      // Create JSON data
      final jsonList = items.map((item) => item.toJson()).toList();
      final data = {
        'items': jsonList,
        'lastSaved': DateTime.now().toIso8601String(),
        'version': 1,
        'totalItems': jsonList.length,
      };
      final jsonString = jsonEncode(data);
      
      // Write to temporary file first (atomic write pattern)
      await tempFile.writeAsString(jsonString);
      
      // Verify the file was written completely
      final tempSize = await tempFile.length();
      if (tempSize == 0 || tempSize < jsonString.length * 0.9) {
        // Write was incomplete, abort the swap
        await tempFile.delete();
        print('⚠️ Price book write incomplete (${tempSize}/${jsonString.length} bytes), aborted swap');
        return;
      }
      
      // Verify JSON integrity by trying to parse it
      try {
        jsonDecode(await tempFile.readAsString());
      } catch (e) {
        // JSON is corrupted, delete and abort
        await tempFile.delete();
        print('⚠️ Price book JSON is corrupt, aborted save: $e');
        return;
      }
      
      // Delete old file if it exists
      if (await file.exists()) {
        await file.delete();
      }
      
      // Atomically rename temp file to final location
      await tempFile.rename(filePath);
      
      print('✅ Price book saved: ${items.length} items, ${tempSize} bytes');
    } catch (e) {
      print('❌ Error saving price book to local: $e');
    }
  }
  
  static List<pb.PriceBookItem> _createSamplePriceBook() {
    return [
      pb.PriceBookItem(
        code: 'CAL',
        name: 'Labour',
        unit: 'hr',
        groupCode: 'LABOUR',
        price: 85.0,
        purchasePrice: 65.0,
        favorite: true,
      ),
      pb.PriceBookItem(
        code: 'OUTLET',
        name: 'Power Outlet',
        unit: 'each',
        groupCode: 'ELECTRICAL',
        price: 45.0,
        purchasePrice: 25.0,
      ),
      pb.PriceBookItem(
        code: 'SWITCH',
        name: 'Light Switch',
        unit: 'each',
        groupCode: 'ELECTRICAL',
        price: 35.0,
        purchasePrice: 18.0,
      ),
      pb.PriceBookItem(
        code: 'CABLE',
        name: 'Electrical Cable (per meter)',
        unit: 'm',
        groupCode: 'ELECTRICAL',
        price: 12.0,
        purchasePrice: 8.0,
      ),
      pb.PriceBookItem(
        code: 'BREAKER',
        name: 'Circuit Breaker',
        unit: 'each',
        groupCode: 'ELECTRICAL',
        price: 65.0,
        purchasePrice: 35.0,
      ),
    ];
  }
  
  // SYNC STATUS METHODS
  
  /// Get sync status for dashboard display
  static Map<String, dynamic> getSyncStatus() {
    return {
      'isAuthenticated': FirebaseAuth.instance.currentUser != null,
      'userEmail': FirebaseAuth.instance.currentUser?.email,
      'isReady': isReady,
      'lastSync': DateTime.now().toIso8601String(),
    };
  }
  
  /// Force sync all data to cloud (for manual sync button)
  static Future<void> forceSyncAll() async {
    if (!isReady) {
      throw Exception('Firebase not ready for sync');
    }
    
    try {
      // Load all local data
      final customers = await _loadCustomersFromLocal();
      final jobs = await _loadJobsFromLocal();
      final priceBook = await _loadPriceBookFromLocal();
      
      // Sync everything to cloud
      final futures = <Future>[];
      
      if (customers.isNotEmpty) {
        futures.add(syncCustomersToCloud(customers));
      }
      
      if (jobs.isNotEmpty) {
        futures.add(syncJobsToCloud(jobs));
      }
      
      if (priceBook.isNotEmpty) {
        futures.add(syncPriceBookToCloud(priceBook));
      }
      
      await Future.wait(futures);
      print('✅ Force sync completed successfully');
    } catch (e) {
      print('❌ Force sync failed: $e');
      rethrow;
    }
  }
}
