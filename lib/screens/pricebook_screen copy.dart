import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/firestore_service.dart';
import '../models/price_book_item.dart' as models;

class PriceBookScreen extends StatefulWidget {
  final List<PriceBookItem> priceBook;
  final void Function(List<PriceBookItem>)? onPriceBookUpdated; // <-- make nullable

  const PriceBookScreen({
    super.key,
    required this.priceBook,
    this.onPriceBookUpdated, // <-- not required anymore
  });

  @override
  _PriceBookScreenState createState() => _PriceBookScreenState();
}

class _PriceBookScreenState extends State<PriceBookScreen> {
  List<PriceBookItem> priceBook = [];
  String searchQuery = '';
  bool showFavoritesOnly = false;
  SortOption _selectedSort = SortOption.code;
  final TextEditingController _searchController = TextEditingController();
  bool _isBarcodeProcessing = false;
  bool _priceBookLoaded = false;
  String _selectedOrigin = "All";

  @override
  void initState() {
    super.initState();
    
    // ENSURE DATA AVAILABILITY: Always start with widget data immediately
    priceBook = List.from(widget.priceBook);
    _priceBookLoaded = true;
    
    print('🚀 PriceBook initialized with ${priceBook.length} items from widget');
    
    // Load from disk to get latest data (but don't block UI
    _loadPriceBookFromDisk().then((_) {
      _ensureHardcodedPriceBookItems();
      print('✅ PriceBook refresh completed - ${priceBook.length} items now available');
    }).catchError((e) {
      print('⚠️ Error refreshing pricebook from disk: $e');
      // UI still works with widget data
    });
  }

  /// Ensures hardcoded items (CAL, EST) are always present in the pricebook
  void _ensureHardcodedPriceBookItems() {
    try {
      final hardcodedItems = [
        PriceBookItem(
          code: 'CAL',
          name: 'Labour',
          unit: 'HR',
          groupCode: 'LABOUR',
          price: 90.0,
          purchasePrice: 0.0,
          favorite: false,
          markupPercent: 0,
          markupOverridden: false,
          origin: 'hardcoded',
          usageCount: 0,
          percentageChanged: 0,
          needsSync: false, // Hardcoded items don't need sync
        ),
        PriceBookItem(
          code: 'EST',
          name: 'Labour',
          unit: 'HR',
          groupCode: 'LABOUR',
          price: 90.0,
          purchasePrice: 0.0,
          favorite: false,
          markupPercent: 0,
          markupOverridden: false,
          origin: 'hardcoded',
          usageCount: 0,
          percentageChanged: 0,
          needsSync: false, // Hardcoded items don't need sync
        ),
      ];

      for (final hardcodedItem in hardcodedItems) {
        try {
          final existingIndex = priceBook.indexWhere((item) => item.code == hardcodedItem.code);
          if (existingIndex == -1) {
            // Item doesn't exist, add it
            setState(() {
              priceBook.add(hardcodedItem);
            });
          } else {
            // Item exists, update it but preserve usage count, percentageChanged, and allow editing
            final existing = priceBook[existingIndex];
            setState(() {
              priceBook[existingIndex] = hardcodedItem.copyWith(
                usageCount: existing.usageCount,
                percentageChanged: existing.percentageChanged,
                // Allow name and price to be editable but keep the code protected
                name: existing.name.isNotEmpty ? existing.name : hardcodedItem.name,
                price: existing.price > 0 ? existing.price : hardcodedItem.price,
                origin: 'hardcoded', // Always mark as hardcoded
                needsSync: false, // Hardcoded items don't need sync
              );
            });
          }
        } catch (e) {
          print('Error processing hardcoded item ${hardcodedItem.code}: $e');
        }
      }
    } catch (e) {
      print('Error in _ensureHardcodedPriceBookItems: $e');
    }
  }

  // ROBUST LOADING: Always prioritize local file, never lose data
  Future<void> _loadPriceBookFromDisk() async {
    try {
      print('🔄 Loading pricebook - prioritizing local file for reliability...');
      
      // ALWAYS load from local file first (most reliable)
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      List<PriceBookItem> localItems = [];
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          try {
            final List<dynamic> jsonList = jsonDecode(contents);
            
            // Load ALL items at once - no limits, no batching
            for (final json in jsonList) {
              try {
                final item = PriceBookItem.fromJson(json);
                localItems.add(item);
              } catch (e) {
                print('⚠️ Error parsing item: $e');
              }
            }
            
            print('📱 Loaded ${localItems.length} items from local file (full dataset)');
          } catch (e) {
            print('❌ Error parsing JSON from local file: $e');
          }
        }
      }
      
      // Use local items if available, otherwise use widget items
      if (localItems.isNotEmpty) {
        setState(() {
          priceBook = localItems;
        });
        print('✅ Using ${priceBook.length} items from local storage');
      } else if (widget.priceBook.isNotEmpty) {
        setState(() {
          priceBook = List.from(widget.priceBook);
        });
        print('✅ Using ${priceBook.length} items from widget (fallback)');
        // Save to local immediately so we have them next time
        await _saveToLocalFile();
      } else {
        print('⚠️ No pricebook data found anywhere, starting with empty list');
      }
      
