import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/pricebook_cloud_sync_service.dart';
import '../services/demo_mode_service.dart';
import 'pricebook_csv_import_screen.dart';

enum PriceBookKind {
  main,
  extensive,
}

class PriceBookScreen extends StatefulWidget {
  final List<PriceBookItem> priceBook;
  final void Function(List<PriceBookItem>)? onPriceBookUpdated; // <-- make nullable
  final PriceBookKind kind;

  const PriceBookScreen({
    super.key,
    required this.priceBook,
    this.onPriceBookUpdated,
    this.kind = PriceBookKind.main,
  });

  String get title => kind == PriceBookKind.extensive ? 'Extensive Price Book' : 'Price Book';
  String get storageFileName => kind == PriceBookKind.extensive
      ? 'price_book_extensive.json'
      : 'price_book.json';

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
  bool _backupAvailable = false;
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

  /// Converts a demo-mode pricebook item into the screen's local
  /// [PriceBookItem] shape so all existing UI/sort/search code works
  /// unmodified while in Demo Mode.
  PriceBookItem _demoItemToPriceBookItem(DemoPriceBookItem item) {
    return PriceBookItem(
      code: item.code,
      name: item.name,
      unit: item.unit,
      groupCode: item.category,
      barcode: item.barcode,
      price: item.salePrice,
      purchasePrice: item.purchasePrice,
      origin: 'demo',
      needsSync: false,
    );
  }

