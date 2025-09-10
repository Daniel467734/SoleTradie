import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Storage strategy options
enum StorageStrategy {
  allLocal,           // Everything cached locally
  hybridRecent,       // Recent items local, old items cloud-only
  hybridSmart,        // Frequently accessed local, others cloud-only
  cloudFirst,         // Minimal local cache, fetch from cloud
  custom,             // User-defined rules
}

/// Data type categories
enum DataType {
  customers,
  jobs,
  priceBook,
  documents,
  estimates,
  invoices,
  builds,           // For estimate/quote/invoice builds
  inProgressBuilds, // Specifically for in-progress builds
}

/// Service to manage what data is stored locally vs cloud-only
class StorageStrategyService {
  // Storage strategies for different data types
  static const String _customersStrategyKey = 'customers_storage_strategy';
  static const String _jobsStrategyKey = 'jobs_storage_strategy';
  static const String _priceBookStrategyKey = 'price_book_storage_strategy';
  static const String _documentsStrategyKey = 'documents_storage_strategy';
  static const String _buildsStrategyKey = 'builds_storage_strategy';
  static const String _inProgressBuildsStrategyKey = 'in_progress_builds_storage_strategy';

  /// Get current storage strategy for a data type
  static Future<StorageStrategy> getStrategy(DataType dataType) async {
    final prefs = await SharedPreferences.getInstance();
    final strategyName = prefs.getString(_getStrategyKey(dataType)) ?? 'hybridRecent';
    return StorageStrategy.values.firstWhere(
      (s) => s.name == strategyName,
      orElse: () => StorageStrategy.hybridRecent,
    );
  }

  /// Set storage strategy for a data type
  static Future<void> setStrategy(DataType dataType, StorageStrategy strategy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getStrategyKey(dataType), strategy.name);
    
