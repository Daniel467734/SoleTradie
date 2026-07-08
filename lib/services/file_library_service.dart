import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class FileLibraryItem {
  final String id;
  String name;
  String filePath;
  int usageCount;
  DateTime lastUsed;

  FileLibraryItem({
    required this.id,
    required this.name,
    required this.filePath,
    this.usageCount = 0,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'usageCount': usageCount,
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory FileLibraryItem.fromJson(Map<String, dynamic> json) => FileLibraryItem(
    id: json['id'],
    name: json['name'],
    filePath: json['filePath'],
    usageCount: json['usageCount'] ?? 0,
    lastUsed: DateTime.parse(json['lastUsed'] ?? DateTime.now().toIso8601String()),
  );
}

class FileLibraryService {
  static const String _libraryFileName = 'file_library.json';
  static List<FileLibraryItem> _cache = [];
  static bool _cacheLoaded = false;

  /// Get the library directory path
  static Future<Directory> _getLibraryDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final libDir = Directory('${appDir.path}/file_library');
    if (!await libDir.exists()) {
      await libDir.create(recursive: true);
    }
    return libDir;
  }

  /// Get the metadata file path
  static Future<File> _getMetadataFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/$_libraryFileName');
  }

  /// Load all library items from metadata
  static Future<void> _loadMetadata() async {
    if (_cacheLoaded) return;

    try {
      final metadataFile = await _getMetadataFile();
      if (await metadataFile.exists()) {
        final jsonString = await metadataFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _cache = jsonList.map((item) => FileLibraryItem.fromJson(item)).toList();
      }
    } catch (e) {
      print('Error loading file library metadata: $e');
      _cache = [];
    }
    _cacheLoaded = true;
  }

  /// Save metadata to file
  static Future<void> _saveMetadata() async {
    try {
      final metadataFile = await _getMetadataFile();
      final jsonList = _cache.map((item) => item.toJson()).toList();
      await metadataFile.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error saving file library metadata: $e');
    }
  }

  /// Add a file to the library
  static Future<FileLibraryItem?> addFile(File sourceFile, String? customName) async {
    await _loadMetadata();

    try {
      final libDir = await _getLibraryDirectory();
      final fileName = customName ?? sourceFile.path.split('/').last;
      final safeName = _sanitizeFileName(fileName);
      final destination = File('${libDir.path}/$safeName');

      // Check if file already exists
      if (await destination.exists()) {
        // Update usage count instead of creating duplicate
        final existingItem = _cache.firstWhere(
          (item) => item.filePath == destination.path,
          orElse: () => FileLibraryItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: safeName,
            filePath: destination.path,
          ),
        );
        existingItem.usageCount++;
        existingItem.lastUsed = DateTime.now();
        await _saveMetadata();
        return existingItem;
      }

      // Copy file to library
      final copiedFile = await sourceFile.copy(destination.path);

      // Create library item
      final item = FileLibraryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: safeName,
        filePath: copiedFile.path,
        usageCount: 1,
      );

      _cache.add(item);
      await _saveMetadata();
      return item;
    } catch (e) {
      print('Error adding file to library: $e');
      return null;
    }
  }

  /// Get all library items sorted by usage
  static Future<List<FileLibraryItem>> getAllItems() async {
    await _loadMetadata();
    final items = _cache.toList();
    // Sort by usage count (descending), then by last used date (descending)
    items.sort((a, b) {
      final usageCompare = b.usageCount.compareTo(a.usageCount);
      if (usageCompare != 0) return usageCompare;
      return b.lastUsed.compareTo(a.lastUsed);
    });
    return items;
  }

  /// Search library items
  static Future<List<FileLibraryItem>> searchItems(String query) async {
    await _loadMetadata();
    if (query.trim().isEmpty) {
      return getAllItems();
    }

    final searchLower = query.toLowerCase();
    final results = _cache.where((item) {
      return item.name.toLowerCase().contains(searchLower);
    }).toList();

    // Sort by usage
    results.sort((a, b) {
      final usageCompare = b.usageCount.compareTo(a.usageCount);
      if (usageCompare != 0) return usageCompare;
      return b.lastUsed.compareTo(a.lastUsed);
    });

    return results;
  }

  /// Mark a file as used (increment usage count)
  static Future<void> markAsUsed(FileLibraryItem item) async {
    await _loadMetadata();
    final existingItem = _cache.firstWhere(
      (i) => i.id == item.id,
      orElse: () => item,
    );
    existingItem.usageCount++;
    existingItem.lastUsed = DateTime.now();
    await _saveMetadata();
  }

  /// Delete a file from library
  static Future<void> deleteItem(FileLibraryItem item) async {
    await _loadMetadata();
    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      _cache.removeWhere((i) => i.id == item.id);
      await _saveMetadata();
    } catch (e) {
      print('Error deleting file from library: $e');
    }
  }

  /// Rename a file in library
  static Future<bool> renameItem(FileLibraryItem item, String newName) async {
    await _loadMetadata();
    try {
      final safeName = _sanitizeFileName(newName);
      final oldFile = File(item.filePath);
      final newPath = '${oldFile.parent.path}/$safeName';

      if (await oldFile.exists()) {
        await oldFile.rename(newPath);
      }

      item.name = safeName;
      item.filePath = newPath;
      await _saveMetadata();
      return true;
    } catch (e) {
      print('Error renaming file in library: $e');
      return false;
    }
  }

  /// Get file size in a human-readable format
  static String getFileSize(FileLibraryItem item) {
    try {
      final file = File(item.filePath);
      if (!file.existsSync()) return 'Unknown';

      final bytes = file.lengthSync();
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Sanitize filename
  static String _sanitizeFileName(String fileName) {
    var name = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return name.replaceAll(RegExp(r'\s+'), '_');
  }

  /// Clear cache (for testing)
  static void clearCache() {
    _cache.clear();
    _cacheLoaded = false;
  }
}