  // ROBUST LOADING: Always prioritize local file, never lose data
  Future<void> _loadPriceBookFromDisk() async {
    // DEMO MODE: read from the in-memory demo pricebook instead of disk.
    if (DemoModeService.instance.isDemoMode) {
      setState(() {
        priceBook = DemoModeService.instance.priceBook
            .map(_demoItemToPriceBookItem)
            .toList();
      });
      _ensureHardcodedPriceBookItems();
      print('✅ [Demo Mode] Loaded ${priceBook.length} pricebook items from demo sandbox');
      return;
    }
    try {
      print('🔄 Loading pricebook - prioritizing local file for reliability...');
      
      // ALWAYS load from local file first (most reliable)
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${widget.storageFileName}');
      List<PriceBookItem> localItems = [];
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          try {
            final decoded = jsonDecode(contents);
            final List<dynamic> jsonList;
            if (decoded is Map<String, dynamic> && decoded.containsKey('items')) {
              jsonList = decoded['items'] as List<dynamic>;
            } else if (decoded is List<dynamic>) {
              jsonList = decoded;
            } else {
              throw Exception('Unexpected pricebook JSON structure');
            }

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
        _ensureHardcodedPriceBookItems();
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
      await _offerRestoreIfBackupIsBetter();
      
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
    } else if (template == 'voltex') {
      importFromVoltexCsv();
    } else if (template == 'custom') {
      importFromCustomCsv();
    } else {
      importFromCsv();
    }
  }

  Future<void> importFromCustomCsv() async {
    try {
      final importedRows = await Navigator.push<List<Map<String, dynamic>>>(
        context,
        MaterialPageRoute(
          builder: (_) => const PriceBookCsvImportScreen(),
        ),
      );

      if (importedRows == null || importedRows.isEmpty) return;

      final imported = importedRows.map((row) {
        return PriceBookItem(
          code: row['code']?.toString() ?? '',
          name: row['name']?.toString() ?? '',
          unit: row['unit']?.toString() ?? '',
          groupCode: row['groupCode']?.toString() ?? '',
          barcode: row['barcode']?.toString(),
          price: (row['price'] is num) ? (row['price'] as num).toDouble() : double.tryParse(row['price']?.toString() ?? '') ?? 0.0,
          purchasePrice: (row['purchasePrice'] is num) ? (row['purchasePrice'] as num).toDouble() : double.tryParse(row['purchasePrice']?.toString() ?? '') ?? 0.0,
          favorite: row['favorite'] is bool ? row['favorite'] as bool : row['favorite']?.toString().toLowerCase() == 'true',
          origin: 'Custom CSV',
        );
      }).where((item) => item.code.isNotEmpty && item.name.isNotEmpty).toList();

      if (imported.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid rows were found in the custom CSV import.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _mergeImportedItems(imported);
      });
      await _savePriceBook();
      if (widget.kind == PriceBookKind.extensive) {
        await _updateMainPriceBookFromExtensiveImport(imported);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully imported ${imported.length} items from custom CSV.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error importing custom CSV: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing custom CSV: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _mergeImportedItems(List<PriceBookItem> imported) {
    final existingItems = {for (var item in priceBook) item.code: item};
    final updated = {for (var item in priceBook) item.code: item};

    for (final newItem in imported) {
      final existing = existingItems[newItem.code];
      if (existing != null) {
        if (existing.markupOverridden || existing.percentageChanged != 0) {
          final newBuy = newItem.purchasePrice;
          final percent = existing.percentageChanged != 0
              ? existing.percentageChanged
              : existing.markupPercent;
          final newSell = newBuy > 0 ? newBuy * (1 + percent / 100) : newItem.price;
          final priceActuallyChanged =
              (newBuy - existing.purchasePrice).abs() >= 0.005 ||
                  (newSell - existing.price).abs() >= 0.005;
          updated[newItem.code] = PriceBookItem(
            code: existing.code,
            name: existing.name,
            unit: newItem.unit,
            groupCode: newItem.groupCode,
            barcode: newItem.barcode ?? existing.barcode,
            price: newSell,
            purchasePrice: newBuy,
            favorite: existing.favorite,
            markupPercent: percent,
            markupOverridden: true,
            origin: newItem.origin,
            usageCount: existing.usageCount,
            percentageChanged: existing.percentageChanged,
            priceLastChangedAt: priceActuallyChanged
                ? DateTime.now()
                : existing.priceLastChangedAt,
          );
        } else {
          final priceActuallyChanged =
              (newItem.purchasePrice - existing.purchasePrice).abs() >= 0.005 ||
                  (newItem.price - existing.price).abs() >= 0.005;
          updated[newItem.code] = PriceBookItem(
            code: existing.code,
            name: existing.name,
            unit: newItem.unit,
            groupCode: newItem.groupCode,
            barcode: newItem.barcode ?? existing.barcode,
            price: newItem.price,
            purchasePrice: newItem.purchasePrice,
            favorite: existing.favorite,
            markupPercent: newItem.markupPercent,
            markupOverridden: false,
            origin: newItem.origin,
            usageCount: existing.usageCount,
            percentageChanged: newItem.percentageChanged,
            priceLastChangedAt: priceActuallyChanged
                ? DateTime.now()
                : existing.priceLastChangedAt,
          );
        }
      } else {
        updated[newItem.code] = newItem;
      }
    }

    priceBook = updated.values.toList();
    for (final item in priceBook) {
      if (imported.any((importedItem) => importedItem.code == item.code)) {
        item.markAsModified();
      }
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
              origin: 'Standard Template',
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
            if (existing.markupOverridden || existing.percentageChanged != 0) {
              final newBuy = newItem.purchasePrice;
              final percent = existing.percentageChanged != 0
              ? existing.percentageChanged
              : existing.markupPercent;
              final newSell = newBuy * (1 + percent / 100);
              final priceActuallyChanged =
                  (newBuy - existing.purchasePrice).abs() >= 0.005 ||
                      (newSell - existing.price).abs() >= 0.005;
              updated[newItem.code] = PriceBookItem(
                code: existing.code,
                name: existing.name,
                unit: newItem.unit,
                groupCode: newItem.groupCode,
                barcode: newItem.barcode,
                price: newSell,
                purchasePrice: newBuy,
                favorite: existing.favorite,
                markupPercent: percent,
                markupOverridden: true,
                priceLastChangedAt: priceActuallyChanged
                    ? DateTime.now()
                    : existing.priceLastChangedAt,
              );
            } else {
              // Not overridden: update buy/sell price from import, keep name
              final priceActuallyChanged =
                  (newItem.purchasePrice - existing.purchasePrice).abs() >= 0.005 ||
                      (newItem.price - existing.price).abs() >= 0.005;
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
                priceLastChangedAt: priceActuallyChanged
                    ? DateTime.now()
                    : existing.priceLastChangedAt,
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
      if (widget.kind == PriceBookKind.extensive) {
        await _updateMainPriceBookFromExtensiveImport(imported);
      }
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

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No rows found in JA CSV file.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Detect whether the first row is a header row, otherwise treat it as data.
    final firstRowText = rows.first.map((e) => e.toString().toLowerCase()).toList();
    final hasHeader = firstRowText.any((cell) =>
        cell.contains('stock code') ||
        cell.contains('product desc') ||
        cell.contains('description') ||
        cell.contains('product group'));

    // Default JA Russell mapping for headered CSV files
    int dataStart = hasHeader ? 1 : 0;
    int codeIdx = 0; // A
    int groupIdx = 2; // C
    int barcodeIdx = 4; // E
    int unitIdx = 5; // F
    int buyPriceIdx = 12; // M
    int nameIIdx = 8; // I
    int nameBIdx = 1; // B
    int sellPriceIdx = 6; // G

    // Some Russell files contain an empty first column and put the stock code in column B.
    if (!hasHeader && rows.first.length > 1 && rows.first[0].toString().trim().isEmpty) {
      codeIdx = 1; // B
      nameIIdx = 8; // I stays the same
      nameBIdx = 0; // A becomes alternate name part when blank first column exists
      unitIdx = 3; // D
      groupIdx = 4; // E
      barcodeIdx = 5; // F
      sellPriceIdx = 6; // G
      buyPriceIdx = rows.first.length > 13 ? 13 : 12; // M if available, otherwise fallback
    }

    // Column indices (0-based): A=0, B=1, C=2, D=3, E=4, F=5, G=6, ..., I=8, M=12
    final Map<String, Map<String, dynamic>> items = {};

    for (var i = dataStart; i < rows.length; i++) {
      final row = rows[i];
      final code = row.length > codeIdx ? row[codeIdx]?.toString().trim() : '';
      if (code == null || code.isEmpty) continue;

      final nameI = row.length > nameIIdx ? row[nameIIdx]?.toString().trim() ?? '' : '';
      final nameB = row.length > nameBIdx ? row[nameBIdx]?.toString().trim() ?? '' : '';
      final barcode = row.length > barcodeIdx ? row[barcodeIdx]?.toString().trim() ?? '' : '';
      final unit = row.length > unitIdx ? row[unitIdx]?.toString().trim() ?? '' : '';
      final groupCode = row.length > groupIdx ? row[groupIdx]?.toString().trim() ?? '' : '';
      final buyPrice = row.length > buyPriceIdx ? double.tryParse(row[buyPriceIdx]?.toString() ?? '') ?? 0.0 : 0.0;
      final sellPrice = row.length > sellPriceIdx ? double.tryParse(row[sellPriceIdx]?.toString() ?? '') ?? 0.0 : 0.0;

      if (!items.containsKey(code)) {
        items[code] = {
          'nameI': '',
          'nameB': '',
          'barcode': barcode,
          'unit': unit,
          'groupCode': groupCode,
          'buyPrice': buyPrice,
          'sellPrice': sellPrice,
        };
      }

      if (nameI.isNotEmpty) items[code]!['nameI'] = nameI;
      if (nameB.isNotEmpty) items[code]!['nameB'] = nameB;
      if (barcode.isNotEmpty) items[code]!['barcode'] = barcode;
      if (unit.isNotEmpty) items[code]!['unit'] = unit;
      if (groupCode.isNotEmpty) items[code]!['groupCode'] = groupCode;
      if (buyPrice > 0) items[code]!['buyPrice'] = buyPrice;
      if (sellPrice > 0) items[code]!['sellPrice'] = sellPrice;
    }

    // Ask user for import name
    final originName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Name this Pricebook Import'),
        content: TextField(
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
          decoration: InputDecoration(hintText: 'e.g. JA Russell ${DateTime.now().toIso8601String().substring(0,10)}'),
          controller: TextEditingController(
              text: 'JA Russell ${DateTime.now().toIso8601String().substring(0,10)}'),
          onSubmitted: (val) => Navigator.pop(context, val.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context,
                  'JA Russell ${DateTime.now().toIso8601String().substring(0,10)}'),
              child: const Text('OK')),
        ],
      ),
    );
    if (originName == null || originName.isEmpty) return;

    final imported = items.entries.map((e) {
      String code = e.key;
      if (code.trim().toLowerCase() == 'labour cal') code = 'CAL';
      if (code.trim().toLowerCase() == 'labour est') code = 'EST';
      final name = [
        e.value['nameI'],
        e.value['nameB']
      ].where((s) => s != null && s.toString().isNotEmpty).join(' ');
      return PriceBookItem(
        code: code,
        name: name,
        unit: e.value['unit'],
        groupCode: e.value['groupCode'],
        barcode: e.value['barcode'],
        price: e.value['sellPrice'],
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
        if (existing != null &&
            (existing.markupOverridden || existing.percentageChanged != 0)) {
          final newBuy = newItem.purchasePrice;
          final percent = existing.percentageChanged != 0
              ? existing.percentageChanged
              : existing.markupPercent;
          final newSell = newBuy > 0 ? newBuy * (1 + percent / 100) : newItem.price;
          final priceActuallyChanged =
              (newBuy - existing.purchasePrice).abs() >= 0.005 ||
                  (newSell - existing.price).abs() >= 0.005;
          updated[newItem.code] = PriceBookItem(
            code: existing.code,
            name: existing.name,
            unit: newItem.unit,
            groupCode: newItem.groupCode,
            barcode: newItem.barcode,
            price: newSell,
            purchasePrice: newBuy,
            favorite: existing.favorite,
            markupPercent: percent,
            markupOverridden: true,
            origin: newItem.origin,
            usageCount: existing.usageCount,
            percentageChanged: existing.percentageChanged,
            priceLastChangedAt: priceActuallyChanged
                ? DateTime.now()
                : existing.priceLastChangedAt,
          );
        } else if (existing != null) {
          final priceActuallyChanged =
              (newItem.purchasePrice - existing.purchasePrice).abs() >= 0.005 ||
                  (newItem.price - existing.price).abs() >= 0.005;
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
            priceLastChangedAt: priceActuallyChanged
                ? DateTime.now()
                : existing.priceLastChangedAt,
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
    if (widget.kind == PriceBookKind.extensive) {
      await _updateMainPriceBookFromExtensiveImport(imported);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully imported ${imported.length} items from JA CSV'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> importFromVoltexCsv() async {
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
            Text('Loading Voltex CSV file...'),
          ],
        ),
      ),
    );

    final file = File(result.files.single.path!);
    final csvString = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n').convert(csvString);

    // Close loading dialog
    Navigator.pop(context);

    if (rows.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No rows found in Voltex CSV file.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Voltex pricebook layout:
    // A = ID Code, E then B = Item Name, C = Buy Price, F = Sell Price
    const codeIdx = 0; // Column A
    const nameAIdx = 4; // Column E
    const nameBIdx = 1; // Column B
    const buyPriceIdx = 2; // Column C
    const sellPriceIdx = 5; // Column F

    final imported = <PriceBookItem>[];
    for (var i = 1; i < rows.length; i++) {
      try {
        final row = rows[i];
        if (row.length <= sellPriceIdx) continue;

        final code = row[codeIdx]?.toString().trim() ?? '';
        if (code.isEmpty) continue;

        final nameParts = <String>[];
        final nameA = row[nameAIdx]?.toString().trim() ?? '';
        final nameB = row[nameBIdx]?.toString().trim() ?? '';
        if (nameA.isNotEmpty) nameParts.add(nameA);
        if (nameB.isNotEmpty) nameParts.add(nameB);
        final name = nameParts.join(' ').trim();
        if (name.isEmpty) continue;

        final buyPrice = double.tryParse(row[buyPriceIdx]?.toString() ?? '') ?? 0.0;
        final sellPrice = double.tryParse(row[sellPriceIdx]?.toString() ?? '') ?? 0.0;

        imported.add(
          PriceBookItem(
            code: code,
            name: name,
            unit: '',
            groupCode: '',
            barcode: null,
            price: sellPrice,
            purchasePrice: buyPrice,
            favorite: false,
            origin: 'Voltex',
          ),
        );
      } catch (e) {
        print('⚠️ Error processing Voltex row $i: $e');
      }
    }

    if (imported.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid Voltex items were found.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      final existingItems = {for (var item in priceBook) item.code: item};
      final Map<String, PriceBookItem> updated = {
        for (var item in priceBook) item.code: item
      };

      for (final newItem in imported) {
        final existing = existingItems[newItem.code];
        if (existing != null) {
          if (existing.markupOverridden || existing.percentageChanged != 0) {
            final newBuy = newItem.purchasePrice;
            final percent = existing.percentageChanged != 0
              ? existing.percentageChanged
              : existing.markupPercent;
            final newSell = newBuy * (1 + percent / 100);
            final priceActuallyChanged =
                (newBuy - existing.purchasePrice).abs() >= 0.005 ||
                    (newSell - existing.price).abs() >= 0.005;
            updated[newItem.code] = PriceBookItem(
              code: existing.code,
              name: existing.name,
              unit: existing.unit,
              groupCode: existing.groupCode,
              barcode: existing.barcode,
              price: newSell,
              purchasePrice: newBuy,
              favorite: existing.favorite,
              markupPercent: percent,
              markupOverridden: true,
              origin: existing.origin,
              usageCount: existing.usageCount,
              percentageChanged: existing.percentageChanged,
              priceLastChangedAt: priceActuallyChanged
                  ? DateTime.now()
                  : existing.priceLastChangedAt,
            );
          } else {
            final priceActuallyChanged =
                (newItem.purchasePrice - existing.purchasePrice).abs() >= 0.005 ||
                    (newItem.price - existing.price).abs() >= 0.005;
            updated[newItem.code] = PriceBookItem(
              code: existing.code,
              name: existing.name,
              unit: existing.unit,
              groupCode: existing.groupCode,
              barcode: existing.barcode,
              price: newItem.price,
              purchasePrice: newItem.purchasePrice,
              favorite: existing.favorite,
              markupPercent: newItem.markupPercent,
              markupOverridden: false,
              origin: existing.origin,
              usageCount: existing.usageCount,
              percentageChanged: newItem.percentageChanged,
              priceLastChangedAt: priceActuallyChanged
                  ? DateTime.now()
                  : existing.priceLastChangedAt,
            );
          }
        } else {
          updated[newItem.code] = newItem;
        }
      }

      priceBook = updated.values.toList();
      for (final item in priceBook) {
        if (imported.any((importedItem) => importedItem.code == item.code)) {
          item.markAsModified();
        }
      }
    });

    await _savePriceBook();
    if (widget.kind == PriceBookKind.extensive) {
      await _updateMainPriceBookFromExtensiveImport(imported);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully imported ${imported.length} items from Voltex CSV'),
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

  // Create a local backup before any save so we can recover from destructive imports
  Future<void> _backupLocalFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${widget.storageFileName}');
      final backupFile = File('${directory.path}/${widget.storageFileName}.bak');
      if (await file.exists()) {
        await file.copy(backupFile.path);
        print('💾 Backup created for ${widget.storageFileName} at ${backupFile.path}');
      }
    } catch (e) {
      print('⚠️ Failed to create backup before save: $e');
    }
  }

  // ROBUST LOCAL FILE SAVING - Always save to device immediately
  Future<void> _saveToLocalFile() async {
    // DEMO MODE: persist edits back into the in-memory demo sandbox only,
    // never touch the real pricebook file on disk.
    if (DemoModeService.instance.isDemoMode) {
      final demoService = DemoModeService.instance;
      for (final item in priceBook) {
        final index =
            demoService.priceBook.indexWhere((p) => p.code == item.code);
        final updated = DemoPriceBookItem(
          id: index != -1
              ? demoService.priceBook[index].id
              : 'demo_pb_${item.code}',
          code: item.code,
          name: item.name,
          category: item.groupCode,
          purchasePrice: item.purchasePrice,
          salePrice: item.price,
          unit: item.unit,
          barcode: item.barcode,
        );
        if (index != -1) {
          demoService.priceBook[index] = updated;
        } else {
          demoService.priceBook.add(updated);
        }
      }
      await demoService.persistCurrentSnapshot();
      print('💾 [Demo Mode] Saved ${priceBook.length} pricebook items to demo sandbox');
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${widget.storageFileName}');
      final jsonList = priceBook.map((item) => item.toJson()).toList();
      final data = {
        'items': jsonList,
        'lastSaved': DateTime.now().toIso8601String(),
        'version': 1,
        'totalItems': jsonList.length,
      };
      await file.writeAsString(jsonEncode(data));
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
      await _backupLocalFile();
      // 1. ALWAYS save to local file first (essential for reliability)
      await _saveToLocalFile();
      
      // 2. Update parent widget immediately only for the main book
      if (widget.kind == PriceBookKind.main && widget.onPriceBookUpdated != null) {
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
      await _syncMainChangesToExtensiveBook();
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

  /// WHOLE-FILE CLOUD SYNC: uploads the entire price book as a single
  /// JSON file to Firebase Storage, instead of writing one Firestore
  /// document per item (the previous approach, `batchSavePriceBookItems`
  /// in firestore_service.dart, became unreliable at ~50,000 items - see
  /// pricebook_cloud_sync_service.dart for the full rationale). This is
  /// a "last write wins" backup of the whole list, not a granular
  /// per-item merge, which is an intentional simplification at this
  /// scale.
  Future<void> _syncChangedItemsToFirestore() async {
    try {
      print('🔍 Starting whole-file cloud sync...');

      if (priceBook.isEmpty) {
        print('✅ Price book is empty - nothing to sync');
        return;
      }

      final itemsJson = priceBook.map((item) => item.toJson()).toList();

      print('🚀 Uploading ${itemsJson.length} items as a single file to Firebase Storage...');
      await PriceBookCloudSyncService.uploadPriceBook(itemsJson);

      // Mark every item as synced now that the whole file (which
      // includes every item, not just the previously-modified ones) has
      // been uploaded.
      for (final item in priceBook) {
        item.markAsSynced(null);
      }

      print('✅ Successfully uploaded whole price book (${itemsJson.length} items) to cloud');
    } catch (e) {
      print('❌ Error in whole-file cloud sync: $e');
      rethrow;
    }
  }

  /// Restores the price book from the whole-file cloud backup (Firebase
  /// Storage), overwriting the current in-memory + local list. Mirrors
  /// `_restoreFromBackup()` (which restores from the local backup file)
  /// but pulls from the cloud copy instead.
  Future<void> _restoreFromCloudBackup() async {
    try {
      final itemsJson = await PriceBookCloudSyncService.downloadPriceBook();
      if (itemsJson.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No cloud backup found for the price book yet.'),
            ),
          );
        }
        return;
      }

      final restoredItems =
          itemsJson.map((json) => PriceBookItem.fromJson(json)).toList();

      setState(() {
        priceBook
          ..clear()
          ..addAll(restoredItems);
      });
      await _saveToLocalFile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Restored ${restoredItems.length} items from cloud backup.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Failed to restore price book from cloud: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore cloud backup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        if (DemoModeService.instance.isDemoMode) {
          // DEMO MODE: resolve/mint via the demo pricebook "magic barcode"
          // fallback, add it into the on-screen list if not already there,
          // and search for it.
          final demoItem =
              DemoModeService.instance.scanBarcode(scannedBarcode);
          setState(() {
            final exists =
                priceBook.any((p) => p.code == demoItem.code);
            if (!exists) {
              priceBook.add(_demoItemToPriceBookItem(demoItem));
            }
            searchQuery = scannedBarcode;
            _searchController.text = scannedBarcode;
          });
        } else {
          setState(() {
            searchQuery = scannedBarcode;
            _searchController.text = scannedBarcode;
          });
        }
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

  Future<void> _syncMainChangesToExtensiveBook() async {
    if (widget.kind != PriceBookKind.main) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book_extensive.json');
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return;

      final List<dynamic> jsonList = jsonDecode(contents);
      final extensiveItems = jsonList
          .whereType<Map<String, dynamic>>()
          .map(PriceBookItem.fromJson)
          .toList();

      final mainItemsByCode = {for (var item in priceBook) item.code: item};
      int changedCount = 0;

      for (final item in extensiveItems) {
        final mainItem = mainItemsByCode[item.code];
        if (mainItem == null) continue;

        if (item.name != mainItem.name ||
            item.unit != mainItem.unit ||
            item.groupCode != mainItem.groupCode ||
            item.barcode != mainItem.barcode ||
            item.price != mainItem.price ||
            item.purchasePrice != mainItem.purchasePrice ||
            item.markupPercent != mainItem.markupPercent ||
            item.markupOverridden != mainItem.markupOverridden) {
          item.name = mainItem.name;
          item.unit = mainItem.unit;
          item.groupCode = mainItem.groupCode;
          item.barcode = mainItem.barcode;
          item.price = mainItem.price;
          item.purchasePrice = mainItem.purchasePrice;
          item.markupPercent = mainItem.markupPercent;
          item.markupOverridden = mainItem.markupOverridden;
          changedCount += 1;
        }
      }

      if (changedCount > 0) {
        await file.writeAsString(jsonEncode(extensiveItems.map((item) => item.toJson()).toList()));
        print('✅ Propagated $changedCount main pricebook change(s) to extensive pricebook');
      }
    } catch (e) {
      print('❌ Error syncing main changes to extensive pricebook: $e');
    }
  }

  Future<void> _updateMainPriceBookFromExtensiveImport(List<PriceBookItem> importedItems) async {
    if (widget.kind != PriceBookKind.extensive || importedItems.isEmpty) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return;

      final List<dynamic> jsonList = jsonDecode(contents);
      final mainPriceBook = jsonList
          .whereType<Map<String, dynamic>>()
          .map(PriceBookItem.fromJson)
          .toList();

      final mainByCode = {for (var item in mainPriceBook) item.code: item};
      int changedCount = 0;

      for (final imported in importedItems) {
        if (imported.code.trim().isEmpty) continue;
        final existing = mainByCode[imported.code];
        if (existing == null) continue;

        if (existing.markupOverridden || existing.percentageChanged != 0) {
          final newBuy = imported.purchasePrice;
          final percent = existing.percentageChanged != 0
              ? existing.percentageChanged
              : existing.markupPercent;
          final newSell = newBuy > 0 ? newBuy * (1 + percent / 100) : imported.price;

          if (existing.purchasePrice != newBuy || existing.price != newSell || existing.unit != imported.unit || existing.groupCode != imported.groupCode || existing.barcode != imported.barcode) {
            final priceActuallyChanged =
                (newBuy - existing.purchasePrice).abs() >= 0.005 ||
                    (newSell - existing.price).abs() >= 0.005;
            existing.unit = imported.unit;
            existing.groupCode = imported.groupCode;
            existing.barcode = imported.barcode;
            existing.purchasePrice = newBuy;
            existing.price = newSell;
            existing.markupPercent = percent;
            existing.markupOverridden = true;
            existing.lastModifiedAt = DateTime.now();
            if (priceActuallyChanged) {
              existing.priceLastChangedAt = DateTime.now();
            }
            existing.needsSync = true;
            changedCount += 1;
          }
        } else {
          if (existing.purchasePrice != imported.purchasePrice || existing.price != imported.price || existing.unit != imported.unit || existing.groupCode != imported.groupCode || existing.barcode != imported.barcode) {
            final priceActuallyChanged =
                (imported.purchasePrice - existing.purchasePrice).abs() >= 0.005 ||
                    (imported.price - existing.price).abs() >= 0.005;
            existing.unit = imported.unit;
            existing.groupCode = imported.groupCode;
            existing.barcode = imported.barcode;
            existing.purchasePrice = imported.purchasePrice;
            existing.price = imported.price;
            existing.markupPercent = imported.markupPercent;
            existing.markupOverridden = false;
            existing.lastModifiedAt = DateTime.now();
            if (priceActuallyChanged) {
              existing.priceLastChangedAt = DateTime.now();
            }
            existing.needsSync = true;
            changedCount += 1;
          }
        }
      }

      if (changedCount > 0) {
        await file.writeAsString(jsonEncode(mainPriceBook.map((item) => item.toJson()).toList()));
        print('✅ Updated $changedCount main pricebook item(s) from extensive import');
      }
    } catch (e) {
      print('❌ Error updating main pricebook from extensive import: $e');
    }
  }

  Future<File> _backupFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/${widget.storageFileName}.bak');
  }

  Future<void> _checkBackupAvailability() async {
    try {
      final backupFile = await _backupFile();
      final exists = await backupFile.exists();
      if (mounted) {
        setState(() {
          _backupAvailable = exists;
        });
      }
    } catch (e) {
      print('⚠️ Failed to check backup availability: $e');
    }
  }

  bool _isOnlyLabourItems(List<PriceBookItem> items) {
    return items.isNotEmpty &&
        items.every((item) => item.code == 'CAL' || item.code == 'EST');
  }

  Future<List<PriceBookItem>> _loadBackupItems() async {
    try {
      final backupFile = await _backupFile();
      if (!await backupFile.exists()) return [];
      final contents = await backupFile.readAsString();
      if (contents.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(contents);
      return jsonList
          .whereType<Map<String, dynamic>>()
          .map((json) => PriceBookItem.fromJson(json))
          .toList();
    } catch (e) {
      print('⚠️ Failed to load backup pricebook items: $e');
      return [];
    }
  }

  Future<void> _restoreFromBackup() async {
    try {
      final backupItems = await _loadBackupItems();
      if (backupItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No backup data is available to restore.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      setState(() {
        priceBook = backupItems;
      });
      await _saveToLocalFile();
      await _checkBackupAvailability();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored ${priceBook.length} items from backup.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Failed to restore pricebook backup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore backup: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<bool> _confirmDeleteAllPriceBook() async {
    String confirmationText = '';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete ALL PriceBook Items?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'This will permanently remove all items except the built-in labour entries. Type DELETE to confirm.'),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  onChanged: (value) => confirmationText = value.trim().toUpperCase(),
                  decoration: const InputDecoration(
                    labelText: 'Enter DELETE to confirm',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: confirmationText == 'DELETE'
                    ? () => Navigator.pop(context, true)
                    : null,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete All'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _offerRestoreIfBackupIsBetter() async {
    await _checkBackupAvailability();
    if (!_backupAvailable || !_isOnlyLabourItems(priceBook)) return;

    final backupItems = await _loadBackupItems();
    if (backupItems.length <= priceBook.length) return;

    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restore Pricebook from Backup?'),
        content: Text(
          'The current pricebook only contains ${priceBook.length} labour entries, but a backup has ${backupItems.length} items.\n\nWould you like to restore the backup now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Current'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore Backup'),
          ),
        ],
      ),
    );

    if (restore == true) {
      await _restoreFromBackup();
    }
  }

  Future<void> _exportPriceBookToCsv() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/price_book_export_$timestamp.csv');

      final header = [
        'code',
        'name',
        'unit',
        'groupCode',
        'barcode',
        'price',
        'purchasePrice',
        'favorite',
        'markupPercent',
        'markupOverridden',
        'origin',
        'usageCount',
        'percentageChanged',
        'lastModifiedAt',
        'lastSyncedAt',
        'needsSync',
        'cloudId',
      ];

      final rows = <List<dynamic>>[
        header,
        ...priceBook.map((item) => [
              item.code,
              item.name,
              item.unit,
              item.groupCode,
              item.barcode ?? '',
              item.price,
              item.purchasePrice,
              item.favorite,
              item.markupPercent,
              item.markupOverridden,
              item.origin,
              item.usageCount,
              item.percentageChanged,
              item.lastModifiedAt.toIso8601String(),
              item.lastSyncedAt?.toIso8601String() ?? '',
              item.needsSync,
              item.cloudId ?? '',
            ])
      ];

      final csv = const ListToCsvConverter().convert(rows);
      await file.writeAsString(csv);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pricebook exported to ${file.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ Failed to export pricebook CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export pricebook: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        Navigator.pop(context);
        return false; // Prevent default pop, since we already did it
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(DemoModeService.instance.isDemoMode
              ? '${widget.title} (Demo Mode)'
              : widget.title),
          backgroundColor:
              DemoModeService.instance.isDemoMode ? Colors.deepPurple : null,
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
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export PriceBook CSV',
              onPressed: _exportPriceBookToCsv,
            ),
            Stack(
              children: [
                GestureDetector(
                  onLongPress: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('☁️ Restore from Cloud'),
                        content: const Text(
                          'This will replace your current price book with '
                          'the last cloud backup. Any local changes made '
                          'since that backup will be lost. Continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style:
                                TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _restoreFromCloudBackup();
                    }
                  },
                  child: IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: 'Cloud Sync (upload whole price book) — long-press to restore from cloud',
                  onPressed: () async {
                    if (priceBook.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Price book is empty - nothing to sync.'),
                        ),
                      );
                      return;
                    }

                    // Warn for large datasets since this uploads the
                    // whole file in one go (no per-item limit like the
                    // old Firestore approach, but still worth confirming
                    // for very large lists on a metered connection).
                    if (priceBook.length > 5000) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('☁️ Cloud Sync'),
                          content: Text(
                            'This will upload all ${priceBook.length} price book items '
                            'as a single file to the cloud (replacing any previous cloud backup).\n\n'
                            'Continue?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style:
                                  TextButton.styleFrom(foregroundColor: Colors.blue),
                              child: const Text('Upload'),
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
                            content:
                                Text('☁️ Uploading ${priceBook.length} items to cloud...'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }

                      await _syncChangedItemsToFirestore();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '✅ Successfully uploaded ${priceBook.length} items to cloud!'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    } catch (e) {
                      print('Cloud sync failed: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ Cloud sync failed: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  ),
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
                        onPressed: () => Navigator.pop(context, 'custom'),
                        child: Text('Custom CSV Template'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'ja_favorites'),
                        child: Text('JA Favorites'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'voltex'),
                        child: Text('Voltex Pricebook CSV'),
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
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete selected pricebook',
              onPressed: () async {
                if (_selectedOrigin == 'All') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Select a specific pricebook filter before deleting.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final originToDelete = _selectedOrigin;
                if (originToDelete == 'hardcoded') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot delete hardcoded pricebook items.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final itemsToDelete = priceBook.where((item) => item.origin == originToDelete && item.code != 'CAL' && item.code != 'EST').toList();
                if (itemsToDelete.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('No items found for "$originToDelete".'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Delete "$originToDelete" Pricebook?'),
                    content: Text('This will remove ${itemsToDelete.length} items imported from "$originToDelete".'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                setState(() {
                  priceBook.removeWhere((item) => item.origin == originToDelete && item.code != 'CAL' && item.code != 'EST');
                  _selectedOrigin = 'All';
                });
                await _savePriceBook();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted ${itemsToDelete.length} items from "$originToDelete".'),
                    backgroundColor: Colors.green,
                  ),
                );
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
                      'Origin: ${item.origin}\nUnit: ${item.unit}  |  Group: ${item.groupCode}  |  Markup: ${item.purchasePrice > 0 ? ((item.price - item.purchasePrice) / item.purchasePrice * 100).toStringAsFixed(1) : '0'}%',
                      maxLines: 3,
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
                                                        if (item.purchasePrice > 0) {
                                                          item.price = double.parse(
                                                            (item.purchasePrice * (1 + v / 100))
                                                                .toStringAsFixed(2),
                                                          );
                                                        }
                                                        item.markPriceChanged();
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
                                final oldPrice = item.price;
                                final oldPurchasePrice = item.purchasePrice;
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
                                final priceActuallyChanged =
                                    (item.price - oldPrice).abs() >= 0.005 ||
                                        (item.purchasePrice - oldPurchasePrice).abs() >= 0.005;
                                if (priceActuallyChanged) {
                                  item.markPriceChanged(); // Track price-specific change
                                } else {
                                  item.markAsModified(); // Track change for sync
                                }
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
                  priceLastChangedAt: DateTime.now(),
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

class PriceBookChoiceScreen extends StatelessWidget {
  final List<PriceBookItem> initialPriceBook;
  final void Function(List<PriceBookItem>)? onPriceBookUpdated;

  const PriceBookChoiceScreen({
    super.key,
    required this.initialPriceBook,
    this.onPriceBookUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Pricebook'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select the pricebook you want to open.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
                       ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PriceBookScreen(
                      priceBook: initialPriceBook,
                      onPriceBookUpdated: onPriceBookUpdated,
                      kind: PriceBookKind.main,
                    ),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Main Pricebook'),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PriceBookScreen(
                      priceBook: const [],
                      kind: PriceBookKind.extensive,
                    ),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Extensive Pricebook'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'The extensive book is stored separately and will not overwrite the main pricebook.',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
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

  // Tracks the last time this item's buy (purchasePrice) or sell (price)
  // value was actually changed - a single combined "price touched"
  // timestamp (not separate buy/sell timestamps). This is distinct from
  // `lastModifiedAt`, which fires on ANY field edit (name, unit, favorite,
  // etc.). Used by the estimate builder's conversion price-change dialog
  // to decide whether a line item should be flagged: if this is on/after
  // the source document's generation date, the item is flagged. Must use
  // the same JSON key ('priceLastChangedAt') as `models.PriceBookItem`
  // since both round-trip through the same price_book.json file.
  DateTime? priceLastChangedAt;

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
    this.priceLastChangedAt,
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
        priceLastChangedAt: json['priceLastChangedAt'] != null
            ? DateTime.tryParse(json['priceLastChangedAt'])
            : null,
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
        'origin': origin,
        'usageCount': usageCount,
        'percentageChanged': percentageChanged,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'needsSync': needsSync,
        'cloudId': cloudId,
        'priceLastChangedAt': priceLastChangedAt?.toIso8601String(),
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
    double? percentageChanged,
    DateTime? lastSyncedAt,
    DateTime? lastModifiedAt,
    bool? needsSync,
    String? cloudId,
    DateTime? priceLastChangedAt,
  }) {
    return PriceBookItem(
      code: code ?? this.code,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      groupCode: groupCode ?? this.groupCode,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      favorite: favorite ?? this.favorite,
      markupPercent: markupPercent ?? this.markupPercent,
      markupOverridden: markupOverridden ?? this.markupOverridden,
      origin: origin ?? this.origin,
      usageCount: usageCount ?? this.usageCount,
      percentageChanged: percentageChanged ?? this.percentageChanged,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      needsSync: needsSync ?? this.needsSync,
      cloudId: cloudId ?? this.cloudId,
      priceLastChangedAt: priceLastChangedAt ?? this.priceLastChangedAt,
    );
  }

  /// Mark this item as modified (for change tracking)
  void markAsModified() {
    lastModifiedAt = DateTime.now();
    needsSync = true;
  }

  /// Mark this item's buy or sell price as having actually changed "now".
  /// This is the dedicated "price touched" timestamp used to decide
  /// whether a conversion (estimate/quote -> invoice) should flag this
  /// item in the price-change dialog. Also marks the item as generally
  /// modified so it syncs to cloud like any other edit.
  void markPriceChanged() {
    priceLastChangedAt = DateTime.now();
    markAsModified();
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