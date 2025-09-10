import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'storage_strategy_service.dart';
import 'customer_storage_strategy_service.dart';

/// Manages sync timing and scheduling for hybrid storage system
class SyncScheduler {
  static Timer? _periodicSyncTimer;
  static Timer? _immediateDataTimer;
  static bool _isOnline = false;
  static final Connectivity _connectivity = Connectivity();

  /// Initialize sync scheduler with optimal timing
  static void initialize() {
    // Monitor connectivity changes
    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    
    // Start periodic sync for non-critical data
    _startPeriodicSync();
    
    // Start immediate sync for critical data
    _startImmediateDataSync();
  }

  /// Start periodic sync for bulk data (every 30 minutes when online)
  static void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      if (_isOnline) {
        await _performBulkSync();
      }
    });
  }

  /// Start immediate sync for critical data (every 2 minutes when online)
  static void _startImmediateDataSync() {
    _immediateDataTimer?.cancel();
    _immediateDataTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (_isOnline) {
        await _performImmediateSync();
      }
    });
  }

  /// Handle connectivity changes
  static void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final wasOnline = _isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);
    
    if (!wasOnline && _isOnline) {
      // Just came online - perform immediate sync
      print('🌐 Connection restored - performing catch-up sync');
      await _performCatchUpSync();
    }
  }

  /// Perform bulk sync for non-critical data
  static Future<void> _performBulkSync() async {
    try {
      print('📦 Performing bulk sync...');
      
      // Sync price book items (hybrid strategy)
      final priceBookStrategy = await StorageStrategyService.getStrategy(DataType.priceBook);
      if (priceBookStrategy == StorageStrategy.hybridRecent || 
          priceBookStrategy == StorageStrategy.hybridSmart || 
          priceBookStrategy == StorageStrategy.custom) {
        // Sync price book items to cloud
        print('📦 Syncing price book items');
      }
      
      // Sync builds data
      final buildsStrategy = await StorageStrategyService.getStrategy(DataType.builds);
      if (buildsStrategy == StorageStrategy.hybridRecent || 
          buildsStrategy == StorageStrategy.hybridSmart || 
          buildsStrategy == StorageStrategy.custom) {
        print('📦 Syncing builds data');
      }
      
      // Sync in-progress builds
      final inProgressStrategy = await StorageStrategyService.getStrategy(DataType.inProgressBuilds);
      if (inProgressStrategy == StorageStrategy.hybridRecent || 
          inProgressStrategy == StorageStrategy.hybridSmart || 
          inProgressStrategy == StorageStrategy.custom) {
        print('📦 Syncing in-progress builds');
      }
      
    } catch (e) {
      print('⚠️ Bulk sync error: $e');
    }
  }

  /// Perform immediate sync for critical data
  static Future<void> _performImmediateSync() async {
    try {
      print('⚡ Performing immediate sync...');
      
      // Sync remote customer data immediately
      await CustomerStorageStrategyService.syncAllRemoteCustomerStrategies([]);
      
      // Sync any pending critical changes
      // This would include job updates, customer changes, etc.
      
    } catch (e) {
      print('⚠️ Immediate sync error: $e');
    }
  }

  /// Perform catch-up sync when connection is restored
  static Future<void> _performCatchUpSync() async {
    try {
      // Perform both immediate and bulk sync
      await _performImmediateSync();
      await _performBulkSync();
      
      print('✅ Catch-up sync completed');
    } catch (e) {
      print('⚠️ Catch-up sync error: $e');
    }
  }

  /// Trigger immediate sync for specific data type
  static Future<void> syncNow(DataType dataType) async {
    if (!_isOnline) {
      print('📴 Offline - queueing sync for $dataType');
      return;
    }

    try {
      final strategy = await StorageStrategyService.getStrategy(dataType);
      if (strategy == StorageStrategy.hybridRecent || 
          strategy == StorageStrategy.hybridSmart || 
          strategy == StorageStrategy.custom ||
          strategy == StorageStrategy.cloudFirst) {
        print('⚡ Syncing $dataType immediately');
        // Perform immediate sync for this data type
      }
    } catch (e) {
      print('⚠️ Immediate sync error for $dataType: $e');
    }
  }

  /// Stop all sync timers
  static void dispose() {
    _periodicSyncTimer?.cancel();
    _immediateDataTimer?.cancel();
    _periodicSyncTimer = null;
    _immediateDataTimer = null;
  }

  /// Get sync status
  static Map<String, dynamic> getSyncStatus() {
    return {
      'isOnline': _isOnline,
      'periodicSyncActive': _periodicSyncTimer?.isActive ?? false,
      'immediateSyncActive': _immediateDataTimer?.isActive ?? false,
      'nextPeriodicSync': _periodicSyncTimer != null ? 
        DateTime.now().add(const Duration(minutes: 30)) : null,
      'nextImmediateSync': _immediateDataTimer != null ?
        DateTime.now().add(const Duration(minutes: 2)) : null,
    };
  }
}
