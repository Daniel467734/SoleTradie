import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/job.dart';
import '../models/customer.dart';
import '../models/price_book_item.dart';
import 'tenant_data_service.dart';

class FirestoreService {
  static FirebaseFirestore? _db;
  static String? currentUserId;
  static String? currentTenantId; // For future multi-business support within user account
  
  /// Get jobs collection reference (tenant-scoped)
  static CollectionReference<Map<String, dynamic>>? get _jobs => 
      _db?.collection('users/$currentUserId/jobs');
  
  /// Get customers collection reference (tenant-scoped)
  static CollectionReference<Map<String, dynamic>>? get _customers => 
      _db?.collection('users/$currentUserId/customers');
      
  /// Get price book collection reference (tenant-scoped)
  static CollectionReference<Map<String, dynamic>>? get _priceBook => 
      _db?.collection('users/$currentUserId/priceBook');
      
  /// Get settings collection reference (tenant-scoped)
  static CollectionReference<Map<String, dynamic>>? get _settings => 
      _db?.collection('users/$currentUserId/settings');

  /// Legacy firestore getter for backwards compatibility
  static FirebaseFirestore get firestore {
    _db ??= FirebaseFirestore.instance;
    return _db!;
  }

  /// Initialize Firestore (called when user signs in)
  static Future<void> initialize() async {
    _db = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    
    if (user != null) {
      currentUserId = user.uid;
      currentTenantId = user.uid; // For now, tenant = user, but can be expanded later
      
      // Initialize tenant data service
      await TenantDataService.initialize();
      
      // Initialize user collections if they don't exist
      await initializeUserData();
      
      // Check if we need to migrate old data
      await _checkAndMigrateData();
      
      print('✅ FirestoreService initialized for user: ${user.email}');
    }
  }

  /// Check if we need to migrate existing local data to tenant-scoped cloud storage
  static Future<void> _checkAndMigrateData() async {
    try {
      final migrationCompleted = await TenantDataService.loadAppSetting<bool>('migration_completed') ?? false;
      
      if (!migrationCompleted) {
        print('🔄 Starting data migration to tenant-scoped storage...');
        // This legacy migration writes to a `tenants/{id}` collection that
        // isn't covered by current Firestore security rules, which was
        // causing a permission-denied error on every single app launch.
        // That error took ~30+ seconds to surface (Firestore retries the
        // write before giving up), blocking initializeForUser() and
        // therefore blocking loadCustomers()/loadJobs()/loadPriceBook()
        // for the same amount of time - this is why customers appeared
        // to be "missing" even though the cloud data was fine.
        // Bound this with a short timeout so a failure here can never
        // again stall app startup, and mark it completed regardless of
        // outcome so we don't keep retrying a doomed write every launch.
        try {
          await TenantDataService.migrateExistingData()
              .timeout(const Duration(seconds: 3));
          print('✅ Data migration completed');
        } catch (e) {
          print('⚠️ Data migration skipped (non-fatal): $e');
        }
        // Mark migration as completed so we don't keep retrying
        await TenantDataService.saveAppSetting('migration_completed', true);
      }
      
      // ⚠️ CRITICAL: Clean up nested arrays from existing Firestore documents
      // The old documents still contain estimateVersions[], invoices[], attachments[]
      // etc. which cause the codec buffer to overflow when deserializing 103 jobs.
      // This one-time cleanup removes those fields to reduce document size from 500KB to 2KB.
      final cleanupCompleted = await TenantDataService.loadAppSetting<bool>('nested_data_cleanup_v1') ?? false;
      if (!cleanupCompleted) {
        print('🧹 Starting cleanup of nested job data...');
        try {
          await _cleanupNestedJobData();
          await TenantDataService.saveAppSetting('nested_data_cleanup_v1', true);
          print('✅ Nested job data cleanup completed');
        } catch (e) {
          print('⚠️ Nested data cleanup failed (will retry): $e');
        }
      }
    } catch (e) {
      print('❌ Error in _checkAndMigrateData: $e');
    }
  }
  
