import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/price_book_item.dart';

/// Hybrid Price Book Service
/// - Stores unlimited items locally
/// - Syncs only changes to cloud (if needed in future)
/// - Supports offline-first with cloud backup
class HybridPriceBookService {
  static const String _localFileName = 'price_book_full.json';
  static const String _syncMetaFileName = 'price_book_sync_meta.json';
  
  static Map<String, dynamic> _syncMeta = {
    'lastSyncTime': null,
    'totalItems': 0,
    'version': 1,
    'changedItems': <String>[], // Track only changed item IDs
  };

  /// Load ALL price book items (with pagination support)
  static Future<List<PriceBookItem>> loadAllItems({
    int? limit,
    int offset = 0,
  }) async {
    try {
      final allItems = await _loadFromDisk();
      
      if (limit != null) {
        return allItems.skip(offset).take(limit).toList();
      }
      return allItems;
    } catch (e) {
      print('Error loading price book: $e');
      return [];
    }
  }

  /// Get total count without loading all items
  static Future<int> getTotalItemCount() async {
    try {
      final meta = await _loadSyncMeta();
      return meta['totalItems'] ?? 0;
    } catch (e) {
      print('Error getting item count: $e');
      return 0;
    }
  }

  /// Search items (supports unlimited items)
  static Future<List<PriceBookItem>> search(String query, {int limit = 50}) async {
    try {
      final allItems = await _loadFromDisk();
      final lowerQuery = query.toLowerCase();
      
      return allItems
          .where((item) =>
              item.name.toLowerCase().contains(lowerQuery) ||
              item.code.toLowerCase().contains(lowerQuery) ||
              (item.groupCode?.toLowerCase().contains(lowerQuery) ?? false))
          .take(limit)
          .toList();
    } catch (e) {
      print('Error searching price book: $e');
      return [];
    }
  }

  /// Save single item with change tracking
  static Future<void> saveItem(PriceBookItem item) async {
    try {
      final allItems = await _loadFromDisk();
      final index = allItems.indexWhere((i) => i.code == item.code);
      
      if (index >= 0) {
        allItems[index] = item;
        _trackChange(item.code);
      } else {
        allItems.add(item);
        _trackChange(item.code);
      }
      
      await _saveToDisk(allItems);
    } catch (e) {
      print('Error saving item: $e');
      rethrow;
    }
  }

  /// Save batch of items (optimized for large datasets)
  static Future<void> saveBatch(List<PriceBookItem> items) async {
    try {
      final allItems = await _loadFromDisk();
      
      for (final item in items) {
        final index = allItems.indexWhere((i) => i.code == item.code);
        if (index >= 0) {
          allItems[index] = item;
        } else {
          allItems.add(item);
        }
        _trackChange(item.code);
      }
      
      await _saveToDisk(allItems);
    } catch (e) {
      print('Error saving batch: $e');
      rethrow;
    }
  }

  /// Delete item
  static Future<void> deleteItem(String code) async {
    try {
      final allItems = await _loadFromDisk();
      allItems.removeWhere((i) => i.code == code);
      _trackChange(code, isDelete: true);
      
      await _saveToDisk(allItems);
    } catch (e) {
      print('Error deleting item: $e');
      rethrow;
    }
  }

  /// Get only changed items since last sync (for cloud backup)
  static Future<List<PriceBookItem>> getChangedItems() async {
    try {
      final meta = await _loadSyncMeta();
      final changedCodes = (meta['changedItems'] as List?)?.cast<String>() ?? [];
      
      if (changedCodes.isEmpty) return [];
      
      final allItems = await _loadFromDisk();
      return allItems
          .where((item) => changedCodes.contains(item.code))
          .toList();
    } catch (e) {
      print('Error getting changed items: $e');
      return [];
    }
  }

  /// Mark all changes as synced
  static Future<void> markSynced() async {
    try {
      await _loadSyncMeta(); // Ensure we have latest
      _syncMeta['lastSyncTime'] = DateTime.now().toIso8601String();
      _syncMeta['changedItems'] = <String>[];
      await _saveSyncMeta();
      print('✅ Price book marked as synced');
    } catch (e) {
      print('Error marking as synced: $e');
    }
  }

  /// Get sync status
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final meta = await _loadSyncMeta();
      final changedItems = (meta['changedItems'] as List?)?.cast<String>() ?? [];
      