    // Trigger data reorganization based on new strategy
    await _reorganizeData(dataType, strategy);
  }

  /// Get storage rules for an item based on strategy
  static Future<StorageRule> getStorageRule(DataType dataType, Map<String, dynamic> itemData) async {
    final strategy = await getStrategy(dataType);
    final now = DateTime.now();
    
    switch (strategy) {
      case StorageStrategy.allLocal:
        return StorageRule(keepLocal: true, syncToCloud: true, priority: StoragePriority.high);
        
      case StorageStrategy.hybridRecent:
        final itemDate = _parseItemDate(itemData);
        final daysSinceCreated = now.difference(itemDate).inDays;
        
        // Keep recent items (last 30 days) local
        if (daysSinceCreated <= 30) {
          return StorageRule(keepLocal: true, syncToCloud: true, priority: StoragePriority.high);
        }
        // Older items cloud-only but with metadata cached
        return StorageRule(keepLocal: false, syncToCloud: true, priority: StoragePriority.low, cacheMetadata: true);
        
      case StorageStrategy.hybridSmart:
        final accessCount = _getAccessCount(dataType, itemData['id'] ?? '');
        final lastAccessed = _getLastAccessed(dataType, itemData['id'] ?? '');
        final daysSinceAccessed = now.difference(lastAccessed).inDays;
        
        // Frequently accessed or recently accessed items stay local
        if (accessCount > 5 || daysSinceAccessed <= 7) {
          return StorageRule(keepLocal: true, syncToCloud: true, priority: StoragePriority.high);
        }
        return StorageRule(keepLocal: false, syncToCloud: true, priority: StoragePriority.medium, cacheMetadata: true);
        
      case StorageStrategy.cloudFirst:
        // Only essential metadata local
        return StorageRule(keepLocal: false, syncToCloud: true, priority: StoragePriority.low, cacheMetadata: true);
        
      case StorageStrategy.custom:
        return await _getCustomStorageRule(dataType, itemData);
    }
  }

  /// Storage rule configuration
  static Future<Map<String, dynamic>> getStorageConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('storage_configuration') ?? '{}';
    return jsonDecode(configJson);
  }

  /// Update storage configuration
  static Future<void> updateStorageConfiguration(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_configuration', jsonEncode(config));
  }

  /// Get data size limits
  static Future<DataSizeLimits> getDataSizeLimits() async {
    final prefs = await SharedPreferences.getInstance();
    return DataSizeLimits(
      maxLocalCustomers: prefs.getInt('max_local_customers') ?? 200,
      maxLocalJobs: prefs.getInt('max_local_jobs') ?? 100,
      maxLocalPriceBookItems: prefs.getInt('max_local_price_book') ?? 500,
      maxLocalDocuments: prefs.getInt('max_local_documents') ?? 50,
      maxLocalBuilds: prefs.getInt('max_local_builds') ?? 100,
      maxLocalInProgressBuilds: prefs.getInt('max_local_in_progress_builds') ?? 50,
    );
  }

  /// Update data size limits
  static Future<void> updateDataSizeLimits(DataSizeLimits limits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_local_customers', limits.maxLocalCustomers);
    await prefs.setInt('max_local_jobs', limits.maxLocalJobs);
    await prefs.setInt('max_local_price_book', limits.maxLocalPriceBookItems);
    await prefs.setInt('max_local_documents', limits.maxLocalDocuments);
    await prefs.setInt('max_local_builds', limits.maxLocalBuilds);
    await prefs.setInt('max_local_in_progress_builds', limits.maxLocalInProgressBuilds);
  }

  // Private helper methods
  static String _getStrategyKey(DataType dataType) {
    switch (dataType) {
      case DataType.customers: return _customersStrategyKey;
      case DataType.jobs: return _jobsStrategyKey;
      case DataType.priceBook: return _priceBookStrategyKey;
      case DataType.documents: return _documentsStrategyKey;
      case DataType.builds: return _buildsStrategyKey;
      case DataType.inProgressBuilds: return _inProgressBuildsStrategyKey;
      default: return '${dataType.name}_storage_strategy';
    }
  }

  static DateTime _parseItemDate(Map<String, dynamic> data) {
    final createdAt = data['created'] ?? data['dateCreated'] ?? data['createdAt'];
    if (createdAt is String) {
      return DateTime.tryParse(createdAt) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static int _getAccessCount(DataType dataType, String itemId) {
    // This would be tracked in your analytics/usage tracking
    // For now, return a default value
    return 0;
  }

  static DateTime _getLastAccessed(DataType dataType, String itemId) {
    // This would be tracked in your analytics/usage tracking
    // For now, return current time
    return DateTime.now();
  }

  static Future<StorageRule> _getCustomStorageRule(DataType dataType, Map<String, dynamic> itemData) async {
    // Apply custom rules logic here based on configuration
    return StorageRule(keepLocal: true, syncToCloud: true, priority: StoragePriority.medium);
  }

  static Future<void> _reorganizeData(DataType dataType, StorageStrategy strategy) async {
    // Trigger data reorganization based on new strategy
    // This would coordinate with your repository layers
    print('Reorganizing $dataType data for strategy: $strategy');
  }
}

/// Rule for how a specific item should be stored
class StorageRule {
  final bool keepLocal;
  final bool syncToCloud;
  final StoragePriority priority;
  final bool cacheMetadata;

  StorageRule({
    required this.keepLocal,
    required this.syncToCloud,
    required this.priority,
    this.cacheMetadata = false,
  });
}

/// Priority levels for storage
enum StoragePriority {
  high,    // Always keep local, sync immediately
  medium,  // Keep local when space available, sync when online
  low,     // Cloud-only unless specifically requested
}

/// Data size limits configuration
class DataSizeLimits {
  final int maxLocalCustomers;
  final int maxLocalJobs;
  final int maxLocalPriceBookItems;
  final int maxLocalDocuments;
  final int maxLocalBuilds;
  final int maxLocalInProgressBuilds;

  DataSizeLimits({
    required this.maxLocalCustomers,
    required this.maxLocalJobs,
    required this.maxLocalPriceBookItems,
    required this.maxLocalDocuments,
    required this.maxLocalBuilds,
    required this.maxLocalInProgressBuilds,
  });
}