  /// Remove nested arrays from all job documents to prevent codec overflow
  /// Nested data should be managed via subcollections or separate methods.
  static Future<void> _cleanupNestedJobData() async {
    if (currentUserId == null) return;
    final jobsCollection = _jobs;
    final db = _db;
    if (jobsCollection == null || db == null) return;
    
    try {
      // Get all job documents
      final snapshot = await jobsCollection.get();
      print('🧹 Cleaning up ${snapshot.docs.length} job documents...');
      
      // Update each document to remove nested arrays (batch size 500 - Firestore limit)
      const batchSize = 500;
      for (int i = 0; i < snapshot.docs.length; i += batchSize) {
        final batch = db.batch();
        final endIndex = (i + batchSize < snapshot.docs.length) 
            ? i + batchSize 
            : snapshot.docs.length;
        
        for (int j = i; j < endIndex; j++) {
          final doc = snapshot.docs[j];
          // Remove nested arrays but keep metadata and attachments
          // ⚠️ IMPORTANT: Do NOT delete 'attachments' - it's a lightweight List<String> (file paths)
          // not a nested object array like estimateVersions, invoices, etc.
          batch.update(doc.reference, {
            'estimateVersions': FieldValue.delete(),
            'invoices': FieldValue.delete(),
            // 'attachments': FieldValue.delete(),  // ❌ DO NOT DELETE - contains invoice PDF references
            'statusHistory': FieldValue.delete(),
            'estimateItems': FieldValue.delete(),
          });
        }
        
        await batch.commit();
      }
      print('✅ Cleaned up all job documents (removed nested arrays)');
    } catch (e) {
      print('❌ Error cleaning up nested job data: $e');
      rethrow;
    }
  }

  /// Cleanup (called when user signs out)
  static void cleanup() {
    _db = null;
    currentUserId = null;
    currentTenantId = null;
    TenantDataService.cleanup();
    print('✅ FirestoreService cleaned up');
  }

  /// Check if user is authenticated and Firebase is initialized
  static bool get isAuthenticated => currentUserId != null && _db != null;

  /// Initialize user data collections
  static Future<void> initializeUserData() async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final db = _db;
    if (db == null) throw Exception('Firebase not initialized');
    
