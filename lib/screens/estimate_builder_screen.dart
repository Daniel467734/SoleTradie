import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/address_search_service.dart';
import '../services/memory_optimization_service.dart';
import '../models/estimate_template.dart';
import '../models/estimate_item.dart' as estimate_item;
import '../models/estimate_build.dart';
import '../models/job.dart' as job_model;
import '../models/estimate_version.dart';
import '../models/price_book_item.dart' as models;
import '../services/firestore_service.dart';
import '../mixins/document_naming_mixin.dart';
import 'pricebook_screen.dart';
import 'timeline_calendar_screen.dart';

class GeneratedDocument {
  final String id;
  final String jobId;
  final String type; // 'Invoice', 'Estimate', 'Quote'
  final String name;
  final String address;
  final DateTime dueDate;
  final double amount;
  final bool isPaid;
  final bool isArchived;
  final DateTime generatedAt;

  GeneratedDocument({
    required this.id,
    required this.jobId,
    required this.type,
    required this.name,
    required this.address,
    required this.dueDate,
    required this.amount,
    required this.isPaid,
    required this.isArchived,
    required this.generatedAt,
  });
}

class SubsectionData {
  String name;
  SubsectionData({required this.name});
}

// --- Helper methods (add these near the top or bottom of your file) ---

DateTime getInvoiceDueDate(String? paymentTerms) {
  // Example: "20th of month following" or "7 days"
  if (paymentTerms == null) return DateTime.now().add(const Duration(days: 7));
  if (paymentTerms.toLowerCase().contains('20th')) {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 20);
    return nextMonth;
  }
  final match = RegExp(r'(\d+)\s*days').firstMatch(paymentTerms.toLowerCase());
  if (match != null) {
    final days = int.tryParse(match.group(1) ?? '7') ?? 7;
    return DateTime.now().add(Duration(days: days));
  }
  return DateTime.now().add(const Duration(days: 7));
}

DateTime getEstimateOrQuoteDueDate() {
  return DateTime.now().add(const Duration(days: 30));
}

Future<String> extractTextFromPdf(File file) async {
  final bytes = await file.readAsBytes();
  final document = sfpdf.PdfDocument(inputBytes: bytes);
  String text = sfpdf.PdfTextExtractor(document).extractText();
  document.dispose();
  return text;
}

String formatQuantity(double quantity) {
  // If the quantity is a whole number, show it without decimal places
  if (quantity == quantity.toInt()) {
    return quantity.toInt().toString();
  } else {
    // Otherwise, show it with appropriate decimal places
    return quantity.toString();
  }
}

// --- EditableHeader widget ---
class EditableHeader extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController addressController;
  const EditableHeader({
    required this.nameController,
    required this.addressController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Customer Name'),
        ),
        TextField(
          controller: addressController,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
  
  }

// --- _SelectExtractedItemsDialogMulti widget ---
class _SelectExtractedItemsDialogMulti extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final bool showQuantity;
  const _SelectExtractedItemsDialogMulti({
    required this.items,
    this.showQuantity = false,
  });

  @override
  State<_SelectExtractedItemsDialogMulti> createState() => _SelectExtractedItemsDialogMultiState();
}

class _SelectExtractedItemsDialogMultiState extends State<_SelectExtractedItemsDialogMulti> {
  late List<bool> _selected;
  late List<TextEditingController> _qtyControllers;

