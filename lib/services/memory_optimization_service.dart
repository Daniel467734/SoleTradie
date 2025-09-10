import 'dart:io';
import 'package:flutter/services.dart';

/// Utility class to help manage memory and performance
class MemoryOptimizationService {
  static const int _maxItemsInMemory = 200;
  static const Duration _cacheTimeout = Duration(minutes: 10);
  
  static final Map<String, DateTime> _cacheTimestamps = {};
  static final Map<String, List<dynamic>> _cache = {};

  /// Suggest garbage collection if memory is getting high
  static void suggestGC() {
    try {
      // Force garbage collection on mobile platforms
      if (Platform.isAndroid || Platform.isIOS) {
        SystemChannels.platform.invokeMethod('SystemChrome.setApplicationSwitcherDescription', {
          'label': 'SoleTradie',
          'primaryColor': 0xFF2196F3,
        });
      }
    } catch (e) {
      print('GC suggestion failed: $e');
    }
  }

  /// Clear expired cache entries
  static void clearExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheTimeout)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      print('Cleared ${expiredKeys.length} expired cache entries');
    }
  }

  /// Check if cache is getting too large
  static bool isCacheOverLimit() {
    final totalItems = _cache.values
        .map((list) => list.length)
        .fold<int>(0, (sum, length) => sum + length);
    
    return totalItems > _maxItemsInMemory;
  }

  /// Clear oldest cache entries if over limit
  static void trimCacheIfNeeded() {
    if (!isCacheOverLimit()) return;

    // Sort by timestamp and remove oldest entries
    final sortedEntries = _cacheTimestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final toRemove = sortedEntries.take(sortedEntries.length ~/ 3).toList();
    
    for (final entry in toRemove) {
      _cache.remove(entry.key);
      _cacheTimestamps.remove(entry.key);
    }

    print('Trimmed ${toRemove.length} cache entries to manage memory');
    suggestGC();
  }

  /// Add items to cache with automatic cleanup
  static void addToCache(String key, List<dynamic> items) {
    clearExpiredCache();
    trimCacheIfNeeded();
    
    _cache[key] = items;
    _cacheTimestamps[key] = DateTime.now();
  }

  /// Get items from cache
  static List<dynamic>? getFromCache(String key) {
    clearExpiredCache();
    return _cache[key];
  }

  /// Clear all cache
  static void clearAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    suggestGC();
    print('All cache cleared');
  }

  /// Get memory usage summary for debugging
  static Map<String, dynamic> getMemorySummary() {
    final totalItems = _cache.values
        .map((list) => list.length)
        .fold<int>(0, (sum, length) => sum + length);

    return {
      'cacheEntries': _cache.length,
      'totalCachedItems': totalItems,
      'isOverLimit': isCacheOverLimit(),
      'oldestCacheAge': _cacheTimestamps.values.isEmpty
          ? 0
          : DateTime.now().difference(_cacheTimestamps.values
              .reduce((a, b) => a.isBefore(b) ? a : b)).inMinutes,
    };
  }

  /// Monitor and log memory status
  static void logMemoryStatus() {
    final summary = getMemorySummary();
    print('Memory Status: ${summary['totalCachedItems']} items cached, '
          '${summary['cacheEntries']} entries, '
          'over limit: ${summary['isOverLimit']}');
  }

  /// Perform maintenance (call periodically)
  static void performMaintenance() {
    clearExpiredCache();
    trimCacheIfNeeded();
    logMemoryStatus();
  }
}
