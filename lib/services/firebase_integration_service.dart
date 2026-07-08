import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
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
  
  // CUSTOMER SYNC METHODS
  
  /// Load customers with cloud-first approach and local fallback
  static Future<List<Customer>> loadCustomers() async {
    try {
      // Try cloud first if authenticated
      if (isReady) {
        final cloudCustomers = await FirestoreService.getCustomers(limit: 200);
        if (cloudCustomers.isNotEmpty) {
          // Save to local as backup
          await _saveCustomersToLocal(cloudCustomers);
          print('✅ Loaded ${cloudCustomers.length} customers from Firebase');
          return cloudCustomers;
        }
      }
      
      // Fallback to local storage
      final localCustomers = await _loadCustomersFromLocal();
      
      // If we have local data and are authenticated, sync to cloud
      if (localCustomers.isNotEmpty && isReady) {
        await syncCustomersToCloud(localCustomers);
      }
      
      print('📱 Loaded ${localCustomers.length} customers from local storage');
      return localCustomers;
    } catch (e) {
      print('❌ Error loading customers: $e');
      return [];
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
  
  // JOB SYNC METHODS
  
  /// Load jobs with cloud-first approach and local fallback
  static Future<List<Job>> loadJobs() async {
    try {
      // Try cloud first if authenticated
      if (isReady) {
        final cloudJobs = await FirestoreService.getJobs(limit: 100);
        if (cloudJobs.isNotEmpty) {
          // Save to local as backup
          await _saveJobsToLocal(cloudJobs);
          print('✅ Loaded ${cloudJobs.length} jobs from Firebase');
          return cloudJobs;
        }
      }
      
      // Fallback to local storage
      final localJobs = await _loadJobsFromLocal();
      
      // If we have local data and are authenticated, sync to cloud
      if (localJobs.isNotEmpty && isReady) {
        await syncJobsToCloud(localJobs);
      }
      
      print('📱 Loaded ${localJobs.length} jobs from local storage');
      return localJobs;
    } catch (e) {
      print('❌ Error loading jobs: $e');
      return [];
    }
  }
  
  /// Save job with automatic cloud sync
  static Future<void> saveJob(Job job) async {
    try {
      // Save to local storage first (faster)
      await _saveJobToLocal(job);
      
      // Sync to cloud if authenticated
      if (isReady) {
        await FirestoreService.saveJob(job);
        print('☁️ Job ${job.title} synced to Firebase');
      }
    } catch (e) {
      print('❌ Error saving job: $e');
      rethrow;
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
  
  // PRICE BOOK SYNC METHODS
  
  /// Load price book with cloud-first approach and local fallback
  static Future<List<pb.PriceBookItem>> loadPriceBook() async {
    try {
      // Try cloud first if authenticated
      if (isReady) {
        final cloudItems = await FirestoreService.getPriceBookItems(limit: 500);
        if (cloudItems.isNotEmpty) {
          final pbItems = cloudItems.map((item) => pb.PriceBookItem.fromJson(item.toJson())).toList();
          // Save to local as backup
          await _savePriceBookToLocal(pbItems);
          print('✅ Loaded ${pbItems.length} price book items from Firebase');
          return pbItems;
        }
      }
      
      // Fallback to local storage
      final localItems = await _loadPriceBookFromLocal();
      
      // If we have local data and are authenticated, sync to cloud
      if (localItems.isNotEmpty && isReady) {
        await syncPriceBookToCloud(localItems);
      }
      
      print('📱 Loaded ${localItems.length} price book items from local storage');
      return localItems;
    } catch (e) {
      print('❌ Error loading price book: $e');
      return _createSamplePriceBook();
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
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(jsonString);
          final jobs = jsonList.map((e) => Job.fromJson(e)).toList();
          // Sync invoices for loaded jobs
          for (final job in jobs) {
            job.syncInvoices();
          }
          return jobs;
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
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('❌ Error saving jobs to local: $e');
    }
  }
  
  static Future<void> _saveJobToLocal(Job job) async {
    try {
      final jobs = await _loadJobsFromLocal();
      final index = jobs.indexWhere((j) => j.id == job.id);
      if (index >= 0) {
        jobs[index] = job;
      } else {
        jobs.add(job);
      }
      await _saveJobsToLocal(jobs);
    } catch (e) {
      print('❌ Error saving job to local: $e');
    }
  }
  
  static Future<List<pb.PriceBookItem>> _loadPriceBookFromLocal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final decoded = jsonDecode(jsonString);
          final List<dynamic> jsonList;
          if (decoded is Map<String, dynamic> && decoded.containsKey('items')) {
            jsonList = decoded['items'] as List<dynamic>;
          } else if (decoded is List<dynamic>) {
            jsonList = decoded;
          } else {
            throw Exception('Unexpected pricebook JSON structure');
          }
          return jsonList.map((e) => pb.PriceBookItem.fromJson(e)).toList();
        }
      }
    } catch (e) {
      print('❌ Error loading price book from local: $e');
    }
    return _createSamplePriceBook();
  }
  
  static Future<void> _savePriceBookToLocal(List<pb.PriceBookItem> items) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      final jsonList = items.map((item) => item.toJson()).toList();
      final data = {
        'items': jsonList,
        'lastSaved': DateTime.now().toIso8601String(),
        'version': 1,
        'totalItems': jsonList.length,
      };
      await file.writeAsString(jsonEncode(data));
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
