// Real persistence implementation for customers
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/sync_customer.dart';
import '../services/local_data_source.dart';

class CustomerLocalDataSource implements LocalDataSource<SyncCustomer> {
  static const String _fileName = 'customers.json';
  static List<SyncCustomer>? _cache;
  
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }
  
  Future<List<SyncCustomer>> _loadCustomers() async {
    if (_cache != null) return _cache!;
    
    try {
      final file = File(await _filePath);
      if (!await file.exists()) {
        _cache = [];
        return _cache!;
      }
      
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _cache = jsonList.map((json) => SyncCustomer.fromJson(json)).toList();
      return _cache!;
    } catch (e) {
      print('Error loading customers: $e');
      _cache = [];
      return _cache!;
    }
  }
  
  Future<void> _saveCustomers() async {
    try {
      final file = File(await _filePath);
      final directory = await getApplicationDocumentsDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final jsonString = jsonEncode(_cache?.map((c) => c.toJson()).toList() ?? []);
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error saving customers: $e');
      rethrow;
    }
  }
  
  @override
  Future<List<SyncCustomer>> getAll() async {
    final customers = await _loadCustomers();
    return customers.where((c) => !c.isDeleted).toList();
  }

  @override
  Future<SyncCustomer?> getById(String id) async {
    final customers = await _loadCustomers();
    try {
      return customers.firstWhere((c) => c.customerId == id && !c.isDeleted);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<SyncCustomer>> search(String query) async {
    final customers = await _loadCustomers();
    return customers.where((c) => 
        !c.isDeleted && 
        (c.name.toLowerCase().contains(query.toLowerCase()) ||
         (c.email?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
         (c.phone?.contains(query) ?? false))
    ).toList();
  }

  @override
  Future<void> insert(SyncCustomer item) async {
    final customers = await _loadCustomers();
    customers.add(item);
    await _saveCustomers();
  }

  @override
  Future<void> update(SyncCustomer item) async {
    final customers = await _loadCustomers();
    final index = customers.indexWhere((c) => c.customerId == item.customerId);
    if (index != -1) {
      item.updatedAt = DateTime.now();
      item.needsSync = true;
      customers[index] = item;
      await _saveCustomers();
    }
  }

  @override
  Future<void> delete(String id) async {
    final item = await getById(id);
    if (item != null) {
      item.isDeleted = true;
      item.needsSync = true;
      item.updatedAt = DateTime.now();
      await _saveCustomers();
    }
  }

  @override
  Future<List<SyncCustomer>> getPendingSync() async {
    final customers = await _loadCustomers();
    return customers.where((c) => c.needsSync).toList();
  }

  @override
  Future<void> markSynced(String id, String cloudId) async {
    final item = await getById(id);
    if (item != null) {
      item.needsSync = false;
      item.cloudId = cloudId;
      await _saveCustomers();
    }
  }

  Future<List<SyncCustomer>> getRemoteCustomers() async {
    final customers = await _loadCustomers();
    return customers.where((c) => c.isRemote && !c.isDeleted).toList();
  }

  Future<void> setRemote(String customerId, bool isRemote) async {
    final customer = await getById(customerId);
    if (customer != null) {
      customer.isRemote = isRemote;
      await update(customer);
    }
  }
  
  // Clear cache to force reload
  static void clearCache() {
    _cache = null;
  }
}