  @override
  void initState() {
    super.initState();
    _selected = List<bool>.filled(widget.items.length, true);
    _qtyControllers = widget.items
        .map((item) => TextEditingController(text: (item['quantity'] ?? 1).toString()))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Items'),
      content: SizedBox(
        width: 350,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final item = widget.items[i];
            return CheckboxListTile(
              value: _selected[i],
              onChanged: (val) => setState(() => _selected[i] = val ?? false),
              title: Text(item['item_name'] ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${item['id_number'] ?? ''}'),
                  if (widget.showQuantity)
                    Row(
                      children: [
                        const Text('Qty: '),
                        SizedBox(
                          width: 50,
                          child: TextField(
                            controller: _qtyControllers[i],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              setState(() {
                                if (parsed != null && parsed > 0) {
                                  _qtyControllers[i].text = parsed.toString();
                                } else {
                                  _qtyControllers[i].text = '1';
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final selectedItems = <Map<String, dynamic>>[];
            for (int i = 0; i < widget.items.length; i++) {
              if (_selected[i]) {
                final item = widget.items[i];
                final qty = int.tryParse(_qtyControllers[i].text) ?? 1;
                selectedItems.add({
                  'id_number': item['id_number'],
                  'item_name': item['item_name'],
                  'quantity': qty,
                });
              }
            }
            Navigator.pop(context, selectedItems);
          },
          child: const Text('Add Selected'),
        ),
      ],
    );
  }
}

/// Dialog to add or edit an estimate item.
class AddEstimateItemDialog extends StatefulWidget {
  final List<PriceBookItem> priceBook;
  final String initialSection;
  final List<String> availableSections;
  final Future<List<estimate_item.EstimateItem>?> Function(String section, {ImageSource source}) onScanReceipt;
  final Future<void> Function() savePriceBook;
  final estimate_item.EstimateItem? initialItem;
  final bool showProfit;

  const AddEstimateItemDialog({
    required this.priceBook,
    required this.initialSection,
    required this.availableSections,
    required this.onScanReceipt,
    required this.savePriceBook,
    this.initialItem,
    this.showProfit = false,
    super.key,
  });

  @override
  State<AddEstimateItemDialog> createState() => _AddEstimateItemDialogState();
}

class _AddEstimateItemDialogState extends State<AddEstimateItemDialog> {
  late TextEditingController nameController;
  late TextEditingController descController;
  late TextEditingController priceController;
  late TextEditingController qtyController;
  late TextEditingController purchasePriceController;
  late TextEditingController markupController;
  late String section;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    nameController = TextEditingController(text: item?.name ?? '');
    descController = TextEditingController(text: item?.description ?? '');
    priceController = TextEditingController(text: item?.unitPrice.toString() ?? '');
    qtyController = TextEditingController(text: item?.quantity.toString() ?? '1');
    purchasePriceController = TextEditingController(text: item?.purchasePrice?.toString() ?? '');
    double markup = 0;
    if (item != null && item.purchasePrice != null && item.purchasePrice! > 0) {
      markup = ((item.unitPrice - item.purchasePrice!) / item.purchasePrice! * 100);
    }
    markupController = TextEditingController(text: markup.toStringAsFixed(1));
    section = widget.initialSection;
  }

  @override
  void dispose() {
    nameController.dispose();
    descController.dispose();
    priceController.dispose();
    qtyController.dispose();
    purchasePriceController.dispose();
    markupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialItem == null ? 'Add Item' : 'Edit Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: section,
              items: widget.availableSections.map((sec) {
                return DropdownMenuItem<String>(
                  value: sec,
                  child: Text(sec),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    section = val;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Section'),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unit Price'),
              onChanged: (val) {
                final buy = double.tryParse(purchasePriceController.text) ?? 0;
                final sell = double.tryParse(val) ?? 0;
                if (buy > 0) {
                  final percent = ((sell - buy) / buy * 100);
                  markupController.text = percent.toStringAsFixed(1);
                }
              },
            ),
            if (widget.showProfit) ...[
              TextField(
                controller: purchasePriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Purchase Price'),
                onChanged: (val) {
                  final buy = double.tryParse(val) ?? 0;
                  final sell = double.tryParse(priceController.text) ?? 0;
                  if (buy > 0) {
                    final percent = ((sell - buy) / buy * 100);
                    markupController.text = percent.toStringAsFixed(1);
                  }
                },
              ),
              TextField(
                controller: markupController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Profit %'),
                onChanged: (val) {
                  final buy = double.tryParse(purchasePriceController.text) ?? 0;
                  final percent = double.tryParse(val) ?? 0;
                  if (buy > 0) {
                    priceController.text = (buy * (1 + percent / 100)).toStringAsFixed(2);
                  }
                },
              ),
            ],
            TextField(
              controller: qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                final price = double.tryParse(priceController.text.trim()) ?? 0;
                final qty = double.tryParse(qtyController.text.trim()) ?? 1;
                final purchasePrice = double.tryParse(purchasePriceController.text.trim()) ?? 0;

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Item name is required')),
                  );
                  return;
                }

                final newItem = estimate_item.EstimateItem(
                  name: name,
                  description: desc,
                  unitPrice: price,
                  quantity: qty,
                  purchasePrice: widget.showProfit ? purchasePrice : null,
                  section: section,
                );

                await widget.savePriceBook();

                Navigator.pop(context, newItem);
              },
              child: Text(widget.initialItem == null ? 'Add Item' : 'Update Item'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class EstimateBuilderScreen extends StatefulWidget {
  final job_model.Job job;
  final EstimateTemplate? initialTemplate;
  final List<estimate_item.EstimateItem>? initialItems;
  final List<String>? initialSubsections;
  final void Function(GeneratedDocument doc)? onDocumentGenerated;
  final bool convertToInvoice; // <-- Add this

  const EstimateBuilderScreen({
    super.key,
    required this.job,
    this.initialTemplate,
    this.initialItems,
    this.initialSubsections,
    this.onDocumentGenerated,
    this.convertToInvoice = false, // <-- Add this
  });

  @override
  State<EstimateBuilderScreen> createState() => _EstimateBuilderScreenState();
}

class _EstimateBuilderScreenState extends State<EstimateBuilderScreen> with WidgetsBindingObserver, DocumentNamingMixin {
  List<estimate_item.EstimateItem> items = [];
  bool _showProfit = true;
  final bool _showLineItemPrices = true;
  final String _pin = '1234';
  final List<SubsectionData> _subsections = []; // <-- Change from List<String> to List<SubsectionData>
  List<PriceBookItem> priceBook = [];
  final Map<String, TextEditingController> _sectionSearchControllers = {};
  final Map<String, String> _sectionSearchQueries = {};
  final Map<String, FocusNode> _sectionSearchFocusNodes = {}; // Add this to your state
  Timer? _searchDebounce;
  Timer? _saveDebounce;
  String? _copiedSectionName;
  final List<estimate_item.EstimateItem> _copiedSectionItems = [];
  late List<EstimateTemplate> _templates;
  
  // Location tracking for template distance filtering
  Position? _currentPosition;
  bool _hasUnsavedChanges = false;

  final List<GeneratedDocument> generatedEstimates = [];
  final List<GeneratedDocument> generatedQuotes = [];
  bool _inProgressSaveCreatedThisSession = false; // Add this field to your _EstimateBuilderScreenState
  String? _currentInProgressId; // Track the current in-progress build ID
  final ScrollController _mainScrollController = ScrollController();

  // Initialize controllers immediately to avoid late initialization errors  
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerAddressController = TextEditingController();

  // Deposit system
  double? _depositAmount; // Fixed dollar amount
  double? _depositPercentage; // Percentage of main total
  bool _isDepositPercentage = false; // Track if it's percentage vs fixed amount

  Future<PdfColor> getPdfBannerColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_banner_color');
    if (colorString != null && colorString.startsWith('#') && colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 | (r * 255).toInt() << 16 | (g * 255).toInt() << 8 | (b * 255).toInt());
    }
    // Default: 
    return PdfColors.green400;
  }

  bool isOptionSection(List<SubsectionData> subsections, SubsectionData section) {
    final dividerIdx = subsections.indexWhere((s) => s.name == '---OPTIONS---');
    return dividerIdx != -1 && subsections.indexOf(section) > dividerIdx;
  }

  void _moveSubsectionBetweenMainAndOptions(SubsectionData section) {
    final isCurrentlyOption = isOptionSection(_subsections, section);
    final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');

    setState(() {
      _subsections.remove(section);
      if (isCurrentlyOption) {
        // Move to main (before divider)
        _subsections.insert(dividerIdx, section);
      } else {
        // Move to options (after divider)
        _subsections.insert(dividerIdx + 1, section);
      }
      _hasUnsavedChanges = true;
    });

    _saveInProgressEstimate();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Section moved!')),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInProgressIfExists();
    _initializeLocation();
  }

  Future<void> _loadInProgressIfExists() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('in_progress_estimate_${widget.job.id}');
    if (json != null) {
      final data = jsonDecode(json);
      setState(() {
        items = (data['items'] as List)
            .map((e) => estimate_item.EstimateItem.fromJson(e))
            .toList();
        _subsections
          ..clear()
          ..addAll((data['subsections'] as List)
              .map((s) => SubsectionData(name: s['name'] as String)));
        
        // Load deposit data
        _depositAmount = data['depositAmount'] as double?;
        _depositPercentage = data['depositPercentage'] as double?;
        _isDepositPercentage = data['isDepositPercentage'] as bool? ?? false;
        
        // Try to find the corresponding in-progress version in job.estimateVersions
        final inProgressVersions = widget.job.estimateVersions
            .where((v) => v.status == 'in_progress' && v.id != null && v.id!.startsWith('in_progress_${widget.job.id}'))
            .toList();
        if (inProgressVersions.isNotEmpty) {
          // Use the most recent in-progress version
          inProgressVersions.sort((a, b) => (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)));
          _currentInProgressId = inProgressVersions.first.id;
        }
      });
    } else if (widget.initialTemplate != null) {
      // Load template when coming from job details screen
      setState(() {
        items = List<estimate_item.EstimateItem>.from(widget.initialTemplate!.items.map((e) => e.copyWith()));
        _subsections
          ..clear()
          ..addAll(widget.initialTemplate!.subsections
              .map((s) => s is SubsectionData ? s : SubsectionData(name: s))
              .toList()
              .cast<SubsectionData>());
      });
    } else if (widget.initialItems != null) {
      items = List<estimate_item.EstimateItem>.from(widget.initialItems!);
    }
    
    // Handle initial subsections if provided separately
    if (widget.initialSubsections != null && widget.initialSubsections!.isNotEmpty) {
      setState(() {
        _subsections
          ..clear()
          ..addAll(widget.initialSubsections!.map((s) => SubsectionData(name: s)));
      });
    }
    // --- Ensure divider is present ---
    if (!_subsections.any((s) => s.name == '---OPTIONS---')) {
      _subsections.add(SubsectionData(name: '---OPTIONS---'));
    }
    _loadPriceBookFromDisk();
    _loadTemplates();

    // Set the text for the controllers instead of reassigning them
    _customerNameController.text = widget.job.customerName ?? '';
    _customerAddressController.text = widget.job.address ?? '';
    
    // Automatically save an initial in-progress version so it appears in job details
    // Only do this if we have some content (items or template loaded)
    if (items.isNotEmpty || widget.initialTemplate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _saveInProgressEstimate();
      });
    }
  }

  Future<void> _initializeLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition();
    } catch (e) {
      print('Error initializing location: $e');
    }
  }

  @override
  void dispose() {
    // Save in-progress estimate and pricebook before disposing
    _saveInProgressEstimate();
    _savePriceBookToDisk();
    
    _searchDebounce?.cancel();
    _saveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _customerNameController.dispose();
    _customerAddressController.dispose();
    _mainScrollController.dispose();
    for (final node in _sectionSearchFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Save in-progress estimate and pricebook when app goes to background or is paused
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveInProgressEstimate();
      _savePriceBookToDisk();
    }
  }

  /// Debounced save to avoid blocking UI with frequent saves (10 second delay)
  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 10), () {
      _saveInProgressEstimate();
    });
  }

  void _debouncedSearch(String sectionName, String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _sectionSearchQueries[sectionName] = query;
      });
    });
  }

  /// Fast update that doesn't trigger save immediately
  void _updateItemFast(estimate_item.EstimateItem oldItem, estimate_item.EstimateItem newItem) {
    final idx = items.indexOf(oldItem);
    if (idx != -1) {
      setState(() {
        items[idx] = newItem;
        _hasUnsavedChanges = true;
      });
      // Don't call _debouncedSave() here to keep it truly fast
    }
  }

  Future<void> _loadPriceBookFromDisk() async {
    // Perform memory cleanup before loading large dataset
    MemoryOptimizationService.performMaintenance();
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/price_book.json');
    if (await file.exists()) {
      try {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        
        // First, ensure hardcoded labour items (CAL, EST) are included
        List<dynamic> priorityItems = [];
        List<dynamic> otherItems = [];
        
        for (final item in jsonList) {
          if (item is Map<String, dynamic> && 
              (item['code'] == 'CAL' || item['code'] == 'EST')) {
            priorityItems.add(item);
          } else {
            otherItems.add(item);
          }
        }
        
        // Limit other items to prevent memory issues, but always include labour items
        final limitedOtherItems = otherItems.take(98).toList(); // Take 98 to leave room for 2 labour items
        final limitedJsonList = [...priorityItems, ...limitedOtherItems];
        
        setState(() {
          priceBook = limitedJsonList.map((e) => PriceBookItem.fromJson(e)).toList();
        });
        
        // Ensure hardcoded labour items are present even if not in file
        _ensureHardcodedLabourItems();
        
        print('📱 Loaded ${priceBook.length} price book items from disk (limited for memory, labour items prioritized)');
        
        // Suggest garbage collection after loading
        MemoryOptimizationService.suggestGC();
      } catch (e) {
        print('❌ Error loading price book: $e');
        setState(() {
          priceBook = [];
        });
        // Still ensure labour items are available even if loading fails
        _ensureHardcodedLabourItems();
      }
    } else {
      setState(() {
        priceBook = [];
      });
      // Ensure labour items are available even if no file exists
      _ensureHardcodedLabourItems();
    }
  }

  /// Ensures hardcoded labour items (CAL, EST) are always present in the estimate builder pricebook
  void _ensureHardcodedLabourItems() {
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
        ),
      ];

      for (final hardcodedItem in hardcodedItems) {
        final existingIndex = priceBook.indexWhere((item) => item.code == hardcodedItem.code);
        if (existingIndex == -1) {
          // Item doesn't exist, add it
          priceBook.add(hardcodedItem);
          print('✅ Added missing labour item: ${hardcodedItem.code}');
        }
      }
    } catch (e) {
      print('❌ Error ensuring hardcoded labour items: $e');
    }
  }

  void _addItemToSection(SubsectionData section) async {
    final item = await showDialog<estimate_item.EstimateItem>(
      context: context,
      builder: (context) => AddEstimateItemDialog(
        priceBook: priceBook,
        initialSection: section.name,
        availableSections: _subsections.map((s) => s.name).toList(),
        onScanReceipt: _scanReceipt,
        savePriceBook: _savePriceBookToDisk,
      ),
    );
    if (item != null) {
      int insertIdx = items.indexWhere((i) => i.section == section.name);
      setState(() {
        if (insertIdx == -1) {
          insertIdx = 0;
          items.insert(0, item);
        } else {
          items.insert(insertIdx, item);
        }
        _hasUnsavedChanges = true;
      });
      _saveInProgressEstimate();

      if (item.description == 'CAL') {
        DateTime selectedDate = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) selectedDate = picked;
        setState(() {
          final idx = items.lastIndexWhere((i) =>
  i.section == section && i.description == 'CAL'
);
          if (idx != -1) {
            final dateStr = '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
            items[idx] = items[idx].copyWith(
              name: 'Labour on $dateStr',
              description: 'Labour on $dateStr',
            );
          }
          _hasUnsavedChanges = true;
        });
      } else {
        _saveInProgressEstimate();
      }
    }
  }

  void _addSubsection() async {
    String? newSection;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Subsection'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Subsection name'),
            onChanged: (val) => newSection = val.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (newSection != null && newSection!.isNotEmpty && !_subsections.any((s) => s.name == newSection)) {
                  final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
                  setState(() {
                    // Insert before the divider, or at end if divider not found
                    if (dividerIdx == -1) {
                      _subsections.add(SubsectionData(name: newSection!));
                    } else {
                      _subsections.insert(dividerIdx, SubsectionData(name: newSection!));
                    }
                    _hasUnsavedChanges = true;
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showAddDepositDialog() async {
    final amountController = TextEditingController(
      text: _isDepositPercentage 
        ? (_depositPercentage?.toStringAsFixed(1) ?? '') 
        : (_depositAmount?.toStringAsFixed(2) ?? '')
    );
    bool isPercentage = _isDepositPercentage;
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set Deposit Amount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Radio<bool>(
                    value: false,
                    groupValue: isPercentage,
                    onChanged: (val) => setState(() => isPercentage = false),
                  ),
                  const Text('Fixed Amount (\$)'),
                ],
              ),
              Row(
                children: [
                  Radio<bool>(
                    value: true,
                    groupValue: isPercentage,
                    onChanged: (val) => setState(() => isPercentage = true),
                  ),
                  const Text('Percentage of Main Total (%)'),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isPercentage ? 'Percentage (%)' : 'Amount (\$)',
                  prefixText: isPercentage ? '' : '\$ ',
                  suffixText: isPercentage ? '%' : '',
                ),
                autofocus: true,
              ),
              if (isPercentage) ...[
                const SizedBox(height: 8),
                Text(
                  'Current amount: \$${(mainTotalIncGst * ((double.tryParse(amountController.text) ?? 0) / 100.0)).toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (_depositAmount != null || _depositPercentage != null)
              TextButton(
                onPressed: () => Navigator.pop(context, {'clear': true}),
                child: Text('Remove Deposit', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(amountController.text);
                if (value != null && value > 0) {
                  Navigator.pop(context, {
                    'isPercentage': isPercentage,
                    'value': value,
                  });
                }
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (result['clear'] == true) {
          _depositAmount = null;
          _depositPercentage = null;
          _isDepositPercentage = false;
        } else {
          _isDepositPercentage = result['isPercentage'];
          if (_isDepositPercentage) {
            _depositPercentage = result['value'];
            _depositAmount = null;
          } else {
            _depositAmount = result['value'];
            _depositPercentage = null;
          }
        }
        _hasUnsavedChanges = true;
      });
      _saveInProgressEstimate();
    }
  }

  void _deleteSubsection(SubsectionData section) {
    setState(() {
      _subsections.remove(section);
      items.removeWhere((item) => item.section == section.name);
      _hasUnsavedChanges = true;
    });
  }

  void _toggleProfitView() async {
    if (_showProfit) {
      setState(() => _showProfit = false);
    } else {
      final enteredPin = await showDialog<String>(
        context: context,
        builder: (context) {
          String pinInput = '';
          return AlertDialog(
            title: const Text('Enter PIN'),
            content: TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              onChanged: (val) => pinInput = val,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, pinInput),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      if (enteredPin == _pin) {
        setState(() => _showProfit = true);
      } else if (enteredPin != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect PIN')),
        );
      }
    }
  }

  Future<List<estimate_item.EstimateItem>?> _scanReceipt(String section, {ImageSource source = ImageSource.camera}) async {
    // First, let user select supplier template
    final selectedTemplate = await _showSupplierTemplateSelector();
    if (selectedTemplate == null) return null;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return null;

    final inputImage = InputImage.fromFile(File(pickedFile.path));
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

    final receiptText = recognizedText.text;
    textRecognizer.close();

    final extractedList = await _analyzeReceiptTextWithTemplate(receiptText, selectedTemplate);

    if (extractedList == null || extractedList is! List || extractedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items found on receipt.')),
      );
      return null;
    }

    // Check for missing id_number and warn user
    final missingIdItems = extractedList.where((item) =>
      (item['id_number'] == null || item['id_number'].toString().trim().isEmpty)
    ).toList();

    if (missingIdItems.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some items missing ID code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The following items do not have an ID code and will be skipped:'),
              ...missingIdItems.map((item) => Text(item['item_name'] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    // Only keep items with id_number for selection
    final filteredExtractedList = extractedList.where((item) =>
      item['id_number'] != null && item['id_number'].toString().trim().isNotEmpty
    ).toList();

    // If no items with id_number, show a warning and return
    if (filteredExtractedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items with ID code found.')),
      );
      return null;
    }

    final selectedItems = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => _SelectExtractedItemsDialogMulti(
        items: filteredExtractedList.cast<Map<String, dynamic>>(),
        showQuantity: true,
      ),
    );

    if (selectedItems != null && selectedItems.isNotEmpty) {
      final newItems = <estimate_item.EstimateItem>[];
      for (final item in selectedItems) {
        final id = (item['id_number'] ?? '').toString().trim();
        final name = (item['item_name'] ?? '').toString().trim();
        final qty = (item['quantity'] ?? 1) is int
            ? item['quantity']
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;

        PriceBookItem? pbItem;
        if (id.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull((pb) => normalizeCode(pb.code) == normalizeCode(id));
        }

        if (pbItem != null) {
          newItems.add(
            estimate_item.EstimateItem(
              name: pbItem.name,
              description: pbItem.code,
              unitPrice: pbItem.price,
              quantity: qty.toDouble(),
              purchasePrice: pbItem.purchasePrice,
              section: section,
            ),
          );
        } else {
          newItems.add(
            estimate_item.EstimateItem(
              name: name,
              description: id,
              unitPrice: 0,
              quantity: qty.toDouble(),
              purchasePrice: 0,
              section: section,
            ),
          );
        }
      }
      setState(() {
        // Find the first index of this section
        final idx = items.indexWhere((i) => i.section == section);
        if (idx == -1) {
          items.insertAll(0, newItems);
        } else {
          items.insertAll(idx, newItems);
        }
        _hasUnsavedChanges = true;
      });

      // Move CAL logic here, after adding items
      for (final item in newItems) {
        if (item.description == 'CAL') {
          DateTime selectedDate = DateTime.now();
          // ignore: use_build_context_synchronously
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) selectedDate = picked;
          setState(() {
            final idx = items.lastIndexWhere((i) =>
  i.section == section && i.description == 'CAL'
);
            if (idx != -1) {
              final dateStr = '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
              items[idx] = items[idx].copyWith(
                name: 'Labour on $dateStr',
                description: 'Labour on $dateStr',
              );
            }
            _hasUnsavedChanges = true;
          });
        }
      }

      _saveInProgressEstimate();
      return newItems;
    }
    return null;
  }

  Future<dynamic> _analyzeReceiptText(String text) async {
    const apiKey = 'REDACTED_OPENAI_KEY';
    final prompt = '''
You are reading a JA Russell invoice. Extract all line items as a JSON array.
For each item, return:
- "id_number": the Stock code (e.g. "100010"). 
  **Never use the Bin column. Never use the Name/Description column as the ID code, even if it contains numbers or codes. 
  The Stock code is always to the right of the Bin column and is numeric.**
- "item_name": the Name/Description (e.g. "1.5mm² TWIN & EARTH CABLE")
- "quantity": the Qty (as an integer)
- "net_price": the Net Price per unit (the purchase price from the "Net Price" column, as a decimal number)

Do NOT ignore the Net Price column - this is the purchase price and must be extracted accurately.

The Bin column is often the first column and may contain numbers or be blank. The Stock code is always the next column to the right of Bin and is numeric (e.g. "100010"). Do not use the Bin value as the Stock code.

Example input:
Bin  Stock code  Name/Description         Qty  Unit  B/ord  Price  Net Price  Extension
---  ----------  -----------------------  ---  ----  -----  -----  ---------  ---------
 12   100010      1.5mm² TWIN & EARTH CABLE  2   RL           45.00    45.00      90.00
      200020      10A SINGLE LIGHT SWITCH    5   EA           3.00     3.00       15.00

Example output:
[
  {"id_number": "100010", "item_name": "1.5mm² TWIN & EARTH CABLE", "quantity": 2, "net_price": 45.00},
  {"id_number": "200020", "item_name": "10A SINGLE LIGHT SWITCH", "quantity": 5, "net_price": 3.00}
]

If you can't find a code, quantity, or net_price, leave it blank or use 1 for quantity and 0 for net_price.

Now extract from this invoice text:
$text
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        "model": "gpt-3.5-turbo",
        "messages": [
          {"role": "user", "content": prompt}
        ],
        "max_tokens": 1000,
        "temperature": 0,
        "stop": ["]}"],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      try {
        final parsed = jsonDecode(content);
        return parsed;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read items from receipt.')),
        );
        return null;
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI error: ${response.body}')),
      );
      throw Exception('Failed to analyze receipt');
    }
  }

  /// Show supplier template selector dialog
  Future<String?> _showSupplierTemplateSelector() async {
    // Get selected supplier templates from settings
    final prefs = await SharedPreferences.getInstance();
    final selectedTemplatesString = prefs.getString('selected_supplier_templates') ?? '';
    final selectedTemplates = selectedTemplatesString.isNotEmpty 
        ? selectedTemplatesString.split(',')
        : <String>[];

    if (selectedTemplates.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Supplier Templates'),
          content: const Text(
            'No supplier templates are selected in settings. Please go to Settings > Company Settings > PDF Receipt Scanner to select your supplier templates.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Supplier Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose the supplier template for this receipt:'),
            const SizedBox(height: 16),
            ...selectedTemplates.map((template) => ListTile(
              title: Text(template),
              leading: const Icon(Icons.receipt_long),
              onTap: () => Navigator.pop(context, template),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Analyze receipt text with specific template
  Future<dynamic> _analyzeReceiptTextWithTemplate(String text, String templateName) async {
    // Load the specific template prompt
    String templatePrompt;
    try {
      final templateFile = await rootBundle.loadString('assets/receipt_templates/${templateName.toLowerCase().replaceAll(' ', '_')}.txt');
      final templateData = jsonDecode(templateFile) as List;
      templatePrompt = templateData.first['prompt'] as String;
    } catch (e) {
      // Fallback to default JA Russell template if template file not found
      templatePrompt = '''
You are reading a receipt/invoice. Extract all line items as a JSON array.
For each item, return:
- "id_number": the product/stock code 
- "item_name": the item description/name
- "quantity": the quantity (as an integer)
- "net_price": the unit price (as a decimal number)

If you can't find a code, quantity, or net_price, leave it blank or use 1 for quantity and 0 for net_price.

Now extract from this invoice text:
''';
    }

    const apiKey = 'REDACTED_OPENAI_KEY';
    final fullPrompt = templatePrompt.replaceAll(r'$text', text);

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4',
        'messages': [
          {'role': 'user', 'content': fullPrompt}
        ],
        'max_tokens': 2000,
        'temperature': 0,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      
      try {
        final parsed = jsonDecode(content);
        return parsed;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read items from receipt.')),
        );
        return null;
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI error: ${response.body}')),
      );
      throw Exception('Failed to analyze receipt');
    }
  }

  void _saveEstimate() async {
    try {
      widget.job.estimateItems
        ..clear()
        ..addAll(items.map((e) => estimate_item.EstimateItem(
              name: e.name,
              description: e.description,
              unitPrice: e.unitPrice,
              quantity: e.quantity,
              purchasePrice: e.purchasePrice,
              section: e.section,
            )));
      
      // Clean up in-progress data when estimate is finalized
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('in_progress_estimate_${widget.job.id}');
      
      // Remove in-progress EstimateBuild entry
      final builds = await loadAllEstimateBuilds();
      builds.removeWhere((b) => b.id == 'in_progress_${widget.job.id}');
      await saveAllEstimateBuilds(builds);
      
      setState(() {
        _hasUnsavedChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimate saved!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save estimate: $e')),
      );
    }
  }

  String normalize(String? s) =>
      (s ?? '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '')
        .replaceAll('\u200B', '')
        .replaceAll('\uFFFD', '')
        .trim();

  String normalizeCode(String? s) =>
      (s ?? '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '')
        .replaceAll('\u200B', '')
        .replaceAll('\uFFFD', '')
        .trim()
        .toLowerCase();

  void _onBarcodeScanned(String scannedBarcode, String section, TextEditingController searchController) async {
    final normalizedScanned = normalize(scannedBarcode);

    final matches = priceBook.where((item) => normalize(item.barcode) == normalizedScanned).toList();

    if (matches.length == 1) {
      final pbItem = matches.first;
      final existing = items.firstWhereOrNull(
        (e) => e.section == section && e.description == pbItem.code,
      );
      setState(() {
        // Increment usage count when item is used via barcode
        pbItem.usageCount = pbItem.usageCount + 1;
        
        if (existing != null) {
          final idx = items.indexOf(existing);
          items[idx] = existing.copyWith(quantity: existing.quantity + 1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Item already in $section, quantity increased by 1.')),
          );
        } else {
          items.add(
            estimate_item.EstimateItem(
              name: pbItem.name,
              description: pbItem.code,
              unitPrice: pbItem.price,
              quantity: 1,
              purchasePrice: pbItem.purchasePrice,
              section: section,
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added ${pbItem.name} to $section.')),
          );
        }
        searchController.clear();
        _sectionSearchQueries[section] = '';
      });
      // Save both estimate and pricebook after usage
      _saveInProgressEstimate();
      _savePriceBookToDisk();

      if (pbItem.code == 'CAL') {
        DateTime selectedDate = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) selectedDate = picked;
        setState(() {
          final idx = items.lastIndexWhere((i) => i.section == section && i.description == 'CAL');
          if (idx != -1) {
            final dateStr = '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
            items[idx] = items[idx].copyWith(
              name: 'Labour on $dateStr',
              description: 'Labour on $dateStr',
            );
          }
        });
        _saveInProgressEstimate();
      }
    } else if (matches.length > 1) {
      setState(() {
        searchController.text = scannedBarcode;
        _sectionSearchQueries[section] = scannedBarcode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Multiple items found, please select from search results.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No item found for this barcode.')),
      );
    }
  }

  Future<int> _getNextDocumentNumber() async {
    final prefs = await SharedPreferences.getInstance();
    int lastNumber = prefs.getInt('last_document_number') ?? 999;
    int nextNumber = lastNumber + 1;
    await prefs.setInt('last_document_number', nextNumber);
    return nextNumber;
  }

  Future<void> _generateEstimatePdf({required String type, required bool showLineItemPrices}) async {
    final prefs = await SharedPreferences.getInstance();
    final logoPath = prefs.getString('company_logo_path');
    final companyName = prefs.getString('company_name') ?? 'Your Company Name';
    final gstNumber = prefs.getString('gst_number') ?? 'GST Number';
    final companyAddress = prefs.getString('company_address') ?? 'Company Address';
    final isGstRegistered = prefs.getBool('is_gst_registered') ?? true;

    pw.Widget? logoWidget;
    if (logoPath != null && logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        final logoBytes = await logoFile.readAsBytes();
        final logoImage = pw.MemoryImage(logoBytes);
        logoWidget = pw.Image(logoImage, height: 60);
      }
    }

    final job = widget.job;
    final customerName = job.customerName ?? '';
    final customerAddress = job.address ?? '';
    final today = DateTime.now();
    final estimateOrQuoteValidUntil = today.add(const Duration(days: 30));
    final invoiceNumber = 'INV-${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}-${job.id}';

    String dueDateString = '';
    DateTime? dueDate;
    if (type == 'invoice') {
      dueDate = getInvoiceDueDate(job.paymentTerms);
      dueDateString = '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
    } else {
      dueDate = getEstimateOrQuoteDueDate();
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoWidget != null) logoWidget,
                  pw.SizedBox(height: 8),
                  pw.Text(companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text(companyAddress, style: const pw.TextStyle(fontSize: 10)),
                  if (isGstRegistered) pw.Text('GST: $gstNumber', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(type.toUpperCase(), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  if (type == 'invoice') ...[
                    pw.Text('Invoice #: $invoiceNumber', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Date: ${today.day}/${today.month}/${today.year}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Due: $dueDateString', style: const pw.TextStyle(fontSize: 10)),
                  ] else ...[
                    pw.Text('Date: ${today.day}/${today.month}/${today.year}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Valid until: ${estimateOrQuoteValidUntil.day}/${estimateOrQuoteValidUntil.month}/${estimateOrQuoteValidUntil.year}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Customer: $customerName', style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Address: $customerAddress', style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
          pw.SizedBox(height: 16),
          // --- Invoice table (all items) ---
          if (type == 'invoice' && items.isNotEmpty)
            pw.Table.fromTextArray(
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey900),
              headers: [
                'ID',
                'Name',
                'Qty',
                if (showLineItemPrices) 'Unit Price',
                if (showLineItemPrices && items.any((item) => (item.discountPercent ?? 0) >= 1))
                  'Discount',
                if (showLineItemPrices) 'Line Total',
              ],
              data: items.map((item) => [
                item.description,
                // For EST, show "Estimated Labour" in Estimate PDFs, else "Labour"
                (item.description == 'EST' && type == 'estimate') ? 'Estimated Labour' : item.name,
                formatQuantity(item.quantity),
                if (showLineItemPrices) '\$${item.unitPrice.toStringAsFixed(2)}',
                if (showLineItemPrices && (item.discountPercent ?? 0) >= 1)
                  '${item.discountPercent?.toStringAsFixed(1) ?? '0'}%',
                if (showLineItemPrices) '\$${_lineTotal(item).toStringAsFixed(2)}',
              ]).toList(),
            ),
          if (type == 'invoice') ...[
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  // Show subtotal only if GST is registered, otherwise show as "Total"
                  if (isGstRegistered)
                    pw.Text('Subtotal (ex GST): \$${subTotalExGst.toStringAsFixed(2)}'),
                  // Only show GST line if GST is registered
                  if (isGstRegistered)
                    pw.Text('GST (15%): \$${gstAmount.toStringAsFixed(2)}'),
                  // Show total with appropriate label
                  pw.Text(
                    isGstRegistered 
                      ? 'Total (inc GST): \$${totalIncGst.toStringAsFixed(2)}'
                      : 'Total: \$${subTotalExGst.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)
                  ),
                ],
              ),
            ),
          ],

          // --- Estimate/Quote logic (main sections + options as separate) ---
          if (type != 'invoice' && mainSections.isNotEmpty)
            ...mainSections.map((section) {
              final sectionItems = items.where((i) => i.section == section.name).toList();
              if (sectionItems.isEmpty) return pw.Container();
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(section.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Table.fromTextArray(
                    cellAlignment: pw.Alignment.centerLeft,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey900),
                    headers: [
                      'ID',
                      'Name',
                      'Qty',
                      if (showLineItemPrices) 'Unit Price',
                      if (showLineItemPrices && sectionItems.any((item) => (item.discountPercent ?? 0) >= 1))
                        'Discount',
                      if (showLineItemPrices) 'Line Total',
                    ],
                    data: sectionItems.map((item) => [
                      item.description,
                      // For EST, show "Estimated Labour" in Estimate PDFs, else "Labour"
                      (item.description == 'EST' && type == 'estimate') ? 'Estimated Labour' : item.name,
                      formatQuantity(item.quantity),
                      if (showLineItemPrices) '\$${item.unitPrice.toStringAsFixed(2)}',
                      if (showLineItemPrices && (item.discountPercent ?? 0) >= 1)
                        '${item.discountPercent?.toStringAsFixed(1) ?? '0'}%',
                      if (showLineItemPrices) '\$${_lineTotal(item).toStringAsFixed(2)}',
                    ]).toList(),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Section Total: \$${sectionItems.fold<double>(0, (sum, i) => sum + _lineTotal(i)).toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],
              );
            }),
          if (type != 'invoice' && mainSections.isNotEmpty)
            pw.Divider(),
          if (type != 'invoice' && mainSections.isNotEmpty)
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  // Show subtotal only if GST is registered, otherwise show as "Total"
                  if (isGstRegistered)
                    pw.Text('Subtotal (ex GST): \$${mainSubTotalExGst.toStringAsFixed(2)}'),
                  // Only show GST line if GST is registered
                  if (isGstRegistered)
                    pw.Text('GST (15%): \$${mainGstAmount.toStringAsFixed(2)}'),
                  // Show total with appropriate label
                  pw.Text(
                    isGstRegistered 
                      ? 'Total (inc GST): \$${mainTotalIncGst.toStringAsFixed(2)}'
                      : 'Total: \$${mainSubTotalExGst.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)
                  ),
                ],
              ),
            ),
          if (type != 'invoice' && optionSections.isNotEmpty)
            ...[
              pw.SizedBox(), // Add a gap before the banner
              pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 4),
              ),
              // --- Option sections ---
              ...optionSections.map((section) {
                final sectionItems = items.where((i) => i.section == section.name).toList();
                if (sectionItems.isEmpty) return pw.Container();
                final subtotal = sectionItems.fold<double>(0, (sum, i) => sum + i.unitPrice * i.quantity);
                final gst = subtotal * 0.15;
                final total = subtotal * 1.15;
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${section.name} (Option)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Table.fromTextArray(
                      cellAlignment: pw.Alignment.centerLeft,
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                      headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey900),
                      headers: [
                        'ID',
                        'Name',
                        'Qty',
                        if (showLineItemPrices) 'Unit Price',
                        if (showLineItemPrices && sectionItems.any((item) => (item.discountPercent ?? 0) >= 1))
                          'Discount',
                        if (showLineItemPrices) 'Line Total',
                      ],
                      data: sectionItems.map((item) => [
                        item.description,
                        // For EST, show "Estimated Labour" in Estimate PDFs, else "Labour"
                        (item.description == 'EST' && type == 'estimate') ? 'Estimated Labour' : item.name,
                        formatQuantity(item.quantity),
                        if (showLineItemPrices) '\$${item.unitPrice.toStringAsFixed(2)}',
                        if (showLineItemPrices && (item.discountPercent ?? 0) >= 1)
                          '${item.discountPercent?.toStringAsFixed(1) ?? '0'}%',
                        if (showLineItemPrices) '\$${_lineTotal(item).toStringAsFixed(2)}',
                      ]).toList(),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          // Show subtotal only if GST is registered, otherwise show as "Total"
                          if (isGstRegistered)
                            pw.Text('Option Subtotal: \$${subtotal.toStringAsFixed(2)}'),
                          // Only show GST line if GST is registered
                          if (isGstRegistered)
                            pw.Text('GST: \$${gst.toStringAsFixed(2)}'),
                          // Show total with appropriate label
                          pw.Text(
                            isGstRegistered 
                              ? 'Option Total: \$${total.toStringAsFixed(2)}'
                              : 'Option Total: \$${subtotal.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 12),
                  ],
                );
              }),
            ],
          if (type == 'invoice')
            ...[
              pw.SizedBox(),
              // ...bank details and payment info...
            ],
          if (type == 'estimate' || type == 'quote')
            ...[
              pw.SizedBox(),
              pw.Text('This $type is valid for 30 days from the date of issue.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              // Add deposit information and bank details for estimates and quotes
              if (currentDepositAmount > 0) ...[
                pw.SizedBox(),
                pw.Divider(),
                pw.SizedBox(),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                ),
              ],
            ],
        ],
      ),
    );

    // Get the next document number
    final docNumber = await _getNextDocumentNumber();
    String typeName;
    String documentNumber;
    switch (type) {
      case 'invoice':
        typeName = 'Invoice';
        documentNumber = 'INV-$docNumber';
        break;
      case 'quote':
        typeName = 'Quote';
        documentNumber = 'QUO-$docNumber';
        break;
      default:
        typeName = 'Estimate';
        documentNumber = 'EST-$docNumber';
    }
    
    // Generate standardized filename using the naming service
    final fileName = generateDocumentName(
      documentType: typeName,
      job: widget.job,
      existingAttachments: widget.job.attachments,
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    setState(() {
      // Only remove the specific in-progress version we're converting to final (if we know which one)
      if (_currentInProgressId != null) {
        widget.job.estimateVersions.removeWhere((v) => v.id == _currentInProgressId);
      }
    });

    final version = EstimateVersion(
      type: type,
      timestamp: DateTime.now(),
      items: List<estimate_item.EstimateItem>.from(items.map((e) => e.copyWith())),
      filePath: file.path,
      status: 'final',
      amount: totalIncGst,
      dueDate: dueDate,
      documentNumber: documentNumber,
      expiryDate: (type == 'estimate' || type == 'quote') ? estimateOrQuoteValidUntil : null, // <-- Save expiry for estimate/quote
      profit: type == 'invoice' ? totalProfit : 0.0, // <-- Save profit for invoice, ensure non-null
    );
    
    setState(() {
      widget.job.estimateVersions = List<EstimateVersion>.from(widget.job.estimateVersions);
      // Only remove the specific in-progress version we're converting to final (if we know which one)
      if (_currentInProgressId != null) {
        widget.job.estimateVersions.removeWhere((v) => v.id == _currentInProgressId);
      }
      widget.job.estimateVersions.add(version);
    });

    // Save the job to cloud after creating final estimate/quote/invoice
    await _persistJobToDisk();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('PDF Preview'),
            actions: [
              IconButton(
                icon: const Icon(Icons.file_upload),
                tooltip: 'Export PDF',
                onPressed: () async {
                  setState(() {
                    widget.job.attachments ??= [];
                    if (!widget.job.attachments!.contains(file.path)) {
                      widget.job.attachments!.add(file.path);
                    }
                  });
                  try {
                    await _persistJobToDisk();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PDF exported and job auto-saved!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to save job: $e')),
                      );
                    }
                  }
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: PdfPreview(
            build: (format) => pdf.save(),
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: false,
            allowSharing: false,
          ),
        ),
      ),
    );

    // Call this after generating any PDF (estimate, quote, invoice)
    if (widget.onDocumentGenerated != null) {
      widget.onDocumentGenerated!(
        GeneratedDocument(
          id: UniqueKey().toString(),
          jobId: widget.job.id,
          type: type[0].toUpperCase() + type.substring(1),
          name: widget.job.customerName ?? '',
          address: widget.job.address ?? '',
          dueDate: dueDate,
          amount: totalIncGst,
          isPaid: false,
          isArchived: false,
          generatedAt: DateTime.now(),
        ),
      );
    }
  }

  void onEstimatePdfGenerated(job_model.Job job, double amount, DateTime expireDate) {
    setState(() {
      generatedEstimates.add(GeneratedDocument(
        id: UniqueKey().toString(),
        jobId: job.id,
        type: 'Estimate',
        name: job.customerName ?? '',
        address: job.address ?? '',
        dueDate: expireDate,
        amount: amount,
        isPaid: false,
        isArchived: false,
        generatedAt: DateTime.now(),
      ));
    });
  }

  void onQuotePdfGenerated(job_model.Job job, double amount, DateTime expireDate) {
    setState(() {
      generatedQuotes.add(GeneratedDocument(
        id: UniqueKey().toString(),
        jobId: job.id,
        type: 'Quote',
        name: job.customerName ?? '',
        address: job.address ?? '',
        dueDate: expireDate,
        amount: amount,
        isPaid: false,
        isArchived: false,
        generatedAt: DateTime.now(),
      ));
    });
  }

  Future<void> _showGeneratePdfDialog() async {
    bool showLineItemPrices = await getShowLineItemPricesDefault();

    // Check for items with qty 0 or price 0
    final zeroQtyItems = items.where((item) => item.quantity == 0).toList();
    final zeroPriceItems = items.where((item) => item.unitPrice == 0 && normalizeCode(item.description) != 'dis').toList();

    bool proceed = true;
    if (zeroQtyItems.isNotEmpty || zeroPriceItems.isNotEmpty) {
      proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invalid Items'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (zeroQtyItems.isNotEmpty)
                ...zeroQtyItems.map((item) => Text('Item "${item.name}" has quantity 0', style: TextStyle(color: Theme.of(context).colorScheme.error))),
              if (zeroPriceItems.isNotEmpty)
                ...zeroPriceItems.map((item) => Text('Item "${item.name}" has \$0 amount', style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 12),
              const Text('Please fix these items before generating a PDF, or continue anyway.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue Anyway'),
            ),
          ],
        ),
      ) ?? false;
    }

    if (!proceed) return;

    final method = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => SimpleDialog(
            title: const Text('Generate PDF'),
            children: [
              CheckboxListTile(
                value: showLineItemPrices,
                onChanged: (val) => setState(() => showLineItemPrices = val ?? false),
                title: const Text('Show Line Item Prices'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'estimate'),
                child: Row(
                  children: const [
                    Icon(Icons.description), SizedBox(width: 8), Text('Estimate'),
                  ],
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'quote'),
                child: Row(
                  children: const [
                    Icon(Icons.request_quote), SizedBox(width: 8), Text('Quote'),
                  ],
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'invoice'),
                child: Row(
                  children: const [
                    Icon(Icons.receipt_long), SizedBox(width: 8), Text('Invoice'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (method != null) {
      await _generateEstimatePdf(type: method, showLineItemPrices: showLineItemPrices);
    }
  }
  List<PriceBookItem> searchPriceBook(
  List<PriceBookItem> priceBook,
  String query,
  {int maxResults = 10}
) {
  if (query.trim().isEmpty) return [];

  final q = query.trim().toLowerCase();

  // --- Any order of words search ---
  List<String> queryWords = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  bool matchesAllWords(String text) {
    final lower = text.toLowerCase();
    return queryWords.every((word) => lower.contains(word));
  }

  // 1. Exact code or name match
  final exact = priceBook.where((item) =>
    item.code.toLowerCase() == q || item.name.toLowerCase() == q
  ).toList();

  // 2. Most used (usageCount > 0, contains query)
  final mostUsed = priceBook.where((item) =>
    item.usageCount > 0 &&
    (item.code.toLowerCase().contains(q) || item.name.toLowerCase().contains(q))
  ).toList()
    ..sort((a, b) => b.usageCount.compareTo(a.usageCount));

  // 3. Starred close match (favorite items, contains query)
  final starred = priceBook.where((item) =>
    (item.favorite == true) &&
    (item.code.toLowerCase().contains(q) || item.name.toLowerCase().contains(q)) &&
    !exact.contains(item) && !mostUsed.contains(item)
  ).toList();

  // 4. Partial exact match (code or name contains query)
  final partial = priceBook.where((item) =>
    (item.code.toLowerCase().contains(q) || item.name.toLowerCase().contains(q)) &&
    !exact.contains(item) && !mostUsed.contains(item) && !starred.contains(item)
  ).toList();

  // 5. Any order of words in name (all words in any order)
  final anyOrder = priceBook.where((item) =>
    queryWords.length > 1 &&
    matchesAllWords(item.name) &&
    !exact.contains(item) && !mostUsed.contains(item) && !starred.contains(item) && !partial.contains(item)
  ).toList();

  // 6. Fuzzy match (Levenshtein distance <= 2)
  final fuzzy = priceBook.where((item) {
    final codeDist = levenshtein(item.code.toLowerCase(), q);
    final nameDist = levenshtein(item.name.toLowerCase(), q);
    return (codeDist <= 2 || nameDist <= 2) &&
      !exact.contains(item) && !mostUsed.contains(item) && !starred.contains(item) && !partial.contains(item) && !anyOrder.contains(item);
  }).toList();

  // Combine and limit
  final results = [
    ...exact,
    ...mostUsed,
    ...starred,
    ...partial,
    ...anyOrder,
    ...fuzzy,
  ];

  // Remove duplicates, keep order
  final seen = <String>{};
  final unique = <PriceBookItem>[];
  for (final item in results) {
    if (!seen.contains(item.code)) {
      unique.add(item);
      seen.add(item.code);
    }
    if (unique.length >= maxResults) break;
  }
  return unique;
}
  // Helper method to calculate the line total for an item, including discount
  double _lineTotal(estimate_item.EstimateItem item) {
    final discount = item.discountAmount ?? 0;
    return (item.unitPrice * item.quantity) - discount;
  }

  double _lineProfit(estimate_item.EstimateItem item) {
    final discount = item.discountAmount ?? 0;
    return ((item.unitPrice * item.quantity - discount) - ((item.purchasePrice ?? 0) * item.quantity));
  }

  @override
  Widget build(BuildContext context) {
  // Theme color variables
  final ColorScheme colorScheme = Theme.of(context).colorScheme;
  
  print('EstimateBuilderScreen build called');
  try {
    final sections = <String, List<estimate_item.EstimateItem>>{};
    for (var section in _subsections) {
      sections[section.name] = [];
    }
    for (var item in items) {
      if (sections.containsKey(item.section)) {
        sections[item.section]!.add(item);
      }
    }

    print('Building WillPopScope');
    return WillPopScope(
      onWillPop: () async {
        if (_hasUnsavedChanges) {
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text('You have unsaved changes. Save as in-progress draft before exiting?'),
              actions: [
                TextButton(
                  onPressed: () async {
                    // Only delete if we created the in-progress save this session
                    if (_inProgressSaveCreatedThisSession) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('in_progress_estimate_${widget.job.id}');
                    }
                    Navigator.pop(context, false); // Don't save
                  },
                  child: const Text("Don't Save"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, null), // Cancel
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _saveInProgressEstimate();
                    Navigator.pop(context, true); // Save
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (result == true) {
            return true;
          } else if (result == false) {
            return true;
          } else {
            return false;
          }
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: Icon(_showProfit ? Icons.visibility : Icons.visibility_off),
              tooltip: _showProfit ? 'Hide Profit' : 'Show ',
              onPressed: _toggleProfitView,
            ),
            // --- Add this block: Profit % icon, only when profit is visible ---
            if (_showProfit)
              IconButton(
                icon: const Icon(Icons.percent),
                tooltip: 'Set Profit % for All Items',
                onPressed: () async {
                  double? percent;
                  await showDialog(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController(text: '40');
                      return AlertDialog(
                        title: const Text('Set Profit Percentage'),
                        content: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Profit %'),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              percent = double.tryParse(controller.text);
                              Navigator.pop(context);
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      );
                    },
                  );
                  if (percent != null) {
                    setState(() {
                      items = items.map((item) {
                        // Only update if purchasePrice > 0
                        if ((item.purchasePrice ?? 0) > 0) {
                          final newUnitPrice = (item.purchasePrice! * (1 + percent! / 100));
                          return item.copyWith(unitPrice: double.parse(newUnitPrice.toStringAsFixed(2)));
                        }
                        return item;
                      }).toList();
                      _hasUnsavedChanges = true;
                    });
                    _saveInProgressEstimate();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Profit set to ${percent!.toStringAsFixed(1)}% for all items.')),
                    );
                  }
                },
              ),
            // --- End profit % icon block ---
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Generate PDF',
              onPressed: _showGeneratePdfDialog,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save Estimate',
              onPressed: _saveEstimate,
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today),
              tooltip: 'Location Timeline',
              onPressed: () async {
                // Build current estimate data
                final currentEstimate = {
                  'id': widget.job.id,
                  'customerName': _customerNameController.text,
                  'address': widget.job.address,
                  'date': DateTime.now().toIso8601String(),
                  'items': items.map((item) => {
                    'code': 'MANUAL', // Default code since EstimateItem doesn't have code
                    'name': item.name,
                    'quantity': item.quantity,
                    'unit': 'EA', // Default unit since EstimateItem doesn't have unit
                    'price': item.unitPrice,
                    'purchasePrice': item.purchasePrice ?? 0.0,
                    'subsection': item.section,
                    'groupCode': 'GENERAL', // Default group code since EstimateItem doesn't have groupCode
                  }).toList(),
                  'subsections': _subsections.map((s) => s.name).toList(),
                  'showLineItemPrices': false,
                };
                
                final labourItemData = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TimelineCalendarScreen(
                      targetEstimate: currentEstimate,
                    ),
                  ),
                );
                
                // If labour item data was returned, add it to the estimate
                if (labourItemData != null) {
                  setState(() {
                    // Check if Labour subsection exists, if not create it
                    if (!_subsections.any((s) => s.name == 'Labour')) {
                      // Insert at the top, before the options divider
                      final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
                      if (dividerIdx != -1) {
                        _subsections.insert(dividerIdx, SubsectionData(name: 'Labour'));
                      } else {
                        _subsections.insert(0, SubsectionData(name: 'Labour'));
                      }
                    }
                    
                    // Create the labour item
                    final labourItem = estimate_item.EstimateItem(
                      name: labourItemData['name'] ?? 'Labour',
                      description: labourItemData['code'] ?? 'CAL',
                      quantity: labourItemData['quantity']?.toDouble() ?? 1.0,
                      unitPrice: labourItemData['price']?.toDouble() ?? 90.0,
                      purchasePrice: labourItemData['purchasePrice']?.toDouble() ?? 0.0,
                      section: 'Labour',
                    );
                    
                    // Add the item to the list
                    items.add(labourItem);
                    _hasUnsavedChanges = true;
                  });
                  
                  // Auto-save the changes
                  _saveInProgressEstimate();
                  
                  // Show success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added ${labourItemData['quantity']}h of labour to estimate'),
                      backgroundColor: colorScheme.primary,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.bookmark),
              tooltip: 'Save as Template',
              onPressed: () async {
                String? templateName = await showDialog<String>(
                  context: context,
                  builder: (context) {
                    String name = '';
                    return AlertDialog(
                      title: const Text('Save Template'),
                      content: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Template Name'),
                        onChanged: (val) => name = val,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, name), child: const Text('Save')),
                      ],
                    );
                  },
                );
                if (templateName != null && templateName.trim().isNotEmpty) {
                  final trimmedName = templateName.trim();
                  setState(() {
                    _templates.removeWhere((t) => t.name == trimmedName);
                    _templates.add(EstimateTemplate(
                      name: trimmedName,
                      items: List<estimate_item.EstimateItem>.from(items.map((e) => e.copyWith())),
                      subsections: _subsections.map((s) => s.name).toList(),
                    ));
                    _hasUnsavedChanges = false;
                  });
                  await _saveTemplates();
                  await _loadTemplates();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Template "$trimmedName" saved!')),
                  );
                }
              },
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            controller: _mainScrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EditableHeader(
                    nameController: _customerNameController,
                    addressController: _customerAddressController,
                  ),
                  if (mainSections.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('Main Sections', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ...mainSections.map((section) { // <-- FIXED: use mainSections, not _subsections.where(...)
                    return DragTarget<SubsectionData>(
                      onWillAcceptWithDetails: (draggedSection) {
                        // Only allow drop if moving between main/options
                        return isOptionSection(_subsections, draggedSection.data) != isOptionSection(_subsections, section);
                      },
                      onAcceptWithDetails: (draggedSection) {
                        _moveSubsectionBetweenMainAndOptions(draggedSection.data);
                      },
                      builder: (context, candidateData, rejectedData) => LongPressDraggable<SubsectionData>(
                        data: section,
                        feedback: Material(
                          child: Card(
                            color: colorScheme.primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(section.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        child: buildSubsectionCard(section, _subsections.indexOf(section)),
                      ),
                    );
                  }),
                  // --- Main Totals ---
                  buildMainTotals(),
                  // --- Option Sections (below totals) ---
                  if (optionSections.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('Option Sections', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ...optionSections.expand((section) => [
                    buildSubsectionCard(section, _subsections.indexOf(section)),
                    buildOptionSectionTotals(section),
                  ]),
                  // --- Add this at the very end, after all sections and options ---
                  const SizedBox(height: 200),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final result = await showModalBottomSheet<String>(
              context: context,
              builder: (context) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('Add Subsection'),
                      onTap: () => Navigator.pop(context, 'add'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.add_box),
                      title: const Text('Add Option'),
                      onTap: () => Navigator.pop(context, 'add_option'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet),
                      title: const Text('Add Deposit Amount'),
                      onTap: () => Navigator.pop(context, 'add_deposit'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.paste),
                      title: const Text('Paste in Subsection'),
                      enabled: _copiedSectionItems.isNotEmpty,
                      onTap: _copiedSectionItems.isNotEmpty
                          ? () => Navigator.pop(context, 'paste')
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.paste),
                      title: const Text('Paste in Options'),
                      enabled: _copiedSectionItems.isNotEmpty,
                      onTap: _copiedSectionItems.isNotEmpty
                          ? () => Navigator.pop(context, 'paste_option')
                          : null,
                    ),
                  ],
                ),
              ),
            );
            if (result == 'add') {
              _addSubsection();
            } else if (result == 'add_option') {
      // --- Add Option logic ---
      String? newOption;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Add Option Subsection'),
            content: TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Option name'),
              onChanged: (val) => newOption = val.trim(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (newOption != null && newOption!.isNotEmpty && !_subsections.any((s) => s.name == newOption)) {
                    final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
                    setState(() {
                      // Only insert after the divider, never before
                      _subsections.insert(dividerIdx + 1, SubsectionData(name: newOption!));
                      _hasUnsavedChanges = true;
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
        
            } else if (result == 'add_deposit') {
              _showAddDepositDialog();
            } else if (result == 'paste') {
      setState(() {
        String newSection = _copiedSectionName ?? 'Section';
        int copyNum = 2;
        while (_subsections.any((s) => s.name == newSection)) {
          newSection = '${_copiedSectionName ?? 'Section'} ($copyNum)';
          copyNum++;
        }
        // Always paste as a main section (before the divider)
        final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
        _subsections.insert(dividerIdx == -1 ? _subsections.length : dividerIdx, SubsectionData(name: newSection));
        final newItems = _copiedSectionItems
            .map((item) => item.copyWith(section: newSection))
            .toList();
        items.addAll(newItems);
        _hasUnsavedChanges = true;
      });
      _saveInProgressEstimate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Section pasted!')),
      );
      setState(() {
        String newSection = _copiedSectionName ?? 'Option';
        int copyNum = 2;
        while (_subsections.any((s) => s.name == newSection)) {
          newSection = '${_copiedSectionName ?? 'Option'} ($copyNum)';
          copyNum++;
        }
        // Always paste as an option section (after the divider)
        final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
        _subsections.insert(dividerIdx == -1 ? _subsections.length : dividerIdx + 1, SubsectionData(name: newSection));
        final newItems = _copiedSectionItems
            .map((item) => item.copyWith(section: newSection))
            .toList();
        items.addAll(newItems);
        _hasUnsavedChanges = true;
      });
      _saveInProgressEstimate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Section pasted into options!')),
      );
    }
  },
        )
),
);
    // End of Scaffold
  } catch (e, stack) {
    print('Caught error in build: $e\n$stack');
    return Scaffold(
      body: Center(
        child: Text('Error: $e\n$stack'),
      ),
    );
  }
} // <-- End of build method

  /// Calculates the total discount for a list of estimate items.
  double sectionDiscountTotal(List<estimate_item.EstimateItem> items) {
    return items.fold(0.0, (sum, i) => sum + (i.unitPrice * i.quantity * ((i.discountPercent ?? 0) / 100.0)));
  }

  /// Calculates the profit for a single line item.
  // Removed duplicate _lineProfit method to resolve naming conflict.

  /// Widget to display main totals (Subtotal, GST, Total)
  Widget buildMainTotals() {
    final mainSectionItems = items.where((item) => mainSections.any((s) => s.name == item.section)).toList();
    final mainDiscount = sectionDiscountTotal(mainSectionItems);
    final mainSubtotal = mainSectionItems.fold<double>(0, (sum, i) => sum + i.unitPrice * i.quantity) - mainDiscount;
    final mainGst = mainSubtotal * 0.15;
    final mainTotal = mainSubtotal + mainGst;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FutureBuilder<bool>(
        future: SharedPreferences.getInstance().then((prefs) => prefs.getBool('is_gst_registered') ?? true),
        builder: (context, gstSnapshot) {
          final bool isGstRegistered = gstSnapshot.data ?? true;
          final double displayTotal = isGstRegistered ? mainTotal : mainSubtotal;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Always show subtotal when GST is registered, or show as "Total" when GST is disabled
              if (isGstRegistered)
                Text('Subtotal (ex GST): \$${mainSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
              // Only show GST line if GST is registered
              if (isGstRegistered)
                Text('GST (15%): \$${mainGst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
              // Show total with appropriate label
              Text(
                isGstRegistered 
                  ? 'Total (inc GST): \$${displayTotal.toStringAsFixed(2)}'
                  : 'Total: \$${displayTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
              ),
              if (mainDiscount.abs() > 0.01)
                Text('Discount Total: \$${mainDiscount.toStringAsFixed(2)}', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
              // ...inside buildMainTotals()
              if (_showProfit)
                Text(
                  'Total Profit: \$${mainSections.fold<double>(0, (sum, section) {
                    final sectionItems = items.where((item) => item.section == section.name).toList();
                    return sum + sectionItems.fold<double>(0, (s, i) => s + _lineProfit(i));
                  }).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    color: mainSections.fold<double>(0, (sum, section) {
                      final sectionItems = items.where((item) => item.section == section.name).toList();
                      return sum + sectionItems.fold<double>(0, (s, i) => s + _lineProfit(i));
                    }) < 0 ? Colors.red : Colors.green,
                  ),
                ),
              // Add deposit display (only for estimates and quotes)
              if (currentDepositAmount > 0)
                GestureDetector(
                  onTap: () => _showAddDepositDialog(),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Required Deposit: \$${currentDepositAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        if (_isDepositPercentage)
                          Text(
                            '(${_depositPercentage!.toStringAsFixed(1)}% of main total)',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap to edit deposit amount',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        // Add bank details below deposit
                        const Divider(height: 16),
                        FutureBuilder<String>(
                          future: SharedPreferences.getInstance().then((prefs) => 
                            prefs.getString('bank_details') ?? 'Bank: 00-0000-0000000-00\nReference: Invoice Number'),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Text(
                                snapshot.data!,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                textAlign: TextAlign.right,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Widget to display totals for an option section
  Widget buildOptionSectionTotals(SubsectionData section) {
    final sectionItems = items.where((item) => item.section == section.name).toList();
    if (sectionItems.isEmpty) return const SizedBox.shrink();

    final subtotal = sectionItems.fold<double>(0, (sum, i) => sum + i.unitPrice * i.quantity);
    final discount = sectionDiscountTotal(sectionItems);
    final gst = (subtotal - discount) * 0.15;
    final total = (subtotal - discount) + gst;
    final profit = sectionItems.fold<double>(0, (sum, i) => sum + _lineProfit(i));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FutureBuilder<bool>(
        future: SharedPreferences.getInstance().then((prefs) => prefs.getBool('is_gst_registered') ?? true),
        builder: (context, gstSnapshot) {
          final bool isGstRegistered = gstSnapshot.data ?? true;
          final double displayTotal = isGstRegistered ? total : (subtotal - discount);
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Show discount if exists
              if (discount.abs() > 0.01)
                Text('Discount: -\$${discount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontSize: 16)),
              // Always show subtotal when GST is registered
              if (isGstRegistered)
                Text('Subtotal (ex GST): \$${(subtotal - discount).toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
              // Only show GST line if GST is registered
              if (isGstRegistered)
                Text('GST (15%): \$${gst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
              // Show total with appropriate label
              Text(
                isGstRegistered 
                  ? 'Total (inc GST): \$${displayTotal.toStringAsFixed(2)}'
                  : 'Total: \$${displayTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
              ),
              if (_showProfit)
                Text(
                  'Total Profit: \$${profit.toStringAsFixed(2)}', 
                  style: TextStyle(
                    fontSize: 16,
                    color: profit < 0 ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  )
                ),
            ],
          );
        },
      ),
    );
  }

  Widget buildSubsectionsList() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Main Sections
      if (mainSections.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Main Sections', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ...mainSections.map((section) => buildSubsectionCard(section, _subsections.indexOf(section))),
      // Main Totals
      buildMainTotals(),
      // Option Sections
      if (optionSections.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Option Sections', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ...optionSections.map((section) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildSubsectionCard(section, _subsections.indexOf(section)),
          buildOptionSectionTotals(section),
        ],
      )),
    ],
  );
}

  Future<void> _showTemplateSelector() async {
    if (_templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No templates available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Template'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final template = _templates[index];
                return ListTile(
                  title: Text(template.name),
                  subtitle: Text('${template.subsections.length} subsections'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _applyTemplate(template);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Applied template: ${template.name}')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _applyTemplate(EstimateTemplate template) {
    setState(() {
      items = List<estimate_item.EstimateItem>.from(template.items.map((e) => e.copyWith()));
      _subsections
        ..clear()
        ..addAll(template.subsections
            .map((s) => s is SubsectionData ? s : SubsectionData(name: s))
            .toList()
            .cast<SubsectionData>());
    });
    _saveInProgressEstimate();
  }

  Future<void> _loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('estimate_templates') ?? [];
    setState(() {
      _templates = jsonList.map((s) => EstimateTemplate.fromJson(jsonDecode(s))).toList();
    });
  }

Future<void> _saveTemplates() async {
  final prefs = await SharedPreferences.getInstance();
  final jsonList = _templates.map((t) => jsonEncode(t.toJson())).toList();
  await prefs.setStringList('estimate_templates', jsonList);
}

Future<void> _savePriceBookToDisk() async {
  try {
    // Save to local file first
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/price_book.json');
    final jsonList = priceBook.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));

    // Also sync to cloud if Firebase is available and user is authenticated
    try {
      if (FirestoreService.isAuthenticated) {
        // Convert to PriceBookItem models for Firestore - use correct field names
        final firestoreItems = priceBook.map((item) => models.PriceBookItem(
          code: item.code,
          name: item.name,
          category: item.groupCode, // groupCode maps to category
          purchasePrice: item.purchasePrice,
          salePrice: item.price, // price maps to salePrice
          unit: item.unit,
          description: '', // Default empty description as it's not in local model
          favorite: item.favorite,
          usageCount: item.usageCount,
        )).toList();
        
        // Use static method for batch sync
        await FirestoreService.batchSavePriceBookItems(firestoreItems);
        print('✅ Pricebook synced to cloud (${firestoreItems.length} items)');
      }
    } catch (e) {
      print('Cloud sync failed, but local save succeeded: $e');
      // Don't throw - local save is more important
    }
  } catch (e) {
    print('❌ Failed to save pricebook: $e');
    // You might want to show a snackbar here if context is available
  }
}

  Future<String?> _scanBarcode() async {
    bool scanned = false;
    return await Navigator.push<String>(

      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan Barcode')),
          body: MobileScanner(
            onDetect: (capture) {
              if (scanned) return;
              final barcode = capture.barcodes.first.rawValue;
              if (barcode != null && barcode.isNotEmpty) {
                scanned = true;
                if (Navigator.of(_).canPop()) {
                  Navigator.pop(_, barcode);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _confirmDeleteSubsection(SubsectionData section) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subsection'),
        content: Text(
          'Are you sure you want to delete the subsection "${section.name}"? '
          'All items in this section will also be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      _deleteSubsection(section);
    }
  }

  Future<void> _showAddItemMethodDialog(SubsectionData section) async {
    final method = await showDialog<String>(
           context: context,
      builder: (context) => SimpleDialog(
        title: Text('Add Item to ${section.name}'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              final source = await showDialog<ImageSource?>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('Scan Receipt'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, ImageSource.camera),
                      child: Row(
                        children: const [
                          Icon(Icons.camera_alt), SizedBox(width: 8), Text('Camera'),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, ImageSource.gallery),
                      child: Row(
                        children: const [
                          Icon(Icons.photo_library), SizedBox(width: 8), Text('Gallery'),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                        if (result != null && result.files.single.path != null) {
                          final file = File(result.files.single.path!);
                          final text = await extractTextFromPdf(file);
                          await _scanReceiptFromText(section.name, text);
                        }
                        Navigator.pop(context);
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.picture_as_pdf), SizedBox(width: 8), Text('Scan from PDF'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              Navigator.pop(context);
              if (source != null) {
                await _scanReceipt(section.name, source: source);
              }
            },
            child: Row(
              children: const [
                Icon(Icons.receipt_long), SizedBox(width: 8), Text('Scan Receipt'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: Row(
              children: const [
                Icon(Icons.edit), SizedBox(width: 8), Text('Manual Entry'),
              ],
                       ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
              if (result != null && result.files.single.path != null) {
                final file = File(result.files.single.path!);
                final text = await extractTextFromPdf(file);
                await _scanReceiptFromText(section.name, text);
              }
              Navigator.pop(context);
            },
            child: Row(
              children: const [
                Icon(Icons.picture_as_pdf), SizedBox(width: 8), Text('Scan from PDF'),
              ],
            ),
          ),
        ],
      ),
    );

    if (method == 'manual') {
      _addItemToSection(section);
    }
 }

/// Add this method to handle scanned receipt text from PDF
Future<void> _scanReceiptFromText(String section, String text) async {
  // Do NOT call _scanReceipt here!
  final extractedList = await _analyzeReceiptText(text);

  if (extractedList == null || extractedList is! List || extractedList.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No items found on receipt.')),
    );
    return;
  }

  // Check for missing id_number and warn user
  final missingIdItems = extractedList.where((item) =>
    (item['id_number'] == null || item['id_number'].toString().trim().isEmpty)
  ).toList();

  if (missingIdItems.isNotEmpty) {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Some items missing ID code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The following items do not have an ID code and will be skipped:'),
            ...missingIdItems.map(( item) => Text(item['item_name'] ?? '', style: const TextStyle(color: Colors.red))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Only keep items with id_number for selection
  final filteredExtractedList = extractedList.where((item) =>
    item['id_number'] != null && item['id_number'].toString().trim().isNotEmpty
  ).toList();

  // If no items with id_number, show a warning and return
  if (filteredExtractedList.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No items with ID code found.')),
    );
    return;
  }

  final selectedItems = await showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (context) => _SelectExtractedItemsDialogMulti(
      items: filteredExtractedList.cast<Map<String, dynamic>>(),
      showQuantity: true,
    ),
  );

  if (selectedItems != null && selectedItems.isNotEmpty) {
    final newItems = <estimate_item.EstimateItem>[];
    for (final item in selectedItems) {
      final id = (item['id_number'] ?? '').toString().trim();
      final name = (item['item_name'] ?? '').toString().trim();
      final qty = (item['quantity'] ?? 1) is int
          ? item['quantity']
          : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
      final netPrice = (item['net_price'] != null) 
          ? double.tryParse(item['net_price'].toString()) ?? 0.0
          : 0.0;

      PriceBookItem? pbItem;
      if (id.isNotEmpty) {
        pbItem = priceBook.firstWhereOrNull((pb) => normalizeCode(pb.code) == normalizeCode(id));
      }
      // Fallback: Try matching by name if not found by code
      if (pbItem == null && name.isNotEmpty) {
        pbItem = priceBook.firstWhereOrNull(
          (pb) => pb.name.trim().toLowerCase() == name.toLowerCase(),
        );
      }

      if (pbItem != null) {
        // Item found in pricebook - use pricebook sale price but receipt net price as purchase price
        newItems.add(
          estimate_item.EstimateItem(
            name: pbItem.name,
            description: pbItem.code,
            unitPrice: pbItem.price, // Use pricebook sale price
            quantity: qty.toDouble(),
            purchasePrice: netPrice > 0 ? netPrice : pbItem.purchasePrice, // Use receipt net price if available, fallback to pricebook
            section: section,
          ),
        );
      } else {
        // Item not found in pricebook - use receipt net price as both sale and purchase price
        newItems.add(
          estimate_item.EstimateItem(
            name: name,
            description: id,
            unitPrice: netPrice > 0 ? netPrice : 0, // Use net price as sale price if not found in pricebook
            quantity: qty.toDouble(),
            purchasePrice: netPrice > 0 ? netPrice : 0, // Use net price as purchase price
            section: section,
          ),
        );
      }
    }
    setState(() {
      items.addAll(newItems);
      _hasUnsavedChanges = true;
    });

    // Move CAL logic here, after adding items
    for (final item in newItems) {
      if (item.description == 'CAL') {
        DateTime selectedDate = DateTime.now();
        // ignore: use_build_context_synchronously
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) selectedDate = picked;
        setState(() {
          final idx = items.lastIndexWhere((i) =>
  i.section == section && i.description == 'CAL'
);
          if (idx != -1) {
              final dateStr = '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
              items[idx] = items[idx].copyWith(
                name: 'Labour on $dateStr',
                description: 'Labour on $dateStr',
              );
            }
        });
      }
    }

    _saveInProgressEstimate();
  }
}

  /// Save the current estimate as an in-progress
  Future<void> _saveInProgressEstimate() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save the current state to SharedPreferences for quick local reload
    await prefs.setString(
      'in_progress_estimate_${widget.job.id}',
      jsonEncode({
        'items': items.map((e) => e.toJson()).toList(),
        'subsections': _subsections.map((s) => {'name': s.name}).toList(),
        'depositAmount': _depositAmount,
        'depositPercentage': _depositPercentage,
        'isDepositPercentage': _isDepositPercentage,
      }),
    );
    
    // Update job.estimateVersions with a draft (this is what gets displayed and synced to cloud)
    final inProgressId = 'in_progress_${widget.job.id}_${DateTime.now().millisecondsSinceEpoch}';
    final draft = EstimateVersion(
      id: inProgressId, // Unique ID for this in-progress estimate
      type: 'estimate',
      timestamp: DateTime.now(),
      items: List<estimate_item.EstimateItem>.from(items.map((e) => e.copyWith())),
      filePath: null,
      status: 'in_progress',
      amount: mainTotalIncGst,
      dueDate: null,
      documentNumber: null,
      expiryDate: null,
      profit: 0.0,
    );
    
    setState(() {
      // Don't remove existing in-progress versions - allow multiple in-progress builds per job
      // Add the new in-progress version
      widget.job.estimateVersions.add(draft);
      _hasUnsavedChanges = false;
      _inProgressSaveCreatedThisSession = true;
      _currentInProgressId = inProgressId; // Track which in-progress build we're working on
      
      print('🔍 DEBUG: Added in-progress build to job.estimateVersions');
      print('🔍 DEBUG: Total estimateVersions count: ${widget.job.estimateVersions.length}');
      print('🔍 DEBUG: In-progress versions count: ${widget.job.estimateVersions.where((v) => v.status == 'in_progress').length}');
      print('🔍 DEBUG: New in-progress ID: $inProgressId');
    });
    
    // Save job to both local and cloud (this persists the EstimateVersion)
    await _persistJobToDisk();
    print('✅ In-progress estimate saved to SharedPreferences and job synced to cloud');
  }

  /// Persist the job to disk and cloud
  Future<void> _persistJobToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      
      // Save individual job file for backward compatibility
      final jobFile = File('${dir.path}/job_${widget.job.id}.json');
      await jobFile.writeAsString(jsonEncode(widget.job.toJson()));
      
      // CRITICAL: Also update the main jobs.json file that the app uses
      final mainJobsFile = File('${dir.path}/jobs.json');
      if (await mainJobsFile.exists()) {
        try {
          final jsonString = await mainJobsFile.readAsString();
          final List<dynamic> jsonList = jsonDecode(jsonString);
          
          // Find and update this job in the main list
          final jobIndex = jsonList.indexWhere((j) => j['id'] == widget.job.id);
          if (jobIndex != -1) {
            jsonList[jobIndex] = widget.job.toJson();
            await mainJobsFile.writeAsString(jsonEncode(jsonList));
            print('✅ Updated job in main jobs.json file');
          } else {
            // Add job if not found
            jsonList.add(widget.job.toJson());
            await mainJobsFile.writeAsString(jsonEncode(jsonList));
            print('✅ Added new job to main jobs.json file');
          }
        } catch (e) {
          print('❌ Error updating main jobs.json: $e');
          // Create new jobs.json if corrupted
          await mainJobsFile.writeAsString(jsonEncode([widget.job.toJson()]));
        }
      } else {
        // Create new jobs.json file if it doesn't exist
        await mainJobsFile.writeAsString(jsonEncode([widget.job.toJson()]));
        print('✅ Created new jobs.json file');
      }
      
      // Save to cloud using Firestore
      await FirestoreService.saveJob(widget.job);
      
      print('✅ Job saved locally and to cloud with in-progress estimate');
    } catch (e) {
      print('❌ Error persisting job: $e');
      // Don't throw - local save is still important
    }
  }

  /// Show comprehensive GPS site history with address validation and labour tracking
  Future<void> _showGpsHistoryScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GpsHistoryScreen(
          job: widget.job,
          onLabourAdded: (labourItem) {
            setState(() {
              // Find or create Labour subsection
              var labourSectionName = 'Labour';
              if (!_subsections.any((s) => s.name == labourSectionName)) {
                // Add Labour section at the top (before divider)
                final dividerIdx = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
                _subsections.insert(dividerIdx == -1 ? 0 : dividerIdx, SubsectionData(name: labourSectionName));
              }
              
              // Add the labour item
              items.add(labourItem.copyWith(section: labourSectionName));
              _hasUnsavedChanges = true;
            });
            _saveInProgressEstimate();
          },
        ),
      ),
    );
  }

  /// Get site visit history based on GPS proximity to job address
  Future<List<Map<String, dynamic>>> _getSiteVisitHistory() async {
    final List<Map<String, dynamic>> visitHistory = [];
    
    // If no address is set, return empty history
    if (widget.job.address == null || widget.job.address!.isEmpty) {
      return visitHistory;
    }
    
    try {
      // Get site coordinates from address using geocoding
      final siteCoordinates = await _getCoordinatesFromAddress(widget.job.address!);
      if (siteCoordinates == null) return visitHistory;
      
      // Load stored GPS history from device
      final storedHistory = await _loadGpsHistoryFromStorage();
      
      // Filter GPS history for visits to this address within specified range
      for (final entry in storedHistory) {
        final entryLat = entry['latitude'] as double?;
        final entryLng = entry['longitude'] as double?;
        final timestamp = entry['timestamp'] as DateTime?;
        
        if (entryLat != null && entryLng != null && timestamp != null) {
          final distance = _calculateDistance(
            entryLat,
            entryLng,
            siteCoordinates['lat']!,
            siteCoordinates['lng']!,
          );
          
          // Only include visits within proximity range (use dynamic radius)
          if (distance <= 100) { // TODO: This should use _proximityRadius from GPS history screen
            visitHistory.add({
              'arrivalTime': timestamp,
              'departureTime': entry['departureTime'],
              'duration': entry['duration'],
              'distance': distance,
              'isCurrentVisit': false,
            });
          }
        }
      }
      
      // Check if currently on site
      if (_currentPosition != null) {
        final currentDistance = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          siteCoordinates['lat']!,
          siteCoordinates['lng']!,
        );
        
        // If currently within range, add current visit
        if (currentDistance <= 100) {
          visitHistory.insert(0, {
            'arrivalTime': DateTime.now().subtract(const Duration(minutes: 30)), // Estimate arrival
            'departureTime': null, // Still on site
            'duration': null,
            'distance': currentDistance,
            'isCurrentVisit': true,
          });
        }
      }
      
      // Sort by most recent first
      visitHistory.sort((a, b) => (b['arrivalTime'] as DateTime).compareTo(a['arrivalTime'] as DateTime));
      
    } catch (e) {
      print('Error getting site visit history: $e');
    }
    
    return visitHistory;
  }

  /// Get coordinates from address using geocoding
  Future<Map<String, double>?> _getCoordinatesFromAddress(String address) async {
    try {
      // Use geocoding package to convert address to coordinates
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return {'lat': locations.first.latitude, 'lng': locations.first.longitude};
      }
      return null;
    } catch (e) {
      print('Error geocoding address: $e');
      return null;
    }
  }

  /// Load GPS history from local storage
  Future<List<Map<String, dynamic>>> _loadGpsHistoryFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;
      
      print('Loading GPS history from storage: ${historyList.length} entries found');
      
      final result = historyList.map((entry) {
        return {
          'latitude': entry['latitude'] as double?,
          'longitude': entry['longitude'] as double?,
          'timestamp': entry['timestamp'] != null ? DateTime.parse(entry['timestamp']) : null,
          'departureTime': entry['departureTime'] != null ? DateTime.parse(entry['departureTime']) : null,
          'duration': entry['duration'] as String?,
          'address': entry['address'] as String?,
        };
      }).toList();
      
      print('Converted ${result.length} entries for timeline display');
      return result;
    } catch (e) {
      print('Error loading GPS history: $e');
      return [];
    }
  }

  /// Save GPS visit to storage
  Future<void> _saveGpsVisit({
    required double latitude,
    required double longitude,
    required DateTime arrivalTime,
    DateTime? departureTime,
    String? duration,
    String? address,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingHistory = await _loadGpsHistoryFromStorage();
      
      // Add new visit
      existingHistory.add({
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': arrivalTime.toIso8601String(),
        'departureTime': departureTime?.toIso8601String(),
        'duration': duration,
        'address': address,
      });
      
      // Keep only last 100 visits to prevent storage bloat
      if (existingHistory.length > 100) {
        existingHistory.removeRange(0, existingHistory.length - 100);
      }
      
      await prefs.setString('gps_visit_history', jsonEncode(existingHistory));
    } catch (e) {
      print('Error saving GPS visit: $e');
    }
  }

  /// Start background GPS tracking (call this when app starts)
  Future<void> _startGpsTracking() async {
    // Check permissions first
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final newPermission = await Geolocator.requestPermission();
      if (newPermission == LocationPermission.denied || newPermission == LocationPermission.deniedForever) {
        return;
      }
    }
    
    // Start position stream for background tracking
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // Only update every 50 meters
        timeLimit: Duration(minutes: 5),
      ),
    ).listen((Position position) {
      _handleLocationUpdate(position);
    });
  }

  /// Handle location updates for automatic visit tracking
  Future<void> _handleLocationUpdate(Position position) async {
    // This would implement logic to detect when you arrive/leave locations
    // For now, just update current position
    setState(() {
      _currentPosition = position;
    });
  }

  /// Debug method to check GPS history data
  Future<void> _debugGpsHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      print('🔍 DEBUG GPS History Raw JSON length: ${historyJson.length}');
      print('🔍 DEBUG GPS History Raw JSON: ${historyJson.substring(0, math.min(500, historyJson.length))}...');
      
      final historyList = jsonDecode(historyJson) as List;
      print('🔍 DEBUG GPS History List length: ${historyList.length}');
      
      if (historyList.isNotEmpty) {
        print('🔍 DEBUG First GPS entry: ${historyList.first}');
      }
    } catch (e) {
      print('❌ DEBUG GPS History Error: $e');
    }
  }

  /// Test geocoding and add current location to GPS history
  Future<void> _testGeocodingAndLocation() async {
    try {
      // First debug the GPS history data
      await _debugGpsHistory();
      
      // 1. Test geocoding first
      if (widget.job.address == null || widget.job.address!.isEmpty) {
        print('❌ No job address to test geocoding');
        return;
      }
      
      print('🧪 Testing geocoding for address: ${widget.job.address}');
      final siteCoordinates = await _getCoordinatesFromAddress(widget.job.address!);
      
      if (siteCoordinates == null) {
        print('❌ Geocoding failed - could not convert address to coordinates');
        return;
      }
      
      print('✅ Geocoding successful!');
      print('   Address: ${widget.job.address}');
      print('   Latitude: ${siteCoordinates['lat']}');
      print('   Longitude: ${siteCoordinates['lng']}');
      
      // 2. Get current real location
      print('📍 Getting current device location...');
      
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions permanently denied');
        return;
      }

      final currentPosition = await Geolocator.getCurrentPosition();
      print('✅ Current location obtained!');
      print('   Your Latitude: ${currentPosition.latitude}');
      print('   Your Longitude: ${currentPosition.longitude}');
      
      // 3. Calculate distance to job site
      final distance = _calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        siteCoordinates['lat']!,
        siteCoordinates['lng']!,
      );
      
      print('📏 Distance to job site: ${distance.toStringAsFixed(1)} meters');
      
      // 4. Save current location as a GPS visit for testing
      await _saveGpsVisit(
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
        arrivalTime: DateTime.now().subtract(const Duration(hours: 1)),
        departureTime: DateTime.now(),
        duration: '1.0',
        address: 'Current location test',
      );
      
      print('✅ Added current location to GPS history');
      print('🎯 Test complete! Check GPS history screen to see if it shows up.');
      
    } catch (e) {
      print('❌ Error during geocoding/location test: $e');
    }
  }

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // Helper functions for EstimateBuild management
  Future<List<EstimateBuild>> loadAllEstimateBuilds() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('estimate_builds') ?? [];
    return jsonList.map((s) => EstimateBuild.fromJson(jsonDecode(s))).toList();
  }

  Future<void> addOrUpdateEstimateBuild(EstimateBuild build) async {
    final builds = await loadAllEstimateBuilds();
    // Remove any existing build with the same id
    builds.removeWhere((b) => b.id == build.id);
    builds.add(build);
    await saveAllEstimateBuilds(builds);
  }

  Future<void> saveAllEstimateBuilds(List<EstimateBuild> builds) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = builds.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList('estimate_builds', jsonList);
  }

  double get gstAmount => subTotalExGst * 0.15;
  double get totalIncGst => subTotalExGst * 1.15;
  double get totalProfit => items.fold(0.0, (sum, item) => sum + ((normalizeCode(item.description) == 'dis' ? -item.unitPrice : (item.unitPrice - (item.purchasePrice ?? 0))) * item.quantity));
  double get subTotalExGst => items.fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));
  double get mainSubTotalExGst => items
      .where((item) => mainSections.any((s) => s.name == item.section))
      .fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));
  double get mainGstAmount => mainSubTotalExGst * 0.15;
  double get mainTotalIncGst => mainSubTotalExGst * 1.15;

  double get currentDepositAmount {
    if (_depositAmount != null && !_isDepositPercentage) {
      return _depositAmount!;
    } else if (_depositPercentage != null && _isDepositPercentage) {
      return mainTotalIncGst * (_depositPercentage! / 100.0);
    }
    return 0.0;
  }

  Future<bool> getShowLineItemPricesDefault() async {
    // You can customize this logic, e.g. load from SharedPreferences if needed
    return true;
  }

List<SubsectionData> get mainSections {
  // All sections before the first "option divider"
  final dividerIndex = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
  if (dividerIndex == -1) return _subsections;
  return _subsections.sublist(0, dividerIndex);
}

List<SubsectionData> get optionSections {
  // All sections after the first "option divider"
  final dividerIndex = _subsections.indexWhere((s) => s.name == '---OPTIONS---');
  if (dividerIndex == -1) return [];
  return _subsections.sublist(dividerIndex + 1);
}

  /// Builds a card widget for a subsection, including its items and controls.
  Widget buildSubsectionCard(SubsectionData section, int index) {
    final sectionItems = items.where((item) => item.section == section.name).toList();

    void showRenameDialog() async {
      String? newName = section.name;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename Subsection'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Subsection name'),
            controller: TextEditingController(text: section.name),
            onChanged: (val) => newName = val.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (newName != null && newName!.isNotEmpty && !_subsections.any((s) => s.name == newName)) {
                  setState(() {
                    // Update section name in _subsections and all items
                    final oldName = section.name;
                    section.name = newName!;
                    for (int i = 0; i < items.length; i++) {
                      if (items[i].section == oldName) {
                        items[i] = items[i].copyWith(section: newName!);
                      }
                    }
                    _hasUnsavedChanges = true;
                  });
                  Navigator.pop(context);
                  _saveInProgressEstimate();
                }
              },
              child: const Text('Rename'),
            ),
          ],
        ),
      );
    }

    void showMultiSelectDialog() async {
      final selected = await showDialog<Set<int>>(
        context: context,
        builder: (context) {
          final tempSelected = <int>{};
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Select Items'),
              content: SizedBox(
                width: 350,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sectionItems.length,
                  itemBuilder: (context, i) {
                    return CheckboxListTile(
                      value: tempSelected.contains(i),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            tempSelected.add(i);
                          } else {
                            tempSelected.remove(i);
                          }
                        });
                      },
                      title: Text(sectionItems[i].name),
                      subtitle: Text(sectionItems[i].description),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, tempSelected),
                  child: const Text('Next'),
                ),
              ],
            ),
          );
        },
      );
      if (selected != null && selected.isNotEmpty) {
        final action = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('What would you like to do?'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'copy'),
                child: const Text('Copy Selected Items'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: const Text('Delete Selected Items'),
              ),
            ],
          ),
        );
        if (action == 'copy') {
          setState(() {
            _copiedSectionName = section.name;
            _copiedSectionItems
              ..clear()
              ..addAll(selected.map((i) => sectionItems[i]));
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Items copied!')),
          );
        } else if (action == 'delete') {
          setState(() {
            for (final i in selected.toList()..sort((a, b) => b.compareTo(a))) {
              items.remove(sectionItems[i]);
            }
            _hasUnsavedChanges = true;
          });
          _saveInProgressEstimate();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Items deleted!')),
          );
        }
      }
    }

    _sectionSearchControllers[section.name] ??= TextEditingController();
    final searchQuery = _sectionSearchQueries[section.name] ?? '';
    final searchResults = searchPriceBook(priceBook, searchQuery);

    final searchFocusNode = _sectionSearchFocusNodes[section.name] ??= FocusNode();

    return Card(
      key: ValueKey(section.name),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: GestureDetector(
              onTap: showRenameDialog,
              child: Text(
                section.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Item',
                  onPressed: () => _showAddItemMethodDialog(section),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDeleteSubsection(section);
                    } else if (value == 'select') {
                      showMultiSelectDialog();
                    } else if (value == 'copy_section') {
                      setState(() {
                        _copiedSectionName = section.name;
                        _copiedSectionItems
                          ..clear()
                          ..addAll(sectionItems.map((e) => e.copyWith()));
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Section copied!')),
                      );
                    } else if (value == 'paste_item') {
                      if (_copiedSectionItems.isNotEmpty) {
                        setState(() {
                          final newItems = _copiedSectionItems
                              .map((item) => item.copyWith(section: section.name))
                              .toList();
                          items.addAll(newItems);
                          _hasUnsavedChanges = true;
                        });
                        _saveInProgressEstimate();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Items pasted!')),
                        );
                                           }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'select',
                      child: Text('Select Items'),
                    ),
                    const PopupMenuItem(
                      value: 'copy_section',
                      child: Text('Copy Subsection'),
                    ),
                    const PopupMenuItem(
                      value: 'paste_item',
                      child: Text('Paste Item(s)'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Section'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // --- Move the search bar here, just under the section header ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _sectionSearchControllers[section.name] ??= TextEditingController(),
                        focusNode: searchFocusNode,
                        decoration: const InputDecoration(
                          labelText: 'Search Pricebook',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onTap: () async {
                          // Wait for the keyboard to open, then scroll
                          await Future.delayed(const Duration(milliseconds: 300));
                          if (searchFocusNode.hasFocus) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (searchFocusNode.context != null) {
                                Scrollable.ensureVisible(
                                  searchFocusNode.context!,
                                  duration: const Duration(milliseconds: 300),
                                  alignment: 0,
                                  curve: Curves.easeIn,
                                );
                              }
                            });
                          }
                        },
                        onChanged: (val) {
                          _debouncedSearch(section.name, val);
                        },
                      ),
                      if (searchQuery.isNotEmpty && searchResults.isNotEmpty)
                        ...searchResults.map((item) => ListTile(
                          title: Text(item.name),
                          subtitle: Text('Code: ${item.code}  \$${item.price.toStringAsFixed(2)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () async {
                              estimate_item.EstimateItem? addedItem;
                              setState(() {
                                item.usageCount = item.usageCount + 1;
                                final insertIdx = items.indexWhere((i) => i.section == section.name);
                               
                                final newItem = estimate_item.EstimateItem(
                                  name: item.name,
                                  description: item.code,
                                  unitPrice: item.price,
                                  quantity: 1,
                                  purchasePrice: item.purchasePrice,
                                  section: section.name,
                                );
                                if (insertIdx == -1) {
                                  items.insert(0, newItem);
                                } else {
                                  items.insert(insertIdx, newItem);
                                }
                                addedItem = newItem;
                                _sectionSearchQueries[section.name] = '';
                                _sectionSearchControllers[section.name]?.clear();
                                _hasUnsavedChanges = true;
                              });
                              // Save both estimate and pricebook after usage count increment
                              _saveInProgressEstimate();
                              _savePriceBookToDisk();

                              // --- Open calendar if CAL ---
                              if (addedItem != null && addedItem!.description == 'CAL') {
                                DateTime selectedDate = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) selectedDate = picked;
                                setState(() {
                                  final idx = items.lastIndexWhere((i) => i.section == section.name && i.description == 'CAL');
                                  if (idx != -1) {
                                    final dateStr = '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
                                    items[idx] = items[idx].copyWith(
                                      name: 'Labour on $dateStr',
                                      description: 'Labour on $dateStr',
                                    );
                                  }
                                });
                                _saveInProgressEstimate();
                              }

                              // --- Open discount dialog if DIS ---
                              if (addedItem != null && addedItem!.description == 'DIS') {
                             final controller = TextEditingController(text: '');
                                final result = await showDialog<double>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Enter Discount Amount'),
                                    content: TextField(
                                      controller: controller,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      autofocus: true,
                                      decoration: const InputDecoration(labelText: 'Discount (\$)'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          final val = double.tryParse(controller.text);
                                          if (val != null && val > 0) {
                                            Navigator.pop(context, val);
                                          }
                                        },
                                        child: const Text('Apply'),
                                      ),
                                    ],
                                  ),
                                );
                                if (result != null) {
                                  setState(() {
                                    // ...existing code...
final idx = items.lastIndexWhere((i) =>
  i.section == section.name && i.description == 'DIS'
);
if (idx != -1) {
  items[idx] = items[idx].copyWith(
    unitPrice: -result.abs(), // Always negative
    name: 'Discount',
  );
}
// ...existing code...
                                    _hasUnsavedChanges = true;
                                  });
                                  _saveInProgressEstimate();
                                }
                              }
                            },
                          ),
                        )),
                      if (searchQuery.isNotEmpty && searchResults.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('No results found.'),
                        ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, size: 32),
                tooltip: 'Scan Barcode',
                onPressed: () async {
                  final barcode = await _scanBarcode();
                  if (barcode != null) {
                    _onBarcodeScanned(barcode, section.name, _sectionSearchControllers[section.name]!);
                  }
                },
              ),
            ],
          ),
        ),
        if (sectionItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No items in this section.', style: TextStyle(color: Colors.grey)),
          ),
        if (sectionItems.isNotEmpty)
          ...sectionItems.asMap().entries.map((entry) {
            final item = entry.value;

            // Calculate discount amount
            final discountAmount = item.discountAmount ?? 0;

            // Calculate profit after discount
            final profit = (item.unitPrice * item.quantity - discountAmount) - ((item.purchasePrice ?? 0) * item.quantity);

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Name row (full width) with 3-dot menu ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
  child: GestureDetector(
    onTap: () async {
      // This is the same as the 3-dots "Edit" logic
      final pbItem = priceBook.firstWhereOrNull((pb) => normalizeCode(pb.code) == normalizeCode(item.description));
      final nameController = TextEditingController(text: item.name);
      final purchaseController = TextEditingController(text: (item.purchasePrice ?? 0).toStringAsFixed(2));
      final priceController = TextEditingController(text: item.unitPrice.toStringAsFixed(2));
      final qtyController = TextEditingController(text: item.quantity.toString());
      final percentController = TextEditingController(
        text: (item.purchasePrice != null && item.purchasePrice! > 0)
            ? (((item.unitPrice - item.purchasePrice!) / item.purchasePrice!) * 100).toStringAsFixed(1)
            : '0',
      );
      final discountController = TextEditingController(
        text: (item.discountPercent ?? 0).toStringAsFixed(1),
      );
      bool saveNameToPB = false;
      bool savePercentToPB = false;

                              await showDialog(
                                context: context,
                                builder: (context) => StatefulBuilder(
                                  builder: (context, setState) => AlertDialog(
                                    title: const Text('Edit Line Item'),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: nameController,
                                                  decoration: const InputDecoration(labelText: 'Name'),
                                                ),
                                              ),
                                              if (pbItem != null)
                                                Checkbox(
                                                  value: saveNameToPB,
                                                  onChanged: (val) => setState(() => saveNameToPB = val ?? false),
                                                ),
                                              if (pbItem != null)
                                                const Text('PB', style: TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                          if (_showProfit && _showLineItemPrices)
                                            TextField(
                                              controller: purchaseController,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: const InputDecoration(labelText: 'Purchase Price'),
                                              onChanged: (val) {
                                                final buy = double.tryParse(val) ?? 0;
                                                final sell = double.tryParse(priceController.text) ?? 0;
                                                if (buy > 0) {
                                                  percentController.text = ((sell - buy) / buy * 100).toStringAsFixed(1);
                                                }
                                              },
                                            ),
                                          TextField(
                                            controller: priceController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(labelText: 'Sale Price'),
                                            onChanged: (val) {
                                              final buy = double.tryParse(purchaseController.text) ?? 0;
                                              final sell = double.tryParse(val) ?? 0;
                                              if (_showProfit && buy > 0) {
                                                percentController.text = ((sell - buy) / buy * 100).toStringAsFixed(1);
                                              }
                                            },
                                          ),
                                          if (_showProfit)
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: percentController,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    decoration: const InputDecoration(labelText: 'Profit %'),
                                                    onChanged: (val) {
                                                      final buy = double.tryParse(purchaseController.text) ?? 0;
                                                      final percent = double.tryParse(val) ?? 0;
                                                      if (buy > 0) {
                                                        priceController.text = (buy * (1 + percent / 100)).toStringAsFixed(2);
                                                      }
                                                    },
                                                  ),
                                                ),
                                                if (pbItem != null)
                                                  Checkbox(
                                                    value: savePercentToPB,
                                                    onChanged: (val) => setState(() => savePercentToPB = val ?? false),
                                                  ),
                                                if (pbItem != null)
                                                  const Text('PB', style: TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    // Show dialog to edit discount %
                                                    final result = await showDialog<double>(
                                                      context: context,
                                                      builder: (context) {
                                                        final ctrl = TextEditingController(text: discountController.text);
                                                        return AlertDialog(
                                                          title: const Text('Edit Discount %'),
                                                          content: TextField(
                                                            controller: ctrl,
                                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                            decoration: const InputDecoration(labelText: 'Discount %'),
                                                            autofocus: true,
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(context),
                                                              child: const Text('Cancel'),
                                                            ),
                                                            ElevatedButton(
                                                              onPressed: () {
                                                                final val = double.tryParse(ctrl.text);
                                                                if (val != null && val > 0) Navigator.pop(context, val);
                                                              },
                                                              child: const Text('Save'),
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    );
                                                    if (result != null) {
                                                      setState(() {
                                                        discountController.text = result.toStringAsFixed(1);
                                                      });
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue[50],
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Discount ${discountController.text}%',
                                                      style: TextStyle(
                                                        color: Colors.blue[800],
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          final newName = nameController.text.trim();
                                          final newPurchase = double.tryParse(purchaseController.text) ?? item.purchasePrice ?? 0;
                                          final newPrice = double.tryParse(priceController.text) ?? item.unitPrice;
                                          final newPercent = double.tryParse(percentController.text) ?? 0.0;
                                          final newQty = double.tryParse(qtyController.text) ?? item.quantity;

                                          setState(() {
                                            final idx = items.indexOf(item);
                                            items[idx] = item.copyWith(
                                              name: newName,
                                              purchasePrice: _showProfit ? newPurchase : item.purchasePrice,
                                              unitPrice: newPrice,
                                              quantity: newQty,
                                            );
                                            _hasUnsavedChanges = true;
                                          });

                                          // Save to pricebook if checked
                                          if (pbItem != null) {
                                            if (saveNameToPB) pbItem.name = newName;
                                            if (savePercentToPB) pbItem.percentageChanged = newPercent;
                                            if (saveNameToPB || savePercentToPB) _savePriceBookToDisk();
                                          }

                  Navigator.pop(context);
                  _saveInProgressEstimate();
                },
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    items.remove(item);
                    Navigator.pop(context);
                  });
                  _saveInProgressEstimate();
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      );
    },
    child: Text(
      item.name,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  ),
),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              // Trigger edit dialog (reuse your existing logic)
                              final pbItem = priceBook.firstWhereOrNull((pb) => normalizeCode(pb.code) == normalizeCode(item.description));
                              final nameController = TextEditingController(text: item.name);
                              final purchaseController = TextEditingController(text: (item.purchasePrice ?? 0).toStringAsFixed(2));
                              final priceController = TextEditingController(text: item.unitPrice.toStringAsFixed(2));
                              final qtyController = TextEditingController(text: item.quantity.toString());
                              final percentController = TextEditingController(
                                text: (item.purchasePrice != null && item.purchasePrice! > 0)
                                    ? (((item.unitPrice - item.purchasePrice!) / item.purchasePrice!) * 100).toStringAsFixed(1)
                                    : '0',
                              );
                              final discountController = TextEditingController(
                                text: (item.discountPercent ?? 0).toStringAsFixed(1),
                              );
                              bool saveNameToPB = false;
                              bool savePercentToPB = false;

                              await showDialog(
                                context: context,
                                builder: (context) => StatefulBuilder(
                                  builder: (context, setState) => AlertDialog(
                                    title: const Text('Edit Line Item'),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: nameController,
                                                  decoration: const InputDecoration(labelText: 'Name'),
                                                ),
                                              ),
                                              if (pbItem != null)
                                                Checkbox(
                                                  value: saveNameToPB,
                                                  onChanged: (val) => setState(() => saveNameToPB = val ?? false),
                                                ),
                                              if (pbItem != null)
                                                const Text('PB', style: TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                          if (_showProfit && _showLineItemPrices)
                                            TextField(
                                              controller: purchaseController,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: const InputDecoration(labelText: 'Purchase Price'),
                                              onChanged: (val) {
                                                final buy = double.tryParse(val) ?? 0;
                                                final sell = double.tryParse(priceController.text) ?? 0;
                                                if (buy > 0) {
                                                  percentController.text = ((sell - buy) / buy * 100).toStringAsFixed(1);
                                                }
                                              },
                                            ),
                                          TextField(
                                            controller: priceController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(labelText: 'Sale Price'),
                                            onChanged: (val) {
                                              final buy = double.tryParse(purchaseController.text) ?? 0;
                                              final sell = double.tryParse(val) ?? 0;
                                              if (_showProfit && buy > 0) {
                                                percentController.text = ((sell - buy) / buy * 100).toStringAsFixed(1);
                                              }
                                            },
                                          ),
                                          if (_showProfit)
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: percentController,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    decoration: const InputDecoration(labelText: 'Profit %'),
                                                    onChanged: (val) {
                                                      final buy = double.tryParse(purchaseController.text) ?? 0;
                                                      final percent = double.tryParse(val) ?? 0;
                                                      if (buy > 0) {
                                                        priceController.text = (buy * (1 + percent / 100)).toStringAsFixed(2);
                                                      }
                                                    },
                                                  ),
                                                ),
                                                if (pbItem != null)
                                                  Checkbox(
                                                    value: savePercentToPB,
                                                    onChanged: (val) => setState(() => savePercentToPB = val ?? false),
                                                  ),
                                                if (pbItem != null)
                                                  const Text('PB', style: TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    // Show dialog to edit discount %
                                                    final result = await showDialog<double>(
                                                      context: context,
                                                      builder: (context) {
                                                        final ctrl = TextEditingController(text: discountController.text);
                                                        return AlertDialog(
                                                          title: const Text('Edit Discount %'),
                                                          content: TextField(
                                                            controller: ctrl,
                                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                            decoration: const InputDecoration(labelText: 'Discount %'),
                                                            autofocus: true,
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(context),
                                                              child: const Text('Cancel'),
                                                            ),
                                                            ElevatedButton(
                                                              onPressed: () {
                                                                final val = double.tryParse(ctrl.text);
                                                                if (val != null && val > 0) Navigator.pop(context, val);
                                                              },
                                                              child: const Text('Save'),
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    );
                                                    if (result != null) {
                                                      setState(() {
                                                        discountController.text = result.toStringAsFixed(1);
                                                      });
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue[50],
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Discount ${discountController.text}%',
                                                      style: TextStyle(
                                                        color: Colors.blue[800],
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          final newName = nameController.text.trim();
                                          final newPurchase = double.tryParse(purchaseController.text) ?? item.purchasePrice ?? 0;
                                          final newPrice = double.tryParse(priceController.text) ?? item.unitPrice;
                                          final newPercent = double.tryParse(percentController.text) ?? 0.0;
                                          final newQty = double.tryParse(qtyController.text) ?? item.quantity;

                                          setState(() {
                                            final idx = items.indexOf(item);
                                            items[idx] = item.copyWith(
                                              name: newName,
                                              purchasePrice: _showProfit ? newPurchase : item.purchasePrice,
                                              unitPrice: newPrice,
                                              quantity: newQty,
                                            );
                                            _hasUnsavedChanges = true;
                                          });

                                          // Save to pricebook if checked
                                          if (pbItem != null) {
                                            if (saveNameToPB) pbItem.name = newName;
                                            if (savePercentToPB) pbItem.percentageChanged = newPercent;
                                            if (saveNameToPB || savePercentToPB) _savePriceBookToDisk();
                                          }

                                          Navigator.pop(context);
                                          _saveInProgressEstimate();
                                        },
                                        child: const Text('Save'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            items.remove(item);
                                            Navigator.pop(context);
                                          });
                                          _saveInProgressEstimate();
                                        },
                                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else if (value == 'copy') {
                              // Copy functionality can be implemented later if needed
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Line item copied!')),
                              );
                            } else if (value == 'delete') {
                              setState(() {
                                items.remove(item);
                                _hasUnsavedChanges = true;
                              });
                              _saveInProgressEstimate();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(value: 'copy', child: Text('Copy')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // --- Sale price, qty, total row ---
                    Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Sale Price
    SizedBox(
      width: 70, // Reduced from 90 to give more room for total
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) _saveInProgressEstimate();
        },
        child: TextField(
          controller: TextEditingController(text: item.unitPrice.toStringAsFixed(2))
            ..selection = TextSelection.fromPosition(TextPosition(offset: item.unitPrice.toStringAsFixed(2).length)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Sale Price',
            isDense: true,
            border: UnderlineInputBorder(),
            contentPadding: EdgeInsets.only(bottom: 0),
          ),
          textAlign: TextAlign.center,
          onTap: () {
            // Select all text on tap for easier editing
          },
          onEditingComplete: () {
            _saveInProgressEstimate();
            FocusScope.of(context).unfocus();
          },
          onSubmitted: (val) {
            final price = double.tryParse(val);
            if (price != null) {
              final newLineTotal = price * item.quantity;
              final newDiscountAmount = item.discountPercent != null
                  ? (item.discountPercent! / 100.0) * newLineTotal
                  : item.discountAmount ?? 0;
              final newItem = item.copyWith(
                unitPrice: price,
                discountAmount: newDiscountAmount,
              );
              _updateItemFast(item, newItem);
            }
            _saveInProgressEstimate();
          },
        ),
      ),
    ),
    // - button
    IconButton(
      icon: const Icon(Icons.remove_circle_outline, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Decrease Quantity',
      onPressed: () {
        if (item.quantity > 1) {
          final newQty = item.quantity - 1;
          final newLineTotal = item.unitPrice * newQty;
          final newDiscountAmount = item.discountPercent != null
              ? (item.discountPercent! / 100.0) * newLineTotal
              : item.discountAmount ?? 0;
          final newItem = item.copyWith(
            quantity: newQty,
            discountAmount: newDiscountAmount,
          );
          _updateItemFast(item, newItem);
        } else {
          setState(() {
            items.remove(item);
            _hasUnsavedChanges = true;
          });
          _debouncedSave();
        }
      },
    ),
    // Quantity TextField
    SizedBox(
      width: 40, // Reduced from 48 to save more space
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) _debouncedSave();
        },
        child: TextField(
          controller: TextEditingController(
            text: item.quantity.truncateToDouble() == item.quantity
                ? item.quantity.toStringAsFixed(0)
                : item.quantity.toStringAsFixed(2),
          )..selection = TextSelection.fromPosition(TextPosition(
            offset: (item.quantity.truncateToDouble() == item.quantity
                ? item.quantity.toStringAsFixed(0)
                : item.quantity.toStringAsFixed(2)).length)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.only(bottom: 0),
          ),
          onTap: () {
            // Select all text on tap for easier editing
          },
          onEditingComplete: () {
            _debouncedSave();
            FocusScope.of(context).unfocus();
          },
          onSubmitted: (val) {
            final qty = double.tryParse(val);
            if (qty != null && qty > 0) {
              final newLineTotal = item.unitPrice * qty;
              final newDiscountAmount = item.discountPercent != null
                  ? (item.discountPercent! / 100.0) * newLineTotal
                  : item.discountAmount ?? 0;
              final newItem = item.copyWith(
                quantity: qty,
                discountAmount: newDiscountAmount,
              );
              _updateItemFast(item, newItem);
            }
            _debouncedSave();
          },
        ),
      ),
    ),
    // + button
    IconButton(
      icon: const Icon(Icons.add_circle_outline, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Increase Quantity',
      onPressed: () {
        final newQty = item.quantity + 1;
        final newLineTotal = item.unitPrice * newQty;
        final newDiscountAmount = item.discountPercent != null
            ? (item.discountPercent! / 100.0) * newLineTotal
            : item.discountAmount ?? 0;
        final newItem = item.copyWith(
          quantity: newQty,
          discountAmount: newDiscountAmount,
        );
        _updateItemFast(item, newItem);
      },
    ),
    // Total (give it more room)
    Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 4), // Reduced from 8 to 4
        child: Text(
          '\$${(item.unitPrice * item.quantity - (item.discountAmount ?? 0)).toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.visible, // Changed from softWrap to overflow
        ),
      ),
    ),
  ],
),
                    // --- Discount and profit row (only show if line item prices are enabled) ---
                    if (_showLineItemPrices) Row(
                      children: [
                        // --- Purchase Price (click to edit) - only show when profit view is enabled ---
                        if (_showProfit) ...[
                          Flexible(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () async {
                                final ctrl = TextEditingController(text: (item.purchasePrice ?? 0).toStringAsFixed(2))
                                  ..selection = TextSelection.fromPosition(TextPosition(offset: (item.purchasePrice ?? 0).toStringAsFixed(2).length));
                                final result = await showDialog<double>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Edit Purchase Price'),
                                    content: TextField(
                                      controller: ctrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: 'Purchase Price'),
                                      autofocus: true,
                                      onTap: () {
                                        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                                      },
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          final val = double.tryParse(ctrl.text);
                                          if (val != null && val >= 0) Navigator.pop(context, val);
                                        },
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                if (result != null) {
                                  final newItem = item.copyWith(
                                    purchasePrice: result,
                                  );
                                  _updateItemFast(item, newItem);
                                  _saveInProgressEstimate();
                                }
                              },
                              child: Text(
                                'Purchase: \$${(item.purchasePrice ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // --- Discount (click to edit) - only show when profit view is enabled and discount > 0 ---
                        if (_showProfit && discountAmount > 0) ...[
                          Flexible(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () async {
                                final percentCtrl = TextEditingController(text: (item.discountPercent ?? 0).toStringAsFixed(1))
                                  ..selection = TextSelection.fromPosition(TextPosition(offset: (item.discountPercent ?? 0).toStringAsFixed(1).length));
                                final dollarCtrl = TextEditingController(text: (item.discountAmount ?? 0).toStringAsFixed(2))
                                  ..selection = TextSelection.fromPosition(TextPosition(offset: (item.discountAmount ?? 0).toStringAsFixed(2).length));
                                final result = await showDialog<Map<String, double>>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Edit Discount'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
                                          controller: percentCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Discount %'),
                                          autofocus: true,
                                          onTap: () {
                                            percentCtrl.selection = TextSelection(baseOffset: 0, extentOffset: percentCtrl.text.length);
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        TextField(
                                          controller: dollarCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Discount \$'),
                                          onTap: () {
                                            dollarCtrl.selection = TextSelection(baseOffset: 0, extentOffset: dollarCtrl.text.length);
                                          },
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                      ElevatedButton(
                                        onPressed: () {
                                          final percent = double.tryParse(percentCtrl.text) ?? 0;
                                          final amt = double.tryParse(dollarCtrl.text) ?? 0;
                                          Navigator.pop(context, {'percent': percent, 'amount': amt});
                                        },
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                if (result != null) {
                                  final newItem = item.copyWith(
                                    discountPercent: result['percent'],
                                    discountAmount: result['amount'],
                                  );
                                  _updateItemFast(item, newItem);
                                  _saveInProgressEstimate();
                                }
                              },
                              child: Text(
                                'Discount \$${discountAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: discountAmount > 0 ? Colors.blue[800] : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // --- Profit (click to edit profit %) - only show when profit view is enabled ---
                        if (_showProfit) ...[
                          Flexible(
                            flex: 3,
                            child: GestureDetector(
                              onTap: () async {
                                final percentCtrl = TextEditingController(
                                  text: item.purchasePrice != null && item.purchasePrice! > 0
                                      ? (((item.unitPrice - item.purchasePrice!) / item.purchasePrice!) * 100).toStringAsFixed(1)
                                      : '0',
                                );
                                final dollarCtrl = TextEditingController(
                                  text: (item.unitPrice - (item.purchasePrice ?? 0)).toStringAsFixed(2),
                                );
                                final result = await showDialog<Map<String, double>>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Edit Profit'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
                                          controller: percentCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Profit %'),
                                          autofocus: true,
                                        ),
                                        const SizedBox(height: 16),
                                        TextField(
                                          controller: dollarCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Profit \$'),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                      ElevatedButton(
                                        onPressed: () {
                                          final dollarAmount = double.tryParse(dollarCtrl.text) ?? 0;
                                          double? newUnitPrice;
                                          
                                          // Calculate new unit price based on profit dollar amount
                                          if (item.purchasePrice != null && item.purchasePrice! > 0) {
                                            newUnitPrice = item.purchasePrice! + dollarAmount;
                                          } else if (dollarAmount > 0) {
                                            // If no purchase price, just add the profit to current price
                                            newUnitPrice = dollarAmount;
                                          }
                                          
                                          Navigator.pop(context, {'unitPrice': newUnitPrice});
                                        },
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                if (result != null && result['unitPrice'] != null) {
                                  final newItem = item.copyWith(
                                    unitPrice: result['unitPrice']!,
                                  );
                                  _updateItemFast(item, newItem);
                                  _saveInProgressEstimate();
                                }
                              },
                              child: Text(
                                'Profit: \$${profit.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: profit < 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              )
              );
            }),

        
        ]
      )
    );
  }
String _monthAbbr(int month) {
  const abbr = [
    '', // 0 index unused
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  if (month < 1 || month > 12) return '';
  return abbr[month];
}

int levenshtein(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  List<List<int>> matrix = List.generate(
    s.length + 1,
    (_) => List.filled(t.length + 1, 0),
  );

  for (int i = 0; i <= s.length; i++) {
    matrix[i][0] = i;
  }
  for (int j = 0; j <= t.length; j++) {
    matrix[0][j] = j;
  }

  for (int i = 1; i <= s.length; i++) {
    for (int j = 1; j <= t.length; j++) {
      int cost = s[i - 1] == t[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return matrix[s.length][t.length];
}
}

// ====================================================================
// GPS HISTORY SCREEN - Comprehensive site visit tracking
// ====================================================================

class GpsHistoryScreen extends StatefulWidget {
  final job_model.Job job;
  final Function(estimate_item.EstimateItem) onLabourAdded;

  const GpsHistoryScreen({
    super.key,
    required this.job,
    required this.onLabourAdded,
  });

  @override
  State<GpsHistoryScreen> createState() => _GpsHistoryScreenState();
}

class _GpsHistoryScreenState extends State<GpsHistoryScreen> {
  List<Map<String, dynamic>> _siteVisits = [];
  Map<String, double>? _siteCoordinates;
  bool _isLoadingHistory = false;
  bool _isLoadingLocation = false;
  bool _isSearchingAddresses = false;
  String _currentAddress = '';
  final TextEditingController _addressController = TextEditingController();
  List<AddressSearchResult> _addressSearchResults = [];
  double _proximityRadius = 50.0; // Default 50 meters
  PriceBookItem? _calLabourItem;
  bool _addressResolved = false;

  @override
  void initState() {
    super.initState();
    _currentAddress = widget.job.address ?? '';
    _addressController.text = _currentAddress;
    _initializeScreen();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// Clear address search results
  void _clearAddressSearch() {
    setState(() {
      _addressSearchResults = [];
    });
  }

  Future<void> _initializeScreen() async {
    // Load CAL LABOUR pricebook item
    await _loadCalLabourItem();
    
    // Check if address needs geocoding
    if (_currentAddress.isNotEmpty) {
      _addressResolved = await _hasGeocodedCoordinates(_currentAddress);
      if (!_addressResolved) {
        // Show address search first
        return;
      }
    }
    
    // Load site coordinates and history
    await _loadSiteCoordinatesAndHistory();
  }

  /// Search for addresses using the address search service
  Future<void> _searchAddresses(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _addressSearchResults = [];
      });
      return;
    }

    setState(() {
      _isSearchingAddresses = true;
    });

    try {
      final results = await AddressSearchService.searchAddresses(query, limit: 5);
      setState(() {
        _addressSearchResults = results;
      });
    } catch (e) {
      print('Error searching addresses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching addresses: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() {
        _isSearchingAddresses = false;
      });
    }
  }

  /// Select an address from search results and geocode it
  Future<void> _selectAddress(AddressSearchResult address) async {
    setState(() {
      _currentAddress = address.address;
      _addressController.text = address.address;
      _addressSearchResults = [];
    });

    if (address.latitude != null && address.longitude != null) {
      // Use coordinates from search result
      _siteCoordinates = {
        'lat': address.latitude!,
        'lng': address.longitude!,
      };
      
      setState(() {
        _addressResolved = true;
      });
      
      // Load visit history now that we have coordinates
      await _loadSiteVisitHistory();
    } else {
      // Fallback to geocoding
      await _geocodeAddress(address.address);
    }
  }

  Future<void> _loadCalLabourItem() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final priceBook = jsonList.map((e) => PriceBookItem.fromJson(e)).toList();
        
        _calLabourItem = priceBook.firstWhere(
          (item) => item.code == 'CAL',
          orElse: () => PriceBookItem(
            code: 'CAL',
            name: 'Labour',
            price: 85.0,
            purchasePrice: 65.0,
            unit: 'hr',
            groupCode: 'LABOUR',
            favorite: false,
            usageCount: 0,
          ),
        );
      }
    } catch (e) {
      print('Error loading CAL LABOUR item: $e');
    }
  }

  Future<bool> _hasGeocodedCoordinates(String address) async {
    try {
      final locations = await locationFromAddress(address);
      return locations.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _geocodeAddress(String address) async {
    setState(() {
      _isLoadingLocation = true;
      _addressSearchResults = []; // Clear search results
    });

    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        _siteCoordinates = {
          'lat': location.latitude,
          'lng': location.longitude,
        };
        
        // Update job address if it changed
        // Note: Job address is final, so we can't update it here
        // In a real implementation, you'd need to update the job through proper channels
        
        setState(() {
          _currentAddress = address;
          _addressResolved = true;
        });
        
        // Load visit history now that we have coordinates
        await _loadSiteVisitHistory();
      } else {
        throw Exception('No coordinates found for this address');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error geocoding address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _loadSiteCoordinatesAndHistory() async {
    if (_currentAddress.isEmpty) return;
    
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Get coordinates from address
      final locations = await locationFromAddress(_currentAddress);
      if (locations.isNotEmpty) {
        final location = locations.first;
        _siteCoordinates = {
          'lat': location.latitude,
          'lng': location.longitude,
        };
        
        // Load visit history
        await _loadSiteVisitHistory();
      }
    } catch (e) {
      print('Error loading site coordinates: $e');
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _loadSiteVisitHistory() async {
    if (_siteCoordinates == null) return;
    
    setState(() {
      _isLoadingHistory = true;
      _siteVisits.clear(); // Clear any existing data
    });

    try {
      // Get current position
      Position? currentPosition;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
            currentPosition = await Geolocator.getCurrentPosition();
          }
        }
      } catch (e) {
        print('Error getting current position: $e');
      }

      // Load stored GPS history from device
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final storedHistory = jsonDecode(historyJson) as List;
      
      final siteHistory = <Map<String, dynamic>>[];
      
      // Process stored GPS history to find visits to this address
      for (final entry in storedHistory) {
        final entryLat = entry['latitude'] as double?;
        final entryLng = entry['longitude'] as double?;
        final timestamp = entry['timestamp'] != null ? DateTime.parse(entry['timestamp']) : null;
        
        if (entryLat != null && entryLng != null && timestamp != null) {
          final distance = Geolocator.distanceBetween(
            entryLat,
            entryLng,
            _siteCoordinates!['lat']!,
            _siteCoordinates!['lng']!,
          );
          
          // Only include visits within proximity range
          if (distance <= _proximityRadius) {
            DateTime? departureTime;
            double? duration = entry['duration']?.toDouble();
            
            if (entry['departureTime'] != null) {
              departureTime = DateTime.parse(entry['departureTime']);
            }
            
            // If no departure time, calculate duration from arrival to current time (still on-site)
            if (departureTime == null && duration == null) {
              final arrivalTime = timestamp;
              final currentTime = DateTime.now();
              duration = currentTime.difference(arrivalTime).inMinutes / 60.0;
            }
            
            siteHistory.add({
              'arrivalTime': timestamp,
              'departureTime': departureTime,
              'duration': duration,
              'distance': distance,
              'isCurrentVisit': false,
            });
          }
        }
      }
      
      // Check if currently on site
      if (currentPosition != null) {
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          _siteCoordinates!['lat']!,
          _siteCoordinates!['lng']!,
        );
        
        // If currently within range, add current visit
        if (distance <= _proximityRadius) {
          siteHistory.insert(0, {
            'arrivalTime': DateTime.now().subtract(const Duration(minutes: 30)), // Estimate arrival
            'departureTime': null, // Still on site
            'duration': null,
            'distance': distance,
            'isCurrentVisit': true,
          });
        }
      }
      
      // Sort by most recent first
      siteHistory.sort((a, b) => (b['arrivalTime'] as DateTime).compareTo(a['arrivalTime'] as DateTime));
      
      setState(() {
        _siteVisits = siteHistory;
      });
      
    } catch (e) {
      print('Error loading site visit history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading GPS history: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Widget _buildSiteVisitsList() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    if (_siteVisits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No GPS visits found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No match at this range for this address.\nIncrease the range or start GPS tracking.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // In a real app, this would start background GPS tracking
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('GPS tracking would start in background (feature to be implemented)'),
                    ),
                  );
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Start GPS Tracking'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _siteVisits.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final visit = _siteVisits[index];
        final arrivalTime = visit['arrivalTime'] as DateTime?;
        final departureTime = visit['departureTime'] as DateTime?;
        final duration = visit['duration'] as double?;
        final distance = visit['distance'] as double?;
        final isCurrentVisit = visit['isCurrentVisit'] as bool? ?? false;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCurrentVisit ? Icons.location_on : Icons.history,
                      color: isCurrentVisit ? Colors.green : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isCurrentVisit ? 'Current Visit' : 'Past Visit',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (distance != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${distance.toStringAsFixed(0)}m',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (arrivalTime != null) ...[
                  Text(
                    'Arrival: ${arrivalTime.day}/${arrivalTime.month}/${arrivalTime.year} ${arrivalTime.hour}:${arrivalTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                if (departureTime != null) ...[
                  Text(
                    'Departure: ${departureTime.day}/${departureTime.month}/${departureTime.year} ${departureTime.hour}:${departureTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                if (duration != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    departureTime == null 
                        ? 'Duration: ${duration.toStringAsFixed(1)} hours (still on-site)'
                        : 'Duration: ${duration.toStringAsFixed(1)} hours',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Add Labour Item: '),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _addLabourFromVisit(visit),
                          child: Text('${duration.toStringAsFixed(1)}h Labour'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _addLabourFromVisit(Map<String, dynamic> visit) {
    if (_calLabourItem == null) return;
    
    final arrivalTime = visit['arrivalTime'] as DateTime?;
    if (arrivalTime == null) return;
    
    final duration = visit['duration'] as double? ?? 0.0;
    final dateStr = '${arrivalTime.day}/${arrivalTime.month}';
    
    final labourItem = estimate_item.EstimateItem(
      name: 'Labour on $dateStr',
      description: 'CAL',
      unitPrice: _calLabourItem!.price,
      purchasePrice: _calLabourItem!.purchasePrice,
      quantity: duration,
      section: 'Labour',
    );
    
    widget.onLabourAdded(labourItem);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${duration}h labour for $dateStr'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Site History'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Address Search Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Site Address',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _addressController,
                            decoration: InputDecoration(
                              hintText: 'Search for site address...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _isSearchingAddresses
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (value) {
                              // Debounce search to avoid too many API calls
                              Future.delayed(const Duration(milliseconds: 500), () {
                                if (value == _addressController.text) {
                                  _searchAddresses(value);
                                }
                              });
                            },
                            onSubmitted: (address) {
                              if (address.trim().isNotEmpty) {
                                _geocodeAddress(address.trim());
                              }
                            },
                          ),
                          // Address search results dropdown
                          if (_addressSearchResults.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _addressSearchResults.length,
                                itemBuilder: (context, index) {
                                  final result = _addressSearchResults[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.location_on, size: 16),
                                    title: Text(
                                      result.address,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    subtitle: result.suburb != null || result.city != null
                                        ? Text(
                                            [result.suburb, result.city, result.postcode]
                                                .where((e) => e != null && e.isNotEmpty)
                                                .join(', '),
                                            style: const TextStyle(fontSize: 12),
                                          )
                                        : null,
                                    onTap: () => _selectAddress(result),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSearchingAddresses
                          ? null
                          : () {
                              final address = _addressController.text.trim();
                              if (address.isNotEmpty) {
                                _searchAddresses(address);
                              }
                            },
                      icon: _isSearchingAddresses
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('Search Addresses'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_addressResolved && _currentAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Please search and select an address to view GPS history',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FutureBuilder<String>(
                  future: AddressSearchService.getSelectedCountry(),
                  builder: (context, snapshot) {
                    final country = snapshot.data ?? 'New Zealand';
                    return Text(
                      'Address search powered by ${country == 'New Zealand' ? 'LINZ' : 'OpenStreetMap'} for $country',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Proximity Slider Section
          if (_addressResolved)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Site Proximity Range',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: _proximityRadius,
                          min: 10.0,
                          max: 100.0,
                          divisions: 18,
                          label: '${_proximityRadius.toInt()}m',
                          onChanged: (value) {
                            setState(() {
                              _proximityRadius = value;
                            });
                          },
                          onChangeEnd: (value) {
                            _loadSiteVisitHistory();
                          },
                        ),
                      ),
                      Text(
                        '${_proximityRadius.toInt()}m',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Test Real Location Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        print('🧪 Starting real location and geocoding test...');
                        
                        try {
                          // Test geocoding first
                          final address = _addressController.text.trim();
                          if (address.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter an address first')),
                            );
                            return;
                          }
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Testing geocoding and getting your location...')),
                          );
                          
                          // Test if address converts to coordinates
                          print('🧪 Testing geocoding for: $address');
                          final locations = await locationFromAddress(address);
                          
                          if (locations.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❌ Geocoding failed - address not found'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          
                          final siteCoords = locations.first;
                          print('✅ Geocoding successful! Lat: ${siteCoords.latitude}, Lng: ${siteCoords.longitude}');
                          
                          // Get current real device location
                          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❌ Please enable location services'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          LocationPermission permission = await Geolocator.checkPermission();
                          if (permission == LocationPermission.denied) {
                            permission = await Geolocator.requestPermission();
                            if (permission == LocationPermission.denied) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('❌ Location permission denied'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                          }

                          final currentPosition = await Geolocator.getCurrentPosition();
                          print('✅ Got current location! Lat: ${currentPosition.latitude}, Lng: ${currentPosition.longitude}');
                          
                          // Calculate distance
                          final distance = Geolocator.distanceBetween(
                            currentPosition.latitude,
                            currentPosition.longitude,
                            siteCoords.latitude,
                            siteCoords.longitude,
                          );
                          
                          print('📏 Distance to job site: ${distance.toStringAsFixed(1)} meters');
                          
                          // Add current location to GPS history
                          final prefs = await SharedPreferences.getInstance();
                          final historyJson = prefs.getString('gps_visit_history') ?? '[]';
                          final historyList = jsonDecode(historyJson) as List;
                          
                          historyList.add({
                            'latitude': currentPosition.latitude,
                            'longitude': currentPosition.longitude,
                            'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
                            'departureTime': DateTime.now().toIso8601String(),
                            'duration': '1.0',
                            'address': 'Test location - $address',
                          });
                          
                          await prefs.setString('gps_visit_history', jsonEncode(historyList));
                          
                          // Reload the GPS history to show the new test entry
                          await _loadSiteVisitHistory();
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ Test complete!\n'
                                'Distance: ${distance.toStringAsFixed(1)}m\n'
                                'Added your location to GPS history',
                              ),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                          
                        } catch (e) {
                          print('❌ Test failed: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('❌ Test failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.science),
                      label: const Text('Test Real Location & Geocoding'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Site Visits List
          if (_addressResolved)
            Expanded(
              child: _isLoadingHistory
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading site visit history...'),
                        ],
                      ),
                    )
                  : _siteVisits.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No site visits found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Visit the site to start tracking your time',
                                style: TextStyle(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _siteVisits.length,
                          itemBuilder: (context, index) {
                            final visit = _siteVisits[index];
                            final arrivalTime = visit['arrivalTime'] as DateTime?;
                            final departureTime = visit['departureTime'] as DateTime?;
                            final duration = visit['duration'] as double? ?? 0.0;
                            final distance = visit['distance'] as double? ?? 0.0;
                            final isCurrentVisit = visit['isCurrentVisit'] as bool? ?? false;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header
                                    Row(
                                      children: [
                                        Icon(
                                          isCurrentVisit
                                              ? Icons.location_on
                                              : Icons.location_history,
                                          color: isCurrentVisit
                                              ? Colors.green
                                              : Colors.blue,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          arrivalTime != null
                                              ? 'Visit on ${arrivalTime.day}/${arrivalTime.month}'
                                              : 'Site Visit',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (isCurrentVisit)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'ON SITE',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Time Details
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Arrival',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                arrivalTime != null
                                                    ? '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}'
                                                    : '—',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Departure',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                departureTime != null
                                                    ? '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}'
                                                    : isCurrentVisit
                                                        ? 'On site'
                                                        : '—',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: isCurrentVisit
                                                      ? Colors.green
                                                      : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Distance',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${distance.toInt()}m',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Duration Control
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Time on Site',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // Display duration from real GPS data (read-only)
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[50],
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.blue[200]!),
                                            ),
                                            child: Text(
                                              departureTime == null
                                                  ? 'Duration: ${duration.toStringAsFixed(1)} hours (still on-site)'
                                                  : 'Duration: ${duration.toStringAsFixed(1)} hours',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Add Labour Button
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: duration > 0 && arrivalTime != null
                                            ? () => _addLabourFromVisit(visit)
                                            : null,
                                        icon: const Icon(Icons.add_task),
                                        label: Text(
                                          arrivalTime != null
                                              ? 'Add Labour (${arrivalTime.day}/${arrivalTime.month})'
                                              : 'Add Labour',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green.shade600,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

          // Address Not Resolved State
          if (!_addressResolved)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_searching,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Address Verification Required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please verify the site address above to view GPS history',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}