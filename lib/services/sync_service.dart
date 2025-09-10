import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sync_outbox.dart';

class SyncService {
  final Connectivity _connectivity;
  static const String _fileName = 'sync_queue.json';
  static List<SyncOutbox>? _cache;
  static int _nextId = 1;
  
  SyncService(this._connectivity);
  
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }
  
  Future<List<SyncOutbox>> _loadSyncQueue() async {
    if (_cache != null) return _cache!;
    
    try {
      final file = File(await _filePath);
      if (!await file.exists()) {
        _cache = [];
        return _cache!;
      }
      
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _cache = jsonList.map((json) => SyncOutbox.fromJson(json)).toList();
      
      // Update next ID
      if (_cache!.isNotEmpty) {
        _nextId = _cache!.map((item) => item.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
      }
      
      return _cache!;
    } catch (e) {
      print('Error loading sync queue: $e');
      _cache = [];
      return _cache!;
    }
  }
  
  Future<void> _saveSyncQueue() async {
    try {
      final file = File(await _filePath);
      final directory = await getApplicationDocumentsDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final jsonString = jsonEncode(_cache?.map((item) => item.toJson()).toList() ?? []);
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error saving sync queue: $e');
      rethrow;
    }
  }
  
  // Queue a sync operation to be processed when online
  Future<void> queueSync(SyncOutbox syncItem) async {
    final syncQueue = await _loadSyncQueue();
    syncItem.id = _nextId++;
    syncQueue.add(syncItem);
    await _saveSyncQueue();
    print('SyncService: Queued sync for ${syncItem.entityType}:${syncItem.entityId}');
  }
  
  // Process queued sync operations
  Future<void> processSyncQueue() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      print('No internet connection - skipping sync');
      return;
    }
    
    final syncQueue = await _loadSyncQueue();
    print('SyncService: Processing ${syncQueue.length} queued items');
    
    final items = List<SyncOutbox>.from(syncQueue);
    bool hasChanges = false;
    
    for (final item in items) {
      try {
        await _processSyncItem(item);
        // Remove from queue on success
        syncQueue.remove(item);
        hasChanges = true;
      } catch (e) {
        // Update retry count and error message
        item.retryCount++;
        item.lastAttempt = DateTime.now();
        item.errorMessage = e.toString();
        hasChanges = true;
        
        print('Failed to sync ${item.entityType}:${item.entityId}: $e');
        
        // Remove items with too many failed attempts
        if (item.retryCount > 5) {
          print('Removing item after ${item.retryCount} failed attempts');
          syncQueue.remove(item);
        }
      }
    }
    
    if (hasChanges) {
      await _saveSyncQueue();
    }
  }
  
  Future<void> _processSyncItem(SyncOutbox item) async {
    print('Processing sync: ${item.entityType} ${item.action.name} ${item.entityId}');
    
    // TODO: Implement actual cloud sync here
    // This would typically call your backend API
    switch (item.entityType) {
      case 'customer':
        await _syncCustomer(item);
        break;
      case 'price_book_item':
        await _syncPriceBookItem(item);
        break;
      case 'job':
        await _syncJob(item);
        break;
      default:
        throw Exception('Unknown entity type: ${item.entityType}');
    }
  }
  
  Future<void> _syncCustomer(SyncOutbox item) async {
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 200));
    
    // TODO: Replace with actual API calls
    switch (item.action) {
      case SyncAction.create:
        print('Would create customer ${item.entityId} on server');
        break;
      case SyncAction.update:
        print('Would update customer ${item.entityId} on server');
        break;
      case SyncAction.delete:
        print('Would delete customer ${item.entityId} on server');
        break;
    }
  }
  
  Future<void> _syncPriceBookItem(SyncOutbox item) async {
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 200));
    
    // TODO: Replace with actual API calls
    switch (item.action) {
      case SyncAction.create:
        print('Would create price book item ${item.entityId} on server');
        break;
      case SyncAction.update:
        print('Would update price book item ${item.entityId} on server');
        break;
      case SyncAction.delete:
        print('Would delete price book item ${item.entityId} on server');
        break;
    }
  }
  
  Future<void> _syncJob(SyncOutbox item) async {
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 200));
    
    // TODO: Replace with actual API calls
    switch (item.action) {
      case SyncAction.create:
        print('Would create job ${item.entityId} on server');
        break;
      case SyncAction.update:
        print('Would update job ${item.entityId} on server');
        break;
      case SyncAction.delete:
        print('Would delete job ${item.entityId} on server');
        break;
    }
  }
  
  // Get pending sync items count
  Future<int> getPendingSyncCount() async {
    final syncQueue = await _loadSyncQueue();
    return syncQueue.length;
  }
  
  // Clear all sync items (use with caution)
  Future<void> clearSyncQueue() async {
    _cache = [];
    await _saveSyncQueue();
  }
  
  // Clear cache to force reload
  static void clearCache() {
    _cache = null;
  }
}
