import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/firestore_service.dart';
import '../models/customer.dart';

/// Simple hybrid customer service - always local first, cloud when available
class CustomerService {
  static const String _fileName = 'customers.json';
  static List<Customer>? _cache;
  
  /// Load all customers - local first, then cloud if empty
  static Future<List<Customer>> loadCustomers() async {
    try {
      print('👥 Loading customers - local first approach');
      
      // Always try local first
      final localItems = await _loadFromLocal();
      if (localItems.isNotEmpty) {
        _cache = localItems;
        print('✅ Loaded ${localItems.length} customers from local storage');
        
        // Try to sync from cloud in background (non-blocking)
        _backgroundSync().catchError((e) {
          print('Background sync failed: $e');
        });
        
        return localItems;
      }
      
      // Only if local is empty, try cloud
      if (FirestoreService.isAuthenticated) {
        print('📡 No local customers, trying cloud...');
        final cloudItems = await FirestoreService.getCustomers();
        if (cloudItems.isNotEmpty) {
          print('☁️ Loaded ${cloudItems.length} customers from cloud');
          await _saveToLocal(cloudItems);
          _cache = cloudItems;
          return cloudItems;
        }
      }
      
      // Return empty list if nothing found
      _cache = [];
      print('📝 No customers found, starting with empty list');
      return [];
      
    } catch (e) {
      print('❌ Error loading customers: $e');
      return _cache ?? [];
    }
  }
  
  /// Save customers locally (always) and to cloud (when possible)
  static Future<void> saveCustomers(List<Customer> customers) async {
    try {
      print('💾 Saving ${customers.length} customers...');
      
      // ALWAYS save locally first (essential)
      await _saveToLocal(customers);
      _cache = customers;
      print('✅ Saved to local storage');
      
      // Try to save to cloud (non-blocking)
      if (FirestoreService.isAuthenticated) {
        _saveToCloudBackground(customers).catchError((e) {
          print('Cloud save failed (will retry later): $e');
        });
      } else {
        print('👤 Not authenticated - skipping cloud save');
      }
      
    } catch (e) {
      print('❌ Error saving customers: $e');
      rethrow;
    }
  }
  
  /// Force sync to cloud (manual sync button)
  static Future<bool> forceSyncToCloud(List<Customer> customers) async {
    if (!FirestoreService.isAuthenticated) {
      print('❌ Cannot sync - not authenticated');
      return false;
    }
    
    try {
      print('🔄 Force syncing ${customers.length} customers to cloud...');
      await FirestoreService.batchSaveCustomers(customers);
      print('✅ Successfully synced to cloud');
      return true;
    } catch (e) {
      print('❌ Force sync failed: $e');
      return false;
    }
  }
  
  /// Get current sync status
  static Map<String, dynamic> getSyncStatus() {
    return {
      'hasLocalData': _cache != null && _cache!.isNotEmpty,
      'itemCount': _cache?.length ?? 0,
      'isAuthenticated': FirestoreService.isAuthenticated,
      'canSync': FirestoreService.isAuthenticated,
    };
  }
  
  // --- PRIVATE METHODS ---
  
  static Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }
  
  static Future<List<Customer>> _loadFromLocal() async {
    try {
      final file = File(await _filePath);
      if (!await file.exists()) return [];
      
      final jsonString = await file.readAsString();
      if (jsonString.trim().isEmpty) return [];
      
      final jsonData = jsonDecode(jsonString);
      final List<dynamic> itemsList;
      
      // Handle both old format (direct list) and new format (with metadata)
      if (jsonData is Map && jsonData.containsKey('customers')) {
        itemsList = jsonData['customers'] as List<dynamic>;
      } else {
        itemsList = jsonData as List<dynamic>;
      }
      
      return itemsList.map((json) => Customer.fromJson(json)).toList();
    } catch (e) {
      print('Error loading customers from local: $e');
      return [];
    }
  }
  
  static Future<void> _saveToLocal(List<Customer> customers) async {
    try {
      final file = File(await _filePath);
      
      // Create enhanced format with metadata
      final data = {
        'customers': customers.map((customer) => customer.toJson()).toList(),
        'lastSaved': DateTime.now().toIso8601String(),
        'version': 1,
        'totalCustomers': customers.length,
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print('Error saving customers to local: $e');
      rethrow;
    }
  }
  
  static Future<void> _backgroundSync() async {
    // Non-blocking background sync from cloud
    if (!FirestoreService.isAuthenticated) return;
    
    try {
      final cloudItems = await FirestoreService.getCustomers();
      if (cloudItems.isNotEmpty && cloudItems.length != (_cache?.length ?? 0)) {
        await _saveToLocal(cloudItems);
        _cache = cloudItems;
        print('🔄 Background sync completed: ${cloudItems.length} customers');
      }
    } catch (e) {
      // Silent fail for background sync
      print('Background sync error: $e');
    }
  }
  
  static Future<void> _saveToCloudBackground(List<Customer> customers) async {
    // Non-blocking cloud save
    try {
      await FirestoreService.batchSaveCustomers(customers);
      print('☁️ Cloud save completed');
    } catch (e) {
      // Will retry later
      rethrow;
    }
  }
}