      return {
        'totalItems': meta['totalItems'] ?? 0,
        'changedItemsCount': changedItems.length,
        'lastSyncTime': meta['lastSyncTime'],
        'needsSync': changedItems.isNotEmpty,
        'changedItems': changedItems,
      };
    } catch (e) {
      print('Error getting sync status: $e');
      return {'needsSync': false, 'totalItems': 0};
    }
  }

  /// Merge cloud items with local (keeping local changes)
  static Future<void> mergeWithCloud(List<PriceBookItem> cloudItems) async {
    try {
      final localItems = await _loadFromDisk();
      final meta = await _loadSyncMeta();
      final changedCodes = (meta['changedItems'] as List?)?.cast<String>() ?? [];
      
      // Update items from cloud, but keep local changes
      for (final cloudItem in cloudItems) {
        if (!changedCodes.contains(cloudItem.code)) {
          final index = localItems.indexWhere((i) => i.code == cloudItem.code);
          if (index >= 0) {
            localItems[index] = cloudItem;
          } else {
            localItems.add(cloudItem);
          }
        }
      }
      
      await _saveToDisk(localItems);
      print('✅ Merged ${cloudItems.length} cloud items with local storage');
    } catch (e) {
      print('Error merging with cloud: $e');
    }
  }

  // ============ PRIVATE METHODS ============

  static void _trackChange(String code, {bool isDelete = false}) {
    final changedItems = (_syncMeta['changedItems'] as List<dynamic>).cast<String>();
    if (!changedItems.contains(code)) {
      changedItems.add(code);
    }
  }

  static Future<List<PriceBookItem>> _loadFromDisk() async {
    try {
      final file = await _getFile();
      
      if (!await file.exists()) {
        return [];
      }

      final contents = await file.readAsString();
      if (contents.isEmpty) return [];
      
      final jsonData = jsonDecode(contents);
      final List<dynamic> itemsList = jsonData is Map 
          ? (jsonData['items'] as List?) ?? [] 
          : (jsonData as List?) ?? [];
      
      return itemsList
          .map((json) => PriceBookItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading from disk: $e');
      return [];
    }
  }

  static Future<void> _saveToDisk(List<PriceBookItem> items) async {
    try {
      final file = await _getFile();
      final dir = file.parent;
      
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final data = {
        'items': items.map((item) => item.toJson()).toList(),
        'lastModified': DateTime.now().toIso8601String(),
        'version': 1,
        'totalItems': items.length,
      };

      await file.writeAsString(jsonEncode(data), flush: true);
      _syncMeta['totalItems'] = items.length;
      await _saveSyncMeta();
      
      print('✅ Saved ${items.length} items to local storage');
    } catch (e) {
      print('Error saving to disk: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _loadSyncMeta() async {
    try {
      final file = await _getSyncMetaFile();
      
      if (!await file.exists()) {
        _syncMeta = {
          'lastSyncTime': null,
          'totalItems': 0,
          'version': 1,
          'changedItems': <String>[],
        };
        return _syncMeta;
      }

      final contents = await file.readAsString();
      if (contents.isEmpty) {
        _syncMeta = {
          'lastSyncTime': null,
          'totalItems': 0,
          'version': 1,
          'changedItems': <String>[],
        };
        return _syncMeta;
      }
      
      _syncMeta = jsonDecode(contents) as Map<String, dynamic>;
      // Ensure changedItems is a list
      if (_syncMeta['changedItems'] == null) {
        _syncMeta['changedItems'] = <String>[];
      }
      return _syncMeta;
    } catch (e) {
      print('Error loading sync meta: $e');
      _syncMeta = {
        'lastSyncTime': null,
        'totalItems': 0,
        'version': 1,
        'changedItems': <String>[],
      };
      return _syncMeta;
    }
  }

  static Future<void> _saveSyncMeta() async {
    try {
      final file = await _getSyncMetaFile();
      await file.writeAsString(jsonEncode(_syncMeta), flush: true);
    } catch (e) {
      print('Error saving sync meta: $e');
    }
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_localFileName');
  }

  static Future<File> _getSyncMetaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_syncMetaFileName');
  }

  /// Export to JSON (for backup/cloud)
  static Future<String> exportToJson() async {
    try {
      final items = await _loadFromDisk();
      return jsonEncode({
        'items': items.map((i) => i.toJson()).toList(),
        'exportedAt': DateTime.now().toIso8601String(),
        'itemCount': items.length,
      });
    } catch (e) {
      print('Error exporting: $e');
      return '';
    }
  }

  /// Import from JSON (from cloud/backup)
  static Future<void> importFromJson(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final itemsList = (data['items'] as List?) ?? [];
      
      final items = itemsList
          .map((json) => PriceBookItem.fromJson(json as Map<String, dynamic>))
          .toList();
      
      await saveBatch(items);
      print('✅ Imported ${items.length} items from JSON');
    } catch (e) {
      print('Error importing: $e');
      rethrow;
    }
  }

  /// Get memory usage estimate
  static Future<String> getMemoryUsage() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return 'Empty';
      
      final sizeInBytes = await file.length();
      final sizeInMB = sizeInBytes / (1024 * 1024);
      
      return '${sizeInMB.toStringAsFixed(2)} MB (${sizeInBytes ~/ 1024} KB)';
    } catch (e) {
      return 'Unknown';
    }
  }
}
