import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/firestore_service.dart';
import '../models/price_book_item.dart';

/// Simple hybrid pricebook service - always local first, cloud when available
class PriceBookService {
  static const String _fileName = 'price_book.json';
  static List<PriceBookItem>? _cache;
  
  /// Load all pricebook items - local first, then cloud if empty
  static Future<List<PriceBookItem>> loadPriceBook() async {
    try {
      print('📚 Loading pricebook - local first approach');
      
      // Always try local first
      final localItems = await _loadFromLocal();
      if (localItems.isNotEmpty) {
        _cache = localItems;
        print('✅ Loaded ${localItems.length} items from local storage');
        
        // Try to sync from cloud in background (non-blocking)
        _backgroundSync().catchError((e) {
          print('Background sync failed: $e');
        });
        
        return localItems;
      }
      
      // Only if local is empty, try cloud
      if (FirestoreService.isAuthenticated) {
        print('📡 No local items, trying cloud...');
        final cloudItems = await FirestoreService.getPriceBookItems();
        if (cloudItems.isNotEmpty) {
          print('☁️ Loaded ${cloudItems.length} items from cloud');
          await _saveToLocal(cloudItems);
          _cache = cloudItems;
          return cloudItems;
        }
      }
      
      // Create sample items if nothing found
      final sampleItems = _createSampleItems();
      await _saveToLocal(sampleItems);
      _cache = sampleItems;
      print('🔧 Created ${sampleItems.length} sample items');
      return sampleItems;
      
    } catch (e) {
      print('❌ Error loading pricebook: $e');
      return _cache ?? [];
    }
  }
  
  /// Save pricebook locally (always) and to cloud (when possible)
  static Future<void> savePriceBook(List<PriceBookItem> items) async {
    try {
      print('💾 Saving ${items.length} pricebook items...');
      
      // ALWAYS save locally first (essential)
      await _saveToLocal(items);
      _cache = items;
      print('✅ Saved to local storage');
      
      // Try to save to cloud (non-blocking)
      if (FirestoreService.isAuthenticated) {
        _saveToCloudBackground(items).catchError((e) {
          print('Cloud save failed (will retry later): $e');
        });
      } else {
        print('👤 Not authenticated - skipping cloud save');
      }
      
    } catch (e) {
      print('❌ Error saving pricebook: $e');
      rethrow;
    }
  }
  
  /// Force sync to cloud (manual sync button)
  static Future<bool> forceSyncToCloud(List<PriceBookItem> items) async {
    if (!FirestoreService.isAuthenticated) {
      print('❌ Cannot sync - not authenticated');
      return false;
    }
    
    try {
      print('🔄 Force syncing ${items.length} items to cloud...');
      await FirestoreService.batchSavePriceBookItems(items);
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
  
  static Future<List<PriceBookItem>> _loadFromLocal() async {
    try {
      final file = File(await _filePath);
      if (!await file.exists()) return [];
      
      final jsonString = await file.readAsString();
      if (jsonString.trim().isEmpty) return [];
      
      final jsonData = jsonDecode(jsonString);
      final List<dynamic> itemsList;
      
      // Handle both old format (direct list) and new format (with metadata)
      if (jsonData is Map && jsonData.containsKey('items')) {
        itemsList = jsonData['items'] as List<dynamic>;
      } else {
        itemsList = jsonData as List<dynamic>;
      }
      
      return itemsList.map((json) => PriceBookItem.fromJson(json)).toList();
    } catch (e) {
      print('Error loading from local: $e');
      return [];
    }
  }
  
  static Future<void> _saveToLocal(List<PriceBookItem> items) async {
    try {
      final file = File(await _filePath);
      
      // Create enhanced format with metadata
      final data = {
        'items': items.map((item) => item.toJson()).toList(),
        'lastSaved': DateTime.now().toIso8601String(),
        'version': 1,
        'totalItems': items.length,
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print('Error saving to local: $e');
      rethrow;
    }
  }
  
  static Future<void> _backgroundSync() async {
    // Non-blocking background sync from cloud
    if (!FirestoreService.isAuthenticated) return;
    
    try {
      final cloudItems = await FirestoreService.getPriceBookItems();
      if (cloudItems.isNotEmpty && cloudItems.length != (_cache?.length ?? 0)) {
        await _saveToLocal(cloudItems);
        _cache = cloudItems;
        print('🔄 Background sync completed: ${cloudItems.length} items');
      }
    } catch (e) {
      // Silent fail for background sync
      print('Background sync error: $e');
    }
  }
  
  static Future<void> _saveToCloudBackground(List<PriceBookItem> items) async {
    // Non-blocking cloud save
    try {
      await FirestoreService.batchSavePriceBookItems(items);
      print('☁️ Cloud save completed');
    } catch (e) {
      // Don't rethrow - this is background sync, should be silent
      print('Cloud save failed silently: $e');
    }
  }
  
  static List<PriceBookItem> _createSampleItems() {
    // Return empty list - let the app handle sample data creation
    return [];
  }
}