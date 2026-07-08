/// HYBRID PRICE BOOK IMPLEMENTATION GUIDE
/// 
/// This system provides:
/// ✅ UNLIMITED price book items
/// ✅ Local storage for offline use
/// ✅ Change tracking for sync-only updates
/// ✅ Memory-efficient pagination
/// ✅ Cloud backup support (future)
/// 
/// KEY ADVANTAGES:
/// - No size limits (store 100K+ items)
/// - Works completely offline
/// - Only changes are synced (minimal bandwidth)
/// - Instant search across all items
/// - Memory efficient with pagination
/// 
/// USAGE EXAMPLES:
/// 
/// 1. LOAD ALL ITEMS (with pagination):
/// ```dart
/// // Load first 100 items
/// final items = await HybridPriceBookService.loadAllItems(limit: 100, offset: 0);
/// 
/// // Load next 100 items
/// final moreItems = await HybridPriceBookService.loadAllItems(limit: 100, offset: 100);
/// 
/// // Get total count
/// final total = await HybridPriceBookService.getTotalItemCount();
/// ```
/// 
/// 2. SEARCH (instant, searches all items):
/// ```dart
/// final results = await HybridPriceBookService.search('cable', limit: 50);
/// ```
/// 
/// 3. SAVE SINGLE ITEM:
/// ```dart
/// final item = PriceBookItem(
///   code: 'CABLE-1',
///   name: 'Electrical Cable',
///   ...
/// );
/// await HybridPriceBookService.saveItem(item);
/// ```
/// 
/// 4. SAVE BATCH (optimized for many items):
/// ```dart
/// await HybridPriceBookService.saveBatch(importedItems);
/// ```
/// 
/// 5. SYNC STATUS (check what changed):
/// ```dart
/// final status = await HybridPriceBookService.getSyncStatus();
/// print('${status['changedItemsCount']} items changed');
/// print('${status['totalItems']} total items');
/// ```
/// 
/// 6. GET ONLY CHANGED ITEMS (for cloud sync):
/// ```dart
/// final changed = await HybridPriceBookService.getChangedItems();
/// // Send 'changed' to cloud
/// // Then call markSynced() when done
/// await HybridPriceBookService.markSynced();
/// ```
/// 
/// 7. EXPORT/IMPORT (for backup/cloud):
/// ```dart
/// // Export to JSON
/// final json = await HybridPriceBookService.exportToJson();
/// 
/// // Import from JSON
/// await HybridPriceBookService.importFromJson(json);
/// ```
/// 
/// 8. MEMORY USAGE:
/// ```dart
/// final usage = await HybridPriceBookService.getMemoryUsage();
/// print('Price book uses: $usage');
/// ```
/// 
/// FEATURES:
/// 
/// ✅ UNLIMITED ITEMS
///    - No size limit on price book
///    - Stores entire list locally on device
///    - Typical device can hold 100,000+ items
/// 
/// ✅ OFFLINE FIRST
///    - All data available without internet
///    - Perfect for field workers
///    - Search works instantly
/// 
/// ✅ CHANGE TRACKING
///    - Only tracks changed items
///    - Minimal cloud sync bandwidth
///    - Automatic tracking on save/delete
/// 
/// ✅ PAGINATION
///    - Load items in batches
///    - Memory efficient UI
///    - Works with large lists
/// 
/// ✅ FUTURE CLOUD SUPPORT
///    - Export to JSON for cloud backup
///    - Merge cloud items without losing local changes
///    - Track which items changed for sync

class HybridPriceBookGuide {}