      // NEVER automatically sync all items - only sync when explicitly requested
      print('✅ Pricebook loading completed - ${priceBook.length} items available');
      
    } catch (e) {
      print('❌ Error loading price book: $e');
      // Always ensure we have some data available
      if (priceBook.isEmpty && widget.priceBook.isNotEmpty) {
        setState(() {
          priceBook = List.from(widget.priceBook);
        });
        print('🔄 Fallback: Using widget pricebook (${priceBook.length} items)');
      }
    }
  }

  void _importCsv(String template) {
    if (template == 'ja') {
      importFromJaCsv();
    } else if (template == 'ja_favorites') {
      importFromJaFavorites();
    } else {
      importFromCsv();
    }
  }

  Future<void> importFromCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) return;

      // Show loading dialog for large imports
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading CSV file...'),
            ],
          ),
        ),
      );

      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      
      // No file size limit - load all items
      final rows = const CsvToListConverter().convert(csvString, eol: '\n');

      // Close loading dialog
      Navigator.pop(context);

      final header = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
      int codeIdx = header.indexOf('stock code');
      int nameIdx = header.indexOf('product desc line 1');
      int unitIdx = header.indexOf('unit of measure');
      int groupIdx = header.indexOf('product group code');
      int barcodeIdx = header.indexOf('barcode');
      int priceIdx = header.indexOf('price');
      int purchasePriceIdx = header.indexOf('purchase price');
      int favIdx = header.indexOf('favourite');

      List<PriceBookItem> imported = [];
      
      // Process all rows efficiently
      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          if (row.length <= priceIdx || row[codeIdx].toString().trim().isEmpty) continue;
          String code = row[codeIdx]?.toString() ?? '';
          // Rename if needed
          if (code.trim().toLowerCase() == 'labour cal') code = 'CAL';
          if (code.trim().toLowerCase() == 'labour est') code = 'EST';
          imported.add(
            PriceBookItem(
              code: code,
              name: row[nameIdx]?.toString() ?? '',
              unit: row[unitIdx]?.toString() ?? '',
              groupCode: row[groupIdx]?.toString() ?? '',
              barcode: row[barcodeIdx]?.toString() ?? '',
              price: double.tryParse(row[priceIdx]?.toString() ?? '') ?? 0.0,
              purchasePrice: double.tryParse(row[purchasePriceIdx]?.toString() ?? '') ?? 0.0,
              favorite: favIdx != -1 && (row[favIdx]?.toString().toLowerCase() == 'true'),
            ),
          );
        } catch (e) {
          print('Error processing row $i: $e');
          // Continue with other rows
        }
      }
      
      print('Successfully processed ${imported.length} items from CSV');
      
      setState(() {
        final existingItems = {for (var item in priceBook) item.code: item};

        // Build a new list, but keep all existing items not in the import
        final Map<String, PriceBookItem> updated = {
          for (var item in priceBook) item.code: item
        };

        for (final newItem in imported) {
          final existing = existingItems[newItem.code];
          if (existing != null) {
            // If markupOverridden, recalculate sale price using stored % and new buy price
            if (existing.markupOverridden) {
              final newBuy = newItem.purchasePrice;
              final percent = existing.markupPercent;
              final newSell = newBuy * (1 + percent / 100);
              updated[newItem.code] = PriceBookItem(
                code: existing.code,
                name: existing.name, // Always preserve name
                unit: newItem.unit,
                groupCode: newItem.groupCode,
                barcode: newItem.barcode,
                price: newSell,
                purchasePrice: newBuy,
                favorite: existing.favorite,
                markupPercent: percent,
                markupOverridden: true,
              );
            } else {
              // Not overridden: update buy/sell price from import, keep name
              updated[newItem.code] = PriceBookItem(
                code: existing.code,
                name: existing.name, // Always preserve name
                unit: newItem.unit,
                groupCode: newItem.groupCode,
                barcode: newItem.barcode,
                price: newItem.price,
                purchasePrice: newItem.purchasePrice,
                favorite: existing.favorite,
                markupPercent: newItem.markupPercent,
                markupOverridden: false,
              );
            }
          } else {
            // New item, just add it
            updated[newItem.code] = newItem;
          }
        }

        priceBook = updated.values.toList();
        // Mark all updated/imported items as modified so they sync to cloud
        for (final item in priceBook) {
          if (imported.any((importedItem) => importedItem.code == item.code)) {
            item.markAsModified();
          }
        }
      });
      await _savePriceBook();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully imported ${imported.length} items from CSV'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      print('Error importing CSV: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing CSV: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> importFromJaCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;

    // Show loading dialog for large imports
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading JA CSV file...'),
          ],
        ),
      ),
    );

    final file = File(result.files.single.path!);
    final csvString = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n').convert(csvString);

    // Close loading dialog
    Navigator.pop(context);

    // Column indices (0-based): A=0, B=1, C=2, D=3, E=4, F=5, G=6, ..., M=12
    const codeIdx = 0; // Stock code (A)
    const groupIdx = 2; // Group code (C)
    const barcodeIdx = 4; // Barcode (E)
    const unitIdx = 5; // Unit (F)
    const listPriceIdx = 6; // List price (G)
    const descIdx = 8; // Description (I)
    const altDescIdx = 1; // Alt Description (B)
    const buyPriceIdx = 12; // Price (M)

    // Group lines by stock code
    final Map<String, Map<String, dynamic>> items = {};

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final code = row[codeIdx]?.toString().trim();
      if (code == null || code.isEmpty) continue;

      final desc = row[descIdx]?.toString().trim() ?? '';
      final altDesc = row[altDescIdx]?.toString().trim() ?? '';
      final barcode = row[barcodeIdx]?.toString().trim() ?? '';
      final unit = row[unitIdx]?.toString().trim() ?? '';
      final groupCode = row[groupIdx]?.toString().trim() ?? '';
      final listPrice = double.tryParse(row[listPriceIdx]?.toString() ?? '') ?? 0.0;
      final buyPrice = double.tryParse(row[buyPriceIdx]?.toString() ?? '') ?? 0.0;

      // Combine I and B lines for name, I first then B
      if (!items.containsKey(code)) {
        items[code] = {
          'desc': '',
          'altDesc': '',
          'barcode': barcode,
          'unit': unit,
          'groupCode': groupCode,
          'listPrice': listPrice,
          'buyPrice': buyPrice,
        };
      }
      // If this row has a main description (I), set it
      if (desc.isNotEmpty) items[code]!['desc'] = desc;
      // If this row has an alt description (B), set it
      if (altDesc.isNotEmpty) items[code]!['altDesc'] = altDesc;
    }

    // Ask user for import name
    final originName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Name this Pricebook Import'),
        content: TextField(textCapitalization: TextCapitalization.sentences, 
          autofocus: true,
          decoration: InputDecoration(hintText: 'e.g. JA Russell 2025-08-22'),
          controller: TextEditingController(text: "JA Russell ${DateTime.now().toIso8601String().substring(0,10)}"),
          onSubmitted: (val) => Navigator.pop(context, val.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: Text('Cancel')),
          TextButton(onPressed: () {
            Navigator.pop(context, "JA Russell ${DateTime.now().toIso8601String().substring(0,10)}");
          }, child: Text('OK')),
        ],
      ),
    );
    if (originName == null || originName.isEmpty) return;

    // Build the list
    final imported = items.entries.map((e) {
      String code = e.key;
      if (code.trim().toLowerCase() == 'labour cal') code = 'CAL';
      if (code.trim().toLowerCase() == 'labour est') code = 'EST';
      final name = [
        e.value['desc'],
        e.value['altDesc']
      ].where((s) => s != null && s.toString().isNotEmpty).join(' ');
      return PriceBookItem(
        code: code,
        name: name,
        unit: e.value['unit'],
        groupCode: e.value['groupCode'],
        barcode: e.value['barcode'],
        price: e.value['listPrice'],
        purchasePrice: e.value['buyPrice'],
        favorite: false,
        origin: originName,
      );
    }).toList();

    setState(() {
      final existingItems = {for (var item in priceBook) item.code: item};
      final Map<String, PriceBookItem> updated = {};

      for (final newItem in imported) {
        final existing = existingItems[newItem.code];
        if (existing != null && existing.markupOverridden) {
          final newBuy = newItem.purchasePrice;
          final percent = existing.markupPercent;
          updated[newItem.code] = PriceBookItem(
            code: existing.code,
            name: existing.name,
            unit: newItem.unit,
            groupCode: newItem.groupCode,
            barcode: newItem.barcode,
            price: newBuy * (1 + percent / 100),
            purchasePrice: newBuy,
            favorite: existing.favorite,
            markupPercent: percent,
            markupOverridden: true,
            origin: newItem.origin,
            usageCount: existing.usageCount,
            percentageChanged: existing.percentageChanged,
          );
        } else if (existing != null) {
          updated[newItem.code] = PriceBookItem(
            code: existing.code,
            name: existing.name,
            unit: newItem.unit,
            groupCode: newItem.groupCode,
            barcode: newItem.barcode,
            price: newItem.price,
            purchasePrice: newItem.purchasePrice,
            favorite: existing.favorite,
            markupPercent: newItem.markupPercent,
            markupOverridden: false,
            origin: newItem.origin,
            usageCount: existing.usageCount,
            percentageChanged: newItem.percentageChanged,
          );
        } else {
          updated[newItem.code] = newItem;
        }
      }

      // Keep existing items that were not part of the import as-is
      for (final existing in priceBook) {
        if (!updated.containsKey(existing.code)) {
          updated[existing.code] = existing;
        }
      }

      priceBook = updated.values.toList();
      _priceBookLoaded = true;
      // Mark all items updated from the import as modified so they sync to cloud
      for (final item in priceBook) {
        if (imported.any((importedItem) => importedItem.code == item.code)) {
          item.markAsModified();
        }
      }
    });
    await _savePriceBook();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully imported ${imported.length} items from JA CSV'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> importFromJaFavorites() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Processing JA Favorites...'),
            ],
          ),
        ),
      );

      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      final rows = const CsvToListConverter(eol: '\n').convert(csvString);
      Navigator.pop(context);

      const codeIdx = 0; // Stock code (A)

      final Map<String, int> codeCounts = {};
      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          if (row.isEmpty || row.length <= codeIdx) continue;
          final rawCode = row[codeIdx]?.toString().trim() ?? '';
          if (rawCode.isEmpty) continue;
          final code = rawCode.toUpperCase();
          codeCounts[code] = (codeCounts[code] ?? 0) + 1;
        } catch (e) {
          print('⚠️ Error processing JA Favorites row $i: $e');
        }
      }

      if (codeCounts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid JA item codes found in the file.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final lookup = {for (var item in priceBook) item.code.toUpperCase(): item};
      int updatedItemCount = 0;
      int totalMatches = 0;
      int notFoundCount = 0;

      setState(() {
        for (final entry in codeCounts.entries) {
          final item = lookup[entry.key];
          if (item != null) {
            item.usageCount += entry.value;
            item.markAsModified();
            updatedItemCount += 1;
            totalMatches += entry.value;
          } else {
            notFoundCount += 1;
          }
        }
      });

      await _savePriceBook();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'JA Favorites updated $updatedItemCount items with $totalMatches matched rows' +
            (notFoundCount > 0 ? ' · $notFoundCount codes not found' : ''),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      print('Error importing JA Favorites: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing JA Favorites: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void sortByName() {
    setState(() {
      priceBook.sort((a, b) => a.name.compareTo(b.name));
    });
  }

  void sortByCode() {
    setState(() {
      priceBook.sort((a, b) => a.code.compareTo(b.code));
    });
  }

  void sortByPrice() {
    setState(() {
      priceBook.sort((a, b) => a.price.compareTo(b.price));
    });
  }

  void sortPriceBook() {
    setState(() {
      priceBook.sort((a, b) {
        switch (_selectedSort) {
          case SortOption.code:
            return a.code.compareTo(b.code);
          case SortOption.name:
            return a.name.compareTo(b.name);
          case SortOption.price:
            return a.price.compareTo(b.price);
          case SortOption.barcode:
            return (a.barcode ?? '').compareTo(b.barcode ?? '');
        }
      });
    });
  }

  // ROBUST LOCAL FILE SAVING - Always save to device immediately
  Future<void> _saveToLocalFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      final jsonList = priceBook.map((item) => item.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
      print('💾 Saved ${priceBook.length} items to local file: ${file.path}');
    } catch (e) {
      print('❌ Error saving to local file: $e');
      rethrow;
    }
  }

  // OPTIMIZED SAVE PROCESS - Local first, smart cloud sync
  Future<void> _savePriceBook() async {
    try {
      print('🔄 Starting optimized price book save...');
      
      // 1. ALWAYS save to local file first (essential for reliability)
      await _saveToLocalFile();
      
      // 2. Update parent widget immediately
      if (widget.onPriceBookUpdated != null) {
        widget.onPriceBookUpdated!(priceBook);
        print('📱 Updated parent widget with ${priceBook.length} items');
      }
      
      final unsyncedCount = priceBook.where((item) => item.hasBeenModified).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Saved ${priceBook.length} items locally! '
              '${unsyncedCount > 0 ? '($unsyncedCount changes waiting for manual cloud sync)' : '(All changes are saved locally)'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      // NOTE: Cloud sync is manual only to avoid large automatic uploads and reduce Firebase cost/latency.
      print('✅ Price book save completed successfully (local-only save).');
    } catch (e) {
      print('❌ Error saving price book: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to save price book: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// SMART CLOUD SYNC: Only sync items that have actually changed
  Future<void> _syncChangedItemsToFirestore() async {
    try {
      print('🔍 Starting smart cloud sync...');
      
      // Find ONLY items that need syncing (modified since last sync)
      final itemsToSync = priceBook.where((item) => item.hasBeenModified).toList();
      
      if (itemsToSync.isEmpty) {
        print('✅ No items need syncing - all up to date');
        return;
      }
      
      print('📤 Found ${itemsToSync.length} items that need syncing (out of ${priceBook.length} total)');
      
      // Safety check - don't sync massive amounts at once
      if (itemsToSync.length > 1000) {
        throw Exception('Too many items to sync (${itemsToSync.length}). Use Force Cloud Sync or reduce dataset size.');
      }
      
      // Convert screen PriceBookItem to models PriceBookItem for Firestore
      final items = itemsToSync.map((screenItem) => models.PriceBookItem(
        code: screenItem.code,
        name: screenItem.name,
        category: screenItem.groupCode,
        purchasePrice: screenItem.purchasePrice,
        salePrice: screenItem.price,
        unit: screenItem.unit,
        description: '',
      )).toList();
      
      print('🚀 Syncing ${items.length} changed items to Firestore...');
      await FirestoreService.batchSavePriceBookItems(items);
      
      // Mark items as synced (clear the modified flag)
      for (final item in itemsToSync) {
        item.markAsSynced(null);
      }
      
      print('✅ Successfully synced ${items.length} changed items to Firestore');
    } catch (e) {
      print('❌ Error in smart cloud sync: $e');
      rethrow;
    }
  }

  Future<void> _scanBarcodeAndSearch() async {
    if (_isBarcodeProcessing) return; // Prevent re-entry
    _isBarcodeProcessing = true;

    try {
      final scannedBarcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Scan Barcode')),
            body: MobileScanner(
              onDetect: (capture) {
                try {
                  final barcode = capture.barcodes.first.rawValue;
                  if (barcode != null && barcode.isNotEmpty) {
                    Navigator.pop(context, barcode);
                  }
                } catch (e) {
                  print('Barcode detection error: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Barcode error: $e')),
                  );
                }
              },
              errorBuilder: (context, error) {
                print('Scanner error: $error');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Scanner error: $error')),
                  );
                });
                return Center(child: Text('Scanner error: $error'));
              },
            ),
          ),
        ),
      );

      if (scannedBarcode != null && scannedBarcode.isNotEmpty) {
        setState(() {
          searchQuery = scannedBarcode;
          _searchController.text = scannedBarcode;
        });
      }
    } catch (e) {
      print('Barcode scan failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode scan failed: $e')),
      );
    } finally {
      _isBarcodeProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_priceBookLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final origins = [
      "All",
      ...{for (var item in priceBook) item.origin}
    ];

    final filtered = priceBook.where((item) {
      if (item.code == 'CAL' || item.code == 'EST') return true;
      if (_selectedOrigin != "All" && item.origin != _selectedOrigin) return false;
      if (showFavoritesOnly && !item.favorite) return false;
      if (searchQuery.isEmpty) return true;

      final searchWords = searchQuery.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final itemWords = ('${item.name} ${item.code} ${item.barcode ?? ''}')
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      return searchWords.every((word) => itemWords.any((itemWord) => itemWord.contains(word)));
    }).toList();

    filtered.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      if (a.usageCount != b.usageCount) return b.usageCount.compareTo(a.usageCount);
      switch (_selectedSort) {
        case SortOption.code:
          return a.code.compareTo(b.code);
        case SortOption.name:
          return a.name.compareTo(b.name);
        case SortOption.price:
          return a.price.compareTo(b.price);
        case SortOption.barcode:
          return (a.barcode ?? '').compareTo(b.barcode ?? '');
      }
    });

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, priceBook); // Return the updated list!
        return false; // Prevent default pop, since we already did it
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Price Book'),
          actions: [
            IconButton(
              icon: Icon(showFavoritesOnly ? Icons.star : Icons.star_border),
              tooltip: 'Show Favorites',
              onPressed: () => setState(() => showFavoritesOnly = !showFavoritesOnly),
            ),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: 'Save Price Book',
                  onPressed: () async {
                    print('📱 Manual save button pressed');
                    await _savePriceBook();
                  },
                ),
                // Show badge with number of items needing sync
                if (priceBook.where((item) => item.hasBeenModified).isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${priceBook.where((item) => item.hasBeenModified).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: 'Smart Cloud Sync',
                  onPressed: () async {
                    final itemsToSync = priceBook.where((item) => item.hasBeenModified).toList();
                    
                    if (itemsToSync.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ All items are already synced to cloud!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      return;
                    }
                    
                    // Show warning for large datasets only
                    if (itemsToSync.length > 200) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('⚡ Smart Cloud Sync'),
                          content: Text(
                            'Found ${itemsToSync.length} changed items to sync.\n\n'
                            'This will only sync items that have been modified (not all ${priceBook.length} items).\n\n'
                            'Continue with smart sync?'
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.blue),
                              child: Text('Smart Sync'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                    }
                    
                    try {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⚡ Smart syncing ${itemsToSync.length} changed items...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      
                      // Force sync by calling the smart sync method directly
                      await _syncChangedItemsToFirestore();
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Successfully synced ${itemsToSync.length} items to cloud!'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    } catch (e) {
                      print('Smart sync failed: $e');
                      if (mounted) {
                        String message = '❌ Smart sync failed';
                        if (e.toString().contains('RESOURCE_EXHAUSTED')) {
                          message = '❌ Smart sync failed: Firebase quota exceeded';
                        } else if (e.toString().contains('too large')) {
                          message = '❌ Dataset too large for sync';
                        }
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                ),
                // Show badge with number of items needing sync
                if (priceBook.where((item) => item.hasBeenModified).isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${priceBook.where((item) => item.hasBeenModified).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Import CSV',
              onPressed: () async {
                final template = await showDialog<String>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text('Select Template'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'ja'),
                        child: Text('JA Template'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'standard'),
                        child: Text('Standard Template'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'ja_favorites'),
                        child: Text('JA Favorites'),
                      ),
                    ],
                  ),
                );
                if (template != null) {
                  _importCsv(template);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Delete All',
              onPressed: () async {
                final firstConfirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete ALL Items?'),
                    content: const Text('Are you sure you want to delete ALL items in the price book? This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );
                if (firstConfirm == true) {
                  final secondConfirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Confirm Deletion'),
                      content: const Text('This is your last chance! Delete ALL items?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Yes, Delete Everything'),
                        ),
                      ],
                    ),
                  );
                  if (secondConfirm == true) {
                    setState(() {
                      priceBook.removeWhere((item) =>
                        item.code != 'CAL' && item.code != 'EST'
                      );
                    });
                    await _savePriceBook();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All items deleted from PriceBook!')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setState(() => searchQuery = val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan Barcode',
                    onPressed: _scanBarcodeAndSearch,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  DropdownButton<SortOption>(
                    value: _selectedSort,
                    items: [
                      const DropdownMenuItem(
                        value: SortOption.code,
                        child: Text('Sort by Code'),
                      ),
                      const DropdownMenuItem(
                        value: SortOption.name,
                        child: Text('Sort by Name'),
                      ),
                      const DropdownMenuItem(
                        value: SortOption.price,
                        child: Text('Sort by Price'),
                      ),
                      const DropdownMenuItem(
                        value: SortOption.barcode,
                        child: Text('Sort by Barcode'),
                      ),
                    ],
                    onChanged: (SortOption? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedSort = newValue;
                          sortPriceBook();
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedOrigin,
                      items: origins.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedOrigin = val);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty 
                ? const Center(child: Text('No items match your search criteria'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90), // <-- Add bottom padding for FAB
                    itemCount: filtered.length,
                    // Optimized for large lists - no artificial limits
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemBuilder: (context, index) {
                      if (index >= filtered.length) return const SizedBox.shrink();
                      
                      final item = filtered[index];
                      return ListTile(
                    leading: IconButton(
                      icon: Icon(
                        item.favorite ? Icons.star : Icons.star_border,
                        color: item.favorite ? Colors.amber : Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          item.favorite = !item.favorite;
                          item.markAsModified(); // Track change for sync
                        });
                      },
                    ),
                    title: Text(
                      '${item.name} - ${item.code}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    subtitle: Text(
                      'Unit: ${item.unit}  |  Group: ${item.groupCode}  |  Markup: ${item.purchasePrice > 0 ? ((item.price - item.purchasePrice) / item.purchasePrice * 100).toStringAsFixed(1) : '0'}%',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          icon: Icon(Icons.info_outline),
                          tooltip: 'Show Item Info',
                          onPressed: () {
                            bool percentOverride = item.percentageChanged != 0;
                            double percentValue = item.percentageChanged;

                            showDialog(
                              context: context,
                              builder: (context) => StatefulBuilder(
                                builder: (context, setState) => AlertDialog(
                                  title: const Text('Item Details'),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('${item.debugInfo()}Origin: ${item.origin}\n'),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Switch(
                                              value: percentOverride,
                                              onChanged: (val) {
                                                setState(() {
                                                  percentOverride = val;
                                                  if (!val) percentValue = 0;
                                                });
                                                if (!val) {
                                                  setState(() {
                                                    item.percentageChanged = 0;
                                                    item.markAsModified();
                                                  });
                                                }
                                              },
                                            ),
                                            const Expanded(
                                              child: Text('Keep % Changed'),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.info_outline, size: 20),
                                              tooltip: 'What does this do?',
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text('Percentage Changed'),
                                                    content: const Text(
                                                      'If this toggle is on, it means future pricebook updates will keep the same percentage you have set based off your purchase price.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context),
                                                        child: const Text('OK'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        if (percentOverride)
                                          Row(
                                            children: [
                                              const Text('Set %:'),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: SizedBox(
                                                  width: 60,
                                                  child: TextField(textCapitalization: TextCapitalization.sentences, 
                                                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                                                    controller: TextEditingController(text: percentValue.toStringAsFixed(1)),
                                                    onChanged: (val) {
                                                      final v = double.tryParse(val) ?? 0;
                                                      setState(() {
                                                        percentValue = v;
                                                        item.percentageChanged = v;
                                                        item.markAsModified();
                                                      });
                                                    },
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const Text('%'),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Close'),
                                    ),
                                    if (item.code != 'CAL' && item.code != 'EST')
                                      TextButton(
                                        onPressed: () async {
                                          setState(() {
                                            item.percentageChanged = percentOverride ? percentValue : 0;
                                            item.markAsModified();
                                          });
                                          await _savePriceBook();
                                          Navigator.of(context).pop();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Saved percentage changed for ${item.name}')),
                                          );
                                        },
                                        child: const Text('Save'),
                                      ),
                                  ],
                                ),
                              )
                              );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit Item',
                          onPressed: () async {
                            final nameController = TextEditingController(text: item.name);
                            final unitController = TextEditingController(text: item.unit);
                            final groupController = TextEditingController(text: item.groupCode);
                            final barcodeController = TextEditingController(text: item.barcode);
                            final priceController = TextEditingController(text: item.price.toString());
                            final purchasePriceController = TextEditingController(text: item.purchasePrice.toString());
                            final markupController = TextEditingController(
                              text: item.purchasePrice > 0
                                  ? ((item.price - item.purchasePrice) / item.purchasePrice * 100).toStringAsFixed(1)
                                  : '0',
                            );

                            void updateSellPrice() {
                              final buy = double.tryParse(purchasePriceController.text) ?? 0;
                              final percent = double.tryParse(markupController.text) ?? 0;
                              if (buy > 0) {
                                priceController.text = (buy * (1 + percent / 100)).toStringAsFixed(2);
                              }
                            }

                            final result = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Edit Item'),
                                content: SingleChildScrollView(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: () => FocusScope.of(context).unfocus(),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ID Code (read-only)
                                        TextFormField(textCapitalization: TextCapitalization.sentences, 
                                          initialValue: item.code,
                                          decoration: const InputDecoration(labelText: 'ID Code'),
                                          enabled: false,
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: purchasePriceController,
                                          decoration: const InputDecoration(labelText: 'Buy Price'),
                                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                                          onChanged: (val) => updateSellPrice(),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: markupController,
                                          decoration: const InputDecoration(labelText: 'Markup %'),
                                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                                          onChanged: (val) => updateSellPrice(),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: priceController,
                                          decoration: const InputDecoration(labelText: 'Sell Price'),
                                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: nameController,
                                          decoration: const InputDecoration(labelText: 'Name'),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: unitController,
                                          decoration: const InputDecoration(labelText: 'Unit'),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: groupController,
                                          decoration: const InputDecoration(labelText: 'Group Code'),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                        TextField(textCapitalization: TextCapitalization.sentences, 
                                          controller: barcodeController,
                                          decoration: const InputDecoration(labelText: 'Barcode'),
                                          onEditingComplete: () => FocusScope.of(context).unfocus(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );

                            if (result == true) {
                              print('Editing item: ${item.code}');
                              setState(() {
                                item.name = nameController.text.trim();
                                item.unit = unitController.text.trim();
                                item.groupCode = groupController.text.trim();
                                item.barcode = barcodeController.text.trim();
                                item.price = double.tryParse(priceController.text) ?? item.price;
                                item.purchasePrice = double.tryParse(purchasePriceController.text) ?? item.purchasePrice;
                                final newMarkup = double.tryParse(markupController.text) ?? 0;
                                final calculatedMarkup = item.purchasePrice > 0
                                    ? ((item.price - item.purchasePrice) / item.purchasePrice * 100)
                                    : 0;
                                item.markupPercent = newMarkup;
                                item.markupOverridden = (newMarkup.toStringAsFixed(2) != calculatedMarkup.toStringAsFixed(2));
                                item.markAsModified(); // Track change for sync
                              });
                              print('Saving after edit...');
                              await _savePriceBook();
                              print('Save completed after edit');
                            }
                          },
                        ),
                        // Only show delete icon if not a labour item
                        if (item.code != 'CAL' && item.code != 'EST')
                          IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () => _deleteItem(item),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final codeController = TextEditingController();
            final nameController = TextEditingController();
            final unitController = TextEditingController();
            final groupController = TextEditingController();
            final barcodeController = TextEditingController();
            final priceController = TextEditingController();
            final purchasePriceController = TextEditingController();
            final markupController = TextEditingController(text: '0');

            void updateSellPrice() {
              final buy = double.tryParse(purchasePriceController.text) ?? 0;
              final percent = double.tryParse(markupController.text) ?? 0;
              if (buy > 0) {
                priceController.text = (buy * (1 + percent / 100)).toStringAsFixed(2);
              }
            }

            final result = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Add PriceBook Item'),
                content: SingleChildScrollView(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: codeController,
                          decoration: const InputDecoration(labelText: 'ID Code'),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: purchasePriceController,
                          decoration: const InputDecoration(labelText: 'Buy Price'),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) => updateSellPrice(),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: markupController,
                          decoration: const InputDecoration(labelText: 'Markup %'),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) => updateSellPrice(),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: priceController,
                          decoration: const InputDecoration(labelText: 'Sell Price'),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: unitController,
                          decoration: const InputDecoration(labelText: 'Unit'),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: groupController,
                          decoration: const InputDecoration(labelText: 'Group Code'),
                        ),
                        TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: barcodeController,
                          decoration: const InputDecoration(labelText: 'Barcode'),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Add'),
                  ),
                ],
              ),
            );

            if (result == true) {
              print('Adding new item to pricebook...');
              setState(() {
                String code = codeController.text.trim();
                if (code.toLowerCase() == 'labour cal') code = 'CAL';
                if (code.toLowerCase() == 'labour est') code = 'EST';
                final buy = double.tryParse(purchasePriceController.text) ?? 0;
                final sell = double.tryParse(priceController.text) ?? 0;
                final percent = double.tryParse(markupController.text) ?? 0;
                final calculated = buy > 0 ? ((sell - buy) / buy * 100) : 0;
                final newItem = PriceBookItem(
                  code: code,
                  name: nameController.text.trim(),
                  unit: unitController.text.trim(),
                  groupCode: groupController.text.trim(),
                  barcode: barcodeController.text.trim(),
                  price: sell,
                  purchasePrice: buy,
                  favorite: false,
                  markupPercent: percent,
                  markupOverridden: percent.toStringAsFixed(2) != calculated.toStringAsFixed(2),
                  origin: "default",
                );
                priceBook.add(newItem);
                print('Added item: ${newItem.code} - ${newItem.name}, total items: ${priceBook.length}');
              });
              print('Saving after adding new item...');
              await _savePriceBook();
              print('Save completed after adding new item');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Item added to PriceBook!')),
              );
            }
          },
          tooltip: 'Add PriceBook Item',
          child: const Icon(Icons.add),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  void _deleteItem(PriceBookItem item) {
    // Prevent deletion of hardcoded items
    if (item.code == 'CAL' || item.code == 'EST') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot delete ${item.name} - this is a protected item')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                priceBook.remove(item);
              });
              _savePriceBook();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted ${item.name}')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class PriceBookItem {
  final String code;
  String name;
  String unit;
  String groupCode;
  String? barcode;
  double price;
  double purchasePrice;
  bool favorite;
  double markupPercent;
  bool markupOverridden;
  String origin; // <-- NEW
  int usageCount;
  double percentageChanged; // <-- NEW FIELD
  
  // Change tracking fields for incremental sync
  DateTime? lastSyncedAt;
  DateTime lastModifiedAt;
  bool needsSync;
  String? cloudId; // Firestore document ID

  PriceBookItem({
    required this.code,
    required this.name,
    required this.unit,
    required this.groupCode,
    this.barcode,
    required this.price,
    required this.purchasePrice,
    this.favorite = false,
    this.markupPercent = 0,
    this.markupOverridden = false,
    this.origin = "default", // <-- NEW
    this.usageCount = 0,
    this.percentageChanged = 0, // <-- NEW
    this.lastSyncedAt,
    DateTime? lastModifiedAt,
    this.needsSync = true,
    this.cloudId,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.now();

  factory PriceBookItem.fromJson(Map<String, dynamic> json) => PriceBookItem(
        code: json['code'] ?? '',
        name: json['name'] ?? '',
        unit: json['unit'] ?? '',
        groupCode: json['groupCode'] ?? '',
        barcode: json['barcode'],
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0.0,
        favorite: json['favorite'] ?? false,
        markupPercent: (json['markupPercent'] as num?)?.toDouble() ?? 0.0,
        markupOverridden: json['markupOverridden'] ?? false,
        origin: json['origin'] ?? "default", // <-- NEW
        usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
        percentageChanged: (json['percentageChanged'] as num?)?.toDouble() ?? 0.0, // <-- NEW
        lastSyncedAt: json['lastSyncedAt'] != null ? DateTime.tryParse(json['lastSyncedAt']) : null,
        lastModifiedAt: json['lastModifiedAt'] != null ? DateTime.tryParse(json['lastModifiedAt']) : null,
        needsSync: json['needsSync'] ?? true,
        cloudId: json['cloudId'],
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'unit': unit,
        'groupCode': groupCode,
        'barcode': barcode,
        'price': price,
        'purchasePrice': purchasePrice,
        'favorite': favorite,
        'markupPercent': markupPercent,
        'markupOverridden': markupOverridden,
        'origin': origin, // <-- NEW
        'usageCount': usageCount,
        'percentageChanged': percentageChanged, // <-- NEW
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'needsSync': needsSync,
        'cloudId': cloudId,
      };

  String debugInfo() {
    return '''
Code: $code
Name: $name
Unit: $unit
Group: $groupCode
Barcode: $barcode
Sell Price: $price
Buy Price: $purchasePrice
Favorite: $favorite
Percentage Changed: $percentageChanged
''';
  }

  PriceBookItem copyWith({
    String? code,
    String? name,
    double? price,
    double? purchasePrice,
    String? unit,
    String? groupCode,
    String? barcode,
    bool? favorite,
    double? markupPercent,
    bool? markupOverridden,
    String? origin,
    int? usageCount,
    double? percentageChanged, // <-- NEW
    DateTime? lastSyncedAt,
    DateTime? lastModifiedAt,
    bool? needsSync,
    String? cloudId,
  }) {
    return PriceBookItem(
      code: code ?? this.code,
      name: name ?? this.name,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      unit: unit ?? this.unit,
      groupCode: groupCode ?? this.groupCode,
      barcode: barcode ?? this.barcode,
      favorite: favorite ?? this.favorite,
      markupPercent: markupPercent ?? this.markupPercent,
      markupOverridden: markupOverridden ?? this.markupOverridden,
      origin: origin ?? this.origin,
      usageCount: usageCount ?? this.usageCount,
      percentageChanged: percentageChanged ?? this.percentageChanged, // <-- NEW
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      needsSync: needsSync ?? this.needsSync,
      cloudId: cloudId ?? this.cloudId,
    );
  }
  
  /// Mark this item as modified (for change tracking)
  void markAsModified() {
    lastModifiedAt = DateTime.now();
    needsSync = true;
  }
  
  /// Mark this item as synced (after successful Firestore sync)
  void markAsSynced(String? firestoreDocId) {
    lastSyncedAt = DateTime.now();
    needsSync = false;
    if (firestoreDocId != null) {
      cloudId = firestoreDocId;
    }
  }
  
  /// Check if this item has been modified since last sync
  bool get hasBeenModified {
    if (needsSync) return true;
    if (lastSyncedAt == null) return true;
    return lastModifiedAt.isAfter(lastSyncedAt!);
  }
}

enum SortOption {
  code,
  name,
  price,
  barcode,
}