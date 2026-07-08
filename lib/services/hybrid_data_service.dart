import '../services/pricebook_service.dart';
import '../services/customer_service.dart';
import '../models/price_book_item.dart';
import '../models/customer.dart';

/// Simple integration helper for hybrid storage
/// Always saves locally first, syncs to cloud when possible
class HybridDataService {
  
  // ========================================
  // PRICEBOOK OPERATIONS
  // ========================================
  
  /// Load pricebook items (local first, cloud fallback)
  static Future<List<PriceBookItem>> loadPriceBook() async {
    return await PriceBookService.loadPriceBook();
  }
  
  /// Save pricebook items (local immediately, cloud in background)
  static Future<void> savePriceBook(List<PriceBookItem> items) async {
    await PriceBookService.savePriceBook(items);
  }
  
  /// Force sync pricebook to cloud (manual sync)
  static Future<bool> syncPriceBookToCloud(List<PriceBookItem> items) async {
    return await PriceBookService.forceSyncToCloud(items);
  }
  
  /// Get pricebook sync status
  static Map<String, dynamic> getPriceBookSyncStatus() {
    return PriceBookService.getSyncStatus();
  }
  
  // ========================================
  // CUSTOMER OPERATIONS  
  // ========================================
  
  /// Load customers (local first, cloud fallback)
  static Future<List<Customer>> loadCustomers() async {
    return await CustomerService.loadCustomers();
  }
  
  /// Save customers (local immediately, cloud in background) 
  static Future<void> saveCustomers(List<Customer> customers) async {
    await CustomerService.saveCustomers(customers);
  }
  
  /// Force sync customers to cloud (manual sync)
  static Future<bool> syncCustomersToCloud(List<Customer> customers) async {
    return await CustomerService.forceSyncToCloud(customers);
  }
  
  /// Get customers sync status
  static Map<String, dynamic> getCustomersSyncStatus() {
    return CustomerService.getSyncStatus();
  }
  
  // ========================================
  // COMBINED OPERATIONS
  // ========================================
  
  /// Get overall sync status for all data types
  static Map<String, dynamic> getOverallSyncStatus() {
    final priceBookStatus = getPriceBookSyncStatus();
    final customersStatus = getCustomersSyncStatus();
    
    return {
      'priceBook': priceBookStatus,
      'customers': customersStatus,
      'isAuthenticated': priceBookStatus['isAuthenticated'],
      'hasLocalData': priceBookStatus['hasLocalData'] || customersStatus['hasLocalData'],
      'totalItems': (priceBookStatus['itemCount'] as int) + (customersStatus['itemCount'] as int),
    };
  }
  
  /// Force sync all data to cloud
  static Future<Map<String, bool>> syncAllToCloud({
    required List<PriceBookItem> priceBookItems,
    required List<Customer> customers,
  }) async {
    
    print('🔄 Starting full data sync to cloud...');
    
    final results = <String, bool>{};
    
    // Sync pricebook
    try {
      results['priceBook'] = await syncPriceBookToCloud(priceBookItems);
      print('${(results['priceBook'] == true) ? '✅' : '❌'} Pricebook sync completed');
    } catch (e) {
      results['priceBook'] = false;
      print('❌ Pricebook sync failed: $e');
    }
    
    // Sync customers
    try {
      results['customers'] = await syncCustomersToCloud(customers);
      print('${(results['customers'] == true) ? '✅' : '❌'} Customers sync completed');
    } catch (e) {
      results['customers'] = false;
      print('❌ Customers sync failed: $e');
    }
    
    final successCount = results.values.where((v) => v).length;
    print('🎯 Sync completed: $successCount/${results.length} successful');
    
    return results;
  }
  
  /// Quick status check - useful for UI indicators
  static String getQuickSyncStatus() {
    final status = getOverallSyncStatus();
    
    if (!status['isAuthenticated']) {
      return 'Offline (Not signed in)';
    }
    
    if (!status['hasLocalData']) {
      return 'No data';
    }
    
    return 'Ready (${status['totalItems']} items)';
  }
}