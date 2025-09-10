import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
// Using mock implementations - Isar replaced with regular Dart classes
import '../services/customer_local_data_source.dart';
import '../services/sync_service_impl.dart'; // Use the implementation version
import '../models/sync_outbox.dart'; // Re-enabled with Isar
import '../models/price_book_item.dart'; // Now using mock implementation
import '../models/sync_customer.dart'; // Now using mock implementation  
// Now using mock implementation
import '../services/local_data_source.dart';
import '../services/remote_data_source.dart';

abstract class Repository<T> {
  Future<List<T>> getAll();
  Future<T?> getById(String id);
  Future<List<T>> search(String query);
  Future<void> save(T item);
  Future<void> delete(String id);
  Stream<List<T>> watch();
  Future<void> sync();
}

class PriceBookRepository implements Repository<PriceBookItem> {
  final LocalDataSource<PriceBookItem> _localDataSource;
  final RemoteDataSource<PriceBookItem> _remoteDataSource;
  final SyncService? _syncService;

  PriceBookRepository(this._localDataSource, this._remoteDataSource, this._syncService);

  @override
  Future<List<PriceBookItem>> getAll() async {
    return await _localDataSource.getAll();
  }

  @override
  Future<PriceBookItem?> getById(String id) async {
    return await _localDataSource.getById(id);
  }

  @override
  Future<List<PriceBookItem>> search(String query) async {
    return await _localDataSource.search(query);
  }

  @override
  Future<void> save(PriceBookItem item) async {
    await _localDataSource.insert(item);
    
    await _syncService?.queueSync(
      SyncOutbox.forSync(
        entityType: 'pricebook',
        entityId: item.code,
        action: SyncAction.create,
        data: jsonEncode(item.toJson()),
      ),
    );
    
    // Try immediate sync if online
    if (await _isOnline()) {
      await sync();
    }
  }

  @override
  Future<void> delete(String id) async {
    await _localDataSource.delete(id);
    
    await _syncService?.queueSync(
      SyncOutbox.forSync(
        entityType: 'pricebook',
        entityId: id,
        action: SyncAction.delete,
        data: '{}',
      ),
    );
    
    // Try immediate sync if online
    if (await _isOnline()) {
      await sync();
    }
  }

  @override
  Stream<List<PriceBookItem>> watch() {
    // In a real implementation, you'd combine local changes with remote streams
    return _remoteDataSource.watchChanges();
  }

  @override
  Future<void> sync() async {
    if (!await _isOnline()) return;
    
    // Pull changes from remote
    try {
      final remoteItems = await _remoteDataSource.getAll();
      for (final item in remoteItems) {
        await _localDataSource.insert(item);
      }
    } catch (e) {
      print('Error pulling pricebook changes: $e');
    }
    
    // Push local changes
    final pendingItems = await _localDataSource.getPendingSync();
    for (final item in pendingItems) {
      try {
        if (item.cloudId == null) {
          // Create new
          final cloudId = await _remoteDataSource.create(item);
          await _localDataSource.markSynced(item.code, cloudId);
        } else if (item.isDeleted) {
          // Delete
          await _remoteDataSource.delete(item.cloudId!);
          await _localDataSource.markSynced(item.code, item.cloudId!);
        } else {
          // Update
          await _remoteDataSource.update(item.cloudId!, item);
          await _localDataSource.markSynced(item.code, item.cloudId!);
        }
      } catch (e) {
        print('Error syncing pricebook item ${item.code}: $e');
      }
    }
  }

  Future<bool> _isOnline() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
}

class CustomerRepository implements Repository<SyncCustomer> {
  final LocalDataSource<SyncCustomer> _localDataSource;
  final RemoteDataSource<SyncCustomer> _remoteDataSource;
  final SyncService? _syncService;

  CustomerRepository(this._localDataSource, this._remoteDataSource, this._syncService);

  @override
  Future<List<SyncCustomer>> getAll() async {
    return await _localDataSource.getAll();
  }

  @override
  Future<SyncCustomer?> getById(String id) async {
    return await _localDataSource.getById(id);
  }

  @override
  Future<List<SyncCustomer>> search(String query) async {
    return await _localDataSource.search(query);
  }

  @override
  Future<void> save(SyncCustomer item) async {
    await _localDataSource.insert(item);
    
    await _syncService?.queueSync(
      SyncOutbox.forSync(
        entityType: 'customer',
        entityId: item.customerId,
        action: SyncAction.create,
        data: jsonEncode(item.toJson()),
      ),
    );
    
    // Try immediate sync if online
    if (await _isOnline()) {
      await sync();
    }
  }

  @override
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
    
    // Try immediate sync if online
    if (await _isOnline()) {
      await sync();
    }
  }

  @override
  Stream<List<SyncCustomer>> watch() {
    return _remoteDataSource.watchChanges();
  }

  @override
  Future<void> sync() async {
    if (!await _isOnline()) return;
    
    // Pull changes from remote
    try {
      final remoteItems = await _remoteDataSource.getAll();
      for (final item in remoteItems) {
        await _localDataSource.insert(item);
      }
    } catch (e) {
      print('Error pulling customer changes: $e');
    }
    
    // Push local changes
    final pendingItems = await _localDataSource.getPendingSync();
    for (final item in pendingItems) {
      try {
        if (item.cloudId == null) {
          // Create new
          final cloudId = await _remoteDataSource.create(item);
          await _localDataSource.markSynced(item.customerId, cloudId);
        } else if (item.isDeleted) {
          // Delete
          await _remoteDataSource.delete(item.cloudId!);
          await _localDataSource.markSynced(item.customerId, item.cloudId!);
        } else {
          // Update
          await _remoteDataSource.update(item.cloudId!, item);
          await _localDataSource.markSynced(item.customerId, item.cloudId!);
        }
      } catch (e) {
        print('Error syncing customer ${item.customerId}: $e');
      }
    }
  }

  Future<bool> _isOnline() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> setRemote(String customerId, bool isRemote) async {
    if (_localDataSource is CustomerLocalDataSource) {
      await _localDataSource.setRemote(customerId, isRemote);
    }
  }

  Future<List<SyncCustomer>> getRemoteCustomers() async {
    if (_localDataSource is CustomerLocalDataSource) {
      return _localDataSource.getRemoteCustomers();
    }
    return [];
  }
}
