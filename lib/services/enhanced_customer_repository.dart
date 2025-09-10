import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/sync_service_impl.dart';
import '../models/sync_customer.dart';
import '../models/sync_outbox.dart';
import '../services/local_data_source.dart';
import '../services/remote_data_source.dart';
import '../services/storage_strategy_service.dart';

/// Enhanced customer repository with storage strategy integration
class EnhancedCustomerRepository {
  final LocalDataSource<SyncCustomer> _localDataSource;
  final RemoteDataSource<SyncCustomer> _remoteDataSource;
  final SyncService? _syncService;

  EnhancedCustomerRepository(
    this._localDataSource,
    this._remoteDataSource,
    this._syncService,
  );

  /// Get all customers based on storage strategy
  Future<List<SyncCustomer>> getAll() async {
    final strategy = await StorageStrategyService.getStrategy(DataType.customers);
    
    switch (strategy) {
      case StorageStrategy.allLocal:
        // Return all local customers, sync from cloud if needed
        await _ensureLocalDataComplete();
        return await _localDataSource.getAll();
        
      case StorageStrategy.hybridRecent:
        // Get local recent customers + metadata for older ones
        final localCustomers = await _localDataSource.getAll();
        final recentCustomers = _filterRecentCustomers(localCustomers);
        
        // Add metadata for older customers if connected
        if (await _isOnline()) {
          final olderCustomersMetadata = await _getOlderCustomersMetadata();
          return [...recentCustomers, ...olderCustomersMetadata];
        }
        return recentCustomers;
        
      case StorageStrategy.hybridSmart:
        // Get frequently accessed + recent customers
        return await _getSmartCustomers();
        
      case StorageStrategy.cloudFirst:
        // Minimal local cache, fetch from cloud
        if (await _isOnline()) {
          return await _getCloudCustomersWithCache();
        } else {
          // Return cached metadata only when offline
          return await _getCachedMetadata();
        }
        
      case StorageStrategy.custom:
        return await _getCustomStrategyCustomers();
    }
  }

  /// Get customer by ID with smart loading
  Future<SyncCustomer?> getById(String id) async {
    // First check local storage
    final localCustomer = await _localDataSource.getById(id);
    if (localCustomer != null && !localCustomer.isRemote) {
      return localCustomer;
    }

    // If not local or is marked remote, check storage strategy
    final strategy = await StorageStrategyService.getStrategy(DataType.customers);
    
    if (strategy == StorageStrategy.cloudFirst || (localCustomer?.isRemote ?? false)) {
      if (await _isOnline()) {
        // Fetch from cloud and optionally cache
        final cloudCustomer = await _remoteDataSource.getById(id);
        if (cloudCustomer != null) {
          final storageRule = await StorageStrategyService.getStorageRule(
            DataType.customers,
            cloudCustomer.toJson(),
          );
          
          if (storageRule.keepLocal) {
            await _localDataSource.insert(cloudCustomer);
          }
          return cloudCustomer;
        }
      }
    }

    return localCustomer;
  }

  /// Save customer with storage strategy consideration
  Future<void> save(SyncCustomer customer) async {
    // Determine storage rule for this customer
    final storageRule = await StorageStrategyService.getStorageRule(
      DataType.customers,
      customer.toJson(),
    );

    if (storageRule.keepLocal) {
      await _localDataSource.insert(customer);
    } else {
      // Mark as remote-only
      customer.isRemote = true;
      await _localDataSource.insert(customer); // Store metadata only
    }

    if (storageRule.syncToCloud) {
      await _syncService?.queueSync(
        SyncOutbox.forSync(
          entityType: 'customer',
          entityId: customer.customerId,
          action: SyncAction.create,
          data: jsonEncode(customer.toJson()),
        ),
      );

      // Immediate sync for high priority items
      if (storageRule.priority == StoragePriority.high && await _isOnline()) {
        await sync();
      }
    }
  }

  /// Delete customer
  Future<void> delete(String id) async {
    await _localDataSource.delete(id);
    
    await _syncService?.queueSync(
      SyncOutbox.forSync(
        entityType: 'customer',
        entityId: id,
        action: SyncAction.delete,
        data: '{}',
      ),
    );

    if (await _isOnline()) {
      await sync();
    }
  }

