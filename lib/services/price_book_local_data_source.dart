// Real persistence implementation for price book items
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/price_book_item.dart';
import '../services/local_data_source.dart';

class PriceBookLocalDataSource implements LocalDataSource<PriceBookItem> {
  static const String _fileName = 'price_book_items.json';
  static List<PriceBookItem>? _cache;
  
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }
  
  Future<List<PriceBookItem>> _loadItems() async {
    if (_cache != null) return _cache!;
    
    try {
      final file = File(await _filePath);
      if (!await file.exists()) {
        _cache = [];
        return _cache!;
      }
      
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _cache = jsonList.map((json) => PriceBookItem.fromJson(json)).toList();
      return _cache!;
    } catch (e) {
      print('Error loading price book items: $e');
      _cache = [];
      return _cache!;
    }
  }
  
  Future<void> _saveItems() async {
    try {
      final file = File(await _filePath);
      final directory = await getApplicationDocumentsDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final jsonString = jsonEncode(_cache?.map((item) => item.toJson()).toList() ?? []);
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error saving price book items: $e');
      rethrow;
    }
  }
  
  @override
  Future<List<PriceBookItem>> getAll() async {
    final items = await _loadItems();
    return items.where((item) => !item.isDeleted).toList();
  }

  @override
  Future<PriceBookItem?> getById(String id) async {
    final items = await _loadItems();
    try {
      return items.firstWhere((item) => item.code == id && !item.isDeleted);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<PriceBookItem>> search(String query) async {
    final items = await _loadItems();
    return items.where((item) => 
        !item.isDeleted && 
        (item.name.toLowerCase().contains(query.toLowerCase()) ||
         item.code.toLowerCase().contains(query.toLowerCase()) ||
         (item.category?.toLowerCase().contains(query.toLowerCase()) ?? false))
    ).toList();
  }

  @override
  Future<void> insert(PriceBookItem item) async {
    final items = await _loadItems();
    items.add(item);
    await _saveItems();
  }

  @override
  Future<void> update(PriceBookItem item) async {
    final items = await _loadItems();
    final index = items.indexWhere((i) => i.code == item.code);
    if (index != -1) {
      item.updatedAt = DateTime.now();
      item.needsSync = true;
      items[index] = item;
      await _saveItems();
    }
  }

  @override
  Future<void> delete(String id) async {
    final item = await getById(id);
    if (item != null) {
      item.isDeleted = true;
      item.needsSync = true;
      item.updatedAt = DateTime.now();
      await _saveItems();
    }
  }

  @override
  Future<List<PriceBookItem>> getPendingSync() async {
    final items = await _loadItems();
    return items.where((item) => item.needsSync).toList();
  }

  @override
  Future<void> markSynced(String id, String cloudId) async {
    final item = await getById(id);
    if (item != null) {
      item.needsSync = false;
      item.cloudId = cloudId;
      await _saveItems();
    }
  }
  
  // Clear cache to force reload
  static void clearCache() {
    _cache = null;
  }
}