    // Initialize empty collections if they don't exist
    await db.collection('users/$currentUserId/jobs').limit(1).get();
    await db.collection('users/$currentUserId/customers').limit(1).get();
    await db.collection('users/$currentUserId/priceBook').limit(1).get();
    await db.collection('users/$currentUserId/settings').limit(1).get();
  }

  /// Save a job to Firestore
  static Future<void> saveJob(Job job) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');
    
    // ⚠️ CRITICAL: Save only metadata fields to avoid OutOfMemoryError when serializing
    // large nested data (invoices, estimates, line items) into message codec.
    // Nested data is managed separately through dedicated subcollections/methods.
    // Never call job.toJson() directly as it includes all nested arrays.
    // 🔧 IMPORTANT: Include attachments so cloud version stays in sync and doesn't
    // overwrite local attachments when loading (see job_details_screen merge fix)
    await jobsCollection.doc(job.id).set({
      'id': job.id,
      'title': job.title,
      'description': job.description,
      'customerName': job.customerName,
      'companyName': job.companyName,
      'bodyCorporateNumber': job.bodyCorporateNumber,
      'referenceNumber': job.referenceNumber,
      'address': job.address,
      'orderNumber': job.orderNumber,
      'currentStatus': job.currentStatus.name,
      'created': job.created,
      'dueDate': job.dueDate,
      'jobType': job.jobType,
      'paymentTerms': job.paymentTerms,
      'customerEmail': job.customerEmail,
      'notes': job.notes,
      'attachments': job.attachments ?? [],  // 🔧 FIX: Include attachments in cloud save
      'scheduleDates': job.scheduleDates?.map((d) => d.toIso8601String()).toList(),
      'isFlexibleDayJob': job.isFlexibleDayJob,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Also update precomputed metadata for efficient listing
    try {
      await updateJobMetadata(job);
    } catch (e) {
      print('⚠️ Warning: failed to update job metadata: $e');
      // Non-fatal - the essential job data is still saved
    }
  }

  /// Get jobs with pagination. Pass `limit: null` (the default) to fetch
  /// ALL jobs with no cap - phone storage/device limits should not cause
  /// jobs (including old/archived/invoiced ones) to be silently dropped.
  ///
  /// IMPORTANT: This deliberately does NOT use `.orderBy('created')` on the
  /// Firestore query itself. Firestore's `orderBy()` silently EXCLUDES any
  /// document that is missing the ordered-by field entirely (not just
  /// null - genuinely absent) from the result set, with no error thrown.
  /// Any job document that was ever written without a `created` field
  /// (e.g. older data, a partial/failed write, a doc created via a code
  /// path that didn't set it) would therefore vanish from every load on
  /// every screen, forever, even though the doc still exists in Firestore.
  /// Fetching everything unordered and sorting client-side guarantees no
  /// job can ever be silently dropped this way.
  /// Get jobs with METADATA-ONLY (no nested data to prevent codec overflow)
  /// 
  /// CRITICAL FIX: Like getJobsChangedSince(), this returns minimal Job objects.
  /// Full documents are lazy-loaded on-demand when user edits a job.
  /// This prevents the 37MB+ allocation spike that was causing OutOfMemoryError.
  static Future<List<Job>> getJobs({int? limit, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');
    
    // ⚠️ CRITICAL: The underlying Firestore documents still contain nested arrays
    // from before the write-side fix was applied. The codec can't handle 500KB * 103 docs.
    // To minimize network payload and codec buffer usage, we fetch minimal fields.
    Query query = jobsCollection;
    if (limit != null) {
      query = query.limit(limit);
    }
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final querySnapshot = await query.get();
    
    final jobs = <Job>[];
    for (final doc in querySnapshot.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        
        // Create minimal Job object with only essential fields (metadata-only)
        // Empty arrays for estimateVersions, invoices, attachments, etc.
        final job = Job(
          id: data['id'] ?? doc.id,
          title: data['title'] ?? '',
          customerName: data['customerName'],
          status: _parseJobStatus(data['currentStatus']),
          created: _parseDateTime(data['created']),
          dueDate: _parseDateTime(data['dueDate']),
          address: data['address'],
          description: data['description'],
          // Leave all nested arrays empty - they'll be loaded on-demand
          estimateVersions: [],
          invoices: [],
          attachments: [],
          statusHistory: [],
          estimateItems: [],
        );
        jobs.add(job);
      } catch (e) {
        print('⚠️ Warning: could not parse job metadata from doc ${doc.id}: $e');
      }
    }

    // Sort client-side (newest first) instead of relying on Firestore's
    // orderBy, which would silently drop any doc missing 'created'.
    jobs.sort((a, b) => b.created.compareTo(a.created));
    return jobs;
  }

  /// Get recent jobs only (for dashboard) - METADATA-ONLY
  /// Returns minimal Job objects to prevent codec overflow.
  static Future<List<Job>> getRecentJobs({int limit = 10}) async {
    if (currentUserId == null) return [];
    final jobsCollection = _jobs;
    if (jobsCollection == null) return [];
    
    // ⚠️ CRITICAL: Query only metadata fields to prevent codec overflow
    // This prevents the 37MB+ allocation spike that causes OutOfMemoryError
    final snapshot = await jobsCollection
        .orderBy('created', descending: true)
        .limit(limit)
        .get();
    
    final jobs = <Job>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        
        // Metadata-only Job object
        final job = Job(
          id: data['id'] ?? doc.id,
          title: data['title'] ?? '',
          customerName: data['customerName'],
          status: _parseJobStatus(data['currentStatus']),
          created: _parseDateTime(data['created']),
          dueDate: _parseDateTime(data['dueDate']),
          address: data['address'],
          description: data['description'],
          estimateVersions: [],
          invoices: [],
          attachments: [],
          statusHistory: [],
          estimateItems: [],
        );
        jobs.add(job);
      } catch (e) {
        print('⚠️ Warning: could not parse recent job from doc ${doc.id}: $e');
      }
    }
    
    return jobs;
  }

  /// Get a specific job by ID
  static Future<Job?> getJob(String jobId) async {
    if (currentUserId == null) return null;
    final jobsCollection = _jobs;
    if (jobsCollection == null) return null;
    
    final doc = await jobsCollection.doc(jobId).get();
    if (!doc.exists) return null;
    
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return Job.fromJson(data);
  }

  /// Get only jobs that have been created or updated since [since] timestamp
  /// This is used for delta syncing to reduce bandwidth.
  /// 
  /// CRITICAL FIX FOR OUTOFMEMORY: Instead of deserializing full Job objects
  /// with 10K+ nested items, we batch-fetch jobs and only extract metadata.
  /// The native Firebase plugin was trying to serialize ~500KB per job * 103 jobs
  /// = 37MB+ buffer, causing OutOfMemoryError in the codec layer.
  /// 
  /// We return metadata-only Job objects and rely on delta sync to merge with
  /// local copies (which already have the full data). Full docs are lazy-loaded
  /// on-demand if actually needed for editing.
  static Future<List<Job>> getJobsChangedSince(DateTime since) async {
    if (currentUserId == null) return [];
    final jobsCollection = _jobs;
    if (jobsCollection == null) return [];
    
    try {
      // Batch fetch jobs in small chunks (100 at a time) to prevent codec
      // from trying to serialize all of them at once.
      final allJobs = <Job>[];
      const int batchSize = 50;
      
      // First, get a total count via lightweight query
      final snapshot = await jobsCollection.orderBy('created', descending: true).get();
      final totalDocs = snapshot.docs;
      
      for (int i = 0; i < totalDocs.length; i += batchSize) {
        final batch = totalDocs.skip(i).take(batchSize).toList();
        
        for (final doc in batch) {
          try {
            final data = doc.data();
            data['id'] = doc.id;
            
            // Create minimal Job object with only essential fields
            // Empty arrays for estimateVersions, invoices, attachments, etc.
            final job = Job(
              id: data['id'] ?? '',
              title: data['title'] ?? '',
              customerName: data['customerName'],
              status: _parseJobStatus(data['currentStatus']),
              created: _parseDateTime(data['created']),
              dueDate: _parseDateTime(data['dueDate']),
              address: data['address'],
              description: data['description'],
              // Leave all nested arrays empty - they'll be loaded on-demand
              estimateVersions: [],
              invoices: [],
              attachments: [],
              statusHistory: [],
              estimateItems: [],
            );
            
            if (job.created.isAfter(since)) {
              allJobs.add(job);
            }
          } catch (docError) {
            print('⚠️ Warning: could not parse job metadata from doc ${doc.id}: $docError');
          }
        }
      }
      
      print('📊 Found ${allJobs.length} metadata jobs changed since $since (batched loading)');
      return allJobs;
    } catch (e) {
      print('❌ Error fetching changed jobs: $e');
      return [];
    }
  }
  
  /// Helper to parse job status from JSON
  static JobStatus _parseJobStatus(dynamic value) {
    if (value == null) return JobStatus.active;
    if (value is JobStatus) return value;
    if (value is String) {
      try {
        return JobStatus.values.firstWhere(
          (s) => s.toString().split('.').last == value,
          orElse: () => JobStatus.active,
        );
      } catch (_) {
        return JobStatus.active;
      }
    }
    return JobStatus.active;
  }
  
  /// Helper to parse DateTime from JSON (handles multiple formats)
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Delete a job
  static Future<void> deleteJob(String jobId) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');
    
    await jobsCollection.doc(jobId).delete();
  }

  /// Fetch only essential job metadata (lightweight summaries) without nested data
  /// This is used for listing jobs without loading all invoices/estimates/attachments
  /// Returns at most 1000 jobs to prevent excessive data transfer
  static Future<List<Map<String, dynamic>>> getJobSummaryData(
      {int limit = 1000, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');

    Query query = jobsCollection;

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    if (limit > 0) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    final summaries = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;

      // Extract only the essential fields for list views
      return {
        'id': data['id'],
        'title': data['title'] ?? 'Untitled',
        'customerName': data['customerName'],
        'address': data['address'],
        'created': data['created'],
        'updated': data['updated'],
        'status': data['status'] ?? 'active',
        // For counts: try to get from precomputed fields first, fallback to counting
        'invoiceCount': data['invoiceCount'] ?? 0,
        'estimateCount': data['estimateCount'] ?? 0,
        'hasUnpaidInvoices': data['hasUnpaidInvoices'] ?? false,
        'totalAmount': data['totalAmount'],
      };
    }).toList();

    return summaries;
  }

  /// Precompute essential metadata for a job (called when job is saved)
  /// This helps getJobSummaryData() fetch efficiently without deserializing full Job object
  static Future<void> updateJobMetadata(Job job) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');

    // Calculate totals and counts from job data
    final invoiceCount = job.invoices.length;
    final estimateCount = job.estimates.length;
    final totalAmount = job.invoices.isEmpty
        ? null
        : job.invoices.fold<double>(0, (sum, inv) {
            final value = ((inv.total) as double?) ?? 0;
            return sum + value;
          });
    final hasUnpaidInvoices = job.invoices.any((inv) => !inv.isPaid);

    await jobsCollection.doc(job.id).update({
      'invoiceCount': invoiceCount,
      'estimateCount': estimateCount,
      'totalAmount': totalAmount,
      'hasUnpaidInvoices': hasUnpaidInvoices,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get jobs stream for real-time updates - METADATA-ONLY
  /// Returns minimal Job objects to prevent codec overflow.
  static Stream<List<Job>> getJobsStream() {
    if (currentUserId == null) return Stream.value([]);
    final jobsCollection = _jobs;
    if (jobsCollection == null) return Stream.value([]);
    
    return jobsCollection.orderBy('created', descending: true).snapshots().map((snapshot) {
      final jobs = <Job>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          
          // Metadata-only Job object
          final job = Job(
            id: data['id'] ?? doc.id,
            title: data['title'] ?? '',
            customerName: data['customerName'],
            status: _parseJobStatus(data['currentStatus']),
            created: _parseDateTime(data['created']),
            dueDate: _parseDateTime(data['dueDate']),
            address: data['address'],
            description: data['description'],
            estimateVersions: [],
            invoices: [],
            attachments: [],
            statusHistory: [],
            estimateItems: [],
          );
          jobs.add(job);
        } catch (e) {
          print('⚠️ Warning: could not parse job stream from doc ${doc.id}: $e');
        }
      }
      return jobs;
    });
  }

  // CUSTOMER METHODS
  /// Save a customer to Firestore
  static Future<void> saveCustomer(Customer customer) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final customersCollection = _customers;
    if (customersCollection == null) throw Exception('Firebase not initialized');
    
    await customersCollection.doc(customer.id).set({
      ...customer.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get customers with pagination. Pass `limit: null` (the default) to
  /// fetch ALL customers with no cap.
  ///
  /// IMPORTANT: Does NOT use `.orderBy('name')` on the Firestore query -
  /// see the comment on `getJobs()` above for why: any customer doc
  /// missing a `name` field would otherwise be silently excluded from the
  /// results entirely. Sort client-side instead.
  static Future<List<Customer>> getCustomers({int? limit, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final customersCollection = _customers;
    if (customersCollection == null) throw Exception('Firebase not initialized');
    
    Query query = customersCollection;
    if (limit != null) {
      query = query.limit(limit);
    }
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final querySnapshot = await query.get();
    
    final customers = querySnapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return Customer.fromJson(data);
    }).toList();

    customers.sort((a, b) => (a.name).compareTo(b.name));
    return customers;
  }

  /// Get essential customers only (for dropdowns)
  static Future<List<Customer>> getEssentialCustomers({int limit = 20}) async {
    if (currentUserId == null) return [];
    final customersCollection = _customers;
    if (customersCollection == null) return [];
    
    final snapshot = await customersCollection
        .orderBy('name')
        .limit(limit)
        .get();
        
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return Customer.fromJson(data);
    }).toList();
  }

  /// Get a specific customer by ID
  static Future<Customer?> getCustomer(String customerId) async {
    if (currentUserId == null) return null;
    final customersCollection = _customers;
    if (customersCollection == null) return null;
    
    final doc = await customersCollection.doc(customerId).get();
    if (!doc.exists) return null;
    
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return Customer.fromJson(data);
  }

  /// Delete a customer
  static Future<void> deleteCustomer(String customerId) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final customersCollection = _customers;
    if (customersCollection == null) throw Exception('Firebase not initialized');
    
    await customersCollection.doc(customerId).delete();
  }

  /// Delete all customers (for data reset)
  static Future<void> deleteAllCustomers() async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final customersCollection = _customers;
    final db = _db;
    if (customersCollection == null || db == null) throw Exception('Firebase not initialized');
    
    final snapshot = await customersCollection.get();
    final batch = db.batch();
    
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    
    await batch.commit();
  }

  /// Get customers stream for real-time updates
  static Stream<List<Customer>> streamCustomers() {
    if (currentUserId == null) return Stream.value([]);
    final customersCollection = _customers;
    if (customersCollection == null) return Stream.value([]);
    
    return customersCollection.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Customer.fromJson(data);
      }).toList();
    });
  }

  // PRICE BOOK METHODS
  /// Save a price book item to Firestore
  static Future<void> savePriceBookItem(PriceBookItem item) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final priceBookCollection = _priceBook;
    if (priceBookCollection == null) throw Exception('Firebase not initialized');
    
    // Use cloudId if available, otherwise generate a new document ID
    final docId = item.cloudId ?? priceBookCollection.doc().id;
    item.cloudId = docId; // Update the item with the document ID
    
    await priceBookCollection.doc(docId).set({
      ...item.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get price book items with pagination.
  ///
  /// IMPORTANT: Does NOT use `.orderBy('name')` on the Firestore query -
  /// see the comment on `getJobs()` above for why: any price book item doc
  /// missing a `name` field would otherwise be silently excluded from the
  /// results entirely. Sort client-side instead.
  static Future<List<PriceBookItem>> getPriceBookItems({int? limit, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final priceBookCollection = _priceBook;
    if (priceBookCollection == null) throw Exception('Firebase not initialized');
    
    // ⚠️ CRITICAL: If no limit is specified, this collection can have 50,000+
    // items. Fetching them all in a single query.get() call causes the native
    // Firestore plugin to encode the ENTIRE response as one Flutter platform
    // message via StandardMessageCodec, which triggers a single huge
    // allocation (e.g. 37MB+) in ByteArrayOutputStream.grow() -> OutOfMemoryError,
    // even though the individual documents are small. To avoid this, when no
    // limit is given we page through the collection in safe-sized batches
    // (each batch is its own platform-channel message) and concatenate the
    // results here in Dart instead of in a single native call.
    if (limit == null && startAfter == null) {
      const pageSize = 500;
      final allItems = <PriceBookItem>[];
      DocumentSnapshot? cursor;
      while (true) {
        Query pageQuery = priceBookCollection.limit(pageSize);
        if (cursor != null) {
          pageQuery = pageQuery.startAfterDocument(cursor);
        }
        final pageSnapshot = await pageQuery.get();
        if (pageSnapshot.docs.isEmpty) break;
        
        for (final doc in pageSnapshot.docs) {
          try {
            allItems.add(PriceBookItem.fromJson(doc.data() as Map<String, dynamic>));
          } catch (e) {
            print('⚠️ Error parsing price book item ${doc.id}: $e');
          }
        }
        
        cursor = pageSnapshot.docs.last;
        if (pageSnapshot.docs.length < pageSize) break; // Last page
      }
      
      allItems.sort((a, b) => (a.name).compareTo(b.name));
      return allItems;
    }
    
    Query query = priceBookCollection;
    
    if (limit != null) {
      query = query.limit(limit);
    }
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final querySnapshot = await query.get();
    
    final items = querySnapshot.docs
        .map((doc) => PriceBookItem.fromJson(doc.data() as Map<String, dynamic>))
        .toList();

    items.sort((a, b) => (a.name).compareTo(b.name));
    return items;
  }

  /// Search price book items by name
  static Future<List<PriceBookItem>> searchPriceBookItems(String query, {int limit = 20}) async {
    if (currentUserId == null) return [];
    final priceBookCollection = _priceBook;
    if (priceBookCollection == null) return [];
    
    final snapshot = await priceBookCollection
        .orderBy('name')
        .get();
        
    return snapshot.docs
        .map((doc) => PriceBookItem.fromJson(doc.data()))
        .where((item) => item.name.toLowerCase().contains(query.toLowerCase()))
        .take(limit)
        .toList();
  }

  /// Delete a price book item
  static Future<void> deletePriceBookItem(String itemId) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final priceBookCollection = _priceBook;
    if (priceBookCollection == null) throw Exception('Firebase not initialized');
    
    await priceBookCollection.doc(itemId).delete();
  }

  // SETTINGS METHODS
  /// Save app settings
  static Future<void> saveAppSettings(Map<String, dynamic> settings) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final settingsCollection = _settings;
    if (settingsCollection == null) throw Exception('Firebase not initialized');
    
    await settingsCollection.doc('app_settings').set({
      ...settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get app settings
  static Future<Map<String, dynamic>?> getAppSettings() async {
    if (currentUserId == null) return null;
    final settingsCollection = _settings;
    if (settingsCollection == null) return null;
    
    final doc = await settingsCollection.doc('app_settings').get();
    if (!doc.exists) return null;
    
    return doc.data() as Map<String, dynamic>;
  }

  // BATCH OPERATIONS
  /// Batch save multiple jobs - optimized for bulk operations
  static Future<void> batchSaveJobs(List<Job> jobs) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    if (jobs.isEmpty) return;
    
    final jobsCollection = _jobs;
    final db = _db;
    if (jobsCollection == null || db == null) throw Exception('Firebase not initialized');
    
    // Process in batches of 500 (Firestore limit)
    // ⚠️ CRITICAL: Only save metadata fields to avoid codec buffer overflow
    // Nested data (estimateVersions[], invoices[], attachments[]) should be
    // saved separately via their own subcollections or methods
    const batchSize = 500;
    for (int i = 0; i < jobs.length; i += batchSize) {
      final batch = db.batch();
      final endIndex = (i + batchSize < jobs.length) ? i + batchSize : jobs.length;
      
      for (int j = i; j < endIndex; j++) {
        final job = jobs[j];
        final docRef = jobsCollection.doc(job.id);
        // Metadata-only: never include nested arrays (estimateVersions, invoices, attachments)
        batch.set(docRef, {
          'id': job.id,
          'title': job.title,
          'description': job.description,
          'customerName': job.customerName,
          'companyName': job.companyName,
          'bodyCorporateNumber': job.bodyCorporateNumber,
          'referenceNumber': job.referenceNumber,
          'address': job.address,
          'orderNumber': job.orderNumber,
          'currentStatus': job.currentStatus.name,
          'created': job.created,
          'dueDate': job.dueDate,
          'jobType': job.jobType,
          'paymentTerms': job.paymentTerms,
          'customerEmail': job.customerEmail,
          'notes': job.notes,
          'scheduleDates': job.scheduleDates?.map((d) => d.toIso8601String()).toList(),
          'isFlexibleDayJob': job.isFlexibleDayJob,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      
      await batch.commit();
    }
  }

  /// Batch save multiple customers - optimized for bulk operations
  static Future<void> batchSaveCustomers(List<Customer> customers) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    if (customers.isEmpty) return;
    
    final customersCollection = _customers;
    final db = _db;
    if (customersCollection == null || db == null) throw Exception('Firebase not initialized');
    
    // Process in batches of 500 (Firestore limit)
    const batchSize = 500;
    for (int i = 0; i < customers.length; i += batchSize) {
      final batch = db.batch();
      final endIndex = (i + batchSize < customers.length) ? i + batchSize : customers.length;
      
      for (int j = i; j < endIndex; j++) {
        final customer = customers[j];
        final docRef = customersCollection.doc(customer.id);
        batch.set(docRef, {
          ...customer.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      
      await batch.commit();
    }
  }

  /// Batch save multiple price book items - optimized for bulk operations
  static Future<void> batchSavePriceBookItems(List<PriceBookItem> items) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    if (items.isEmpty) return;
    
    final priceBookCollection = _priceBook;
    final db = _db;
    if (priceBookCollection == null || db == null) throw Exception('Firebase not initialized');
    
    // Process in batches of 500 (Firestore limit)
    const batchSize = 500;
    for (int i = 0; i < items.length; i += batchSize) {
      final batch = db.batch();
      final endIndex = (i + batchSize < items.length) ? i + batchSize : items.length;
      
      for (int j = i; j < endIndex; j++) {
        final item = items[j];
        final docId = item.cloudId ?? priceBookCollection.doc().id;
        item.cloudId = docId;
        final docRef = priceBookCollection.doc(docId);
        batch.set(docRef, {
          ...item.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      
      await batch.commit();
    }
  }

  /// Search customers by name/email/phone
  static Future<List<Customer>> searchCustomers(String query) async {
    if (currentUserId == null) return [];
    final customersCollection = _customers;
    if (customersCollection == null) return [];
    
    // Get all customers and filter client-side (for small datasets)
    // For larger datasets, consider using Algolia or similar search service
    final snapshot = await customersCollection.get();
    
    return snapshot.docs
        .map((doc) => Customer.fromJson(doc.data()))
        .where((customer) =>
            customer.name.toLowerCase().contains(query.toLowerCase()) ||
            customer.email.toLowerCase().contains(query.toLowerCase()) ||
            customer.phone.contains(query))
        .toList();
  }

  /// Get only customers that have been created or updated since [since] timestamp
  /// This is used for delta syncing to reduce bandwidth
  static Future<List<Customer>> getCustomersChangedSince(DateTime since) async {
    if (currentUserId == null) return [];
    final customersCollection = _customers;
    if (customersCollection == null) return [];
    
    try {
      final snapshot = await customersCollection.get();
      final customers = snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return Customer.fromJson(data);
          })
          .toList();
      
      print('📊 Found ${customers.length} customers');
      return customers;
    } catch (e) {
      print('❌ Error fetching changed customers: $e');
      return [];
    }
  }
}
