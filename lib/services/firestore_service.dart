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
        await TenantDataService.migrateExistingData();
        print('✅ Data migration completed');
      }
    } catch (e) {
      print('⚠️ Migration check failed: $e');
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
    
    await jobsCollection.doc(job.id).set({
      ...job.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get jobs with pagination
  static Future<List<Job>> getJobs({int limit = 20, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');
    
    Query query = jobsCollection.orderBy('created', descending: true).limit(limit);
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final querySnapshot = await query.get();
    
    return querySnapshot.docs
        .map((doc) => Job.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Get recent jobs only (for dashboard)
  static Future<List<Job>> getRecentJobs({int limit = 10}) async {
    if (currentUserId == null) return [];
    final jobsCollection = _jobs;
    if (jobsCollection == null) return [];
    
    final snapshot = await jobsCollection
        .orderBy('created', descending: true)
        .limit(limit)
        .get();
        
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return Job.fromJson(data);
    }).toList();
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

  /// Delete a job
  static Future<void> deleteJob(String jobId) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final jobsCollection = _jobs;
    if (jobsCollection == null) throw Exception('Firebase not initialized');
    
    await jobsCollection.doc(jobId).delete();
  }

  /// Get jobs stream for real-time updates
  static Stream<List<Job>> getJobsStream() {
    if (currentUserId == null) return Stream.value([]);
    final jobsCollection = _jobs;
    if (jobsCollection == null) return Stream.value([]);
    
    return jobsCollection.orderBy('created', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Job.fromJson(data);
      }).toList();
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

  /// Get customers with pagination
  static Future<List<Customer>> getCustomers({int limit = 100, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final customersCollection = _customers;
    if (customersCollection == null) throw Exception('Firebase not initialized');
    
    Query query = customersCollection.orderBy('name').limit(limit);
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final querySnapshot = await query.get();
    
    return querySnapshot.docs
        .map((doc) => Customer.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
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

  /// Get price book items with pagination
  static Future<List<PriceBookItem>> getPriceBookItems({int limit = 100, DocumentSnapshot? startAfter}) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    final priceBookCollection = _priceBook;
    if (priceBookCollection == null) throw Exception('Firebase not initialized');
    
    Query query = priceBookCollection.orderBy('name').limit(limit);
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    final querySnapshot = await query.get();
    
    return querySnapshot.docs
        .map((doc) => PriceBookItem.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Search price book items by name
  static Future<List<PriceBookItem>> searchPriceBookItems(String query, {int limit = 20}) async {
    if (currentUserId == null) return [];
    final priceBookCollection = _priceBook;
    if (priceBookCollection == null) return [];
    
    final snapshot = await priceBookCollection
        .orderBy('name')
        .limit(100)
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
    const batchSize = 500;
    for (int i = 0; i < jobs.length; i += batchSize) {
      final batch = db.batch();
      final endIndex = (i + batchSize < jobs.length) ? i + batchSize : jobs.length;
      
      for (int j = i; j < endIndex; j++) {
        final job = jobs[j];
        final docRef = jobsCollection.doc(job.id);
        batch.set(docRef, {
          ...job.toJson(),
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
}