  /// Search customers with strategy awareness
  Future<List<SyncCustomer>> search(String query) async {
    final strategy = await StorageStrategyService.getStrategy(DataType.customers);
    
    // Search local customers first
    final localResults = await _localDataSource.search(query);
    
    // For cloud-first strategy, also search remote if online
    if ((strategy == StorageStrategy.cloudFirst || strategy == StorageStrategy.hybridSmart) 
        && await _isOnline()) {
      try {
        // This would require implementing search in your remote data source
        // For now, return local results
        return localResults;
      } catch (e) {
        print('Cloud search failed: $e');
        return localResults;
      }
    }
    
    return localResults;
  }

  /// Sync with storage strategy awareness
  Future<void> sync() async {
    if (!await _isOnline()) return;
    
    // Pull changes from remote based on strategy
    try {
      final remoteItems = await _remoteDataSource.getAll();
      
      for (final item in remoteItems) {
        final storageRule = await StorageStrategyService.getStorageRule(
          DataType.customers,
          item.toJson(),
        );
        
        if (storageRule.keepLocal) {
          await _localDataSource.insert(item);
        } else if (storageRule.cacheMetadata) {
          // Store metadata only
          item.isRemote = true;
          await _localDataSource.insert(item);
        }
      }
    } catch (e) {
      print('Error pulling customer changes: $e');
    }

    // Push local changes
    final pendingItems = await _localDataSource.getPendingSync();
    for (final item in pendingItems) {
      try {
        if (item.cloudId == null) {
          final cloudId = await _remoteDataSource.create(item);
          await _localDataSource.markSynced(item.customerId, cloudId);
        } else if (item.isDeleted) {
          await _remoteDataSource.delete(item.cloudId!);
          await _localDataSource.markSynced(item.customerId, item.cloudId!);
        } else {
          await _remoteDataSource.update(item.cloudId!, item);
          await _localDataSource.markSynced(item.customerId, item.cloudId!);
        }
      } catch (e) {
        print('Error syncing customer ${item.customerId}: $e');
      }
    }
  }

  /// Clean up local storage based on strategy and limits
  Future<void> cleanupLocalStorage() async {
    final limits = await StorageStrategyService.getDataSizeLimits();
    final allLocal = await _localDataSource.getAll();
    
    if (allLocal.length > limits.maxLocalCustomers) {
      final strategy = await StorageStrategyService.getStrategy(DataType.customers);
      
      // Sort by strategy-specific criteria
      final sortedCustomers = await _sortForCleanup(allLocal, strategy);
      
      // Keep only the limit amount and remove excess customers
      final toRemove = sortedCustomers.skip(limits.maxLocalCustomers).toList();
      
      // Remove excess customers (but keep metadata if needed)
      for (final customer in toRemove) {
        if (customer.cloudId != null) {
          // Convert to metadata-only
          customer.isRemote = true;
          await _localDataSource.update(customer);
        } else {
          // Ensure it's synced to cloud first
          if (await _isOnline()) {
            await sync();
          }
        }
      }
    }
  }

  // Private helper methods
  Future<bool> _isOnline() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> _ensureLocalDataComplete() async {
    if (await _isOnline()) {
      await sync();
    }
  }

  List<SyncCustomer> _filterRecentCustomers(List<SyncCustomer> customers) {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return customers.where((c) => c.createdAt.isAfter(thirtyDaysAgo)).toList();
  }

  Future<List<SyncCustomer>> _getOlderCustomersMetadata() async {
    // This would fetch metadata for older customers from cloud
    return [];
  }

  Future<List<SyncCustomer>> _getSmartCustomers() async {
    // This would implement smart caching based on usage patterns
    return await _localDataSource.getAll();
  }

  Future<List<SyncCustomer>> _getCloudCustomersWithCache() async {
    final cloudCustomers = await _remoteDataSource.getAll();
    
    // Cache essential ones locally
    final limits = await StorageStrategyService.getDataSizeLimits();
    final essentialCustomers = cloudCustomers.take(limits.maxLocalCustomers ~/ 4).toList();
    
    for (final customer in essentialCustomers) {
      await _localDataSource.insert(customer);
    }
    
    return cloudCustomers;
  }

  Future<List<SyncCustomer>> _getCachedMetadata() async {
    return await _localDataSource.getAll();
  }

  Future<List<SyncCustomer>> _getCustomStrategyCustomers() async {
    // Implement custom strategy logic
    return await _localDataSource.getAll();
  }

  Future<List<SyncCustomer>> _sortForCleanup(List<SyncCustomer> customers, StorageStrategy strategy) async {
    switch (strategy) {
      case StorageStrategy.hybridRecent:
        customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case StorageStrategy.hybridSmart:
        // Sort by access frequency (would need to implement tracking)
        customers.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      default:
        customers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return customers;
  }
}
