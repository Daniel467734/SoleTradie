import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
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
import 'package:firebase_auth/firebase_auth.dart';
import '../services/memory_optimization_service.dart';
import '../services/openai_key_service.dart';
import '../models/estimate_template.dart';
import '../models/estimate_item.dart' as estimate_item;
import '../models/estimate_build.dart';
import '../models/job.dart' as job_model;
import '../models/estimate_version.dart';
import '../models/price_book_item.dart' as models;
import '../services/firestore_service.dart';
import '../services/delta_sync_service.dart';
import '../services/in_progress_build_service.dart';
import '../mixins/document_naming_mixin.dart';
import '../widgets/voice_text_field.dart';
import 'todo_list_screen.dart';
import 'estimate_builder/editable_header.dart';
import 'estimate_builder/select_extracted_items_dialog.dart';
import 'estimate_builder/add_estimate_item_dialog.dart';
import 'estimate_builder/gps_history_screen.dart';

part 'estimate_builder/estimate_builder_utils.dart';
part 'estimate_builder/estimate_builder_profit.dart';
part 'estimate_builder/estimate_builder_totals.dart';
part 'estimate_builder/estimate_builder_pricebook.dart';
part 'estimate_builder/estimate_builder_drag.dart';
part 'estimate_builder/estimate_builder_gps_helpers.dart';
part 'estimate_builder/estimate_builder_scanner_helpers.dart';
part 'estimate_builder/estimate_builder_templates.dart';

// 🔴 PERFORMANCE: Top-level function so it can run on a background isolate via
// compute(). Encoding the full pricebook (50k+ items) with jsonEncode() is
// expensive - doing it on the UI thread was a major source of typing/scrolling
// jank, since _savePriceBookToDisk() is called frequently while the user works.
String _encodePriceBookJson(Map<String, dynamic> data) {
  return jsonEncode(data);
}

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
  String description;
  // Internal-only cost deducted from this subsection's profit. Never shown
  // to the customer (not included in PDF exports), it only affects the
  // profit figures shown in-app.
  double extraCost;
  SubsectionData(
      {required this.name, this.description = '', this.extraCost = 0.0});
}

/// Represents a single line item whose purchase (buy) price differs from
/// the current pricebook value at the moment an estimate/quote is converted
/// to an invoice. Drives the "Purchase Prices Have Changed" dialog shown
/// right when the conversion builder opens: the buy price is always synced
/// to the pricebook afterwards, while the sell price is only updated for
/// items the user selects (or all of them, if none are individually
/// selected).
class ConversionPriceChange {
  final estimate_item.EstimateItem item;
  final double oldPurchasePrice;
  final double newPurchasePrice;
  final double oldSellPrice;
  final double newSellPrice;
  bool selected;
  // True when this item's sell price was hand-edited by the user rather
  // than pricebook-derived. Such items are shown informationally in the
  // conversion dialog (buy price change only) but are never selectable for
  // a sell-price update - their manually-set price is always preserved.
  final bool sellPriceLocked;

  ConversionPriceChange({
    required this.item,
    required this.oldPurchasePrice,
    required this.newPurchasePrice,
    required this.oldSellPrice,
    required this.newSellPrice,
    this.selected = false,
    this.sellPriceLocked = false,
  });

  bool get sellPriceWouldChange =>
      !sellPriceLocked && (newSellPrice - oldSellPrice).abs() >= 0.005;
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

// Testing code insertion location

/// 🔴 PERFORMANCE: Decodes the raw pricebook JSON string and separates
/// priority (CAL/EST labour) items from the rest, all in a background
/// isolate. This is the expensive part (jsonDecode of 50k+ items) that
/// was blocking the main thread for ~1-2s and causing frame skips when
/// opening the estimate builder. Must be a top-level function for compute().
List<dynamic> _parseAndOrganizePriceBookJson(String jsonString) {
  final decoded = jsonDecode(jsonString);
  final List<dynamic> jsonList;
  if (decoded is Map<String, dynamic> && decoded.containsKey('items')) {
    jsonList = decoded['items'] as List<dynamic>;
  } else if (decoded is List<dynamic>) {
    jsonList = decoded;
  } else {
    throw Exception('Unexpected pricebook JSON structure');
  }

  final List<dynamic> priorityItems = [];
  final List<dynamic> otherItems = [];
  for (final item in jsonList) {
    if (item is Map<String, dynamic> &&
        (item['code'] == 'CAL' || item['code'] == 'EST')) {
      priorityItems.add(item);
    } else {
      otherItems.add(item);
    }
  }
  return [...priorityItems, ...otherItems];
}

class EstimateBuilderScreen extends StatefulWidget {
  final job_model.Job job;
  final List<estimate_item.EstimateItem>? initialItems;
  final List<String>? initialSubsections;
  final EstimateTemplate? initialTemplate;
  final bool convertToInvoice;
  final String? initialSourceType;
  // The generation date/timestamp of the source estimate/quote document
  // being converted to an invoice. Used as the comparison anchor for the
  // conversion price-change dialog: a pricebook item is only flagged if
  // its price was actually touched on or after this date. Falls back to
  // the PDF generation date (`EstimateVersion.timestamp`) at the call
  // site since we don't separately track a per-item "added to estimate"
  // date. Left null for documents that predate this feature, in which
  // case the price-change check falls back to always flagging a numeric
  // buy-price difference (see `_checkAndApplyConversionPriceChanges`).
  final DateTime? initialSourceTimestamp;
  final String?
      inProgressBuildId; // Add parameter for overwriting existing builds
  final void Function(GeneratedDocument doc)? onDocumentGenerated;
  final double? initialDepositAmount;
  final double? initialDepositPercentage;
  final bool initialIsDepositPercentage;
  final String? initialScopeSummary;
  final String?
      initialBuildType; // 'estimate' | 'invoice' | 'quote' - decided up-front when starting a new build

  const EstimateBuilderScreen({
    super.key,
    required this.job,
    this.initialItems,
    this.initialSubsections,
    this.initialTemplate,
    this.convertToInvoice = false,
    this.initialSourceType,
    this.initialSourceTimestamp,
    this.inProgressBuildId, // Add to constructor
    this.onDocumentGenerated,
    this.initialDepositAmount,
    this.initialDepositPercentage,
    this.initialIsDepositPercentage = false,
    this.initialScopeSummary,
    this.initialBuildType,
  });

  @override
  State<EstimateBuilderScreen> createState() => _EstimateBuilderScreenState();
}

class _EstimateBuilderScreenState extends State<EstimateBuilderScreen>
    with WidgetsBindingObserver, DocumentNamingMixin {
  List<estimate_item.EstimateItem> items = [];
  bool _showProfit = true;
  final bool _showLineItemPrices = true;
  final String _pin = '1234';
  final List<SubsectionData> _subsections =
      []; // <-- Change from List<String> to List<SubsectionData>
  List<models.PriceBookItem> priceBook = [];
  bool _didLoadTemplate = false;
  String? _notes; // Add notes field
  final Map<String, TextEditingController> _sectionSearchControllers = {};
  final Map<String, String> _sectionSearchQueries = {};
  final Map<String, FocusNode> _sectionSearchFocusNodes =
      {}; // Add this to your state
  // Tracks whether the inline pricebook search results list is expanded (10 vs 30 rows).
  final Map<String, bool> _sectionSearchShowMore = {};
  // Tracks the item just added via the inline '+' button so repeat taps bump its quantity
  // instead of inserting duplicate lines, keyed by section name -> pricebook code.
  final Map<String, Map<String, estimate_item.EstimateItem>>
      _sectionSearchAddedItems = {};
  final Map<String, Map<String, int>> _sectionSearchAddCounts = {};
  final Map<String, TextEditingController> _sectionDescriptionControllers = {};
  final Map<String, TextEditingController> _sectionExtraCostControllers = {};
  final Map<String, TextEditingController> _itemSalePriceControllers = {};
  final Map<String, TextEditingController> _itemQuantityControllers = {};
  final Map<String, FocusNode> _itemSalePriceFocusNodes = {};
  final Map<String, FocusNode> _itemQuantityFocusNodes = {};
  Timer? _searchDebounce;
  Timer? _saveDebounce;
  Timer? _priceBookSaveDebounce;
  bool _priceBookSaveInFlight = false;
  bool _priceBookSavePending = false;
  String? _copiedSectionName;
  final List<estimate_item.EstimateItem> _copiedSectionItems = [];
  late List<EstimateTemplate> _templates;

  // Change tracking for final builds being edited
  List<estimate_item.EstimateItem> _originalItems = [];
  List<String> _originalSubsections = [];
  bool _isEditingFinalBuild = false;
  bool _isSaving = false;
  List<estimate_item.EstimateItem> _conversionReferenceItems = [];
  Timer? _autoSaveTimer;

  /// Whether the "Purchase Prices Have Changed" conversion dialog has
  /// already been shown/checked for this screen instance. Prevents it from
  /// re-appearing on subsequent rebuilds of the same conversion session.
  bool _hasCheckedConversionPriceChanges = false;

  /// The type of document this build will become: 'estimate' | 'quote' | 'invoice'.
  /// Decided up-front when the build is created (or restored from a saved
  /// in-progress build), and changeable at any time from within the builder
  /// via the type selector in the app bar. Changing it never touches items,
  /// subsections, scope/exclusions notes or risks - only the type tag itself.
  String _buildType = 'estimate';

  /// Whether the build-type switcher in the app bar should be interactive.
  /// Disabled while converting an estimate/quote straight to an invoice
  /// (that flow is structurally invoice-only - deposit deduction, remaining
  /// quantities etc. - so switching away mid-conversion isn't supported),
  /// and disabled when editing an already-generated final document (it
  /// already has a fixed type and document number, so it's not an
  /// in-progress draft whose type is still undecided).
  bool get _canChangeBuildType =>
      !widget.convertToInvoice && !_isEditingFinalBuild;

  /// 🔴 NEW: Fixed quoted totals for subsections from the original estimate/quote.
  /// Maps subsection name -> the original quoted amount (doesn't change as items are added/removed).
  /// Used to calculate "Quote Remaining" by comparing against current actual total.
  final Map<String, double> _quotedSubsectionAmounts = {};

  /// 🔴 NEW: Fixed quoted total for the entire document from the original estimate/quote.
  /// Used at the bottom to show overall "Quote Remaining" alongside Subtotal/GST/Total.
  double _quotedDocumentTotal = 0.0;

  String _buildTypeLabel(String? type) {
    switch (type) {
      case 'invoice':
        return 'Invoice';
      case 'quote':
        return 'Quote';
      case 'estimate':
      default:
        return 'Estimate';
    }
  }

  IconData _buildTypeIcon(String? type) {
    switch (type) {
      case 'invoice':
        return Icons.receipt_long;
      case 'quote':
        return Icons.request_quote;
      case 'estimate':
      default:
        return Icons.description;
    }
  }

  Widget _buildTypeOption(String value, IconData icon, String label) {
    final bool isSelected = value == _buildType;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          if (isSelected) const Icon(Icons.check, color: Colors.green),
        ],
      ),
    );
  }

  /// Lets the user change the build's type (estimate/quote/invoice) from
  /// within the builder at any time - e.g. if the wrong type was chosen when
  /// starting the build. This ONLY changes the `_buildType` tag (and, where
  /// possible, renames an auto-named in-progress build to match); it never
  /// touches items, subsections, scope/exclusions text or liability risks.
  Future<void> _showChangeBuildTypeDialog() async {
    if (!_canChangeBuildType) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change Build Type'),
        children: [
          _buildTypeOption('estimate', Icons.description, 'Estimate'),
          _buildTypeOption('quote', Icons.request_quote, 'Quote'),
          _buildTypeOption('invoice', Icons.receipt_long, 'Invoice'),
        ],
      ),
    );

    if (selected == null || selected == _buildType) return;

    final previousType = _buildType;
    setState(() {
      _buildType = selected;
      _hasUnsavedChanges = true;
    });
    print('🔧 Build type changed: $previousType -> $selected');

    // If the underlying in-progress build still has its auto-generated
    // default name (e.g. "Estimate Build 1"), keep the name in sync with the
    // new type (e.g. -> "Invoice Build 1"). A user-customised name is left
    // untouched.
    final buildId = _currentInProgressId ?? widget.inProgressBuildId;
    if (buildId != null) {
      try {
        final existingBuild =
            await InProgressBuildService.getBuildById(buildId);
        if (existingBuild != null) {
          final newName = InProgressBuildService.renameForNewType(
              existingBuild.name, selected);
          if (newName != null && newName != existingBuild.name) {
            await InProgressBuildService.renameBuild(
                buildId: buildId, newName: newName);
            print('🔧 Renamed build $buildId to "$newName" for new type');
          }
        }
      } catch (e) {
        print('⚠️ Failed to rename build after type change: $e');
      }
    }

    // Persist the new type alongside everything else already tracked in
    // additionalData (items/subsections are passed through unchanged).
    await _saveInProgressEstimate();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Build type changed to ${_buildTypeLabel(selected)}. All items, subsections, scope and risk details were kept.'),
        ),
      );
    }
  }

  String get _documentSourceLabel =>
      widget.initialSourceType == 'estimate' ? 'Estimate' : 'Quote';

  final int _lastSavedItemCount = 0; // Track item count to detect real changes
  String? _lastSavedBuildId; // Track the last saved build ID
  DateTime? _lastSaveTime;
  static final Map<String, DateTime> _globalSaveTimes =
      {}; // Global prevention across all instances

  void _debouncedAutoSave() {
    // TEMPORARILY DISABLED - only save on navigation away
    print('🔄 Auto-save disabled to prevent duplicates - will save on exit');
  }

  // (Removed duplicate _saveInProgressEstimateSimple)

  // Debug method to check current state
  // 🔴 PERFORMANCE: This was being called on EVERY build() invocation,
  // meaning every quantity +/- tap, keyboard open/close, and price edit
  // triggered 2-4 synchronous print() calls to logcat. Physical device
  // logcat I/O is surprisingly slow and was contributing directly to the
  // "Skipped X frames!" warnings seen during simple UI interactions.
  // Disabled by default; flip _debugBuildLogging to true only when
  // actively debugging item-list state issues.
  static const bool _debugBuildLogging = false;
  void debugCurrentState() {
    if (!_debugBuildLogging) return;
    print('🎨 DEBUG BUILD: _items.length = ${items.length}');
    print(
        '🎨 DEBUG BUILD: widget.initialItems?.length = ${widget.initialItems?.length ?? 0}');
    if (items.isNotEmpty) {
      print(
          '🎨 DEBUG BUILD: First _item = ${items[0].description} - ${items[0].quantity} x ${items[0].unitPrice}');
    } else if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      print(
          '🎨 DEBUG BUILD: First widget.initialItems = ${widget.initialItems![0].description} - ${widget.initialItems![0].quantity} x ${widget.initialItems![0].unitPrice}');
    }
  }

  // Location tracking for template distance filtering
  Position? _currentPosition;
  bool _hasUnsavedChanges = false;

  // Simple test to verify SharedPreferences functionality
  void testSharedPrefs() async {
    print('🧪 TEST: Testing SharedPreferences');
    try {
      final prefs = await SharedPreferences.getInstance();

      // Test writing
      await prefs.setString('test_key', 'test_value');
      print('🧪 TEST: Successfully wrote to SharedPreferences');

      // Test reading
      final value = prefs.getString('test_key');
      print('🧪 TEST: Read value: $value');

      if (value == 'test_value') {
        print('🧪 TEST: SharedPreferences working correctly');
      } else {
        print('🧪 TEST: SharedPreferences not working properly');
      }
    } catch (e) {
      print('🧪 TEST: Error with SharedPreferences: $e');
    }
  }

  final List<GeneratedDocument> generatedEstimates = [];
  final List<GeneratedDocument> generatedQuotes = [];
  bool _inProgressSaveCreatedThisSession =
      false; // Now mutable for session tracking
  String? _currentInProgressId; // Track the current in-progress build ID
  bool _originalInProgressBuildDeleted =
      false; // Track if the original in-progress build was deleted
  final ScrollController _mainScrollController = ScrollController();
  bool _isDraggingSectionItem = false;
  Offset? _dragPointerPosition;
  double _dragAutoScrollViewportHeight = 0.0;
  Timer? _dragAutoScrollTimer;

  // Initialize controllers immediately to avoid late initialization errors
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerAddressController =
      TextEditingController();
  final TextEditingController _orderNumberController = TextEditingController();
  final TextEditingController _jobNotesController = TextEditingController();
  final TextEditingController _scopeSummaryController = TextEditingController();
  final TextEditingController _scopeExclusionsController =
      TextEditingController();
  final TextEditingController _liabilityRiskSearchController =
      TextEditingController();
  String _liabilityRiskSearchQuery = '';
  List<Map<String, String>> _selectedLiabilityRisks = [];
  static final List<Map<String, String>> _defaultLiabilityRisks = [
    {
      'title': 'Ceiling Damage risk',
      'description':
          'Ceiling space contains insulation that covers or obscure timber framing and safe stepping points. This increases the risk of reduced footing visibility and potential incidental contact with ceiling linings causing damage to ceiling.',
    },
    {
      'title': 'Pipe Work In Ceiling Risk',
      'description':
          'Existing pipework may be concealed under insulation. There is a risk of accidental damage when moving through the ceiling if the pipe is old or brittle (including water damage from a broken pipe).',
    },
    {
      'title': 'Concealed Wall Services',
      'description':
          'Walls may contain unknown electrical wiring, plumbing, structural elements, or other services not visible prior to drilling or cutting. There is a risk of incidental damage with concealed services during installation work.',
    },
    {
      'title': 'Potential Access Cutting',
      'description':
          'To complete installation work, wall linings may need to be cut or opened to access concealed areas or route services. If required there will be a verbal conversation about options first. Where this is required due to construction limitations, repair and reinstatement of wall linings (including stopping, plastering, painting, and finishing) is the responsibility of the customer.',
    },
    {
      'title': 'Access Cutting',
      'description':
          'To complete installation work, wall linings need to be cut or opened to access concealed areas or route services. Where this is required due to construction limitations, repair and reinstatement of wall linings (including stopping, plastering, painting, and finishing) is the responsibility of the customer unless otherwise agreed.',
    },
    {
      'title': 'Drilling Down Wall Cavity',
      'description':
          'Drilling from roof space using long-reach drill bits may result in minor deviation of the exit point due to limited visibility, angle variation, insulation, framing, or concealed obstructions. This may result in unintended exit through wall linings or adjacent surfaces.',
    },
    {
      'title': 'Plan Alteration Possibility',
      'description':
          'During installation, concealed framing, services, or structural elements may prevent cables or fixtures being installed at the requested location. Alternative routing or installation positions may be required.',
    },
    {
      'title': 'Investigation Damage',
      'description':
          'To install the fitting I may need to cut into the lining to first determine if install is possible in that location. If a hole is cut and the fixture can\'t go in that location there will be painting and plastering required to fix the lining.',
    },
    {
      'title': 'Loss of Power',
      'description':
          'During the work there will be times the entire house power will be off. If this is a concern for you, please let me know so I can arrange a suitable time for power to be switched off.',
    },
    {
      'title': 'Loss of Power for Day',
      'description':
          'During the work there will be a loss of power for most of the day.',
    },
    {
      'title': 'Loss of Work and Damage to Devices',
      'description':
          'During the work there will be times when the power to the entire house is turned off. I will notify you before turning the power off, but there is also a chance the power may accidentally trip. Please make sure work is backed up and sensitive devices are powered down (like computers).',
    },
  ];
  static const String _builderNotePrefix = '[Estimate Builder Note] ';

  // Deposit system
  double? _depositAmount; // Fixed dollar amount
  double? _depositPercentage; // Percentage of main total
  bool _isDepositPercentage = false; // Track if it's percentage vs fixed amount

  Future<PdfColor> getPdfBannerColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_banner_color');
    if (colorString != null &&
        colorString.startsWith('#') &&
        colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 |
          (r * 255).toInt() << 16 |
          (g * 255).toInt() << 8 |
          (b * 255).toInt());
    }
    // Default:
    return PdfColors.green400;
  }

  Future<PdfColor> getPdfLineItemColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_line_item_color');
    if (colorString != null &&
        colorString.startsWith('#') &&
        colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 |
          (r * 255).toInt() << 16 |
          (g * 255).toInt() << 8 |
          (b * 255).toInt());
    }
    // Default to banner color if not set
    return await getPdfBannerColor();
  }

  Future<PdfColor> getPdfTotalsColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_totals_color');
    if (colorString != null &&
        colorString.startsWith('#') &&
        colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 |
          (r * 255).toInt() << 16 |
          (g * 255).toInt() << 8 |
          (b * 255).toInt());
    }
    // Default to banner color if not set
    return await getPdfBannerColor();
  }

  // --- PDF styling helpers (shared look & feel for a more professional document) ---

  /// A very light tint of the accent/banner color, used for zebra-striping
  /// table rows and subtle highlight boxes without overpowering the page.
  PdfColor _pdfLightTint(PdfColor color, {double strength = 0.08}) =>
      color.shade(strength);

  /// A darker tint of the accent/banner color, used for emphasis text.
  PdfColor _pdfDarkTint(PdfColor color, {double strength = 0.75}) =>
      color.shade(strength);

  /// Clean, modern table border: no harsh full grid — just a colored rule
  /// under the header and faint hairlines between rows.
  pw.TableBorder _pdfTableBorder(PdfColor bannerColor) {
    return pw.TableBorder(
      top: pw.BorderSide(color: bannerColor, width: 1),
      bottom: pw.BorderSide(color: bannerColor, width: 1),
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    );
  }

  /// Consistently styled data table used for line items throughout the PDF:
  /// colored header band, zebra-striped rows, subtle hairline separators
  /// instead of a full grid, and tidy padding.
  pw.Widget _pdfStyledTable({
    required List<String> headers,
    required List<List<dynamic>> data,
    required PdfColor lineItemColor,
  }) {
    return pw.Table.fromTextArray(
      cellAlignment: pw.Alignment.centerLeft,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: lineItemColor),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      cellStyle: const pw.TextStyle(fontSize: 10),
      oddCellStyle: const pw.TextStyle(fontSize: 10),
      oddRowDecoration:
          pw.BoxDecoration(color: _pdfLightTint(lineItemColor, strength: 0.06)),
      border: _pdfTableBorder(lineItemColor),
      headers: headers,
      data: data,
    );
  }

  /// A section title with a colored accent bar and optional description,
  /// replacing plain bold text for a more polished, document-like hierarchy.
  pw.Widget _pdfSectionHeader(String title, PdfColor bannerColor,
      {String? subtitle}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 4,
              height: 22,
              margin: const pw.EdgeInsets.only(right: 8, top: 1),
              decoration: pw.BoxDecoration(color: bannerColor),
            ),
            pw.Expanded(
              child: pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black)),
            ),
          ],
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12),
            child: pw.Text(subtitle,
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ),
        ],
      ],
    );
  }

  /// A highlighted totals box for the grand total of a document/section,
  /// making the final figure stand out instead of blending into plain text.
  /// A highlighted totals box for the grand total of a document/section,
  /// making the final figure stand out instead of blending into plain text.
  pw.Widget _pdfTotalsBox({
    required List<pw.Widget> lines,
    required PdfColor totalsColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _pdfLightTint(totalsColor, strength: 0.06),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
            color: _pdfLightTint(totalsColor, strength: 0.2), width: 0.75),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: lines,
      ),
    );
  }

  /// A rounded card with a colored accent bar on the left edge and a light
  /// grey fill — used for bank details, deposit notices, and risk/liability
  /// callouts.
  ///
  /// NOTE: This is intentionally built with a [pw.Stack] + [pw.Positioned]
  /// (instead of a single [pw.BoxDecoration] with `borderRadius` + a
  /// left-only [pw.Border], or a [pw.Row] with `CrossAxisAlignment.stretch`):
  ///  - [pw.BoxDecoration] throws `'A borderRadius can only be given for a
  ///    uniform Border.'` if you combine a corner radius with a non-uniform
  ///    (single-side) border.
  ///  - A [pw.Row] with `CrossAxisAlignment.stretch` asks its childless accent
  ///    bar [pw.Container] to stretch to the Row's cross size, which the
  ///    `pdf` package resolves to *Infinity* whenever the Row sits in an
  ///    unbounded-height context (e.g. directly inside a [pw.MultiPage]'s
  ///    flowing content, as this card always does) — triggering
  ///    `Widget won't fit into the page as its height (Infinity)...`.
  /// The [pw.Stack] avoids this because its height is derived from the real
  /// (non-positioned) content child first; the accent bar is then
  /// [pw.Positioned] to stretch to that already-finite height.
  pw.Widget _pdfAccentCard({
    required pw.Widget child,
    required PdfColor bannerColor,
    PdfColor? fillColor,
    double accentWidth = 3,
    double radius = 6,
    pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(12),
    pw.EdgeInsetsGeometry? margin,
  }) {
    final card = pw.ClipRRect(
      horizontalRadius: radius,
      verticalRadius: radius,
      child: pw.Stack(
        children: [
          pw.Container(
            width: double.infinity,
            padding: padding.add(pw.EdgeInsets.only(left: accentWidth)),
            color: fillColor ?? PdfColors.grey100,
            child: child,
          ),
          pw.Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: pw.Container(width: accentWidth, color: bannerColor),
          ),
        ],
      ),
    );
    return margin != null ? pw.Padding(padding: margin, child: card) : card;
  }

  bool isOptionSection(
      List<SubsectionData> subsections, SubsectionData section) {
    final dividerIdx = subsections.indexWhere((s) => s.name == '---OPTIONS---');
    return dividerIdx != -1 && subsections.indexOf(section) > dividerIdx;
  }

  void _moveSubsectionBetweenMainAndOptions(SubsectionData section) {
    final isCurrentlyOption = isOptionSection(_subsections, section);
    final dividerIdx =
        _subsections.indexWhere((s) => s.name == '---OPTIONS---');

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

  // Add debug logging to track initialization
  @override
  void initState() {
    super.initState();

    print('🔧 EstimateBuilder initState');
    print('🔧 Initial items provided: ${widget.initialItems?.length ?? 0}');
    print('🔧 InProgress build ID: ${widget.inProgressBuildId}');
    print(
        '🔧 convertToInvoice=${widget.convertToInvoice}, initialTemplate=${widget.initialTemplate != null}');
    if (widget.initialDepositAmount != null ||
        widget.initialDepositPercentage != null) {
      _depositAmount = widget.initialDepositAmount;
      _depositPercentage = widget.initialDepositPercentage;
      _isDepositPercentage = widget.initialIsDepositPercentage;
      print(
          '🔧 Loaded initial deposit state: amount=$_depositAmount percentage=$_depositPercentage isPercentage=$_isDepositPercentage');
    }
    // Establish the initial build type. Priority: explicit conversion to
    // invoice > explicitly requested build type (from the "Builder" type
    // picker) > previously known source type (editing an existing
    // estimate/quote) > default to 'estimate'. This may be overridden again
    // below once an existing in-progress build's saved additionalData is
    // loaded, so the type "sticks" across app restarts.
    if (widget.convertToInvoice) {
      _buildType = 'invoice';
    } else if (widget.initialBuildType != null &&
        widget.initialBuildType!.isNotEmpty) {
      _buildType = widget.initialBuildType!;
    } else if (widget.initialSourceType != null &&
        widget.initialSourceType!.isNotEmpty) {
      _buildType = widget.initialSourceType!;
    }
    print('🔧 Initial build type: $_buildType');
    // ...existing initState code...
    WidgetsBinding.instance.addObserver(this);
    _loadInProgressIfExists().then((_) => _startAutoSaveTimer());
    _initializeLocation();

    // Load initial data from widget
    // Note: _items and _subsections are not defined in this class, so we log the existing fields
    print('🔧 Loaded ${items.length} items into items list');
    for (int i = 0; i < items.length && i < 3; i++) {
      print(
          '🔧 Item $i: ${items[i].description} - ${items[i].quantity} x ${items[i].unitPrice}');
    }
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (mounted &&
          !_isEditingFinalBuild &&
          _hasUnsavedChanges &&
          !_isSaving) {
        print('⏱️ Auto-saving in-progress build...');
        await _saveInProgressEstimate();
      }
    });
  }

  Future<void> _loadInProgressIfExists() async {
    // Always load from template or initial items first
    if (widget.initialTemplate != null) {
      // Load template when coming from job details screen
      print('📋 Loading template: ${widget.initialTemplate!.name}');
      setState(() {
        items = List<estimate_item.EstimateItem>.from(
            widget.initialTemplate!.items.map((e) => e.copyWith()));
        _subsections
          ..clear()
          ..addAll(widget.initialTemplate!.subsections
              .map((s) => s is SubsectionData ? s : SubsectionData(name: s))
              .toList()
              .cast<SubsectionData>());
      });
      print(
          '📋 Loaded template with ${items.length} items and ${_subsections.length} subsections');
      _didLoadTemplate = true;
    } else if (widget.initialItems != null) {
      // Load existing build items (when editing existing in-progress build OR final build)
      print('📋 Loading existing build items: ${widget.initialItems!.length}');

      // Check if this is a final build being edited (no inProgressBuildId but has items)
      _isEditingFinalBuild = widget.convertToInvoice
          ? false
          : (widget.inProgressBuildId == null &&
              widget.initialItems!.isNotEmpty);

      final originalItems =
          widget.initialItems!.map((item) => item.copyWith()).toList();
      final convertedReferenceItems = widget.initialItems!.map((item) {
        final originalQty = item.originalEstimateQuantity ?? item.quantity;
        final alreadyInvoiced = _calculateAlreadyInvoicedQuantity(item);
        final remainingQty =
            (originalQty - alreadyInvoiced).clamp(0.0, double.infinity);
        return item.copyWith(
          quantity: 0,
          originalEstimateQuantity: remainingQty,
        );
      }).toList();

      setState(() {
        items = widget.convertToInvoice
            ? convertedReferenceItems
            : List<estimate_item.EstimateItem>.from(widget.initialItems!);
        if (widget.convertToInvoice) {
          _conversionReferenceItems = convertedReferenceItems;
          _scopeSummaryController.text = widget.initialScopeSummary ?? '';
          _scopeExclusionsController.text = '';
          _selectedLiabilityRisks = [];
          // 🔴 NEW: Load the original quoted amounts from the source estimate/quote
          // This captures the fixed budget amounts that will be used to calculate "Quote Remaining"
          _loadQuotedAmountsFromSourceEstimate();
        }

        // Store original state for change tracking BEFORE any modifications
        if (_isEditingFinalBuild) {
          _originalItems = originalItems;
          print(
              '📋 Stored ${_originalItems.length} original items for change tracking');
        }
      });
      if (widget.initialDepositAmount != null ||
          widget.initialDepositPercentage != null) {
        setState(() {
          _depositAmount = widget.initialDepositAmount;
          _depositPercentage = widget.initialDepositPercentage;
          _isDepositPercentage = widget.initialIsDepositPercentage;
        });
        print('📋 Restored deposit state from initial props');
      }

      if (_isEditingFinalBuild) {
        print('📋 Editing final build - change tracking enabled');
      }
    }

    // Handle initial subsections if provided separately
    if (widget.initialSubsections != null &&
        widget.initialSubsections!.isNotEmpty) {
      print('📋 Loading initial subsections: ${widget.initialSubsections}');
      setState(() {
        _subsections
          ..clear()
          ..addAll(
              widget.initialSubsections!.map((s) => SubsectionData(name: s)));

        // Store original subsections for change tracking BEFORE any modifications
        if (_isEditingFinalBuild) {
          _originalSubsections = List<String>.from(widget.initialSubsections!);
          print(
              '📋 Stored ${_originalSubsections.length} original subsections for change tracking');
        }
      });
    } else if (items.isNotEmpty && _subsections.isEmpty) {
      // 🔴 NEW: Auto-populate subsections from items if not provided
      // This is important for conversions where initialSubsections might be null
      // but we still need subsections to match the items' section names
      final uniqueSections = <String>[];
      for (final item in items) {
        if (!uniqueSections.contains(item.section)) {
          uniqueSections.add(item.section);
        }
      }
      if (uniqueSections.isNotEmpty) {
        print(
            '📋 Auto-creating ${uniqueSections.length} subsections from items');
        setState(() {
          _subsections
              .addAll(uniqueSections.map((s) => SubsectionData(name: s)));
        });
      }
    }

    // Track the current in-progress build for later saves
    if (widget.inProgressBuildId != null) {
      _currentInProgressId = widget.inProgressBuildId;
    }

    if (widget.convertToInvoice) {
      print(
          '📋 convertToInvoice load: initialItems=${widget.initialItems?.length ?? 0} inProgressBuildId=${widget.inProgressBuildId} currentInProgressId=$_currentInProgressId items=${items.length}');
    }

    if (widget.inProgressBuildId != null) {
      try {
        final existingBuild = await InProgressBuildService.getBuildById(
            widget.inProgressBuildId!);
        if (existingBuild != null) {
          if (existingBuild.isFinalized) {
            // This build has already been turned into a PDF (estimate,
            // quote or invoice) and must be preserved untouched as the
            // record for that document. Any edits made in this session
            // should be saved as a brand-new duplicate build instead of
            // mutating the original, so pretend we never had an id to
            // update in place.
            _currentInProgressId = null;
            _originalInProgressBuildDeleted = true;
            print(
                '📋 Opened finalized build ${existingBuild.id} (linked to document ${existingBuild.finalizedDocumentId}) - edits will create a new duplicate build');
          }
          final additionalData =
              existingBuild.currentVersion.additionalData ?? {};
          final sectionDescriptions =
              (additionalData['sectionDescriptions'] as Map?)
                      ?.cast<String, dynamic>() ??
                  {};
          final sectionExtraCosts =
              (additionalData['sectionExtraCosts'] as Map?)
                      ?.cast<String, dynamic>() ??
                  {};

          if (widget.initialItems == null) {
            setState(() {
              items = List<estimate_item.EstimateItem>.from(
                existingBuild.currentVersion.items.map((e) => e.copyWith()),
              );
              _subsections
                ..clear()
                ..addAll(existingBuild.currentVersion.subsections
                    .map((s) => SubsectionData(
                          name: s,
                          description: sectionDescriptions[s] is String
                              ? sectionDescriptions[s] as String
                              : '',
                          extraCost: sectionExtraCosts[s] is num
                              ? (sectionExtraCosts[s] as num).toDouble()
                              : 0.0,
                        )));
              _syncSectionDescriptionControllersFromModel();
            });
          } else {
            setState(() {
              for (final section in _subsections) {
                section.description =
                    sectionDescriptions[section.name] is String
                        ? sectionDescriptions[section.name] as String
                        : section.description;
                section.extraCost = sectionExtraCosts[section.name] is num
                    ? (sectionExtraCosts[section.name] as num).toDouble()
                    : section.extraCost;
              }
              _syncSectionDescriptionControllersFromModel();
            });
          }

          if (additionalData.isNotEmpty) {
            setState(() {
              _depositAmount = additionalData['depositAmount'] is num
                  ? (additionalData['depositAmount'] as num).toDouble()
                  : _depositAmount;
              _depositPercentage = additionalData['depositPercentage'] is num
                  ? (additionalData['depositPercentage'] as num).toDouble()
                  : _depositPercentage;
              _isDepositPercentage =
                  additionalData['isDepositPercentage'] == true;
              // Restore the build type saved with this in-progress build, so
              // that a build's chosen type (estimate/quote/invoice) survives
              // app restarts and re-opening the build later. Only trust a
              // non-empty saved value; otherwise keep whatever initState
              // already determined (e.g. from initialBuildType/convertToInvoice).
              final savedBuildType = additionalData['buildType'];
              if (savedBuildType is String &&
                  savedBuildType.trim().isNotEmpty) {
                _buildType = savedBuildType;
              }
              _jobNotesController.text =
                  (additionalData['builderNote'] as String?) ??
                      _jobNotesController.text;
              _scopeSummaryController.text =
                  (additionalData['scopeSummaryNotes'] as String?) ??
                      _scopeSummaryController.text;
              _scopeExclusionsController.text =
                  (additionalData['scopeExclusionsNotes'] as String?) ??
                      _scopeExclusionsController.text;
              _selectedLiabilityRisks =
                  (additionalData['liabilityRisks'] as List<dynamic>?)
                          ?.map((risk) {
                            if (risk is Map) {
                              return {
                                'title': (risk['title'] ?? '').toString(),
                                'description':
                                    (risk['description'] ?? '').toString(),
                              };
                            }
                            return <String, String>{
                              'title': '',
                              'description': '',
                            };
                          })
                          .where((risk) => risk['title']?.isNotEmpty == true)
                          .toList() ??
                      _selectedLiabilityRisks;
              // 🔴 NEW: Restore quoted amounts so "Quote Remaining" persists
              // This is critical for conversions - the quoted amounts are fixed at conversion time
              // and should survive closing/reopening the build
              if (additionalData['quotedDocumentTotal'] is num) {
                _quotedDocumentTotal =
                    (additionalData['quotedDocumentTotal'] as num).toDouble();
                print(
                    '📋 Restored quoted document total: \$${_quotedDocumentTotal.toStringAsFixed(2)}');
              }
              if (additionalData['quotedSubsectionAmounts'] is Map) {
                final quotedMap =
                    additionalData['quotedSubsectionAmounts'] as Map;
                _quotedSubsectionAmounts.clear();
                quotedMap.forEach((key, value) {
                  if (value is num) {
                    _quotedSubsectionAmounts[key.toString()] = value.toDouble();
                  }
                });
                print(
                    '📋 Restored ${_quotedSubsectionAmounts.length} quoted subsection amounts');
              }
            });
          }

          print(
              '📋 Loaded saved in-progress build ${existingBuild.id} with ${items.length} items and ${_subsections.length} sections');
        }
      } catch (e) {
        print(
            '❌ Failed to retrieve in-progress build ${widget.inProgressBuildId}: $e');
      }
    }

    // --- Ensure divider is present ---
    if (!_subsections.any((s) => s.name == '---OPTIONS---')) {
      _subsections.add(SubsectionData(name: '---OPTIONS---'));
    }

    if (!_isEditingFinalBuild &&
        _currentInProgressId == null &&
        items.isNotEmpty) {
      await _saveInProgressEstimate();
      if (widget.convertToInvoice) {
        print(
            '📋 Saved converted invoice builder as in-progress build $_currentInProgressId');
      }
    }

    if (widget.convertToInvoice) {
      // Buy prices must always be synced from the pricebook when converting
      // to an invoice (and the user given a chance to opt in to matching
      // sell price updates). `_loadPriceBookFromDisk` populates `priceBook`
      // via `setState`, so awaiting it here guarantees it has actually
      // finished before we compare against it below. Show a loading
      // spinner for this whole sequence since checking a large pricebook
      // can take up to ~20 seconds.
      _showBuildConvertingLoadingDialog();
      try {
        await _loadPriceBookFromDisk();
        _loadTemplates();
        if (mounted) {
          await _checkAndApplyConversionPriceChanges();
        }
      } finally {
        _closeBuildConvertingLoadingDialog();
      }
    } else {
      _loadPriceBookFromDisk();
      _loadTemplates();
    }

    for (final section in _subsections) {
      _moveVehicleItemsToBottomInSection(section.name);
    }

    // Set the text for the controllers instead of reassigning them
    _customerNameController.text = widget.job.customerName ?? '';
    _customerAddressController.text = widget.job.address ?? '';
    _orderNumberController.text = widget.job.orderNumber ?? '';
    if (_jobNotesController.text.isEmpty) {
      _jobNotesController.text = _loadBuilderNoteFromJob() ?? '';
    }
    _orderNumberController.addListener(() {
      widget.job.orderNumber = _orderNumberController.text.trim();
    });

    // Only auto-save if we loaded content AND we have a build ID
    // Don't auto-save new templates immediately to prevent duplicates
    // Don't auto-save final builds being edited until changes are made
    if ((items.isNotEmpty || widget.initialItems != null) &&
        widget.inProgressBuildId != null &&
        !_isEditingFinalBuild) {
      print(
          '📋 Scheduling auto-save for existing in-progress build ${widget.inProgressBuildId}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _saveInProgressEstimateSimple();
      });
    } else if (widget.initialTemplate != null && !_isEditingFinalBuild) {
      print('📋 New template loaded - will save on first modification');
    } else if (_isEditingFinalBuild) {
      print(
          '📋 Final build loaded - will save as in-progress only if changes are made');
      // DO NOT auto-save final builds - only save when user actually makes changes
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
    _autoSaveTimer?.cancel();
    // Save in-progress estimate and pricebook before disposing
    // For final builds being edited, save as in-progress only if changes were made
    if (items.isNotEmpty && !_isSaving) {
      print(
          '🔄 Disposing - checking if save needed with ${items.length} items');
      if (_isEditingFinalBuild) {
        if (_hasChangesFromOriginal()) {
          print('🔄 Final build has changes - saving as in-progress');
          _saveInProgressEstimateSimple();
        } else {
          print('🔄 Final build has no changes - not saving');
        }
      } else {
        print('🔄 Regular build - saving');
        _saveInProgressEstimateSimple();
      }
    }
    _savePriceBookToDisk();

    _searchDebounce?.cancel();
    _saveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _customerNameController.dispose();
    _customerAddressController.dispose();
    _orderNumberController.dispose();
    _jobNotesController.dispose();
    _scopeSummaryController.dispose();
    _scopeExclusionsController.dispose();
    _liabilityRiskSearchController.dispose();
    for (final controller in _sectionDescriptionControllers.values) {
      controller.dispose();
    }
    for (final controller in _sectionExtraCostControllers.values) {
      controller.dispose();
    }
    for (final controller in _sectionSearchControllers.values) {
      controller.dispose();
    }
    for (final controller in _itemSalePriceControllers.values) {
      controller.dispose();
    }
    for (final controller in _itemQuantityControllers.values) {
      controller.dispose();
    }
    for (final node in _itemSalePriceFocusNodes.values) {
      node.dispose();
    }
    for (final node in _itemQuantityFocusNodes.values) {
      node.dispose();
    }
    _dragAutoScrollTimer?.cancel();
    _mainScrollController.dispose();
    for (final node in _sectionSearchFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  TextEditingController _getSectionDescriptionController(
      SubsectionData section) {
    return _sectionDescriptionControllers.putIfAbsent(
      section.name,
      () => TextEditingController(text: section.description),
    );
  }

  TextEditingController _getSectionExtraCostController(SubsectionData section) {
    return _sectionExtraCostControllers.putIfAbsent(
      section.name,
      () => TextEditingController(
          text: section.extraCost == 0
              ? ''
              : section.extraCost.toStringAsFixed(2)),
    );
  }

  /// Keeps any already-created section description controllers in sync with
  /// the underlying `SubsectionData.description` values. This is necessary
  /// because `_getSectionDescriptionController` lazily caches a controller
  /// the first time a subsection card is built (e.g. with a blank
  /// description before the saved build finishes loading asynchronously).
  /// Without this sync, a later autosave would read the stale/blank cached
  /// controller text and overwrite the correctly-loaded description,
  /// causing subsection descriptions to silently disappear from PDFs.
  void _syncSectionDescriptionControllersFromModel() {
    for (final section in _subsections) {
      final controller = _sectionDescriptionControllers[section.name];
      if (controller != null && controller.text != section.description) {
        controller.text = section.description;
      }
      final costController = _sectionExtraCostControllers[section.name];
      final costText =
          section.extraCost == 0 ? '' : section.extraCost.toStringAsFixed(2);
      if (costController != null && costController.text != costText) {
        costController.text = costText;
      }
    }
  }

  void _renameSectionRelatedKeys(String oldName, String newName) {
    if (_sectionDescriptionControllers.containsKey(oldName)) {
      final controller = _sectionDescriptionControllers.remove(oldName)!;
      _sectionDescriptionControllers[newName] = controller;
    }
    if (_sectionExtraCostControllers.containsKey(oldName)) {
      final controller = _sectionExtraCostControllers.remove(oldName)!;
      _sectionExtraCostControllers[newName] = controller;
    }
    if (_sectionSearchControllers.containsKey(oldName)) {
      final controller = _sectionSearchControllers.remove(oldName)!;
      _sectionSearchControllers[newName] = controller;
    }
    if (_sectionSearchFocusNodes.containsKey(oldName)) {
      final focusNode = _sectionSearchFocusNodes.remove(oldName)!;
      _sectionSearchFocusNodes[newName] = focusNode;
    }
    if (_sectionSearchQueries.containsKey(oldName)) {
      _sectionSearchQueries[newName] = _sectionSearchQueries.remove(oldName)!;
    }
    if (_sectionSearchShowMore.containsKey(oldName)) {
      _sectionSearchShowMore[newName] = _sectionSearchShowMore.remove(oldName)!;
    }
    if (_sectionSearchAddedItems.containsKey(oldName)) {
      _sectionSearchAddedItems[newName] =
          _sectionSearchAddedItems.remove(oldName)!;
    }
    if (_sectionSearchAddCounts.containsKey(oldName)) {
      _sectionSearchAddCounts[newName] =
          _sectionSearchAddCounts.remove(oldName)!;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Save in-progress estimate and pricebook when app goes to background or is paused
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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
  void _updateItemFast(
      estimate_item.EstimateItem oldItem, estimate_item.EstimateItem newItem) {
    final idx = items.indexWhere((existing) => identical(existing, oldItem));
    if (idx != -1) {
      setState(() {
        items[idx] = newItem;
        _hasUnsavedChanges = true;
      });

      final oldKey = _lineItemControllerKey(oldItem);
      final newKey = _lineItemControllerKey(newItem);

      if (_itemSalePriceControllers.containsKey(oldKey)) {
        final controller = _itemSalePriceControllers.remove(oldKey)!;
        controller.text = newItem.unitPrice.toStringAsFixed(2);
        _itemSalePriceControllers[newKey] = controller;
      }
      if (_itemQuantityControllers.containsKey(oldKey)) {
        final controller = _itemQuantityControllers.remove(oldKey)!;
        controller.text =
            newItem.quantity.truncateToDouble() == newItem.quantity
                ? newItem.quantity.toStringAsFixed(0)
                : newItem.quantity.toStringAsFixed(2);
        _itemQuantityControllers[newKey] = controller;
      }
      if (_itemSalePriceFocusNodes.containsKey(oldKey)) {
        _itemSalePriceFocusNodes[newKey] =
            _itemSalePriceFocusNodes.remove(oldKey)!;
      }
      if (_itemQuantityFocusNodes.containsKey(oldKey)) {
        _itemQuantityFocusNodes[newKey] =
            _itemQuantityFocusNodes.remove(oldKey)!;
      }
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

        // 🔴 PERFORMANCE: jsonDecode() + reorganizing 50k+ items was
        // running synchronously on the main thread, causing the
        // "Skipped 53 frames!" lag seen when opening the estimate
        // builder. Moved to a background isolate via compute().
        final limitedJsonList =
            await compute(_parseAndOrganizePriceBookJson, jsonString);

        if (!mounted) return;
        setState(() {
          priceBook = limitedJsonList
              .map((e) => models.PriceBookItem.fromJson(e))
              .toList();
        });

        // Ensure hardcoded labour items are present even if not in file
        _ensureHardcodedLabourItems();
        _refreshTemplateItemPricesFromPriceBook();
      } catch (e) {
        print('❌ Error loading price book in estimate builder: $e');
      }
    }
  }

  bool _isBuildConvertingLoadingDialogShown = false;

  /// Shows a non-dismissible "Converting build..." loading spinner while
  /// the pricebook is loaded from disk and checked for price changes as
  /// part of converting an estimate/quote to an invoice. This whole
  /// sequence can take up to ~20 seconds for large pricebooks, so the user
  /// gets clear feedback that something is happening rather than the
  /// screen appearing to hang.
  void _showBuildConvertingLoadingDialog() {
    if (!mounted || _isBuildConvertingLoadingDialogShown) return;
    _isBuildConvertingLoadingDialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Converting build... checking pricebook for price '
                  'changes. This may take up to 20 seconds.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Closes the "Converting build..." loading spinner shown by
  /// `_showBuildConvertingLoadingDialog`, if currently open.
  void _closeBuildConvertingLoadingDialog() {
    if (!_isBuildConvertingLoadingDialogShown) return;
    _isBuildConvertingLoadingDialogShown = false;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// When converting an estimate/quote to an invoice, checks every line
  /// item's buy (purchase) price against the current pricebook value.
  /// - The buy price is ALWAYS synced to the pricebook's current value,
  ///   regardless of whether the user is shown/responds to any dialog.
  /// - If syncing the buy price would also change the sell price for any
  ///   item (i.e. the item's sell price is derived from purchase price +
  ///   markup), a dialog is shown listing exactly those items so the user
  ///   can choose, per item, whether to also update the sell price. Items
  ///   the user doesn't select keep their original (estimate/quote) sell
  ///   price - only the buy price changes for those.
  /// - If no item's buy price has actually changed, nothing happens and no
  ///   dialog is shown.
  Future<void> _checkAndApplyConversionPriceChanges() async {
    if (_hasCheckedConversionPriceChanges) return;
    _hasCheckedConversionPriceChanges = true;

    if (priceBook.isEmpty || items.isEmpty) return;

    final List<ConversionPriceChange> changes = [];

    // Date-only anchor (time-of-day stripped) for the source
    // estimate/quote's generation date - matches the user's "same date or
    // later" wording rather than requiring an exact time-of-day match.
    final sourceTimestamp = widget.initialSourceTimestamp;
    final sourceDateOnly = sourceTimestamp != null
        ? DateTime(
            sourceTimestamp.year, sourceTimestamp.month, sourceTimestamp.day)
        : null;

    for (final item in items) {
      // Skip synthetic/non-catalogue lines (deposits, manual discounts etc.)
      final normalizedDescription = normalizeCode(item.description);
      final normalizedName = normalizeCode(item.name);
      if (normalizedDescription == 'deposit' ||
          normalizedName == 'deposit received' ||
          normalizedDescription == 'dis') {
        continue;
      }

      final match = _findPriceBookMatchForItem(item);
      if (match == null) continue;

      final oldPurchasePrice = item.purchasePrice ?? 0.0;
      final newPurchasePrice = match.purchasePrice;
      final numericPurchasePriceDiffers =
          (newPurchasePrice - oldPurchasePrice).abs() >= 0.005;

      // Decide whether this item counts as "changed" for conversion
      // purposes (i.e. gets its buy price synced and becomes a candidate
      // for the sell-price dialog below). Prefer the date-based check -
      // was this pricebook item's buy OR sell price actually touched
      // (edited) on or after the source estimate/quote's generation date?
      // - since that also correctly catches items that were edited back
      // to the same numeric value. Fall back to the old numeric-
      // difference check whenever we don't have both dates available
      // (e.g. items/documents that predate this feature), so nothing
      // slips through during the transition period.
      final priceTouchedAt = match.priceLastChangedAt;
      final bool shouldTrigger;
      if (sourceDateOnly != null && priceTouchedAt != null) {
        final touchedDateOnly = DateTime(
            priceTouchedAt.year, priceTouchedAt.month, priceTouchedAt.day);
        shouldTrigger = !touchedDateOnly.isBefore(sourceDateOnly);
      } else {
        shouldTrigger = numericPurchasePriceDiffers;
      }

      if (!shouldTrigger) continue;

      final newSellPrice = _effectivePriceFromPriceBookItem(match);

      changes.add(ConversionPriceChange(
        item: item,
        oldPurchasePrice: oldPurchasePrice,
        newPurchasePrice: newPurchasePrice,
        oldSellPrice: item.unitPrice,
        newSellPrice: newSellPrice > 0 ? newSellPrice : item.unitPrice,
        sellPriceLocked: item.sellPriceManuallyEdited,
      ));
    }

    if (changes.isEmpty) return;

    // The buy price is ALWAYS updated from the pricebook, no matter what the
    // user decides about the sell price below.
    for (final change in changes) {
      final updatedItem = change.item.copyWith(
        purchasePrice: change.newPurchasePrice,
      );
      _updateItemFast(change.item, updatedItem);
    }

    // Show the dialog for any item where syncing the buy price would also
    // change the sell price (the normal case), OR where the item's sell
    // price is locked (manually edited) but its buy price still changed -
    // shown informationally in that case so the user knows the buy price
    // moved, even though the sell price itself can't be touched.
    final sellPriceChanges = changes
        .where((c) => c.sellPriceWouldChange || c.sellPriceLocked)
        .toList();
    if (sellPriceChanges.isEmpty || !mounted) return;

    await _showConversionPriceChangeDialog(sellPriceChanges);
  }

  /// Shows the "Purchase Prices Have Changed" dialog listing every item
  /// whose sell price would change if synced to the (already-applied) new
  /// pricebook buy price. Lets the user tick individual items, "Change All"
  /// (or "Change Selected" once some are ticked), or keep the original sell
  /// prices.
  Future<void> _showConversionPriceChangeDialog(
      List<ConversionPriceChange> changes) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Locked (manually-priced) items are informational only - they
            // never count toward "selected"/"all selected"/"Select All"/
            // "Change All" since their sell price can't be changed here.
            final selectableChanges =
                changes.where((c) => !c.sellPriceLocked).toList();
            final anySelected = selectableChanges.any((c) => c.selected);
            final allSelected = selectableChanges.isNotEmpty &&
                selectableChanges.every((c) => c.selected);

            return AlertDialog(
              title: const Text('Purchase Prices Have Changed'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'The buy price for the items below has changed since '
                      'this document was created. The buy price has been '
                      'updated automatically. Tick any items where you also '
                      'want to update the sell price to match the new '
                      'pricing, or leave unticked to keep the original sell '
                      'price. Items with a manually-set sell price are '
                      'shown for reference only and are never changed here.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: changes.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final change = changes[index];
                          if (change.sellPriceLocked) {
                            return ListTile(
                              leading: const Icon(Icons.lock_outline,
                                  color: Colors.black45),
                              title: Text(
                                change.item.name.isNotEmpty
                                    ? change.item.name
                                    : change.item.description,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Buy: \$${change.oldPurchasePrice.toStringAsFixed(2)} → \$${change.newPurchasePrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const Text(
                                    'Sell price manually set - kept as-is.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                              dense: true,
                            );
                          }
                          return CheckboxListTile(
                            value: change.selected,
                            onChanged: (value) {
                              setDialogState(() {
                                change.selected = value ?? false;
                              });
                            },
                            title: Text(
                              change.item.name.isNotEmpty
                                  ? change.item.name
                                  : change.item.description,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Buy: \$${change.oldPurchasePrice.toStringAsFixed(2)} → \$${change.newPurchasePrice.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Sell: \$${change.oldSellPrice.toStringAsFixed(2)} → \$${change.newSellPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: change.newSellPrice >
                                            change.oldSellPrice
                                        ? Colors.red
                                        : Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    // Cancel backs all the way out to the Job Details screen
                    // instead of continuing in the builder. Any buy-price
                    // sync already applied in memory is simply discarded
                    // since we never save before popping.
                    if (mounted && Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Keep Same'),
                ),
                if (selectableChanges.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        for (final change in selectableChanges) {
                          change.selected = true;
                        }
                      });
                    },
                    child: const Text('Select All'),
                  ),
                if (selectableChanges.isNotEmpty)
                  ElevatedButton(
                    onPressed: () {
                      _applySelectedConversionSellPriceChanges(anySelected
                          ? selectableChanges.where((c) => c.selected).toList()
                          : selectableChanges);
                      Navigator.pop(dialogContext);
                    },
                    child: Text(anySelected
                        ? (allSelected ? 'Change All' : 'Change Selected')
                        : 'Change All'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Applies the new (pricebook-derived) sell price to exactly the items the
  /// user chose to update from the conversion price-change dialog. The buy
  /// price for every affected item has already been updated regardless.
  void _applySelectedConversionSellPriceChanges(
      List<ConversionPriceChange> changesToApply) {
    for (final change in changesToApply) {
      // Find the item's current in-list instance (its purchasePrice was
      // already updated by `_checkAndApplyConversionPriceChanges`, so we
      // must look it up fresh rather than reusing `change.item`, which may
      // now be stale/replaced in the `items` list).
      final currentItem = items.firstWhereOrNull((i) =>
          normalizeCode(i.description) ==
              normalizeCode(change.item.description) &&
          normalizeCode(i.name) == normalizeCode(change.item.name) &&
          i.section == change.item.section);
      if (currentItem == null) continue;

      final updatedItem = currentItem.copyWith(unitPrice: change.newSellPrice);
      _updateItemFast(currentItem, updatedItem);
    }
    if (changesToApply.isNotEmpty) {
      _hasUnsavedChanges = true;
      _saveInProgressEstimate();
    }
  }

  Future<void> _searchExtensivePriceBookAndOfferImport(
      SubsectionData section, String query) async {
    if (query.trim().isEmpty || !mounted) return;

    print('🔎 [ExtensiveSearch] query="$query" for section="${section.name}"');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    List<models.PriceBookItem> extensiveItems = [];
    try {
      extensiveItems = await _loadExtensivePriceBookFromDisk();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
    if (!mounted) return;

    print(
        '🔎 [ExtensiveSearch] loaded extensive items count: ${extensiveItems.length}');
    if (extensiveItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Extensive pricebook is empty or unavailable.')),
      );
      return;
    }

    final results = searchPriceBook(extensiveItems, query, maxResults: 30);
    print('🔎 [ExtensiveSearch] found ${results.length} search results');
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No items found in the extensive pricebook.')),
      );
      return;
    }

    // Session-scoped (dialog-lifetime only) tracking so repeat '+' taps bump
    // quantity instead of duplicating lines, mirroring the inline search box.
    final addedItems = <String, estimate_item.EstimateItem>{};
    final addCounts = <String, int>{};
    bool showMoreResults = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final displayedCount =
              math.min(results.length, showMoreResults ? 30 : 10);
          return AlertDialog(
            title: const Text('Extensive pricebook results'),
            content: SizedBox(
              width: 420,
              height: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: displayedCount,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        final addCount = addCounts[item.code] ?? 0;
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                              'Code: ${item.code}  \$${item.salePrice.toStringAsFixed(2)}'),
                          // Tapping the tile adds the item and closes the dialog.
                          onTap: () {
                            setState(() {
                              _addOrBumpExtensivePriceBookItem(
                                  section, item,
                                  existing: addedItems[item.code]);
                            });
                            Navigator.pop(dialogContext);
                          },
                          // The '+' button adds/bumps quantity but keeps the
                          // dialog open so multiple items can be added in a row.
                          trailing: TextButton(
                            onPressed: () {
                              late estimate_item.EstimateItem added;
                              setState(() {
                                added = _addOrBumpExtensivePriceBookItem(
                                    section, item,
                                    existing: addedItems[item.code]);
                              });
                              setDialogState(() {
                                addedItems[item.code] = added;
                                addCounts[item.code] = addCount + 1;
                              });
                            },
                            child: Text(
                                addCount > 0 ? '+ ($addCount)' : '+'),
                          ),
                        );
                      },
                    ),
                  ),
                  if (addedItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final entry in addedItems.entries)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.check, size: 16),
                              label: Text(
                                  '${entry.value.name} x${addCounts[entry.key] ?? 1}'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (results.length > 10)
                TextButton(
                  onPressed: () => setDialogState(
                      () => showMoreResults = !showMoreResults),
                  child: Text(showMoreResults ? 'Show less' : 'Show more'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted || addedItems.isEmpty) return;
    setState(() {
      _sectionSearchQueries[section.name] = '';
      _sectionSearchControllers[section.name]?.clear();
    });
    _saveInProgressEstimateSimple();
  }

  /// Adds an extensive-pricebook search result to the subsection (importing it
  /// into the local pricebook cache first), or bumps `existing`'s quantity if
  /// it was already added earlier in this same dialog session. Must be called
  /// inside setState.
  /// 🔴 NEW: Creates a custom item from the search text.
  /// Takes the typed search query and opens the manual entry dialog with it as the item name.
  Future<void> _createCustomItemFromSearch(
      SubsectionData section, String searchText) async {
    // Create an item with the search text as the name
    final customItem = estimate_item.EstimateItem(
      name: searchText.trim(),
      description: '', // Empty code - user can fill it in manually
      quantity: 1,
      unitPrice: 0,
      section: section.name,
      isPerMeter: false,
      meterAmount: 1,
    );

    // Open the manual entry dialog with this item pre-filled
    final item = await showDialog<estimate_item.EstimateItem>(
      context: context,
      builder: (context) => AddEstimateItemDialog(
        priceBook: priceBook,
        initialSection: section.name,
        availableSections: _subsections.map((s) => s.name).toList(),
        onScanReceipt: _scanReceipt,
        savePriceBook: () async => _savePriceBookToDisk(),
        initialItem: customItem,
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
        _moveVehicleItemsToBottomInSection(section.name);
        _hasUnsavedChanges = true;
        _sectionSearchQueries[section.name] = '';
        _sectionSearchControllers[section.name]?.clear();
      });
      _saveInProgressEstimateSimple();
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
        savePriceBook: () async => _savePriceBookToDisk(),
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
        _moveVehicleItemsToBottomInSection(section.name);
        _hasUnsavedChanges = true;
        _sectionSearchQueries[section.name] = '';
        _sectionSearchControllers[section.name]?.clear();
      });
      _saveInProgressEstimateSimple(); // Use the simple save method

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
          final idx = items.lastIndexWhere(
              (i) => i.section == section && i.description == 'CAL');
          if (idx != -1) {
            final dateStr =
                '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
            items[idx] = items[idx].copyWith(
              name: 'Labour on $dateStr',
              description: 'Labour on $dateStr',
            );
          }
          _hasUnsavedChanges = true;
        });
      } else {
        _saveInProgressEstimateSimple();
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
            textCapitalization: TextCapitalization.sentences,
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
                if (newSection != null &&
                    newSection!.isNotEmpty &&
                    !_subsections.any((s) => s.name == newSection)) {
                  final dividerIdx =
                      _subsections.indexWhere((s) => s.name == '---OPTIONS---');
                  setState(() {
                    // Insert before the divider, or at end if divider not found
                    if (dividerIdx == -1) {
                      _subsections.add(SubsectionData(name: newSection!));
                    } else {
                      _subsections.insert(
                          dividerIdx, SubsectionData(name: newSection!));
                    }
                    _hasUnsavedChanges = true;
                  });
                  Navigator.pop(context);
                  _saveInProgressEstimateSimple(); // Save after adding subsection
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
            : (_depositAmount?.toStringAsFixed(2) ?? ''));
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
                textCapitalization: TextCapitalization.sentences,
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
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
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                child: Text('Remove Deposit',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
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
      _saveInProgressEstimateSimple();
    }
  }

  void _deleteSubsection(SubsectionData section) {
    setState(() {
      _subsections.remove(section);
      items.removeWhere((item) => item.section == section.name);
      _sectionDescriptionControllers.remove(section.name)?.dispose();
      _sectionExtraCostControllers.remove(section.name)?.dispose();
      _sectionSearchControllers.remove(section.name)?.dispose();
      _sectionSearchFocusNodes.remove(section.name)?.dispose();
      _sectionSearchQueries.remove(section.name);
      _sectionSearchShowMore.remove(section.name);
      _sectionSearchAddedItems.remove(section.name);
      _sectionSearchAddCounts.remove(section.name);
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _editLiabilityRisk(int index) async {
    final risk = _selectedLiabilityRisks[index];
    final titleController = TextEditingController(text: risk['title']);
    final descriptionController =
        TextEditingController(text: risk['description']);

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit risk or liability'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (save != true) return;

    final updatedTitle = titleController.text.trim();
    final updatedDescription = descriptionController.text.trim();
    if (updatedTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A risk title is required.')),
      );
      return;
    }

    final duplicateIndex = _selectedLiabilityRisks.indexWhere((other) {
      return other != risk &&
          (other['title'] ?? '').toLowerCase() == updatedTitle.toLowerCase();
    });
    if (duplicateIndex != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A risk with that title already exists.')),
      );
      return;
    }

    setState(() {
      _selectedLiabilityRisks[index] = {
        'title': updatedTitle,
        'description': updatedDescription,
      };
      _hasUnsavedChanges = true;
    });
    _saveInProgressEstimate();
  }

  Future<List<estimate_item.EstimateItem>?> _scanReceipt(String section,
      {ImageSource source = ImageSource.camera}) async {
    // First, let user select supplier template
    final selectedTemplate = await _showSupplierTemplateSelector();
    if (selectedTemplate == null) return null;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return null;

    final inputImage = InputImage.fromFile(File(pickedFile.path));
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText =
        await textRecognizer.processImage(inputImage);

    final receiptText = recognizedText.text;
    textRecognizer.close();

    final extractedList =
        await _analyzeReceiptTextWithTemplate(receiptText, selectedTemplate);

    if (extractedList == null ||
        extractedList is! List ||
        extractedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items found on receipt.')),
      );
      return null;
    }

    // Check for missing id_number and warn user
    final missingIdItems = extractedList
        .where((item) => (item['id_number'] == null ||
            item['id_number'].toString().trim().isEmpty))
        .toList();

    if (missingIdItems.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some items missing ID code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'The following items do not have an ID code and will be skipped:'),
              ...missingIdItems.map((item) => Text(item['item_name'] ?? '',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
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
    final filteredExtractedList = extractedList
        .where((item) =>
            item['id_number'] != null &&
            item['id_number'].toString().trim().isNotEmpty)
        .toList();

    // If no items with id_number, show a warning and return
    if (filteredExtractedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items with ID code found.')),
      );
      return null;
    }

    final selectedItems = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => SelectExtractedItemsDialogMulti(
        items: filteredExtractedList.cast<Map<String, dynamic>>(),
        showQuantity: true,
      ),
    );

    if (selectedItems != null && selectedItems.isNotEmpty) {
      final newItems = <estimate_item.EstimateItem>[];
      for (final item in selectedItems) {
        final bin = (item['bin_number'] ?? '').toString().trim();
        final id = (item['id_number'] ?? '').toString().trim();
        final name = (item['item_name'] ?? '').toString().trim();
        final qty = (item['quantity'] ?? 1) is int
            ? item['quantity']
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;

        // DEBUG: Print extracted bin_number, id_number and name
        print(
            '🟢 Extracted item: bin_number="$bin", id_number="$id", name="$name"');

        models.PriceBookItem? pbItem;
        // Try bin_number first if present
        if (bin.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull(
              (pb) => normalizeCode(pb.code) == normalizeCode(bin));
        }
        // If not found, try id_number
        if (pbItem == null && id.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull(
              (pb) => normalizeCode(pb.code) == normalizeCode(id));
        }
        // If still not found, try name
        if (pbItem == null && name.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull(
              (pb) => pb.name.trim().toLowerCase() == name.toLowerCase());
        }

        // DEBUG: Print pricebook match result
        if (pbItem != null) {
          print(
              '✅ Pricebook match found: code="${pbItem.code}", price=${pbItem.price}');
        } else {
          print(
              '❌ No pricebook match for bin_number="$bin" or id_number="$id"');
        }

        if (pbItem != null) {
          pbItem.isUsed = true; // <-- Mark as used
          newItems.add(
            estimate_item.EstimateItem(
              name: pbItem.name,
              description: pbItem.code,
              unitPrice: _effectivePriceFromPriceBookItem(pbItem),
              quantity: qty.toDouble(),
              purchasePrice: pbItem.purchasePrice,
              section: section,
              // 🔴 NEW: Pass per-meter pricing from pricebook item
              isPerMeter: pbItem.isPerMeter,
              meterAmount: pbItem.meterAmount,
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
        _moveVehicleItemsToBottomInSection(section);
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
            final idx = items.lastIndexWhere(
                (i) => i.section == section && i.description == 'CAL');
            if (idx != -1) {
              final dateStr =
                  '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
              items[idx] = items[idx].copyWith(
                name: 'Labour on $dateStr',
                description: 'Labour on $dateStr',
              );
            }
            _hasUnsavedChanges = true;
          });
        }
      }

      _saveInProgressEstimateSimple();
      _savePriceBookToDisk(); // <-- Save pricebook after marking as used
      return newItems;
    }
    return null;
  }

  Future<void> _showAiProgressDialog(String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  Future<dynamic> _analyzeReceiptText(String text) async {
    final apiKey = await OpenAiKeyService.getKey();
    final prompt = '''
You are reading a JA Russell invoice. Extract all line items as a JSON array.
For each item, return:
- "id_number": the Stock code (e.g. "100010" or "Q5070535").
  **Never use the Bin column. Never use the Name/Description column as the ID code, even if it contains numbers or codes.
  The Stock code is always to the right of the Bin column and may be numeric or alphanumeric (e.g. "100010" or "Q5070535").
  Do not return "0" for id_number unless the stock code in the invoice is literally "0".**
- "item_name": the Name/Description (e.g. "1.5mm² TWIN & EARTH CABLE")
- "quantity": the Qty (as an integer)
- "net_price": the Net Price per unit (the purchase price from the "Net Price" column, as a decimal number)

Do NOT ignore the Net Price column - this is the purchase price and must be extracted accurately.

The Bin column is often the first column and may contain numbers or be blank. The Stock code is always the next column to the right of Bin and may be numeric or alphanumeric (e.g. "100010" or "Q5070535"). Do not use the Bin value as the Stock code.

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

    _showAiProgressDialog('Sending receipt data to AI...');
    try {
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
        // Parse error response for better error message
        String errorMessage = 'AI error (${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            final error = errorData['error'];
            if (error is Map && error.containsKey('message')) {
              errorMessage = error['message'] ?? errorMessage;
            }
          }
        } catch (_) {
          errorMessage = 'AI error: ${response.statusCode}';
        }

        debugPrint('❌ Receipt analysis failed: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        throw Exception('Failed to analyze receipt: $errorMessage');
      }
    } catch (e) {
      // Catch network or other errors
      debugPrint('❌ Receipt analysis error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
      rethrow;
    } finally {
      // Ensure the progress dialog is dismissed if not already
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  /// Show supplier template selector dialog
  Future<String?> _showSupplierTemplateSelector() async {
    // Get selected supplier templates from settings
    final prefs = await SharedPreferences.getInstance();
    final selectedTemplatesString =
        prefs.getString('selected_supplier_templates') ?? '';
    final selectedTemplates = selectedTemplatesString.isNotEmpty
        ? selectedTemplatesString.split(',')
        : <String>[];

    if (selectedTemplates.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Supplier Templates'),
          content: const Text(
              'No supplier templates are selected in settings. Please go to Settings > Company Settings > PDF Receipt Scanner to select your supplier templates.'),
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
  Future<dynamic> _analyzeReceiptTextWithTemplate(
      String text, String templateName) async {
    // Load the specific template prompt
    String templatePrompt;
    try {
      final templateFile = await rootBundle.loadString(
          'assets/receipt_templates/${templateName.toLowerCase().replaceAll(' ', '_')}.txt');
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

    final apiKey = await OpenAiKeyService.getKey();
    final fullPrompt = templatePrompt.replaceAll(r'$text', text);

    _showAiProgressDialog('Sending receipt data to AI...');
    try {
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
        // Parse error response for better error message
        String errorMessage = 'AI error (${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            final error = errorData['error'];
            if (error is Map && error.containsKey('message')) {
              errorMessage = error['message'] ?? errorMessage;
            }
          }
        } catch (_) {
          errorMessage = 'AI error: ${response.statusCode}';
        }

        debugPrint('❌ Template receipt analysis failed: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        throw Exception('Failed to analyze receipt: $errorMessage');
      }
    } catch (e) {
      // Catch network or other errors
      debugPrint('❌ Template receipt analysis error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
      rethrow;
    } finally {
      // Ensure the progress dialog is dismissed if not already
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
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

      final saved = await _saveInProgressEstimate();
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Build saved successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to save build. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save build: $e')),
      );
    }
  }

  String normalize(String? s) => (s ?? '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '')
      .replaceAll('\u200B', '')
      .replaceAll('\uFFFD', '')
      .trim();

  String normalizeCode(String? s) => (s ?? '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '')
      .replaceAll('\u200B', '')
      .replaceAll('\uFFFD', '')
      .trim()
      .toLowerCase();

  void _onBarcodeScanned(String scannedBarcode, String section,
      TextEditingController searchController) async {
    // 🔍 MEMORY DEBUG: Entry point
    print('🔍 [BARCODE SCAN ENTRY] barcode=$scannedBarcode, section=$section');
    final searchStopwatch = Stopwatch()..start();

    final normalizedScanned = normalizeCode(scannedBarcode);

    // Try to match barcode field first (if present)
    final matchesByBarcode = priceBook.where((item) {
      final itemBarcode = (item.barcode ?? '').toString();
      return normalizeCode(itemBarcode) == normalizedScanned;
    }).toList();
    print('🔍 [BARCODE SEARCH] Barcode matches: ${matchesByBarcode.length}');

    // Fallback: match by code
    final matchesByCode = priceBook.where((item) {
      return normalizeCode(item.code) == normalizedScanned;
    }).toList();
    print('🔍 [BARCODE SEARCH] Code matches: ${matchesByCode.length}');

    // Fallback: match by name
    final matchesByName = priceBook.where((item) {
      return normalizeCode(item.name) == normalizedScanned;
    }).toList();
    print('🔍 [BARCODE SEARCH] Name matches: ${matchesByName.length}');

    // Merge unique matches (barcode > code > name)
    final matches = <models.PriceBookItem>[
      ...matchesByBarcode,
      ...matchesByCode
          .where((c) => !matchesByBarcode.any((b) => b.code == c.code)),
      ...matchesByName.where((n) =>
          !matchesByBarcode.any((b) => b.code == n.code) &&
          !matchesByCode.any((c) => c.code == n.code)),
    ];
    print(
        '🔍 [BARCODE SEARCH] Total search time: ${searchStopwatch.elapsedMilliseconds}ms, final matches: ${matches.length}');

    if (matches.length == 1) {
      final pbItem = matches.first;
      final existing = items.firstWhereOrNull(
        (e) => e.section == section && e.description == pbItem.code,
      );

      // � MEMORY DEBUG: Before setState
      print(
          '🔍 [BEFORE SETSTATE] items.count=${items.length}, existing=${existing != null}');
      final setStateStopwatch = Stopwatch()..start();

      // �🚀 PERFORMANCE: Batch all setState() calls into ONE update,
      // then save in background (don't block UI on file I/O)
      setState(() {
        pbItem.usageCount = pbItem.usageCount + 1;
        pbItem.isUsed = true;
        if (existing != null) {
          final idx = items.indexOf(existing);
          items[idx] = existing.copyWith(quantity: existing.quantity + 1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Item already in $section, quantity increased by 1.')),
          );
        } else {
          items.add(
            estimate_item.EstimateItem(
              name: pbItem.name,
              description: pbItem.code,
              unitPrice: _effectivePriceFromPriceBookItem(pbItem),
              quantity: 1,
              purchasePrice: pbItem.purchasePrice,
              section: section,
              // 🔴 NEW: Pass per-meter pricing from pricebook item
              isPerMeter: pbItem.isPerMeter,
              meterAmount: pbItem.meterAmount,
            ),
          );
          _moveVehicleItemsToBottomInSection(section);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added ${pbItem.name} to $section.')),
          );
        }
        searchController.clear();
        _sectionSearchQueries[section] = '';
      });

      // 🔍 MEMORY DEBUG: After setState, before saves
      print(
          '🔍 [AFTER SETSTATE] setState took ${setStateStopwatch.elapsedMilliseconds}ms, items now=${items.length}');

      // Save in background - don't block UI on file I/O
      // Fire & forget pattern: errors are printed but don't interrupt user
      final saveStopwatch = Stopwatch()..start();
      _saveInProgressEstimate().catchError((e) {
        print('❌ Auto-save estimate failed: $e');
        print('⏱️ Save took ${saveStopwatch.elapsedMilliseconds}ms');
        return false;
      });

      // 🔍 MEMORY DEBUG: Track price book save
      print('🔍 [BEFORE PRICEBOOK SAVE] Calling _savePriceBookToDisk()...');
      _savePriceBookToDisk(); // Debounced async save, won't block UI
      print('🔍 [AFTER PRICEBOOK SAVE] (async, may still be running)');

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
          final idx = items.lastIndexWhere(
              (i) => i.section == section && i.description == 'CAL');
          if (idx != -1) {
            final dateStr =
                '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
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
        const SnackBar(
            content: Text(
                'Multiple items found, please select from search results.')),
      );
    } else {
      final searchExtensive = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Item not found'),
          content: const Text(
              'This barcode was not found in the main pricebook. Search the extensive pricebook?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Search Extensive')),
          ],
        ),
      );

      if (searchExtensive == true) {
        await _searchExtensivePriceBookAndOfferImport(
            SubsectionData(name: section),
            searchController.text.isNotEmpty
                ? searchController.text
                : scannedBarcode);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No item found for this barcode.')),
        );
      }
    }
  }

  Future<String> _getNextDocumentNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final dateKey = '$yy$mm$dd'; // e.g. 260903

    final lastDate = prefs.getString('last_document_date') ?? '';
    int counter = 1;
    if (lastDate == dateKey) {
      counter = (prefs.getInt('last_document_counter') ?? 0) + 1;
    } else {
      counter = 1;
    }

    await prefs.setString('last_document_date', dateKey);
    await prefs.setInt('last_document_counter', counter);

    return '$dateKey${counter.toString()}';
  }

  Future<void> _generateEstimatePdf(
      {required String type,
      required String layout,
      bool includeScopePage = false}) async {
    FocusScope.of(context).unfocus();
    final bool showItems = layout != 'summary';
    final bool showLineTotals = layout == 'full';
    print(
        '🧾 _generateEstimatePdf called: type=$type layout=$layout items=${items.length} showItems=$showItems showLineTotals=$showLineTotals');
    // DEBUG: inserted marker for preview route patch test
    final prefs = await SharedPreferences.getInstance();
    final logoPath = prefs.getString('company_logo_path');
    final companyName = prefs.getString('company_name') ?? 'Your Company Name';
    final gstNumber = prefs.getString('gst_number') ?? 'GST Number';
    final companyAddress =
        prefs.getString('company_address') ?? 'Company Address';
    final isGstRegistered = prefs.getBool('is_gst_registered') ?? true;
    final bankAccount = prefs.getString('bank_details') ?? '';
    final bannerColor = await getPdfBannerColor();
    final lineItemColor = await getPdfLineItemColor();
    final totalsColor = await getPdfTotalsColor();

    // Use a Unicode-friendly embedded font so Māori macron vowels render correctly.
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

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
    final customerName =
        (job.companyName != null && job.companyName!.trim().isNotEmpty)
            ? job.companyName!
            : (job.customerName ?? '');
    final customerAddress = job.address ?? '';
    final customerBodyCorporateNumber = job.bodyCorporateNumber ?? '';
    final orderNumber = _orderNumberController.text.trim();
    final today = DateTime.now();
    final estimateOrQuoteValidUntil = today.add(const Duration(days: 30));

    final List<estimate_item.EstimateItem> invoiceItems =
        List<estimate_item.EstimateItem>.from(items.map((e) => e.copyWith()));
    invoiceItems.removeWhere((item) =>
        normalizeCode(item.description) == 'deposit' ||
        normalizeCode(item.name) == 'deposit received');
    invoiceItems.removeWhere((item) => item.quantity == 0);
    print('🧾 invoiceItems count after deposit filter: ${invoiceItems.length}');
    final List<SubsectionData> invoiceSections = [
      ...mainSections,
      ...optionSections
    ];
    print('🧾 invoiceSections: ${invoiceSections.map((s) => s.name).toList()}');
    final double depositPreGst;
    final estimate_item.EstimateItem? depositLineItem;
    if (type == 'invoice' && currentDepositAmount > 0) {
      depositPreGst = currentDepositAmount / 1.15;
      depositLineItem = estimate_item.EstimateItem(
        name: 'Deposit Received',
        description: 'DEPOSIT',
        unitPrice: -depositPreGst,
        quantity: 1,
        purchasePrice: 0,
        section: 'Payments',
      );
      invoiceItems.add(depositLineItem);
      if (!invoiceSections.any((s) => s.name == 'Payments')) {
        invoiceSections.add(SubsectionData(name: 'Payments'));
      }
    } else {
      depositPreGst = 0.0;
      depositLineItem = null;
    }

    final invoiceSubTotalExGst = invoiceItems.fold<double>(
        0.0, (sum, item) => sum + item.unitPrice * item.quantity);
    final invoiceGstAmount =
        isGstRegistered ? invoiceSubTotalExGst * 0.15 : 0.0;
    final invoiceTotalIncGst =
        isGstRegistered ? invoiceSubTotalExGst * 1.15 : invoiceSubTotalExGst;

    // Move this flag outside the widget collection so it can be used in fallback invoice table
    final bool showInvoiceDiscountColumn =
        invoiceItems.any((item) => (item.discountAmount ?? 0) > 0);

    String dueDateString = '';
    DateTime? dueDate;
    if (type == 'invoice') {
      dueDate = getInvoiceDueDate(job.paymentTerms);
      dueDateString =
          '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
    } else {
      dueDate = getEstimateOrQuoteDueDate();
    }

    // Assign documentNumber and typeName before PDF build
    final docNumber = await _getNextDocumentNumber();
    String typeName;
    String documentNumber;
    switch (type) {
      case 'invoice':
        typeName = 'Invoice';
        documentNumber = docNumber;
        break;
      case 'quote':
        typeName = 'Quote';
        documentNumber = docNumber;
        break;
      default:
        typeName = 'Estimate';
        documentNumber = docNumber;
    }

    final String scopeSummaryText = _scopeSummaryController.text.trim();
    final String exclusionsText = _scopeExclusionsController.text.trim();
    print(
        '🧾 Building PDF: type=$type layout=$layout items=${invoiceItems.length} invoiceSections=${invoiceSections.map((s) => s.name).toList()} showInvoiceDiscountColumn=$showInvoiceDiscountColumn');
    try {
      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 36),
          footer: (context) => pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, thickness: 0.75),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(companyName,
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 14),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: bannerColor, width: 2.5)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoWidget != null) logoWidget,
                      pw.SizedBox(height: 8),
                      pw.Text(companyName,
                          style: pw.TextStyle(
                              fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.Text(companyAddress,
                          style: const pw.TextStyle(fontSize: 10)),
                      if (isGstRegistered)
                        pw.Text('GST: $gstNumber',
                            style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(type.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 26,
                              fontWeight: pw.FontWeight.bold,
                              color: _pdfDarkTint(bannerColor),
                              letterSpacing: 1.2)),
                      pw.SizedBox(height: 4),
                      if (type == 'invoice') ...[
                        pw.Text('Invoice #: $documentNumber',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                            'Date: ${today.day}/${today.month}/${today.year}',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Due: $dueDateString',
                            style: const pw.TextStyle(fontSize: 10)),
                      ] else ...[
                        pw.Text(
                            'Date: ${today.day}/${today.month}/${today.year}',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                            'Valid until: ${estimateOrQuoteValidUntil.day}/${estimateOrQuoteValidUntil.month}/${estimateOrQuoteValidUntil.year}',
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Customer: $customerName',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  if (customerBodyCorporateNumber.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                        'Body Corporate Number: $customerBodyCorporateNumber',
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                  pw.SizedBox(height: 2),
                  pw.Text('Address: $customerAddress',
                      style: const pw.TextStyle(fontSize: 11)),
                  if (orderNumber.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text('Order Number: $orderNumber',
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                ],
              ),
            ),
            // --- Invoice summary sections ---
            if (type == 'invoice') ...[
              if (invoiceSections.isNotEmpty)
                ...invoiceSections.expand((section) {
                  final sectionItems = invoiceItems
                      .where((i) => i.section == section.name)
                      .toList();
                  if (sectionItems.isEmpty) return <pw.Widget>[];
                  final sectionTotal = sectionItems.fold<double>(
                      0.0, (sum, item) => sum + _lineTotal(item));
                  return <pw.Widget>[
                    pw.NewPage(freeSpace: 120),
                    _pdfSectionHeader(section.name, bannerColor,
                        subtitle: section.description),
                    if (showItems) ...[
                      pw.SizedBox(height: 8),
                      _pdfStyledTable(
                        lineItemColor: lineItemColor,
                        headers: [
                          'ID',
                          'Name',
                          'Qty',
                          if (showLineTotals) 'Unit Price',
                          if (showLineTotals &&
                              sectionItems.any(
                                  (item) => (item.discountPercent ?? 0) >= 1))
                            'Discount',
                          if (showLineTotals) 'Line Total',
                        ],
                        data: sectionItems
                            .map((item) => [
                                  item.description,
                                  (item.description == 'EST' &&
                                          type == 'estimate')
                                      ? 'Estimated Labour'
                                      : item.name,
                                  formatQuantity(item.quantity),
                                  if (showLineTotals)
                                    '\$${item.unitPrice.toStringAsFixed(2)}',
                                  if (showLineTotals &&
                                      (item.discountPercent ?? 0) >= 1)
                                    '${item.discountPercent!.toStringAsFixed(1)}%',
                                  if (showLineTotals)
                                    '\$${_lineTotal(item).toStringAsFixed(2)}',
                                ])
                            .toList(),
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'Section Total: \$${sectionTotal.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.SizedBox(height: 12),
                  ];
                }),
              if (invoiceSections.isEmpty && invoiceItems.isNotEmpty) ...[
                pw.NewPage(freeSpace: 120),
                _pdfSectionHeader('Invoice Summary', bannerColor),
                if (showItems) ...[
                  pw.SizedBox(height: 8),
                  _pdfStyledTable(
                    lineItemColor: lineItemColor,
                    headers: [
                      'ID',
                      'Name',
                      'Qty',
                      if (showLineTotals) 'Unit Price',
                      if (showLineTotals &&
                          invoiceItems
                              .any((item) => (item.discountPercent ?? 0) >= 1))
                        'Discount',
                      if (showLineTotals) 'Line Total',
                    ],
                    data: invoiceItems
                        .map((item) => [
                              item.description,
                              (item.description == 'EST' && type == 'estimate')
                                  ? 'Estimated Labour'
                                  : item.name,
                              formatQuantity(item.quantity),
                              if (showLineTotals)
                                '\$${item.unitPrice.toStringAsFixed(2)}',
                              if (showLineTotals &&
                                  (item.discountPercent ?? 0) >= 1)
                                '${item.discountPercent!.toStringAsFixed(1)}%',
                              if (showLineTotals)
                                '\$${_lineTotal(item).toStringAsFixed(2)}',
                            ])
                        .toList(),
                  ),
                ],
                pw.SizedBox(height: 10),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: _pdfTotalsBox(
                    totalsColor: totalsColor,
                    lines: [
                      if (isGstRegistered)
                        pw.Text(
                            'Subtotal (ex GST): \$${invoiceSubTotalExGst.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      if (isGstRegistered)
                        pw.Text(
                            'GST (15%): \$${invoiceGstAmount.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        isGstRegistered
                            ? 'Total (inc GST): \$${invoiceTotalIncGst.toStringAsFixed(2)}'
                            : 'Total: \$${invoiceTotalIncGst.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
              ],
              if (invoiceSections.isNotEmpty && invoiceItems.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: _pdfTotalsBox(
                    totalsColor: totalsColor,
                    lines: [
                      if (isGstRegistered)
                        pw.Text(
                            'Subtotal (ex GST): \$${invoiceSubTotalExGst.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      if (isGstRegistered)
                        pw.Text(
                            'GST (15%): \$${invoiceGstAmount.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        isGstRegistered
                            ? 'Total (inc GST): \$${invoiceTotalIncGst.toStringAsFixed(2)}'
                            : 'Total: \$${invoiceTotalIncGst.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            // --- Estimate/Quote logic (main sections + options as separate) ---
            if (type != 'invoice' && mainSections.isNotEmpty)
              ...mainSections.expand((section) {
                final sectionItems =
                    items.where((i) => i.section == section.name).toList();
                if (sectionItems.isEmpty) return <pw.Widget>[];
                final sectionTotal = sectionItems.fold<double>(
                    0.0, (sum, i) => sum + _lineTotal(i));
                return <pw.Widget>[
                  pw.NewPage(freeSpace: 120),
                  _pdfSectionHeader(section.name, bannerColor,
                      subtitle: section.description),
                  if (showItems) ...[
                    pw.SizedBox(height: 8),
                    _pdfStyledTable(
                      lineItemColor: lineItemColor,
                      headers: [
                        'ID',
                        'Name',
                        'Qty',
                        if (showLineTotals) 'Unit Price',
                        if (showLineTotals &&
                            sectionItems.any(
                                (item) => (item.discountPercent ?? 0) >= 1))
                          'Discount',
                        if (showLineTotals) 'Line Total',
                      ],
                      data: sectionItems
                          .map((item) => [
                                item.description,
                                (item.description == 'EST' &&
                                        type == 'estimate')
                                    ? 'Estimated Labour'
                                    : item.name,
                                formatQuantity(item.quantity),
                                if (showLineTotals)
                                  '\$${item.unitPrice.toStringAsFixed(2)}',
                                if (showLineTotals &&
                                    (item.discountPercent ?? 0) >= 1)
                                  '${item.discountPercent!.toStringAsFixed(1)}%',
                                if (showLineTotals)
                                  '\$${_lineTotal(item).toStringAsFixed(2)}',
                              ])
                          .toList(),
                    ),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Section Total: \$${sectionTotal.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ];
              }),
            if (type != 'invoice' &&
                items.any(
                    (i) => mainSections.any((s) => s.name == i.section))) ...[
              pw.SizedBox(height: 4),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: _pdfTotalsBox(
                  totalsColor: totalsColor,
                  lines: [
                    if (isGstRegistered)
                      pw.Text(
                          'Subtotal (ex GST): \$${mainSubTotalExGst.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    if (isGstRegistered)
                      pw.Text(
                          'GST (15%): \$${mainGstAmount.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      isGstRegistered
                          ? 'Total (inc GST): \$${mainTotalIncGst.toStringAsFixed(2)}'
                          : 'Total: \$${mainSubTotalExGst.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
            if (type != 'invoice' && optionSections.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('OPTIONS',
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                        letterSpacing: 1.0)),
              ),
              pw.SizedBox(height: 8),
              ...optionSections.expand((section) {
                final sectionItems =
                    items.where((i) => i.section == section.name).toList();
                if (sectionItems.isEmpty) return <pw.Widget>[];
                final subtotal = sectionItems.fold<double>(
                    0.0, (sum, i) => sum + i.unitPrice * i.quantity);
                final total = subtotal * 1.15;
                return <pw.Widget>[
                  pw.NewPage(freeSpace: 120),
                  _pdfSectionHeader('${section.name} (Option)', bannerColor,
                      subtitle: section.description),
                  if (showItems) ...[
                    pw.SizedBox(height: 8),
                    _pdfStyledTable(
                      lineItemColor: lineItemColor,
                      headers: [
                        'ID',
                        'Name',
                        'Qty',
                        if (showLineTotals) 'Unit Price',
                        if (showLineTotals &&
                            sectionItems.any(
                                (item) => (item.discountPercent ?? 0) >= 1))
                          'Discount',
                        if (showLineTotals) 'Line Total',
                      ],
                      data: sectionItems
                          .map((item) => [
                                item.description,
                                (item.description == 'EST' &&
                                        type == 'estimate')
                                    ? 'Estimated Labour'
                                    : item.name,
                                formatQuantity(item.quantity),
                                if (showLineTotals)
                                  '\$${item.unitPrice.toStringAsFixed(2)}',
                                if (showLineTotals &&
                                    (item.discountPercent ?? 0) >= 1)
                                  '${item.discountPercent!.toStringAsFixed(1)}%',
                                if (showLineTotals)
                                  '\$${_lineTotal(item).toStringAsFixed(2)}',
                              ])
                          .toList(),
                    ),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (isGstRegistered)
                          pw.Text(
                              'Option Subtotal: \$${subtotal.toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 10)),
                        if (isGstRegistered)
                          pw.Text(
                              'GST: \$${(subtotal * 0.15).toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                          isGstRegistered
                              ? 'Option Total: \$${total.toStringAsFixed(2)}'
                              : 'Option Total: \$${subtotal.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ];
              }),
            ],
            if (type == 'invoice') ...[
              pw.SizedBox(height: 16),
              if (bankAccount.isNotEmpty) ...[
                pw.NewPage(freeSpace: 120),
                _pdfAccentCard(
                  bannerColor: bannerColor,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Bank Account:',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.Text(bankAccount,
                          style: const pw.TextStyle(fontSize: 12)),
                      pw.SizedBox(height: 8),
                      pw.Text('Reference: $documentNumber',
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
            if (type != 'invoice') ...[
              pw.SizedBox(),
              pw.Text('This $type is valid for 30 days from the date of issue.',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
              // Add deposit information and bank details for estimates and quotes
              if (currentDepositAmount > 0) ...[
                pw.NewPage(freeSpace: 120),
                pw.SizedBox(height: 12),
                _pdfAccentCard(
                  bannerColor: bannerColor,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Deposit Required',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _isDepositPercentage
                            ? 'A deposit of \$${currentDepositAmount.toStringAsFixed(2)} (${_depositPercentage!.toStringAsFixed(1)}% of the main total) is required.'
                            : 'A deposit of \$${currentDepositAmount.toStringAsFixed(2)} is required.',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('This amount is due before work begins.',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                      if (bankAccount.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Text('Bank Details',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text(bankAccount,
                            style: const pw.TextStyle(fontSize: 12)),
                        pw.SizedBox(height: 4),
                        pw.Text(
                            'Please use Invoice Number as reference: $documentNumber',
                            style: const pw.TextStyle(
                                fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      );
      if (includeScopePage &&
          (scopeSummaryText.isNotEmpty || exclusionsText.isNotEmpty)) {
        pdf.addPage(
          pw.MultiPage(
            margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 36),
            footer: (context) => pw.Column(
              children: [
                pw.Divider(color: PdfColors.grey300, thickness: 0.75),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(companyName,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                    pw.Text(
                        'Page ${context.pageNumber} of ${context.pagesCount}',
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            build: (context) => [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 14),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: bannerColor, width: 2.5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(companyName,
                            style: pw.TextStyle(
                                fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        if (companyAddress.isNotEmpty)
                          pw.Text(companyAddress,
                              style: const pw.TextStyle(
                                  fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                    if (logoWidget != null)
                      pw.Container(width: 120, child: logoWidget),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Job Scope Summary',
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: _pdfDarkTint(bannerColor))),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Date: ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              if (scopeSummaryText.isNotEmpty) ...[
                _pdfSectionHeader('Scope of Work', bannerColor),
                pw.SizedBox(height: 10),
                pw.Text(scopeSummaryText,
                    style: const pw.TextStyle(fontSize: 12, height: 1.6),
                    textAlign: pw.TextAlign.justify),
              ],
              if (scopeSummaryText.isNotEmpty && exclusionsText.isNotEmpty)
                pw.SizedBox(height: 20),
              if (exclusionsText.isNotEmpty) ...[
                _pdfSectionHeader('Exclusions', bannerColor),
                pw.SizedBox(height: 10),
                pw.Text(exclusionsText,
                    style: const pw.TextStyle(fontSize: 12, height: 1.6),
                    textAlign: pw.TextAlign.justify),
              ],
              if (_selectedLiabilityRisks.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                _pdfSectionHeader(
                    'Risks, Liabilities and Notable Information', bannerColor),
                pw.SizedBox(height: 10),
                pw.Text(
                    'This section captures risks, liabilities and notable information discussed for this job. By accepting this quote you acknowledge these matters and your responsibility (if applicable).',
                    style: const pw.TextStyle(fontSize: 12, height: 1.6),
                    textAlign: pw.TextAlign.justify),
                pw.SizedBox(height: 12),
                ..._selectedLiabilityRisks.map((risk) {
                  return _pdfAccentCard(
                    bannerColor: bannerColor,
                    margin: const pw.EdgeInsets.only(bottom: 12),
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(risk['title'] ?? '',
                            style: pw.TextStyle(
                                fontSize: 13, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        pw.Text(risk['description'] ?? '',
                            style:
                                const pw.TextStyle(fontSize: 11, height: 1.5),
                            textAlign: pw.TextAlign.justify),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ],
          ),
        );
      }
    } catch (e, stack) {
      print('❌ Error building PDF page: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to build PDF page: $e')),
        );
      }
      return;
    }

    print('🧾 PDF page built, saving PDF now...');
    final fileName = generateDocumentName(
      documentType: typeName,
      job: widget.job,
      existingAttachments: widget.job.attachments,
      documentNumber: type == 'invoice' ? documentNumber : null,
    );

    File? file;
    String? cloudPdfUrl;
    try {
      final pdfBytes = await pdf.save();
      print('🧾 PDF saved successfully, byte length=${pdfBytes.length}');

      if (kIsWeb) {
        cloudPdfUrl = await DeltaSyncService.uploadGeneratedPdfBytes(
          fileName: fileName,
          jobId: widget.job.id,
          bytes: pdfBytes,
        );
        print('☁️ Browser PDF uploaded: $fileName');
      } else {
        final dir = await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        print('🧾 PDF file written to ${file.path}');
      }

      // ✅ IMPORTANT: Add the PDF to job.attachments immediately after saving
      // This ensures subsequent document generations use correct naming
      // (avoiding duplicate names for multiple PDFs)
      setState(() {
        widget.job.attachments ??= [];
        final attachmentPath = cloudPdfUrl ?? file?.path;
        if (attachmentPath != null &&
            !widget.job.attachments!.contains(attachmentPath)) {
          widget.job.attachments!.add(attachmentPath);
          print('📎 Added PDF to job attachments: $fileName');
        }
      });
    } catch (e, stack) {
      print('❌ Error saving PDF: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save PDF: $e')),
        );
      }
      return;
    }

    // For converted estimate invoices, preserve the builder snapshot and remaining estimate build.
    String? invoiceBuilderBuildId;
    if (widget.convertToInvoice && type == 'invoice') {
      if (_currentInProgressId == null) {
        await _saveInProgressEstimate();
      }
      await _createInvoiceSnapshotBuilds(
        invoiceTotalIncGst: invoiceTotalIncGst,
        totalProfit: totalProfit,
      );
      invoiceBuilderBuildId = _currentInProgressId;
    }
    // For a normal finalize (not the estimate->invoice conversion snapshot
    // flow above), link the document to whichever in-progress build is
    // currently backing this session, so it can be preserved and shown
    // alongside the resulting document.
    final linkedBuildId = invoiceBuilderBuildId ??
        _currentInProgressId ??
        widget.inProgressBuildId;

    // Convert in-progress build to final build version
    final version = EstimateVersion(
      type: type,
      invoiceNumber: type == 'invoice' ? documentNumber : null,
      estimateNumber: type != 'invoice' ? documentNumber : null,
      timestamp: DateTime.now(),
      items: List<estimate_item.EstimateItem>.from(
          invoiceItems.map((e) => e.copyWith())),
      sections: invoiceSections
          .map((s) => s.name)
          .toList(), // Save invoice subsections, including Payments if present
      filePath: file?.path,
      cloudPdfUrl: cloudPdfUrl,
      status: 'final',
      amount: type == 'invoice' ? invoiceTotalIncGst : totalIncGst,
      dueDate: dueDate,
      documentNumber: documentNumber,
      depositAmount: _depositAmount,
      depositPercentage: _depositPercentage,
      isDepositPercentage: _isDepositPercentage,
      builderBuildId: linkedBuildId,
      expiryDate: (type == 'estimate' || type == 'quote')
          ? estimateOrQuoteValidUntil
          : null,
      profit: type == 'invoice' ? totalProfit : 0.0,
      // 🔴 CRITICAL: ALWAYS explicitly set these fields to ensure consistency
      // between newly created invoices and backup format. Previous versions
      // only relied on constructor defaults, which could cause format mismatch
      // during delta sync if any field was omitted from serialization.
      isPaid: false,
      isVoided: false,
      isArchived: false,
      isConverted: false,
      emailSent: false,
      paidVia: 'manual',
    );
    // Give the document a stable id so the originating build can be linked
    // to it via finalizedDocumentId, and so the "In Progress Builds" UI can
    // resolve which document a preserved build now belongs to.
    version.id ??=
        '${widget.job.id}_doc_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      widget.job.estimateVersions =
          List<EstimateVersion>.from(widget.job.estimateVersions);
      widget.job.estimateVersions.add(version);
    });

    // Preserve the in-progress build(s) that produced this document instead
    // of deleting them - mark them as finalized/linked to the resulting
    // EstimateVersion so they stay associated with it forever. If the user
    // reopens a finalized build later, a new duplicate build is created
    // instead of mutating this one (see the inProgressBuildId load logic).
    final originalBuildId = widget.inProgressBuildId;
    final currentBuildId = _currentInProgressId;
    final buildIdsToPreserve = <String>{
      if (originalBuildId != null) originalBuildId,
      if (currentBuildId != null) currentBuildId,
    };

    if (buildIdsToPreserve.isNotEmpty) {
      for (final buildId in buildIdsToPreserve) {
        try {
          print(
              '� Linking in-progress build $buildId to finalized document ${version.id} (type $type)');
          await InProgressBuildService.markFinalized(
            buildId: buildId,
            documentId: version.id!,
          );
          print('✅ In-progress build preserved and linked: $buildId');
        } catch (e) {
          print(
              '⚠️ Failed to mark in-progress build $buildId as finalized: $e');
        }
      }
    }
    // Any further edits to this build (if reopened) must go into a new
    // duplicate build, not this one.
    _currentInProgressId = null;
    _originalInProgressBuildDeleted = true;
    // No legacy cleanup here, only the build that created this document.

    // Save the job to cloud after creating final estimate/quote/invoice
    _persistJobToDisk().catchError((e) async {
      print('⚠️ Warning: failed to persist job before PDF preview: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Warning: PDF created but failed to save job: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    print('🧾 PDF ready, launching preview route.');
    final previewResult = await _showPdfPreview(pdf, file, fileName);
    if (previewResult == true) {
      if (mounted) {
        print('🧾 PDF preview route returned: $previewResult');
        Navigator.of(context).pop(true);
      }
      return;
    }

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

  Future<bool?> _showPdfPreview(
    pw.Document pdf,
    File? file,
    String fileName,
  ) async {
    if (!mounted) return null;
    try {
      final previewResult =
          await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('PDF Preview'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  tooltip: 'Export PDF',
                  onPressed: () async {
                    if (kIsWeb) {
                      try {
                        await Printing.sharePdf(
                          bytes: await pdf.save(),
                          filename: fileName,
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Could not download PDF: $e')),
                          );
                        }
                      }
                      return;
                    }
                    if (file == null) return;
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
                          const SnackBar(
                              content:
                                  Text('PDF exported and job auto-saved!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save job: $e')),
                        );
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'Done - return to job',
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            ),
            body: PdfPreview(
              build: (format) {
                print('🧾 PdfPreview build called with format $format');
                return pdf.save();
              },
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: false,
              allowSharing: false,
            ),
          ),
        ),
      );
      return previewResult;
    } catch (e, stack) {
      print('❌ Error launching PDF preview route: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch PDF preview: $e')),
        );
      }
      return null;
    }
  }

  void onEstimatePdfGenerated(
      job_model.Job job, double amount, DateTime expireDate) {
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

  void onQuotePdfGenerated(
      job_model.Job job, double amount, DateTime expireDate) {
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
    print('🧾 _showGeneratePdfDialog opened; items=${items.length}');

    final missingCustomer = widget.job.customerName == null ||
        widget.job.customerName!.trim().isEmpty;
    final missingAddress =
        widget.job.address == null || widget.job.address!.trim().isEmpty;

    if (missingCustomer || missingAddress) {
      final warningProceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Missing Job Details'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (missingCustomer)
                    const Text('This job has no customer name.'),
                  if (missingAddress)
                    const Text('This job has no site address.'),
                  const SizedBox(height: 12),
                  const Text(
                    'A PDF generated without customer or address information may be blank or incomplete.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                      'Please add these details before generating a PDF.'),
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
          ) ??
          false;

      if (!warningProceed) return;
    }

    // Check for items with qty 0 or price 0
    final zeroQtyItems = widget.convertToInvoice
        ? <estimate_item.EstimateItem>[]
        : items.where((item) => item.quantity == 0).toList();
    final zeroPriceItems = items
        .where((item) =>
            item.unitPrice == 0 && normalizeCode(item.description) != 'dis')
        .toList();

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
                    ...zeroQtyItems.map((item) => Text(
                        'Item "${item.name}" has quantity 0',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
                  if (zeroPriceItems.isNotEmpty)
                    ...zeroPriceItems.map((item) => Text(
                        'Item "${item.name}" has \$0 amount',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 12),
                  const Text(
                      'Please fix these items before generating a PDF, or continue anyway.'),
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
          ) ??
          false;
    }

    if (!proceed) return;

    // The document type is now decided up-front when the build is started
    // (and changeable at any time via the type selector in the app bar), so
    // we no longer re-ask here - just use whatever `_buildType` currently is.
    final method = _buildType;
    print('🧾 Generating PDF using build type: $method');

    final String scopeText = _scopeSummaryController.text.trim();
    final String exclusionsText = _scopeExclusionsController.text.trim();
    final bool scopePageAvailable = scopeText.isNotEmpty ||
        exclusionsText.isNotEmpty ||
        _selectedLiabilityRisks.isNotEmpty;
    final prefs = await SharedPreferences.getInstance();
    final bool defaultAttachScopePage =
        prefs.getBool('attach_scope_page_by_default') ?? true;

    final pdfOptions = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        String selectedLayout = 'full';
        bool includeScope = scopePageAvailable && defaultAttachScopePage;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Generate PDF'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _canChangeBuildType
                          ? () async {
                              Navigator.pop(context, null);
                              await _showChangeBuildTypeDialog();
                              await _showGeneratePdfDialog();
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8.0, horizontal: 4.0),
                        child: Row(
                          children: [
                            Icon(_buildTypeIcon(method),
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Generating: ${_buildTypeLabel(method)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (_canChangeBuildType) ...[
                              const Spacer(),
                              const Text('Change',
                                  style: TextStyle(color: Colors.blue)),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: Colors.blue),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    RadioListTile<String>(
                      value: 'full',
                      groupValue: selectedLayout,
                      title: const Text('Full line item pricing'),
                      subtitle: const Text(
                          'Full line item detail + subsection totals + description'),
                      onChanged: (value) {
                        setState(() => selectedLayout = value!);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'compact',
                      groupValue: selectedLayout,
                      title: const Text('No line item pricing'),
                      subtitle: const Text(
                          'Line items only, no line totals + subsection totals + description'),
                      onChanged: (value) {
                        setState(() => selectedLayout = value!);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'summary',
                      groupValue: selectedLayout,
                      title: const Text('Descriptions only'),
                      subtitle:
                          const Text('Descriptions only + subsection totals'),
                      onChanged: (value) {
                        setState(() => selectedLayout = value!);
                      },
                    ),
                    const Divider(),
                    if (scopePageAvailable) ...[
                      CheckboxListTile(
                        value: includeScope,
                        onChanged: (value) {
                          setState(() => includeScope = value ?? false);
                        },
                        title: const Text('Attach job scope page to PDF'),
                        subtitle: const Text(
                            'Add a job scope summary page with date, company and work outline.'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'No scope or exclusions text is available to attach.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, {
                    'layout': selectedLayout,
                    'includeScopePage': includeScope,
                  }),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    if (pdfOptions == null) return;

    final layout = pdfOptions['layout'] as String;
    final includeScopePage = pdfOptions['includeScopePage'] as bool;

    print(
        '🧾 PDF generation method selected: $method layout=$layout includeScopePage=$includeScopePage');
    FocusScope.of(context).unfocus();
    await _generateEstimatePdf(
      type: method,
      layout: layout,
      includeScopePage: includeScopePage,
    );
  }

  /// Closes the inline pricebook search for a subsection without adding anything.
  void _closeSectionSearch(SubsectionData section) {
    setState(() {
      _sectionSearchQueries[section.name] = '';
      _sectionSearchControllers[section.name]?.clear();
      _sectionSearchAddedItems[section.name]?.clear();
      _sectionSearchAddCounts[section.name]?.clear();
      _sectionSearchShowMore[section.name] = false;
    });
    _sectionSearchFocusNodes[section.name]?.unfocus();
  }

  /// Handles the CAL (opens date picker) / DIS (opens discount amount dialog)
  /// special-case pricebook items after they've been added via search.
  Future<void> _handleSpecialSearchItemAdded(
      SubsectionData section, estimate_item.EstimateItem? addedItem) async {
    if (addedItem == null) return;

    if (addedItem.description == 'CAL') {
      DateTime selectedDate = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) selectedDate = picked;
      setState(() {
        final idx = items.lastIndexWhere(
            (i) => i.section == section.name && i.description == 'CAL');
        if (idx != -1) {
          final dateStr =
              '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
          items[idx] = items[idx].copyWith(
            name: 'Labour on $dateStr',
            description: 'Labour on $dateStr',
          );
        }
      });
      _saveInProgressEstimate();
    }

    if (addedItem.description == 'DIS') {
      final controller = TextEditingController(text: '');
      final result = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enter Discount Amount'),
          content: TextField(
            textCapitalization: TextCapitalization.sentences,
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
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
          final idx = items.lastIndexWhere(
              (i) => i.section == section.name && i.description == 'DIS');
          if (idx != -1) {
            items[idx] = items[idx].copyWith(
              unitPrice: -result.abs(), // Always negative
              name: 'Discount',
            );
          }
          _hasUnsavedChanges = true;
        });
        _saveInProgressEstimate();
      }
    }
  }

  /// 🔴 NEW: Applies a 15% project manager markup to all items' sell prices
  /// This adds 15% to every item's unit price (sell price)
  void _applyProjectManagerMarkup() {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to mark up')),
      );
      return;
    }

    setState(() {
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final newPrice = item.unitPrice * 1.15; // Add 15%
        items[i] = item.copyWith(unitPrice: newPrice);

        // Update the inline sale price controller if it exists
        final controller =
            _itemSalePriceControllers[_lineItemControllerKey(item)];
        if (controller != null) {
          controller.text = newPrice.toStringAsFixed(2);
        }
      }
      _hasUnsavedChanges = true;
    });

    _debouncedSave();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Added 15% project manager cut to all items'),
        duration: Duration(seconds: 2),
      ),
    );
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
              textCapitalization: TextCapitalization.sentences,
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

  @override
  Widget build(BuildContext context) {
    // Debug current state at start of build (no-op unless _debugBuildLogging = true)
    debugCurrentState();
    // Theme color variables
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

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

      return WillPopScope(
        onWillPop: () async {
          if (_hasUnsavedChanges) {
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Unsaved Changes'),
                content: const Text(
                    'You have unsaved changes. Save as in-progress draft before exiting?'),
                actions: [
                  TextButton(
                    onPressed: () async {
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
                      final saved = await _saveInProgressEstimate();
                      if (saved) {
                        Navigator.pop(context, true); // Save
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Failed to save draft. Please try again.')),
                        );
                      }
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
              title: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _canChangeBuildType ? _showChangeBuildTypeDialog : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_buildTypeIcon(_buildType), size: 20),
                      const SizedBox(width: 8),
                      Text(_buildTypeLabel(_buildType)),
                      if (_canChangeBuildType) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                      _showProfit ? Icons.visibility : Icons.visibility_off),
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
                              textCapitalization: TextCapitalization.sentences,
                              controller: controller,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              decoration:
                                  const InputDecoration(labelText: 'Profit %'),
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
                            final baseCost = (item.purchasePrice ?? 0) > 0
                                ? item.purchasePrice!
                                : item.unitPrice;
                            final newUnitPrice =
                                baseCost * (1 + percent! / 100);
                            return item.copyWith(
                                unitPrice: double.parse(
                                    newUnitPrice.toStringAsFixed(2)));
                          }).toList();
                          _hasUnsavedChanges = true;
                        });
                        _saveInProgressEstimate();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Profit set to ${percent!.toStringAsFixed(1)}% for all items.')),
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
                  icon: Icon(_buildTypeIcon(_buildType)),
                  tooltip: _canChangeBuildType
                      ? 'Change Document Type'
                      : 'Type locked during editing',
                  onPressed:
                      _canChangeBuildType ? _showChangeBuildTypeDialog : null,
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
                            textCapitalization: TextCapitalization.sentences,
                            autofocus: true,
                            decoration: const InputDecoration(
                                labelText: 'Template Name'),
                            onChanged: (val) => name = val,
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel')),
                            ElevatedButton(
                                onPressed: () => Navigator.pop(context, name),
                                child: const Text('Save')),
                          ],
                        );
                      },
                    );
                    if (templateName != null &&
                        templateName.trim().isNotEmpty) {
                      final trimmedName = templateName.trim();
                      setState(() {
                        _templates.removeWhere(
                            (t) => t.name == trimmedName && t.type == 'build');
                        _templates.add(EstimateTemplate(
                          name: trimmedName,
                          items: List<estimate_item.EstimateItem>.from(
                              items.map((e) => e.copyWith())),
                          subsections: _subsections.map((s) => s.name).toList(),
                          type: 'build',
                          scopeSummary: _scopeSummaryController.text.trim(),
                          scopeExclusions:
                              _scopeExclusionsController.text.trim(),
                          builderNote: _jobNotesController.text.trim(),
                          liabilityRisks: _selectedLiabilityRisks
                              .map((risk) => {
                                    'title': risk['title'] ?? '',
                                    'description': risk['description'] ?? '',
                                  })
                              .toList(),
                        ));
                        _hasUnsavedChanges = false;
                      });
                      await _saveTemplates();
                      await _loadTemplates();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Template "$trimmedName" saved!')),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add_task),
                  tooltip: 'Add to To-Do List',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ToDoListScreen(
                          prefilledTitle:
                              'Follow up: ${_customerNameController.text}',
                          linkedJobId: widget.job.id,
                          linkedJobTitle:
                              '${_customerNameController.text} - Estimate',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                _dragAutoScrollViewportHeight = constraints.maxHeight;
                return Listener(
                  onPointerMove: _onDragPointerMove,
                  onPointerDown: _onDragPointerDown,
                  onPointerUp: _onDragPointerUp,
                  onPointerCancel: _onDragPointerCancel,
                  behavior: HitTestBehavior.translucent,
                  child: SingleChildScrollView(
                    controller: _mainScrollController,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          EditableHeader(
                            nameController: _customerNameController,
                            addressController: _customerAddressController,
                            orderNumberController: _orderNumberController,
                          ),
                          const SizedBox(height: 12),
                          VoiceTextField(
                            controller: _jobNotesController,
                            labelText: 'General Job Notes',
                            hintText:
                                'General notes for this job (saved to Job Details)',
                            maxLines: 4,
                            continuousListening: true,
                            decoration: const InputDecoration(
                              isDense: true,
                            ),
                            onChanged: () {
                              _hasUnsavedChanges = true;
                            },
                            onEditingComplete: () async {
                              await _saveJobNotes();
                            },
                          ),
                          const SizedBox(height: 12),
                          if (mainSections.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Main Sections',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          if (mainSections.isNotEmpty)
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: true,
                              onReorderStart: (_) => _startDragAutoScroll(),
                              onReorderEnd: (_) => _stopDragAutoScroll(),
                              onReorder: (oldIndex, newIndex) =>
                                  _reorderSubsection(oldIndex, newIndex, false),
                              itemCount: mainSections.length,
                              itemBuilder: (context, index) {
                                final section = mainSections[index];
                                // 🔴 PERFORMANCE: RepaintBoundary isolates each
                                // section card's paint layer so editing one
                                // section doesn't force siblings to repaint.
                                return RepaintBoundary(
                                  key: ValueKey(section),
                                  child: buildSubsectionCard(
                                      section, _subsections.indexOf(section)),
                                );
                              },
                            ),
                          // --- Main Totals ---
                          buildMainTotals(),
                          // --- Option Sections (below totals) ---
                          if (optionSections.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Option Sections',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          if (optionSections.isNotEmpty)
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: true,
                              onReorderStart: (_) => _startDragAutoScroll(),
                              onReorderEnd: (_) => _stopDragAutoScroll(),
                              onReorder: (oldIndex, newIndex) =>
                                  _reorderSubsection(oldIndex, newIndex, true),
                              itemCount: optionSections.length,
                              itemBuilder: (context, index) {
                                final section = optionSections[index];
                                // 🔴 PERFORMANCE: RepaintBoundary isolates each
                                // option section's paint layer (card + totals)
                                // so editing one doesn't force siblings to repaint.
                                return RepaintBoundary(
                                  key: ValueKey(section),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      buildSubsectionCard(section,
                                          _subsections.indexOf(section)),
                                      buildOptionSectionTotals(section),
                                    ],
                                  ),
                                );
                              },
                            ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              'Scope of Work',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: VoiceTextField(
                              controller: _scopeSummaryController,
                              labelText: 'Scope Summary',
                              hintText:
                                  'Write the job scope summary here. Use the PDF option to include this page when generating a document.',
                              maxLines: 6,
                              continuousListening: true,
                              decoration: const InputDecoration(isDense: true),
                              onChanged: () {
                                _hasUnsavedChanges = true;
                              },
                              onEditingComplete: () async {
                                await _saveInProgressEstimate();
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              'Exclusions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: VoiceTextField(
                              controller: _scopeExclusionsController,
                              labelText: 'Exclusions',
                              hintText:
                                  'List any exclusions for this job. These appear on the scope page if attached.',
                              maxLines: 6,
                              continuousListening: true,
                              decoration: const InputDecoration(isDense: true),
                              onChanged: () {
                                _hasUnsavedChanges = true;
                              },
                              onEditingComplete: () async {
                                await _saveInProgressEstimate();
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              'Risks, Liabilities and Notable Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 4.0),
                            child: Text(
                              'This section captures risks, liabilities and notable information discussed for this job. By accepting this quote you acknowledge these matters and your responsibility .',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black87),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: TextField(
                              controller: _liabilityRiskSearchController,
                              decoration: InputDecoration(
                                labelText: 'Search or add a risk',
                                hintText:
                                    'Search default risks or type a custom risk title',
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.add),
                                  tooltip: 'Add custom risk',
                                  onPressed: () {
                                    final rawText =
                                        _liabilityRiskSearchController.text
                                            .trim();
                                    if (rawText.isEmpty) return;
                                    setState(() {
                                      final customRisk = {
                                        'title': rawText,
                                        'description': '',
                                      };
                                      if (!_selectedLiabilityRisks.any((risk) =>
                                          (risk['title'] ?? '').toLowerCase() ==
                                          rawText.toLowerCase())) {
                                        _selectedLiabilityRisks.add(customRisk);
                                        _hasUnsavedChanges = true;
                                      }
                                      _liabilityRiskSearchController.clear();
                                      _liabilityRiskSearchQuery = '';
                                    });
                                    _saveInProgressEstimate();
                                  },
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _liabilityRiskSearchQuery = value.trim();
                                });
                              },
                              onSubmitted: (value) {
                                final rawText = value.trim();
                                if (rawText.isEmpty) return;
                                setState(() {
                                  final customRisk = {
                                    'title': rawText,
                                    'description': '',
                                  };
                                  if (!_selectedLiabilityRisks.any((risk) =>
                                      (risk['title'] ?? '').toLowerCase() ==
                                      rawText.toLowerCase())) {
                                    _selectedLiabilityRisks.add(customRisk);
                                    _hasUnsavedChanges = true;
                                  }
                                  _liabilityRiskSearchController.clear();
                                  _liabilityRiskSearchQuery = '';
                                });
                                _saveInProgressEstimate();
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Suggested default risks',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      _defaultLiabilityRisks.where((risk) {
                                    final query =
                                        _liabilityRiskSearchQuery.toLowerCase();
                                    final title =
                                        (risk['title'] ?? '').toLowerCase();
                                    return query.isEmpty ||
                                        title.contains(query);
                                  }).map((risk) {
                                    final alreadyAdded = _selectedLiabilityRisks
                                        .any((selected) =>
                                            (selected['title'] ?? '')
                                                .toLowerCase() ==
                                            (risk['title'] ?? '')
                                                .toLowerCase());
                                    return ActionChip(
                                      label: Text(risk['title'] ?? ''),
                                      avatar: alreadyAdded
                                          ? const Icon(Icons.check, size: 18)
                                          : null,
                                      onPressed: alreadyAdded
                                          ? null
                                          : () {
                                              setState(() {
                                                _selectedLiabilityRisks
                                                    .add(risk);
                                                _hasUnsavedChanges = true;
                                              });
                                              _saveInProgressEstimate();
                                            },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          if (_selectedLiabilityRisks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _selectedLiabilityRisks
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final index = entry.key;
                                  final risk = entry.value;
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 6.0),
                                    child: ListTile(
                                      title: Text(risk['title'] ?? ''),
                                      subtitle: Text(risk['description'] ?? ''),
                                      onTap: () => _editLiabilityRisk(index),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          setState(() {
                                            _selectedLiabilityRisks.removeWhere(
                                                (selected) =>
                                                    selected['title'] ==
                                                    risk['title']);
                                            _hasUnsavedChanges = true;
                                          });
                                          _saveInProgressEstimate();
                                        },
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.trending_up,
                              color: Colors.green),
                          title: const Text('Add 15% PM Cut'),
                          subtitle: const Text('Increases all prices by 15%'),
                          onTap: () => Navigator.pop(context, 'add_pm_cut'),
                        ),
                      ],
                    ),
                  ),
                );
                if (result == 'add') {
                  _addSubsection();
                } else if (result == 'add_pm_cut') {
                  _applyProjectManagerMarkup();
                } else if (result == 'add_option') {
                  // --- Add Option logic ---
                  String? newOption;
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Add Option Subsection'),
                        content: TextField(
                          textCapitalization: TextCapitalization.sentences,
                          autofocus: true,
                          decoration:
                              const InputDecoration(labelText: 'Option name'),
                          onChanged: (val) => newOption = val.trim(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (newOption != null &&
                                  newOption!.isNotEmpty &&
                                  !_subsections
                                      .any((s) => s.name == newOption)) {
                                final dividerIdx = _subsections.indexWhere(
                                    (s) => s.name == '---OPTIONS---');
                                setState(() {
                                  // Only insert after the divider, never before
                                  _subsections.insert(dividerIdx + 1,
                                      SubsectionData(name: newOption!));
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
                      newSection =
                          '${_copiedSectionName ?? 'Section'} ($copyNum)';
                      copyNum++;
                    }
                    // Always paste as a main section (before the divider)
                    final dividerIdx = _subsections
                        .indexWhere((s) => s.name == '---OPTIONS---');
                    _subsections.insert(
                        dividerIdx == -1 ? _subsections.length : dividerIdx,
                        SubsectionData(name: newSection));
                    final newItems = _copiedSectionItems
                        .map((item) => item.copyWith(section: newSection))
                        .toList();
                    items.addAll(newItems);
                    _moveVehicleItemsToBottomInSection(newSection);
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
                      newSection =
                          '${_copiedSectionName ?? 'Option'} ($copyNum)';
                      copyNum++;
                    }
                    // Always paste as an option section (after the divider)
                    final dividerIdx = _subsections
                        .indexWhere((s) => s.name == '---OPTIONS---');
                    _subsections.insert(
                        dividerIdx == -1 ? _subsections.length : dividerIdx + 1,
                        SubsectionData(name: newSection));
                    final newItems = _copiedSectionItems
                        .map((item) => item.copyWith(section: newSection))
                        .toList();
                    items.addAll(newItems);
                    _moveVehicleItemsToBottomInSection(newSection);
                    _hasUnsavedChanges = true;
                  });
                  _saveInProgressEstimate();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Section pasted into options!')),
                  );
                }
              },
            )),
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
    return items.fold(
        0.0,
        (sum, i) =>
            sum +
            (i.unitPrice * i.quantity * ((i.discountPercent ?? 0) / 100.0)));
  }

  /// Calculates the profit for a single line item.
  // Removed duplicate _lineProfit method to resolve naming conflict.

  /// Widget to display main totals (Subtotal, GST, Total)
  Widget buildMainTotals() {
    final mainSectionItems = items
        .where((item) => mainSections.any((s) => s.name == item.section))
        .toList();
    final mainDiscount = sectionDiscountTotal(mainSectionItems);
    final mainSubtotal = mainSectionItems.fold<double>(
            0, (sum, i) => sum + i.unitPrice * i.quantity) -
        mainDiscount;
    final mainGst = mainSubtotal * 0.15;
    final mainTotal = mainSubtotal + mainGst;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: FutureBuilder<bool>(
          future: SharedPreferences.getInstance()
              .then((prefs) => prefs.getBool('is_gst_registered') ?? true),
          builder: (context, gstSnapshot) {
            final bool isGstRegistered = gstSnapshot.data ?? true;
            final double displayTotal =
                isGstRegistered ? mainTotal : mainSubtotal;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Always show subtotal when GST is registered, or show as "Total" when GST is disabled
                if (isGstRegistered)
                  Text(
                      'Subtotal (ex GST): \$${mainSubtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16)),
                // Only show GST line if GST is registered
                if (isGstRegistered)
                  Text('GST (15%): \$${mainGst.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16)),
                // Show total with appropriate label
                Text(
                    isGstRegistered
                        ? 'Total (inc GST): \$${displayTotal.toStringAsFixed(2)}'
                        : 'Total: \$${displayTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                // 🔴 FIX: Show Quote Remaining ONLY when there's an actual quoted amount to compare against
                // This prevents showing negative "remaining" when converting from fresh invoice with no quote
                if (_quotedDocumentTotal > 0)
                  Builder(
                    builder: (context) {
                      final documentRemaining =
                          _quotedDocumentTotal - displayTotal;
                      return Text(
                        'Quote Remaining: \$${documentRemaining.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: documentRemaining < 0
                              ? Colors.red
                              : Colors.purple,
                        ),
                      );
                    },
                  ),
                if (mainDiscount.abs() > 0.01)
                  Text('Discount Total: \$${mainDiscount.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                // ...inside buildMainTotals()
                if (_showProfit)
                  Builder(builder: (context) {
                    final mainProfit =
                        mainSections.fold<double>(0, (sum, section) {
                      final sectionItems = items
                          .where((item) => item.section == section.name)
                          .toList();
                      return sum +
                          sectionItems.fold<double>(
                              0, (s, i) => s + _lineProfit(i)) -
                          section.extraCost;
                    });
                    return Text(
                      'Total Profit: \$${mainProfit.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        color: mainProfit < 0 ? Colors.red : Colors.green,
                      ),
                    );
                  }),
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
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
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
                                prefs.getString('bank_details') ??
                                'Bank: 00-0000-0000000-00\nReference: Invoice Number'),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Text(
                                  snapshot.data!,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
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
      ),
    );
  }

  /// Widget to display totals for an option section
  Widget buildOptionSectionTotals(SubsectionData section) {
    final sectionItems =
        items.where((item) => item.section == section.name).toList();
    if (sectionItems.isEmpty && section.extraCost == 0) {
      return const SizedBox.shrink();
    }

    final subtotal = sectionItems.fold<double>(
        0, (sum, i) => sum + i.unitPrice * i.quantity);
    final discount = sectionDiscountTotal(sectionItems);
    final gst = (subtotal - discount) * 0.15;
    final total = (subtotal - discount) + gst;
    final profit =
        sectionItems.fold<double>(0, (sum, i) => sum + _lineProfit(i)) -
            section.extraCost;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: FutureBuilder<bool>(
          future: SharedPreferences.getInstance()
              .then((prefs) => prefs.getBool('is_gst_registered') ?? true),
          builder: (context, gstSnapshot) {
            final bool isGstRegistered = gstSnapshot.data ?? true;
            final double displayTotal =
                isGstRegistered ? total : (subtotal - discount);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Show discount if exists
                if (discount.abs() > 0.01)
                  Text('Discount: -\$${discount.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.red, fontSize: 16)),
                // Always show subtotal when GST is registered
                if (isGstRegistered)
                  Text(
                      'Subtotal (ex GST): \$${(subtotal - discount).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16)),
                // Only show GST line if GST is registered
                if (isGstRegistered)
                  Text('GST (15%): \$${gst.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16)),
                // Show total with appropriate label
                Text(
                    isGstRegistered
                        ? 'Total (inc GST): \$${displayTotal.toStringAsFixed(2)}'
                        : 'Total: \$${displayTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (_showProfit)
                  Text('Total Profit: \$${profit.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        color: profit < 0 ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      )),
              ],
            );
          },
        ),
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
            child: Text('Main Sections',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ...mainSections.map((section) =>
            buildSubsectionCard(section, _subsections.indexOf(section))),
        // Main Totals
        buildMainTotals(),
        // Option Sections
        if (optionSections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Option Sections',
                style: TextStyle(fontWeight: FontWeight.bold)),
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

  /// Applies a "build" template (selected from the Job Details "Builder"
  /// button). Item ID/code (`description`) and quantity are kept exactly as
  /// saved in the template, but buy price, sell price, and item name are
  /// always pulled fresh from the current pricebook for any matched item -
  /// none of that is treated as "saved" on the template itself, so price/
  /// name changes made in the pricebook since the template was saved are
  /// always reflected.
  void _applyTemplate(EstimateTemplate template) {
    final updatedItems = template.items.map((templateItem) {
      final matchingPriceBookItem = _findPriceBookMatchForItem(templateItem);
      if (matchingPriceBookItem == null) return templateItem;

      final newUnitPrice =
          _effectivePriceFromPriceBookItem(matchingPriceBookItem);
      return templateItem.copyWith(
        unitPrice: newUnitPrice > 0 ? newUnitPrice : templateItem.unitPrice,
        purchasePrice: matchingPriceBookItem.purchasePrice,
        name: matchingPriceBookItem.name.isNotEmpty
            ? matchingPriceBookItem.name
            : templateItem.name,
      );
    }).toList();

    setState(() {
      items = List<estimate_item.EstimateItem>.from(
          updatedItems.map((e) => e.copyWith()));
      _subsections
        ..clear()
        ..addAll(template.subsections
            .map((s) => s is SubsectionData ? s : SubsectionData(name: s))
            .toList()
            .cast<SubsectionData>());
      _scopeSummaryController.text = template.scopeSummary;
      _scopeExclusionsController.text = template.scopeExclusions;
      _jobNotesController.text = template.builderNote;
      _selectedLiabilityRisks = template.liabilityRisks
          .map((risk) => {
                'title': risk['title'] ?? '',
                'description': risk['description'] ?? '',
              })
          .toList();
      _hasUnsavedChanges = true;
    });
    _saveInProgressEstimate();
  }

  Future<void> _loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('estimate_templates') ?? [];
    setState(() {
      _templates = jsonList
          .map((s) => EstimateTemplate.fromJson(jsonDecode(s)))
          .toList();
    });
  }

  // 🎯 PERFORMANCE FIX: Debounce + background-isolate encode for pricebook saves.
  // _savePriceBookToDisk() is called from many places (item add, mark-used, edit,
  // etc.) - potentially many times per second while the user is actively working.
  // Each call used to synchronously jsonEncode() the ENTIRE pricebook (50k+ items)
  // on the UI thread, which is exactly what caused the typing/scrolling lag and
  // memory pressure reported after cloud storage was added (the local save path,
  // not just the cloud sync, was the expensive part).
  //
  // Fix:
  // 1. Debounce calls by 800ms so rapid successive edits collapse into one save.
  // 2. Run the actual jsonEncode() on a background isolate via compute() so the
  //    UI thread never blocks on it.
  // 3. Guard against overlapping saves (if one is still in-flight when the next
  //    debounce fires, queue a single follow-up save instead of stacking isolates).
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
                      onPressed: () =>
                          Navigator.pop(context, ImageSource.camera),
                      child: Row(
                        children: const [
                          Icon(Icons.camera_alt),
                          SizedBox(width: 8),
                          Text('Camera'),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(context, ImageSource.gallery),
                      child: Row(
                        children: const [
                          Icon(Icons.photo_library),
                          SizedBox(width: 8),
                          Text('Gallery'),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf']);
                        if (result != null &&
                            result.files.single.path != null) {
                          final file = File(result.files.single.path!);
                          final text = await extractTextFromPdf(file);
                          await _scanReceiptFromText(section.name, text);
                        }
                        Navigator.pop(context);
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.picture_as_pdf),
                          SizedBox(width: 8),
                          Text('Scan from PDF'),
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
                Icon(Icons.receipt_long),
                SizedBox(width: 8),
                Text('Scan Receipt'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: Row(
              children: const [
                Icon(Icons.edit),
                SizedBox(width: 8),
                Text('Manual Entry'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              FilePickerResult? result = await FilePicker.platform
                  .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
              if (result != null && result.files.single.path != null) {
                final file = File(result.files.single.path!);
                final text = await extractTextFromPdf(file);
                await _scanReceiptFromText(section.name, text);
              }
              Navigator.pop(context);
            },
            child: Row(
              children: const [
                Icon(Icons.picture_as_pdf),
                SizedBox(width: 8),
                Text('Scan from PDF'),
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

    if (extractedList == null ||
        extractedList is! List ||
        extractedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items found on receipt.')),
      );
      return;
    }

    // Check for missing id_number and warn user
    final missingIdItems = extractedList
        .where((item) => (item['id_number'] == null ||
            item['id_number'].toString().trim().isEmpty))
        .toList();

    if (missingIdItems.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some items missing ID code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'The following items do not have an ID code and will be skipped:'),
              ...missingIdItems.map((item) => Text(item['item_name'] ?? '',
                  style: const TextStyle(color: Colors.red))),
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
    final filteredExtractedList = extractedList
        .where((item) =>
            item['id_number'] != null &&
            item['id_number'].toString().trim().isNotEmpty)
        .toList();

    // If no items with id_number, show a warning and return
    if (filteredExtractedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items with ID code found.')),
      );
      return;
    }

    final selectedItems = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => SelectExtractedItemsDialogMulti(
        items: filteredExtractedList.cast<Map<String, dynamic>>(),
        showQuantity: true,
      ),
    );

    if (selectedItems != null && selectedItems.isNotEmpty) {
      final newItems = <estimate_item.EstimateItem>[];
      for (final item in selectedItems) {
        final bin = (item['bin_number'] ?? '').toString().trim();
        final id = (item['id_number'] ?? '').toString().trim();
        final name = (item['item_name'] ?? '').toString().trim();
        final qty = (item['quantity'] ?? 1) is int
            ? item['quantity']
            : int.tryParse(item['quantity']?.toString() ?? '') ?? 1;
        final netPrice = (item['net_price'] != null)
            ? double.tryParse(item['net_price'].toString()) ?? 0.0
            : 0.0;

        // DEBUG: Print extracted bin_number, id_number and name
        print(
            '🟦 PDF Extracted item: bin_number="$bin", id_number="$id", name="$name", qty=$qty, net_price=$netPrice');

        models.PriceBookItem? pbItem;
        // Try bin_number first if present
        if (bin.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull(
              (pb) => normalizeCode(pb.code) == normalizeCode(bin));
        }
        // If not found, try id_number
        if (pbItem == null && id.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull(
              (pb) => normalizeCode(pb.code) == normalizeCode(id));
        }
        // If still not found, try name
        if (pbItem == null && name.isNotEmpty) {
          pbItem = priceBook.firstWhereOrNull(
              (pb) => pb.name.trim().toLowerCase() == name.toLowerCase());
        }

        if (pbItem == null) {
          final extensiveMatch =
              await _findExtensivePriceBookItemForReceipt(bin, id, name);
          if (extensiveMatch != null) {
            print(
                '✅ PDF Extensive pricebook match: code="${extensiveMatch.code}", sale=${extensiveMatch.price}, purchase=${extensiveMatch.purchasePrice}');
            final existingIndex = priceBook.indexWhere((pb) =>
                normalizeCode(pb.code) == normalizeCode(extensiveMatch.code));
            if (existingIndex == -1) {
              final importedExtensiveItem = models.PriceBookItem(
                code: extensiveMatch.code,
                name: extensiveMatch.name,
                category: extensiveMatch.category,
                purchasePrice: extensiveMatch.purchasePrice,
                salePrice: extensiveMatch.salePrice,
                unit: extensiveMatch.unit,
                description: extensiveMatch.description ?? extensiveMatch.name,
                barcode: extensiveMatch.barcode,
                favorite: extensiveMatch.favorite,
                origin: 'extensive_import',
                usageCount: extensiveMatch.usageCount + 1,
                percentageChanged: extensiveMatch.percentageChanged,
                isEdited: true,
                needsSync: true,
                isUsed: true,
              );
              priceBook.add(importedExtensiveItem);
              pbItem = importedExtensiveItem;
            } else {
              priceBook[existingIndex].usageCount += 1;
              priceBook[existingIndex].isUsed = true;
              pbItem = priceBook[existingIndex];
            }
            _savePriceBookToDisk();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Imported ${extensiveMatch.name} from extensive pricebook.')),
            );
          }
        }

        if (pbItem != null) {
          print(
              '✅ PDF Pricebook match: code="${pbItem.code}", sale=${pbItem.price}, purchase=${pbItem.purchasePrice}');
          pbItem.isUsed = true;
          newItems.add(
            estimate_item.EstimateItem(
              name: pbItem.name,
              description: pbItem.code,
              unitPrice: _effectivePriceFromPriceBookItem(
                  pbItem), // SELL price from pricebook
              quantity: qty.toDouble(),
              purchasePrice: netPrice > 0 ? netPrice : pbItem.purchasePrice,
              section: section,
            ),
          );
        } else {
          print(
              '❌ PDF No pricebook match for bin="$bin" id="$id" name="$name"');
          newItems.add(
            estimate_item.EstimateItem(
              name: name,
              description: id.isNotEmpty ? id : bin, // keep something traceable
              unitPrice: 0,
              quantity: qty.toDouble(),
              purchasePrice: netPrice > 0 ? netPrice : 0,
              section: section,
            ),
          );
        }
      }
      setState(() {
        items.addAll(newItems);
        _moveVehicleItemsToBottomInSection(section);
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
            final idx = items.lastIndexWhere(
                (i) => i.section == section && i.description == 'CAL');
            if (idx != -1) {
              final dateStr =
                  '${selectedDate.day} ${_monthAbbr(selectedDate.month)}';
              items[idx] = items[idx].copyWith(
                name: 'Labour on $dateStr',
                description: 'Labour on $dateStr',
              );
            }
          });
        }
      }

      _saveInProgressEstimate();
      _savePriceBookToDisk(); // <-- Save pricebook after marking as used
    }
  }

  String? _loadBuilderNoteFromJob() {
    return widget.job.notes
        ?.firstWhereOrNull((note) => note.startsWith(_builderNotePrefix))
        ?.substring(_builderNotePrefix.length);
  }

  void _syncBuilderNoteToJob() {
    final text = _jobNotesController.text.trim();
    final notes = widget.job.notes ?? <String>[];
    final existingIndex =
        notes.indexWhere((note) => note.startsWith(_builderNotePrefix));
    if (text.isEmpty) {
      if (existingIndex != -1) {
        notes.removeAt(existingIndex);
      }
    } else {
      final noteText = '$_builderNotePrefix$text';
      if (existingIndex != -1) {
        notes[existingIndex] = noteText;
      } else {
        notes.add(noteText);
      }
    }
    widget.job.notes = notes;
  }

  String _generateScopeSummaryText() {
    final customerName = (widget.job.companyName != null &&
            widget.job.companyName!.trim().isNotEmpty)
        ? widget.job.companyName!.trim()
        : (widget.job.customerName?.trim().isNotEmpty == true
            ? widget.job.customerName!.trim()
            : 'the customer');
    final address = widget.job.address?.trim();
    final jobNotes = _jobNotesController.text.trim();

    final summaryLines = <String>[];
    summaryLines.add(
        'This job for $customerName${address != null && address.isNotEmpty ? ' at $address' : ''} is designed to clearly define the work scope and customer expectations.');

    if (_subsections.isEmpty) {
      summaryLines.add(
          'No subsections have been added yet, so the scope is currently captured only in the general notes. Add sections and items to build a stronger written scope summary.');
    } else {
      final mainSectionLines = <String>[];
      for (final section in mainSections) {
        final sectionItems =
            items.where((item) => item.section == section.name).toList();
        final sectionNote =
            (_sectionDescriptionControllers[section.name]?.text ??
                    section.description)
                .trim();
        final itemNames = sectionItems
            .map((item) => item.name.trim().isNotEmpty
                ? item.name.trim()
                : item.description.trim())
            .where((value) => value.isNotEmpty)
            .toList();

        if (sectionItems.isEmpty) {
          final sectionText =
              'The ${section.name} section currently has no specific line items.${sectionNote.isNotEmpty ? ' ${sectionNote[0].toUpperCase()}${sectionNote.substring(1)}' : ''}';
          mainSectionLines.add(sectionText);
        } else {
          final firstItems = itemNames.take(4).join(', ');
          final moreSuffix = itemNames.length > 4 ? ' and more' : '';
          final sectionText =
              'The ${section.name} section includes ${itemNames.length} ${itemNames.length == 1 ? 'item' : 'items'} such as $firstItems$moreSuffix.${sectionNote.isNotEmpty ? ' ${sectionNote[0].toUpperCase()}${sectionNote.substring(1)}' : ''}';
          mainSectionLines.add(sectionText);
        }
      }

      if (mainSectionLines.isNotEmpty) {
        summaryLines.add('Primary scope details:');
        summaryLines.addAll(mainSectionLines);
      }

      if (optionSections.isNotEmpty) {
        final optionLines = <String>[];
        for (final section in optionSections) {
          final sectionItems =
              items.where((item) => item.section == section.name).toList();
          final sectionNote =
              (_sectionDescriptionControllers[section.name]?.text ??
                      section.description)
                  .trim();
          final itemNames = sectionItems
              .map((item) => item.name.trim().isNotEmpty
                  ? item.name.trim()
                  : item.description.trim())
              .where((value) => value.isNotEmpty)
              .toList();

          if (sectionItems.isEmpty) {
            final sectionText =
                'The optional section ${section.name} has no line items yet.${sectionNote.isNotEmpty ? ' ${sectionNote[0].toUpperCase()}${sectionNote.substring(1)}' : ''}';
            optionLines.add(sectionText);
          } else {
            final firstItems = itemNames.take(4).join(', ');
            final moreSuffix = itemNames.length > 4 ? ' and more' : '';
            final sectionText =
                'Optional work under ${section.name} includes ${itemNames.length} ${itemNames.length == 1 ? 'item' : 'items'} such as $firstItems$moreSuffix.${sectionNote.isNotEmpty ? ' ${sectionNote[0].toUpperCase()}${sectionNote.substring(1)}' : ''}';
            optionLines.add(sectionText);
          }
        }
        summaryLines.add('Optional scope notes:');
        summaryLines.addAll(optionLines);
      }
    }

    if (jobNotes.isNotEmpty) {
      summaryLines.add('Additional project notes: $jobNotes');
    }

    return summaryLines.join('\n\n').trim();
  }

  Future<void> _saveJobNotes() async {
    _syncBuilderNoteToJob();
    await _persistJobToDisk();
  }

  Future<String?> _createInvoiceSnapshotBuilds({
    required double invoiceTotalIncGst,
    required double totalProfit,
  }) async {
    try {
      final List<String> subsections = _subsections.map((s) => s.name).toList();
      final Map<String, dynamic> additionalData = {
        'depositAmount': _depositAmount,
        'depositPercentage': _depositPercentage,
        'isDepositPercentage': _isDepositPercentage,
        'buildType': _buildType,
        'sectionDescriptions': {
          for (final section in _subsections) section.name: section.description,
        },
        'sectionExtraCosts': {
          for (final section in _subsections) section.name: section.extraCost,
        },
        'builderNote': _jobNotesController.text.trim(),
        'scopeSummaryNotes': _scopeSummaryController.text.trim(),
        'scopeExclusionsNotes': _scopeExclusionsController.text.trim(),
        'liabilityRisks': _selectedLiabilityRisks,
      };

      final invoiceSnapshotBuild = await InProgressBuildService.createNewBuild(
        jobId: widget.job.id,
        items: items.map((item) => item.copyWith()).toList(),
        subsections: subsections,
        buildName: 'Invoice Snapshot Build',
        buildType: 'invoice',
        totalAmount: invoiceTotalIncGst,
        totalProfit: totalProfit,
        additionalData: additionalData,
      );

      final remainingItems =
          items.map((item) => item.copyWith(quantity: 0)).toList();
      await InProgressBuildService.createNewBuild(
        jobId: widget.job.id,
        items: remainingItems,
        subsections: subsections,
        buildName: 'Remaining Invoice Build',
        buildType: _buildType,
        totalAmount: 0.0,
        totalProfit: 0.0,
        additionalData: additionalData,
      );

      return invoiceSnapshotBuild.id;
    } catch (e) {
      print('⚠️ Failed to create invoice snapshot builds: $e');
      return null;
    }
  }

  Future<bool> _saveInProgressEstimate() async {
    // 🔍 MEMORY DEBUG: Save method entry
    print('🔍 [SAVE ENTRY] Starting _saveInProgressEstimate()');

    print('💾 Save method called - editing final build: $_isEditingFinalBuild');

    if (_isEditingFinalBuild && !_hasChangesFromOriginal()) {
      print('💾 SKIPPED: No changes detected for final build');
      return true;
    }

    if (_isSaving) {
      print('💾 BLOCKED: Save already in progress');
      return false;
    }

    _isSaving = true;
    bool success = false;
    final buildId =
        (_currentInProgressId != null || !_originalInProgressBuildDeleted)
            ? _currentInProgressId ?? widget.inProgressBuildId
            : null;

    final previousJobNotes = List<String>.from(widget.job.notes ?? []);
    _syncBuilderNoteToJob();
    final builderNotesChanged =
        !ListEquality().equals(previousJobNotes, widget.job.notes ?? []);

    for (final section in _subsections) {
      section.description =
          _sectionDescriptionControllers[section.name]?.text ??
              section.description;
      final costText = _sectionExtraCostControllers[section.name]?.text;
      if (costText != null) {
        section.extraCost = double.tryParse(costText.trim()) ?? 0.0;
      }
    }
    final List<String> subsections = _subsections.map((s) => s.name).toList();
    final Map<String, dynamic> additionalData = {
      'depositAmount': _depositAmount,
      'depositPercentage': _depositPercentage,
      'isDepositPercentage': _isDepositPercentage,
      'buildType': _buildType,
      'sectionDescriptions': {
        for (final section in _subsections) section.name: section.description,
      },
      'sectionExtraCosts': {
        for (final section in _subsections) section.name: section.extraCost,
      },
      'builderNote': _jobNotesController.text.trim(),
      'scopeSummaryNotes': _scopeSummaryController.text.trim(),
      'scopeExclusionsNotes': _scopeExclusionsController.text.trim(),
      'liabilityRisks': _selectedLiabilityRisks,
      // 🔴 NEW: Persist quoted amounts so "Quote Remaining" survives close/reopen
      if (_quotedDocumentTotal > 0) 'quotedDocumentTotal': _quotedDocumentTotal,
      if (_quotedSubsectionAmounts.isNotEmpty)
        'quotedSubsectionAmounts': _quotedSubsectionAmounts,
    };

    if (builderNotesChanged) {
      try {
        await widget.job.save();
        print('💾 Synced builder note into local job storage');
      } catch (e) {
        print('⚠️ Failed to save builder note to local job storage: $e');
      }
    }

    try {
      if (buildId != null) {
        try {
          await InProgressBuildService.updateBuild(
            buildId: buildId,
            items: items,
            subsections: subsections,
            totalAmount: totalIncGst,
            totalProfit: totalProfit,
            additionalData: additionalData,
          );
          print('💾 Updated existing in-progress build $buildId');
          success = true;
        } catch (e) {
          print(
              '⚠️ Failed to update build $buildId, creating a new build instead: $e');
          final newBuild = await InProgressBuildService.createNewBuild(
            jobId: widget.job.id,
            items: items,
            subsections: subsections,
            buildName: widget.convertToInvoice ? 'Converted Build' : null,
            buildType: _buildType,
            totalAmount: totalIncGst,
            totalProfit: totalProfit,
            templateName: widget.initialTemplate?.name,
            additionalData: additionalData,
          );
          _currentInProgressId = newBuild.id;
          _inProgressSaveCreatedThisSession = true;
          print('💾 Created fallback in-progress build ${newBuild.id}');
          success = true;
        }
      } else {
        final newBuild = await InProgressBuildService.createNewBuild(
          jobId: widget.job.id,
          items: items,
          subsections: subsections,
          buildName: widget.convertToInvoice ? 'Converted Build' : null,
          buildType: _buildType,
          totalAmount: totalIncGst,
          totalProfit: totalProfit,
          templateName: widget.initialTemplate?.name,
          additionalData: additionalData,
        );
        _currentInProgressId = newBuild.id;
        _inProgressSaveCreatedThisSession = true;
        print('💾 Created new in-progress build ${newBuild.id}');
        success = true;
      }

      if (success) {
        _hasUnsavedChanges = false;
      }
    } catch (e) {
      print('❌ SAVE ERROR: $e');
      success = false;
    } finally {
      _isSaving = false;
    }

    // 🔍 MEMORY DEBUG: Save method exit
    print(
        '🔍 [SAVE EXIT] _saveInProgressEstimate() completed, success=$success');
    return success;
  }

  void _saveInProgressEstimateSimple() {
    // 🔴 DEBOUNCE: Don't save immediately on every keystroke!
    // Cancel previous timer if it exists
    _saveDebounce?.cancel();

    // Schedule save for 500ms in future
    // If user keeps typing/editing, this keeps getting reset
    // Only saves after 500ms of inactivity
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _saveInProgressEstimate();
      }
    });
  }

  /// Delete ALL in-progress builds for this job
  /// Called when converting estimate/quote/invoice to final PDF
  Future<void> _deleteAllInProgressBuilds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jobId = widget.job.id;
      final buildListKey = 'in_progress_builds_$jobId';
      final legacyEstimateKey = 'in_progress_estimate_$jobId';

      await prefs.remove(buildListKey);
      await prefs.remove(legacyEstimateKey);

      final estimateBuildsJson = prefs.getStringList('estimate_builds') ?? [];
      if (estimateBuildsJson.isNotEmpty) {
        final updatedBuilds = estimateBuildsJson.where((buildJson) {
          try {
            final data = jsonDecode(buildJson) as Map<String, dynamic>;
            return data['jobId'] != jobId;
          } catch (_) {
            return true;
          }
        }).toList();
        if (updatedBuilds.length != estimateBuildsJson.length) {
          await prefs.setStringList('estimate_builds', updatedBuilds);
        }
      }
      print('🗑️ Successfully deleted all in-progress storage for job $jobId');
    } catch (e) {
      print(
          '❌ Error deleting all in-progress builds for job ${widget.job.id}: $e');
    }
  }

  /// Persist the job to disk and cloud
  Future<void> _persistJobToDisk() async {
    try {
      print('� [PERSIST] Starting to save job: ${widget.job.id}');
      print(
          '🔍 [PERSIST] Job has ${widget.job.estimateVersions.length} estimate versions');

      final dir = await getApplicationDocumentsDirectory();
      final jobId = widget.job.id;
      final jobJson = widget.job.toJson();

      // Save individual job file for backward compatibility
      final jobFile = File('${dir.path}/job_$jobId.json');
      await jobFile.writeAsString(jsonEncode(jobJson));
      print('✅ [PERSIST] Saved individual job file: ${jobFile.path}');

      // CRITICAL: Also update the main jobs.json file that the app uses
      final mainJobsFile = File('${dir.path}/jobs.json');
      print(
          '🔍 [PERSIST] Main jobs file exists: ${await mainJobsFile.exists()}');

      if (await mainJobsFile.exists()) {
        try {
          final jsonString = await mainJobsFile.readAsString();
          print(
              '🔍 [PERSIST] Read jobs.json, length: ${jsonString.length} chars');

          final List<dynamic> jsonList = jsonDecode(jsonString);
          print('🔍 [PERSIST] Decoded JSON list: ${jsonList.length} jobs');

          // Find and update this job in the main list
          final jobIndex = jsonList.indexWhere((j) => j['id'] == jobId);
          print('🔍 [PERSIST] Found job at index: $jobIndex');

          if (jobIndex != -1) {
            jsonList[jobIndex] = jobJson;
            final updatedJson = jsonEncode(jsonList);
            await mainJobsFile.writeAsString(updatedJson);
            print('✅ [PERSIST] Updated job in main jobs.json file');
            print('🔍 [PERSIST] New file size: ${updatedJson.length} chars');
          } else {
            // Add job if not found
            jsonList.add(jobJson);
            final updatedJson = jsonEncode(jsonList);
            await mainJobsFile.writeAsString(updatedJson);
            print('✅ [PERSIST] Added new job to main jobs.json file');
            print('🔍 [PERSIST] New file size: ${updatedJson.length} chars');
          }
        } catch (e) {
          print('❌ [PERSIST] Error updating main jobs.json: $e');
          // Create new jobs.json if corrupted
          final newJson = jsonEncode([jobJson]);
          await mainJobsFile.writeAsString(newJson);
          print('🔍 [PERSIST] Recreated jobs.json with single job');
        }
      } else {
        // Create new jobs.json file if it doesn't exist
        final newJson = jsonEncode([jobJson]);
        await mainJobsFile.writeAsString(newJson);
        print('✅ [PERSIST] Created new jobs.json file');
        print('🔍 [PERSIST] File size: ${newJson.length} chars');
      }

      print('✅ [PERSIST] Job saved successfully (direct save)');
    } catch (e) {
      print('❌ [PERSIST] Error persisting job: $e');
      // Don't throw - local save is still important
    }

    // 🔴 NEW: Push to the cloud too - previously this method only wrote
    // local JSON, so estimates/quotes/invoices and their PDFs never left
    // the device that created them. Best-effort: local save above already
    // succeeded, so a cloud failure here must never be treated as fatal.
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        final urlsChanged =
            await DeltaSyncService.syncPdfsWithDelta(widget.job);
        await FirestoreService.saveJob(widget.job);
        if (urlsChanged) {
          // cloudPdfUrl values were just set on some versions after saveJob
          // already pushed the subcollection - push once more so they stick.
          await FirestoreService.saveJob(widget.job);
        }
        print('☁️ [PERSIST] Job + estimate versions + PDFs synced to cloud');
      } catch (e) {
        print(
            '⚠️ [PERSIST] Cloud sync failed (local save still succeeded): $e');
      }
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
                final dividerIdx =
                    _subsections.indexWhere((s) => s.name == '---OPTIONS---');
                _subsections.insert(dividerIdx == -1 ? 0 : dividerIdx,
                    SubsectionData(name: labourSectionName));
              }

              // Add the labour item
              items.add(labourItem.copyWith(section: labourSectionName));
              _moveVehicleItemsToBottomInSection(labourSectionName);
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
      final siteCoordinates =
          await _getCoordinatesFromAddress(widget.job.address!);
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
          if (distance <= 100) {
            // TODO: This should use _proximityRadius from GPS history screen
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
            'arrivalTime': DateTime.now()
                .subtract(const Duration(minutes: 30)), // Estimate arrival
            'departureTime': null, // Still on site
            'duration': null,
            'distance': currentDistance,
            'isCurrentVisit': true,
          });
        }
      }

      // Sort by most recent first
      visitHistory.sort((a, b) => (b['arrivalTime'] as DateTime)
          .compareTo(a['arrivalTime'] as DateTime));
    } catch (e) {
      print('Error getting site visit history: $e');
    }

    return visitHistory;
  }

  /// Get coordinates from address using geocoding
  Future<Map<String, double>?> _getCoordinatesFromAddress(
      String address) async {
    try {
      // Use geocoding package to convert address to coordinates
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return {
          'lat': locations.first.latitude,
          'lng': locations.first.longitude
        };
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

      print(
          'Loading GPS history from storage: ${historyList.length} entries found');

      final result = historyList.map((entry) {
        return {
          'latitude': entry['latitude'] as double?,
          'longitude': entry['longitude'] as double?,
          'timestamp': entry['timestamp'] != null
              ? DateTime.parse(entry['timestamp'])
              : null,
          'departureTime': entry['departureTime'] != null
              ? DateTime.parse(entry['departureTime'])
              : null,
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
      if (newPermission == LocationPermission.denied ||
          newPermission == LocationPermission.deniedForever) {
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
      print(
          '🔍 DEBUG GPS History Raw JSON: ${historyJson.substring(0, math.min(500, historyJson.length))}...');

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
      final siteCoordinates =
          await _getCoordinatesFromAddress(widget.job.address!);

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
      print(
          '🎯 Test complete! Check GPS history screen to see if it shows up.');
    } catch (e) {
      print('❌ Error during geocoding/location test: $e');
    }
  }

  // Helper functions for EstimateBuild management
  /// Manual save trigger - only save when user navigates away
  void _saveOnExit() {
    if (items.isNotEmpty && !_isSaving) {
      print('🔄 Manual save on exit - ${items.length} items');
      _saveInProgressEstimateSimple();
    }
  }

  Future<void> _saveSectionAsTemplate(SubsectionData section) async {
    final sectionItems =
        items.where((item) => item.section == section.name).toList();
    if (sectionItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in this subsection to save.')),
      );
      return;
    }

    String? templateName = await showDialog<String>(
      context: context,
      builder: (context) {
        String name = '';
        return AlertDialog(
          title: const Text('Save Section as Template'),
          content: TextField(
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Template Name'),
            onChanged: (val) => name = val,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, name),
                child: const Text('Save')),
          ],
        );
      },
    );

    if (templateName == null || templateName.trim().isEmpty) return;

    final trimmedName = templateName.trim();
    final subsectionTemplate = EstimateTemplate(
      name: trimmedName,
      items: sectionItems
          .map((item) => item.copyWith(section: section.name))
          .toList(),
      subsections: [section.name],
      type: 'section', // Mark this as a section template
    );

    setState(() {
      // Only allow one section template with this name and type
      _templates
          .removeWhere((t) => t.name == trimmedName && t.type == 'section');
      _templates.add(subsectionTemplate);
      _hasUnsavedChanges = true;
    });
    await _saveTemplates();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Section template "$trimmedName" saved.')),
    );
  }

  Future<void> _saveSubsectionItemProfitPercentToPriceBook(
      SubsectionData section) async {
    final sectionItems =
        items.where((item) => item.section == section.name).toList();
    if (sectionItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in this subsection to save.')),
      );
      return;
    }

    int savedCount = 0;
    for (final item in sectionItems) {
      if (item.purchasePrice == null || item.purchasePrice! <= 0) {
        continue;
      }
      final pbItem = priceBook.firstWhereOrNull((pb) {
        final codeMatch =
            normalizeCode(pb.code) == normalizeCode(item.description);
        final nameMatch =
            normalizeCode(pb.name) == normalizeCode(item.description);
        final nameMatchAlt = normalizeCode(pb.name) == normalizeCode(item.name);
        return codeMatch || nameMatch || nameMatchAlt;
      });
      if (pbItem == null) {
        continue;
      }
      final percent =
          ((item.unitPrice - item.purchasePrice!) / item.purchasePrice!) * 100;
      final priceActuallyChanged =
          (item.purchasePrice! - pbItem.purchasePrice).abs() >= 0.005 ||
              (item.unitPrice - pbItem.price).abs() >= 0.005;
      pbItem.percentageChanged = percent;
      pbItem.markupPercent = percent;
      pbItem.markupOverridden = true;
      pbItem.purchasePrice = item.purchasePrice!;
      pbItem.price = item.unitPrice;
      if (priceActuallyChanged) {
        pbItem.markPriceChanged();
      }
      savedCount++;
    }

    if (savedCount > 0) {
      _savePriceBookToDisk();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedCount > 0
              ? 'Saved profit % for $savedCount item${savedCount == 1 ? '' : 's'}.'
              : 'No matching pricebook items were updated.',
        ),
      ),
    );
  }

  Future<void> _showSectionTemplatePicker(SubsectionData section) async {
    if (_templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No templates available.')),
      );
      return;
    }

    final selectedTemplate = await showDialog<EstimateTemplate>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Section Template'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView.builder(
              itemCount: _templates.where((t) => t.type == 'section').length,
              itemBuilder: (context, index) {
                final template = _templates
                    .where((t) => t.type == 'section')
                    .toList()[index];
                return ListTile(
                  title: Text(template.name),
                  subtitle: Text('${template.items.length} items'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Template?'),
                          content: Text(
                              'Delete template "${template.name}"? This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        setState(() {
                          _templates.remove(template);
                        });
                        await _saveTemplates();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Template "${template.name}" deleted.')),
                        );
                      }
                    },
                  ),
                  onTap: () => Navigator.pop(context, template),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedTemplate != null) {
      setState(() {
        // Item ID/code (`description`) and quantity are kept exactly as
        // saved in the section template, but buy price, sell price, and
        // item name are always pulled fresh from the current pricebook for
        // any matched item, the same as build templates.
        final templateItems = selectedTemplate.items
            .map((item) => item.copyWith(section: section.name))
            .map((templateItem) {
          final matchingPriceBookItem =
              _findPriceBookMatchForItem(templateItem);
          if (matchingPriceBookItem == null) return templateItem;

          final newUnitPrice =
              _effectivePriceFromPriceBookItem(matchingPriceBookItem);
          return templateItem.copyWith(
            unitPrice: newUnitPrice > 0 ? newUnitPrice : templateItem.unitPrice,
            purchasePrice: matchingPriceBookItem.purchasePrice,
            name: matchingPriceBookItem.name.isNotEmpty
                ? matchingPriceBookItem.name
                : templateItem.name,
          );
        }).toList();
        if (templateItems.isNotEmpty) {
          final insertIdx = items.indexWhere((i) => i.section == section.name);
          if (insertIdx == -1) {
            items.addAll(templateItems);
          } else {
            items.insertAll(insertIdx, templateItems);
          }
          _moveVehicleItemsToBottomInSection(section.name);
          _hasUnsavedChanges = true;
        }
      });
      await _saveInProgressEstimate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template "${selectedTemplate.name}" applied.')),
      );
    }
  }

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

  void _moveVehicleItemsToBottomInSection(String sectionName) {
    final sectionItems =
        items.where((item) => item.section == sectionName).toList();
    if (sectionItems.length < 2) return;

    final vehicleItems = sectionItems
        .where((item) => normalizeCode(item.description) == 'vehicle')
        .toList();
    if (vehicleItems.isEmpty) return;

    final otherItems = sectionItems
        .where((item) => normalizeCode(item.description) != 'vehicle')
        .toList();
    final reorderedSection = [...otherItems, ...vehicleItems];

    if (ListEquality().equals(sectionItems, reorderedSection)) return;

    int sectionIndex = 0;
    items = items.map((item) {
      if (item.section == sectionName) {
        return reorderedSection[sectionIndex++];
      }
      return item;
    }).toList();
  }

  void _moveItemWithinSection(
      SubsectionData section, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final sectionItems =
        items.where((item) => item.section == section.name).toList();
    if (oldIndex < 0 ||
        oldIndex >= sectionItems.length ||
        newIndex < 0 ||
        newIndex > sectionItems.length) return;
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final movedItem = sectionItems.removeAt(oldIndex);
    sectionItems.insert(newIndex, movedItem);

    setState(() {
      int sectionIndex = 0;
      items = items.map((item) {
        if (item.section == section.name) {
          return sectionItems[sectionIndex++];
        }
        return item;
      }).toList();
      _moveVehicleItemsToBottomInSection(section.name);
      _hasUnsavedChanges = true;
    });

    _saveInProgressEstimate();
  }

  void _reorderSubsection(int oldIndex, int newIndex, bool isOptionSection) {
    if (oldIndex == newIndex) return;
    final dividerIdx =
        _subsections.indexWhere((s) => s.name == '---OPTIONS---');

    if (isOptionSection) {
      if (dividerIdx == -1) return;
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = _subsections.removeAt(dividerIdx + 1 + oldIndex);
      _subsections.insert(dividerIdx + 1 + newIndex, moved);
    } else {
      final mainEnd = dividerIdx == -1 ? _subsections.length : dividerIdx;
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = _subsections.removeAt(oldIndex);
      _subsections.insert(newIndex.clamp(0, mainEnd), moved);
    }

    setState(() {
      _hasUnsavedChanges = true;
    });
    _saveInProgressEstimate();
  }

  /// Builds a card widget for a subsection, including its items and controls.
  Widget buildSubsectionCard(SubsectionData section, int index) {
    final sectionItems =
        items.where((item) => item.section == section.name).toList();

    // 🔴 MAJOR FIX: Calculate purple difference based on ENTIRE SUBSECTION TOTALS
    // not individual item leftovers. This accounts for items that weren't quoted
    // but were used (added to invoice), and items that were quoted but weren't used.
    final sectionQuoteRemaining = _subsectionQuotedDifference(sectionItems);

    void showRenameDialog() async {
      String? newName = section.name;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename Subsection'),
          content: TextField(
            textCapitalization: TextCapitalization.sentences,
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
                if (newName != null &&
                    newName!.isNotEmpty &&
                    !_subsections.any((s) => s.name == newName)) {
                  final renamedSectionName = newName!;
                  setState(() {
                    // Update section name in _subsections and all items
                    final oldName = section.name;
                    section.name = renamedSectionName;
                    _renameSectionRelatedKeys(oldName, renamedSectionName);
                    for (int i = 0; i < items.length; i++) {
                      if (items[i].section == oldName) {
                        items[i] =
                            items[i].copyWith(section: renamedSectionName);
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
    final searchResults =
        searchPriceBook(priceBook, searchQuery, maxResults: 30);
    final showMoreResults = _sectionSearchShowMore[section.name] ?? false;
    final displayedResultsCount =
        math.min(searchResults.length, showMoreResults ? 30 : 10);
    final searchAddCounts = _sectionSearchAddCounts[section.name] ?? const {};
    // Items already added via '+' this search session, kept visible even if
    // the query is edited afterwards so it's clear they're still included.
    final sessionAddedItems =
        _sectionSearchAddedItems[section.name] ?? const {};

    final searchFocusNode =
        _sectionSearchFocusNodes[section.name] ??= FocusNode();

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
                  onSelected: (value) async {
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
                              .map((item) =>
                                  item.copyWith(section: section.name))
                              .toList();
                          items.addAll(newItems);
                          _moveVehicleItemsToBottomInSection(section.name);
                          _hasUnsavedChanges = true;
                        });
                        _saveInProgressEstimate();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Items pasted!')),
                        );
                      }
                    } else if (value == 'save_subsection_template') {
                      _saveSectionAsTemplate(section);
                    } else if (value == 'add_template_items') {
                      _showSectionTemplatePicker(section);
                    } else if (value == 'save_subsection_profit_percent') {
                      await _saveSubsectionItemProfitPercentToPriceBook(
                          section);
                    } else if (value == 'flip_items') {
                      setState(() {
                        final sectionIndices = <int>[];
                        for (var i = 0; i < items.length; i++) {
                          if (items[i].section == section.name) {
                            sectionIndices.add(i);
                          }
                        }
                        final reversedItems = sectionIndices
                            .map((index) => items[index])
                            .toList()
                            .reversed
                            .toList();
                        for (var i = 0; i < sectionIndices.length; i++) {
                          items[sectionIndices[i]] = reversedItems[i];
                        }
                        _hasUnsavedChanges = true;
                      });
                      _saveInProgressEstimate();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Section items flipped!')),
                      );
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
                      value: 'save_subsection_template',
                      child: Text('Create subsection template'),
                    ),
                    const PopupMenuItem(
                      value: 'add_template_items',
                      child: Text('Add Template / Search templates'),
                    ),
                    const PopupMenuItem(
                      value: 'save_subsection_profit_percent',
                      child: Text('Save item profit %'),
                    ),
                    const PopupMenuItem(
                      value: 'flip_items',
                      child: Text('Flip Items'),
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
                      VoiceTextField(
                        controller: _getSectionDescriptionController(section),
                        labelText: 'Subsection description',
                        minLines: 2,
                        maxLines: null,
                        continuousListening: true,
                        decoration: const InputDecoration(
                          isDense: true,
                        ),
                        onChanged: () {
                          section.description =
                              _getSectionDescriptionController(section).text;
                          _hasUnsavedChanges = true;
                        },
                        onEditingComplete: () => _saveInProgressEstimate(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _sectionSearchControllers[section.name] ??=
                            TextEditingController(),
                        focusNode: searchFocusNode,
                        // This field sits inside a ReorderableListView (subsection
                        // card is an item of the outer reorderable list). Same fix
                        // as the sale price/quantity fields and VoiceTextField: disable
                        // interactive selection so the internal CompositedTransformFollower
                        // used for selection handles/magnifier doesn't throw
                        // "LeaderLayer must come before FollowerLayer" when the
                        // keyboard opens/animates while this field is nested inside
                        // the reorderable list.
                        enableInteractiveSelection: false,
                        decoration: const InputDecoration(
                          labelText: 'Search Pricebook',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onTap: () async {
                          // Wait for the keyboard to open, then scroll this field to top
                          await Future.delayed(
                              const Duration(milliseconds: 100));
                          if (searchFocusNode.hasFocus && mounted) {
                            // Scroll the search field to the top of the viewport
                            // so search results will be visible below it
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (searchFocusNode.context != null && mounted) {
                                // Use a longer scroll duration and center alignment
                                // to ensure the search field and results area is
                                // fully visible above the keyboard
                                Scrollable.ensureVisible(
                                  searchFocusNode.context!,
                                  duration: const Duration(milliseconds: 400),
                                  alignment: 0.3, // Position near top of screen
                                  curve: Curves.easeInOut,
                                );
                              }
                            });
                          }
                        },
                        onChanged: (val) {
                          _debouncedSearch(section.name, val);
                        },
                      ),
                      // 🎯 PERFORMANCE: Limit results to 10 and use ListView.builder for efficiency
                      // Restored to its own independent scroll (per user preference) -
                      // this box has a fixed max height, so it scrolls its own results
                      // instead of expanding/competing with the page scroll.
                      if (searchQuery.isNotEmpty && searchResults.isNotEmpty)
                        SizedBox(
                          height:
                              math.min(displayedResultsCount * 72.0, 320.0),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: displayedResultsCount,
                            itemBuilder: (context, idx) {
                              final item = searchResults[idx];
                              final addCount = searchAddCounts[item.code] ?? 0;
                              return ListTile(
                                title: Text(item.name),
                                subtitle: Text(
                                    'Code: ${item.code}  \$${item.price.toStringAsFixed(2)}'),
                                // Tapping the tile adds the item and closes the search.
                                onTap: () async {
                                  estimate_item.EstimateItem? addedItem;
                                  setState(() {
                                    addedItem = _addOrBumpPriceBookSearchResult(
                                        section, item,
                                        closeSearchAfter: true);
                                  });
                                  searchFocusNode.unfocus();
                                  _saveInProgressEstimateSimple();
                                  await _handleSpecialSearchItemAdded(
                                      section, addedItem);
                                },
                                // The '+' button adds/bumps quantity but keeps the
                                // search open so multiple items can be added in a row.
                                trailing: TextButton(
                                  onPressed: () async {
                                    estimate_item.EstimateItem? addedItem;
                                    setState(() {
                                      addedItem =
                                          _addOrBumpPriceBookSearchResult(
                                              section, item,
                                              closeSearchAfter: false);
                                    });
                                    _saveInProgressEstimateSimple();
                                    await _handleSpecialSearchItemAdded(
                                        section, addedItem);
                                  },
                                  child: Text(
                                      addCount > 0 ? '+ ($addCount)' : '+'),
                                ),
                              );
                            },
                          ),
                        ),
                      // Persist a reminder of what's been '+'-added this session even
                      // after the search text changes and those items scroll out of
                      // the results list - they're already in the subsection.
                      if (sessionAddedItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final entry in sessionAddedItems.entries)
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(Icons.check, size: 16),
                                  label: Text(
                                    '${entry.value.name} x${searchAddCounts[entry.key] ?? 1}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (searchQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (searchResults.length > 10)
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _sectionSearchShowMore[
                                              section.name] = !showMoreResults;
                                        });
                                      },
                                      child: Text(showMoreResults
                                          ? 'Show less'
                                          : 'Show more'),
                                    ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () =>
                                        _closeSectionSearch(section),
                                    child: const Text('Done'),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(searchResults.isEmpty
                                        ? 'No results found.'
                                        : 'Search extensive book for more results.'),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.search, size: 18),
                                    label: const Text('Search extensive book'),
                                    onPressed: () {
                                      _searchExtensivePriceBookAndOfferImport(
                                          section, searchQuery);
                                    },
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              // 🔴 NEW: Custom Item button
                              TextButton.icon(
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 18),
                                label: const Text('Create Custom Item'),
                                onPressed: () {
                                  _createCustomItemFromSearch(
                                      section, searchQuery);
                                },
                              ),
                            ],
                          ),
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
                      _onBarcodeScanned(barcode, section.name,
                          _sectionSearchControllers[section.name]!);
                    }
                  },
                ),
              ],
            ),
          ),
          if (sectionItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No items in this section.',
                  style: TextStyle(color: Colors.grey)),
            ),
          if (sectionItems.isNotEmpty)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              onReorderStart: (_) => _startDragAutoScroll(),
              onReorderEnd: (_) => _stopDragAutoScroll(),
              onReorder: (oldIndex, newIndex) =>
                  _moveItemWithinSection(section, oldIndex, newIndex),
              children: sectionItems.asMap().entries.map((entry) {
                final item = entry.value;

                // Calculate discount amount
                final discountAmount = item.discountAmount ?? 0;

                // Calculate profit after discount
                final profit =
                    (item.unitPrice * item.quantity - discountAmount) -
                        ((item.purchasePrice ?? 0) * item.quantity);

                // 🔴 PERFORMANCE: RepaintBoundary isolates this row's paint
                // layer so editing/animating one item (e.g. tapping +/-,
                // typing a price) doesn't force Flutter to re-raster every
                // other row's pixels too. This doesn't reduce how often
                // build() runs (that would need extracting the whole row
                // into its own widget - a much bigger refactor), but it
                // significantly cuts the GPU/raster cost of each rebuild,
                // which is the part of "lag across the entire build" that's
                // safe to fix without touching any of the row's logic.
                return RepaintBoundary(
                  key: ValueKey(item), // Add a key for reorderable list
                  child: Container(
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
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
                                      final pbItem = priceBook.firstWhereOrNull(
                                          (pb) =>
                                              normalizeCode(pb.code) ==
                                              normalizeCode(item.description));
                                      final nameController =
                                          TextEditingController(
                                              text: item.name);
                                      final purchaseController =
                                          TextEditingController(
                                              text: (item.purchasePrice ?? 0)
                                                  .toStringAsFixed(2));
                                      final priceController =
                                          TextEditingController(
                                              text: item.unitPrice
                                                  .toStringAsFixed(2));
                                      final qtyController =
                                          TextEditingController(
                                              text: item.quantity.toString());
                                      final percentController =
                                          TextEditingController(
                                        text: (item.purchasePrice != null &&
                                                item.purchasePrice! > 0)
                                            ? (((item.unitPrice -
                                                            item.purchasePrice!) /
                                                        item.purchasePrice!) *
                                                    100)
                                                .toStringAsFixed(1)
                                            : '0',
                                      );
                                      final discountController =
                                          TextEditingController(
                                        text: (item.discountPercent ?? 0)
                                            .toStringAsFixed(1),
                                      );
                                      bool saveNameToPB = false;
                                      bool savePercentToPB = false;
                                      bool savePriceToPB = false;

                                      await showDialog(
                                        context: context,
                                        builder: (context) => StatefulBuilder(
                                          builder: (context, setState) =>
                                              AlertDialog(
                                            title: const Text('Edit Line Item'),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextField(
                                                          textCapitalization:
                                                              TextCapitalization
                                                                  .sentences,
                                                          controller:
                                                              nameController,
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      'Name'),
                                                        ),
                                                      ),
                                                      if (pbItem != null)
                                                        Checkbox(
                                                          value: saveNameToPB,
                                                          onChanged: (val) =>
                                                              setState(() =>
                                                                  saveNameToPB =
                                                                      val ??
                                                                          false),
                                                        ),
                                                      if (pbItem != null)
                                                        const Text('PB',
                                                            style: TextStyle(
                                                                fontSize: 12)),
                                                    ],
                                                  ),
                                                  if (_showProfit &&
                                                      _showLineItemPrices)
                                                    TextField(
                                                      textCapitalization:
                                                          TextCapitalization
                                                              .sentences,
                                                      controller:
                                                          purchaseController,
                                                      keyboardType:
                                                          const TextInputType
                                                              .numberWithOptions(
                                                              decimal: true,
                                                              signed: true),
                                                      decoration:
                                                          const InputDecoration(
                                                              labelText:
                                                                  'Purchase Price'),
                                                      onChanged: (val) {
                                                        final buy =
                                                            double.tryParse(
                                                                    val) ??
                                                                0;
                                                        final sell =
                                                            double.tryParse(
                                                                    priceController
                                                                        .text) ??
                                                                0;
                                                        if (buy > 0) {
                                                          percentController
                                                              .text = ((sell -
                                                                      buy) /
                                                                  buy *
                                                                  100)
                                                              .toStringAsFixed(
                                                                  1);
                                                        }
                                                      },
                                                    ),
                                                  TextField(
                                                    textCapitalization:
                                                        TextCapitalization
                                                            .sentences,
                                                    controller: priceController,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true,
                                                            signed: true),
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Sale Price'),
                                                    onChanged: (val) {
                                                      final buy = double.tryParse(
                                                              purchaseController
                                                                  .text) ??
                                                          0;
                                                      final sell =
                                                          double.tryParse(
                                                                  val) ??
                                                              0;
                                                      if (_showProfit &&
                                                          buy > 0) {
                                                        percentController
                                                            .text = ((sell -
                                                                    buy) /
                                                                buy *
                                                                100)
                                                            .toStringAsFixed(1);
                                                      }
                                                    },
                                                  ),
                                                  if (pbItem != null)
                                                    Row(
                                                      children: [
                                                        Checkbox(
                                                          value: savePriceToPB,
                                                          onChanged: (val) =>
                                                              setState(() =>
                                                                  savePriceToPB =
                                                                      val ??
                                                                          false),
                                                        ),
                                                        const Text(
                                                            'Save sale price to PB',
                                                            style: TextStyle(
                                                                fontSize: 12)),
                                                      ],
                                                    ),
                                                  if (_showProfit)
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextField(
                                                            textCapitalization:
                                                                TextCapitalization
                                                                    .sentences,
                                                            controller:
                                                                percentController,
                                                            keyboardType:
                                                                const TextInputType
                                                                    .numberWithOptions(
                                                                    decimal:
                                                                        true,
                                                                    signed:
                                                                        true),
                                                            decoration:
                                                                const InputDecoration(
                                                                    labelText:
                                                                        'Profit %'),
                                                            onChanged: (val) {
                                                              final buy = double
                                                                      .tryParse(
                                                                          purchaseController
                                                                              .text) ??
                                                                  0;
                                                              final percent =
                                                                  double.tryParse(
                                                                          val) ??
                                                                      0;
                                                              if (buy > 0) {
                                                                priceController
                                                                    .text = (buy *
                                                                        (1 +
                                                                            percent /
                                                                                100))
                                                                    .toStringAsFixed(
                                                                        2);
                                                              }
                                                            },
                                                          ),
                                                        ),
                                                        if (pbItem != null)
                                                          Checkbox(
                                                            value:
                                                                savePercentToPB,
                                                            onChanged: (val) =>
                                                                setState(() =>
                                                                    savePercentToPB =
                                                                        val ??
                                                                            false),
                                                          ),
                                                        if (pbItem != null)
                                                          const Text('PB',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      12)),
                                                      ],
                                                    ),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: GestureDetector(
                                                          onTap: () async {
                                                            // Show dialog to edit discount %
                                                            final result =
                                                                await showDialog<
                                                                    double>(
                                                              context: context,
                                                              builder:
                                                                  (context) {
                                                                final ctrl =
                                                                    TextEditingController(
                                                                        text: discountController
                                                                            .text);
                                                                return AlertDialog(
                                                                  title: const Text(
                                                                      'Edit Discount %'),
                                                                  content:
                                                                      TextField(
                                                                    textCapitalization:
                                                                        TextCapitalization
                                                                            .sentences,
                                                                    controller:
                                                                        ctrl,
                                                                    keyboardType: const TextInputType
                                                                        .numberWithOptions(
                                                                        decimal:
                                                                            true,
                                                                        signed:
                                                                            true),
                                                                    decoration: const InputDecoration(
                                                                        labelText:
                                                                            'Discount %'),
                                                                    autofocus:
                                                                        true,
                                                                  ),
                                                                  actions: [
                                                                    TextButton(
                                                                      onPressed:
                                                                          () =>
                                                                              Navigator.pop(context),
                                                                      child: const Text(
                                                                          'Cancel'),
                                                                    ),
                                                                    ElevatedButton(
                                                                      onPressed:
                                                                          () {
                                                                        final val =
                                                                            double.tryParse(ctrl.text);
                                                                        if (val !=
                                                                                null &&
                                                                            val >
                                                                                0)
                                                                          Navigator.pop(
                                                                              context,
                                                                              val);
                                                                      },
                                                                      child: const Text(
                                                                          'Save'),
                                                                    ),
                                                                  ],
                                                                );
                                                              },
                                                            );
                                                            if (result !=
                                                                null) {
                                                              setState(() {
                                                                discountController
                                                                        .text =
                                                                    result
                                                                        .toStringAsFixed(
                                                                            1);
                                                              });
                                                            }
                                                          },
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        4),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .blue[50],
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                            child: Text(
                                                              'Discount ${discountController.text}%',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .blue[800],
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
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
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  final newName = nameController
                                                      .text
                                                      .trim();
                                                  final newPurchase =
                                                      double.tryParse(
                                                              purchaseController
                                                                  .text) ??
                                                          item.purchasePrice ??
                                                          0;
                                                  final newPrice =
                                                      double.tryParse(
                                                              priceController
                                                                  .text) ??
                                                          item.unitPrice;
                                                  final newPercent =
                                                      double.tryParse(
                                                              percentController
                                                                  .text) ??
                                                          0.0;
                                                  final newQty =
                                                      double.tryParse(
                                                              qtyController
                                                                  .text) ??
                                                          item.quantity;

                                                  setState(() {
                                                    final idx =
                                                        items.indexOf(item);
                                                    items[idx] = item.copyWith(
                                                      name: newName,
                                                      purchasePrice: _showProfit
                                                          ? newPurchase
                                                          : item.purchasePrice,
                                                      unitPrice: newPrice,
                                                      quantity: newQty,
                                                    );
                                                    _hasUnsavedChanges = true;
                                                  });

                                                  // Save to pricebook if checked
                                                  if (pbItem != null) {
                                                    final oldPbPrice =
                                                        pbItem.price;
                                                    final oldPbPurchasePrice =
                                                        pbItem.purchasePrice;
                                                    if (saveNameToPB) {
                                                      pbItem.name = newName;
                                                    }
                                                    if (savePriceToPB) {
                                                      pbItem.price = newPrice;
                                                      pbItem.purchasePrice =
                                                          newPurchase;
                                                    }
                                                    if (savePercentToPB) {
                                                      pbItem.percentageChanged =
                                                          newPercent;
                                                      pbItem.markupPercent =
                                                          newPercent;
                                                      pbItem.markupOverridden =
                                                          true;
                                                      if (newPurchase > 0) {
                                                        pbItem.purchasePrice =
                                                            newPurchase;
                                                      }
                                                      pbItem.price = newPrice;
                                                    }
                                                    if (saveNameToPB ||
                                                        savePriceToPB ||
                                                        savePercentToPB) {
                                                      final priceActuallyChanged = (pbItem
                                                                          .price -
                                                                      oldPbPrice)
                                                                  .abs() >=
                                                              0.005 ||
                                                          (pbItem.purchasePrice -
                                                                      oldPbPurchasePrice)
                                                                  .abs() >=
                                                              0.005;
                                                      if (priceActuallyChanged) {
                                                        pbItem
                                                            .markPriceChanged();
                                                      }
                                                      _savePriceBookToDisk();
                                                    }
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
                                                child: const Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red)),
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
                                      final pbItem = priceBook.firstWhereOrNull(
                                          (pb) =>
                                              normalizeCode(pb.code) ==
                                              normalizeCode(item.description));
                                      final nameController =
                                          TextEditingController(
                                              text: item.name);
                                      final purchaseController =
                                          TextEditingController(
                                              text: (item.purchasePrice ?? 0)
                                                  .toStringAsFixed(2));
                                      final priceController =
                                          TextEditingController(
                                              text: item.unitPrice
                                                  .toStringAsFixed(2));
                                      final qtyController =
                                          TextEditingController(
                                              text: item.quantity.toString());
                                      final percentController =
                                          TextEditingController(
                                        text: (item.purchasePrice != null &&
                                                item.purchasePrice! > 0)
                                            ? (((item.unitPrice -
                                                            item.purchasePrice!) /
                                                        item.purchasePrice!) *
                                                    100)
                                                .toStringAsFixed(1)
                                            : '0',
                                      );
                                      final discountController =
                                          TextEditingController(
                                        text: (item.discountPercent ?? 0)
                                            .toStringAsFixed(1),
                                      );
                                      bool saveNameToPB = false;
                                      bool savePercentToPB = false;
                                      bool savePriceToPB = false;

                                      await showDialog(
                                        context: context,
                                        builder: (context) => StatefulBuilder(
                                          builder: (context, setState) =>
                                              AlertDialog(
                                            title: const Text('Edit Line Item'),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextField(
                                                          textCapitalization:
                                                              TextCapitalization
                                                                  .sentences,
                                                          controller:
                                                              nameController,
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      'Name'),
                                                        ),
                                                      ),
                                                      if (pbItem != null)
                                                        Checkbox(
                                                          value: saveNameToPB,
                                                          onChanged: (val) =>
                                                              setState(() =>
                                                                  saveNameToPB =
                                                                      val ??
                                                                          false),
                                                        ),
                                                      if (pbItem != null)
                                                        const Text('PB',
                                                            style: TextStyle(
                                                                fontSize: 12)),
                                                    ],
                                                  ),
                                                  if (_showProfit &&
                                                      _showLineItemPrices)
                                                    TextField(
                                                      textCapitalization:
                                                          TextCapitalization
                                                              .sentences,
                                                      controller:
                                                          purchaseController,
                                                      keyboardType:
                                                          const TextInputType
                                                              .numberWithOptions(
                                                              decimal: true,
                                                              signed: true),
                                                      decoration:
                                                          const InputDecoration(
                                                              labelText:
                                                                  'Purchase Price'),
                                                      onChanged: (val) {
                                                        final buy =
                                                            double.tryParse(
                                                                    val) ??
                                                                0;
                                                        final sell =
                                                            double.tryParse(
                                                                    priceController
                                                                        .text) ??
                                                                0;
                                                        if (buy > 0) {
                                                          percentController
                                                              .text = ((sell -
                                                                      buy) /
                                                                  buy *
                                                                  100)
                                                              .toStringAsFixed(
                                                                  1);
                                                        }
                                                      },
                                                    ),
                                                  TextField(
                                                    textCapitalization:
                                                        TextCapitalization
                                                            .sentences,
                                                    controller: priceController,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true,
                                                            signed: true),
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Sale Price'),
                                                    onChanged: (val) {
                                                      final buy = double.tryParse(
                                                              purchaseController
                                                                  .text) ??
                                                          0;
                                                      final sell =
                                                          double.tryParse(
                                                                  val) ??
                                                              0;
                                                      if (_showProfit &&
                                                          buy > 0) {
                                                        percentController
                                                            .text = ((sell -
                                                                    buy) /
                                                                buy *
                                                                100)
                                                            .toStringAsFixed(1);
                                                      }
                                                    },
                                                  ),
                                                  if (_showProfit) ...[
                                                    if (pbItem != null)
                                                      Row(
                                                        children: [
                                                          Checkbox(
                                                            value:
                                                                savePriceToPB,
                                                            onChanged: (val) =>
                                                                setState(() =>
                                                                    savePriceToPB =
                                                                        val ??
                                                                            false),
                                                          ),
                                                          const Text(
                                                              'Save sale price to PB',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      12)),
                                                        ],
                                                      ),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextField(
                                                            textCapitalization:
                                                                TextCapitalization
                                                                    .sentences,
                                                            controller:
                                                                percentController,
                                                            keyboardType:
                                                                const TextInputType
                                                                    .numberWithOptions(
                                                                    decimal:
                                                                        true,
                                                                    signed:
                                                                        true),
                                                            decoration:
                                                                const InputDecoration(
                                                                    labelText:
                                                                        'Profit %'),
                                                            onChanged: (val) {
                                                              final buy = double
                                                                      .tryParse(
                                                                          purchaseController
                                                                              .text) ??
                                                                  0;
                                                              final percent =
                                                                  double.tryParse(
                                                                          val) ??
                                                                      0;
                                                              if (buy > 0) {
                                                                priceController
                                                                    .text = (buy *
                                                                        (1 +
                                                                            percent /
                                                                                100))
                                                                    .toStringAsFixed(
                                                                        2);
                                                              }
                                                            },
                                                          ),
                                                        ),
                                                        if (pbItem != null)
                                                          Checkbox(
                                                            value:
                                                                savePercentToPB,
                                                            onChanged: (val) =>
                                                                setState(() =>
                                                                    savePercentToPB =
                                                                        val ??
                                                                            false),
                                                          ),
                                                        if (pbItem != null)
                                                          const Text('PB',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      12)),
                                                      ],
                                                    ),
                                                  ],
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: GestureDetector(
                                                          onTap: () async {
                                                            // Show dialog to edit discount %
                                                            final result =
                                                                await showDialog<
                                                                    double>(
                                                              context: context,
                                                              builder:
                                                                  (context) {
                                                                final ctrl =
                                                                    TextEditingController(
                                                                        text: discountController
                                                                            .text);
                                                                return AlertDialog(
                                                                  title: const Text(
                                                                      'Edit Discount %'),
                                                                  content:
                                                                      TextField(
                                                                    textCapitalization:
                                                                        TextCapitalization
                                                                            .sentences,
                                                                    controller:
                                                                        ctrl,
                                                                    keyboardType: const TextInputType
                                                                        .numberWithOptions(
                                                                        decimal:
                                                                            true,
                                                                        signed:
                                                                            true),
                                                                    decoration: const InputDecoration(
                                                                        labelText:
                                                                            'Discount %'),
                                                                    autofocus:
                                                                        true,
                                                                  ),
                                                                  actions: [
                                                                    TextButton(
                                                                      onPressed:
                                                                          () =>
                                                                              Navigator.pop(context),
                                                                      child: const Text(
                                                                          'Cancel'),
                                                                    ),
                                                                    ElevatedButton(
                                                                      onPressed:
                                                                          () {
                                                                        final val =
                                                                            double.tryParse(ctrl.text);
                                                                        if (val !=
                                                                                null &&
                                                                            val >
                                                                                0)
                                                                          Navigator.pop(
                                                                              context,
                                                                              val);
                                                                      },
                                                                      child: const Text(
                                                                          'Save'),
                                                                    ),
                                                                  ],
                                                                );
                                                              },
                                                            );
                                                            if (result !=
                                                                null) {
                                                              setState(() {
                                                                discountController
                                                                        .text =
                                                                    result
                                                                        .toStringAsFixed(
                                                                            1);
                                                              });
                                                            }
                                                          },
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        4),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .blue[50],
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                            child: Text(
                                                              'Discount ${discountController.text}%',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .blue[800],
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
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
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  final newName = nameController
                                                      .text
                                                      .trim();
                                                  final newPurchase =
                                                      double.tryParse(
                                                              purchaseController
                                                                  .text) ??
                                                          item.purchasePrice ??
                                                          0;
                                                  final newPrice =
                                                      double.tryParse(
                                                              priceController
                                                                  .text) ??
                                                          item.unitPrice;
                                                  final newPercent =
                                                      double.tryParse(
                                                              percentController
                                                                  .text) ??
                                                          0.0;
                                                  final newQty =
                                                      double.tryParse(
                                                              qtyController
                                                                  .text) ??
                                                          item.quantity;

                                                  setState(() {
                                                    final idx =
                                                        items.indexOf(item);
                                                    items[idx] = item.copyWith(
                                                      name: newName,
                                                      purchasePrice: _showProfit
                                                          ? newPurchase
                                                          : item.purchasePrice,
                                                      unitPrice: newPrice,
                                                      quantity: newQty,
                                                    );
                                                    _hasUnsavedChanges = true;
                                                  });

                                                  // Save to pricebook if checked
                                                  if (pbItem != null) {
                                                    final oldPbPrice =
                                                        pbItem.price;
                                                    final oldPbPurchasePrice =
                                                        pbItem.purchasePrice;
                                                    if (saveNameToPB) {
                                                      pbItem.name = newName;
                                                    }
                                                    if (savePriceToPB) {
                                                      pbItem.price = newPrice;
                                                      pbItem.purchasePrice =
                                                          newPurchase;
                                                    }
                                                    if (savePercentToPB) {
                                                      pbItem.percentageChanged =
                                                          newPercent;
                                                      pbItem.markupPercent =
                                                          newPercent;
                                                      pbItem.markupOverridden =
                                                          true;
                                                      if (newPurchase > 0) {
                                                        pbItem.purchasePrice =
                                                            newPurchase;
                                                      }
                                                      pbItem.price = newPrice;
                                                    }
                                                    if (saveNameToPB ||
                                                        savePriceToPB ||
                                                        savePercentToPB) {
                                                      final priceActuallyChanged = (pbItem
                                                                          .price -
                                                                      oldPbPrice)
                                                                  .abs() >=
                                                              0.005 ||
                                                          (pbItem.purchasePrice -
                                                                      oldPbPurchasePrice)
                                                                  .abs() >=
                                                              0.005;
                                                      if (priceActuallyChanged) {
                                                        pbItem
                                                            .markPriceChanged();
                                                      }
                                                      _savePriceBookToDisk();
                                                    }
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
                                                child: const Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    } else if (value == 'copy') {
                                      // Copy functionality can be implemented later if needed
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('Line item copied!')),
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
                                    const PopupMenuItem(
                                        value: 'edit', child: Text('Edit')),
                                    const PopupMenuItem(
                                        value: 'copy', child: Text('Copy')),
                                    const PopupMenuItem(
                                        value: 'delete', child: Text('Delete')),
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
                                  width:
                                      70, // Reduced from 90 to give more room for total
                                  child: Focus(
                                    onFocusChange: (hasFocus) {
                                      if (!hasFocus)
                                        _commitSalePriceEdit(item, save: true);
                                    },
                                    child: TextField(
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      controller: _getSalePriceController(item),
                                      // Disabled: this field always selects-all on tap and
                                      // doesn't need drag-selection handles/magnifier. Those
                                      // rely on an internal CompositedTransformFollower which
                                      // can throw "LeaderLayer must come before FollowerLayer"
                                      // when this field sits inside a ReorderableListView and
                                      // the keyboard opens/animates - causing per-frame jank.
                                      enableInteractiveSelection: false,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true, signed: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Sale Price',
                                        isDense: true,
                                        border: UnderlineInputBorder(),
                                        contentPadding:
                                            EdgeInsets.only(bottom: 0),
                                      ),
                                      textAlign: TextAlign.center,
                                      focusNode: _getSalePriceFocusNode(item),
                                      onTap: () {
                                        // Select all text on tap for easier editing
                                        final ctrl =
                                            _getSalePriceController(item);
                                        ctrl.selection = TextSelection(
                                            baseOffset: 0,
                                            extentOffset: ctrl.text.length);
                                        // Some taps land while the field already "has"
                                        // focus (e.g. stale focus left over from the
                                        // ReorderableListView drag arena), so Flutter
                                        // skips reopening the keyboard. Force it explicitly.
                                        final focusNode =
                                            _getSalePriceFocusNode(item);
                                        if (!focusNode.hasFocus) {
                                          focusNode.requestFocus();
                                        }
                                        SystemChannels.textInput
                                            .invokeMethod('TextInput.show');
                                      },
                                      onEditingComplete: () {
                                        _commitSalePriceEdit(item, save: true);
                                        FocusScope.of(context).unfocus();
                                      },
                                      onSubmitted: (val) {
                                        _commitSalePriceEdit(item);
                                      },
                                    ),
                                  ),
                                ),
                                // - button
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Decrease Quantity',
                                  onPressed: () {
                                    if (item.quantity > 0) {
                                      final newQty = item.quantity - 1;
                                      if (newQty >= 0) {
                                        final newLineTotal =
                                            item.unitPrice * newQty;
                                        final newDiscountAmount =
                                            item.discountPercent != null
                                                ? (item.discountPercent! /
                                                        100.0) *
                                                    newLineTotal
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
                                  width:
                                      40, // Reduced from 48 to save more space
                                  child: Focus(
                                    onFocusChange: (hasFocus) {
                                      if (!hasFocus)
                                        _commitQuantityEdit(item, save: true);
                                    },
                                    child: TextField(
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      controller: _getQuantityController(item),
                                      focusNode: _getQuantityFocusNode(item),
                                      // See sale price field above for why this is disabled.
                                      enableInteractiveSelection: false,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true, signed: true),
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        border: UnderlineInputBorder(),
                                        isDense: true,
                                        contentPadding:
                                            EdgeInsets.only(bottom: 0),
                                      ),
                                      onTap: () {
                                        // Select all text on tap for easier editing
                                        final ctrl =
                                            _getQuantityController(item);
                                        ctrl.selection = TextSelection(
                                            baseOffset: 0,
                                            extentOffset: ctrl.text.length);
                                        // See sale price field above: force the keyboard
                                        // open since stale focus state can silently
                                        // suppress it otherwise.
                                        final focusNode =
                                            _getQuantityFocusNode(item);
                                        if (!focusNode.hasFocus) {
                                          focusNode.requestFocus();
                                        }
                                        SystemChannels.textInput
                                            .invokeMethod('TextInput.show');
                                      },
                                      onEditingComplete: () {
                                        _commitQuantityEdit(item, save: true);
                                        FocusScope.of(context).unfocus();
                                      },
                                      onSubmitted: (val) {
                                        _commitQuantityEdit(item, save: true);
                                      },
                                    ),
                                  ),
                                ),
                                // + button
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Increase Quantity',
                                  onPressed: () {
                                    final newQty = item.quantity + 1;
                                    final newLineTotal =
                                        item.unitPrice * newQty;
                                    final newDiscountAmount =
                                        item.discountPercent != null
                                            ? (item.discountPercent! / 100.0) *
                                                newLineTotal
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
                                    padding: const EdgeInsets.only(
                                        left: 4), // Reduced from 8 to 4
                                    child: Text(
                                      '\$${(item.unitPrice * item.quantity - (item.discountAmount ?? 0)).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                      overflow: TextOverflow
                                          .visible, // Changed from softWrap to overflow
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (item.originalEstimateQuantity != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '$_documentSourceLabel Qty: ${formatQuantity(item.originalEstimateQuantity! - item.quantity)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: (item.originalEstimateQuantity! -
                                                item.quantity) <
                                            0
                                        ? Colors.red
                                        : Colors.purple,
                                  ),
                                ),
                              ),
                            // --- Discount and profit row (only show if line item prices are enabled) ---
                            if (_showLineItemPrices)
                              Row(
                                children: [
                                  // --- Purchase Price (click to edit) - only show when profit view is enabled ---
                                  if (_showProfit) ...[
                                    Flexible(
                                      flex: 2,
                                      child: GestureDetector(
                                        onTap: () async {
                                          final ctrl = TextEditingController(
                                              text: (item.purchasePrice ?? 0)
                                                  .toStringAsFixed(2))
                                            ..selection = TextSelection
                                                .fromPosition(TextPosition(
                                                    offset:
                                                        (item.purchasePrice ??
                                                                0)
                                                            .toStringAsFixed(2)
                                                            .length));
                                          final result =
                                              await showDialog<double>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text(
                                                  'Edit Purchase Price'),
                                              content: TextField(
                                                textCapitalization:
                                                    TextCapitalization
                                                        .sentences,
                                                controller: ctrl,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true,
                                                        signed: true),
                                                decoration:
                                                    const InputDecoration(
                                                        labelText:
                                                            'Purchase Price'),
                                                autofocus: true,
                                                onTap: () {
                                                  ctrl.selection =
                                                      TextSelection(
                                                          baseOffset: 0,
                                                          extentOffset:
                                                              ctrl.text.length);
                                                },
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('Cancel'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    final val = double.tryParse(
                                                        ctrl.text);
                                                    if (val != null && val >= 0)
                                                      Navigator.pop(
                                                          context, val);
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
                                            decoration:
                                                TextDecoration.underline,
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
                                          final percentCtrl = TextEditingController(
                                              text: (item.discountPercent ?? 0)
                                                  .toStringAsFixed(1))
                                            ..selection = TextSelection
                                                .fromPosition(TextPosition(
                                                    offset:
                                                        (item.discountPercent ??
                                                                0)
                                                            .toStringAsFixed(1)
                                                            .length));
                                          final dollarCtrl = TextEditingController(
                                              text: (item.discountAmount ?? 0)
                                                  .toStringAsFixed(2))
                                            ..selection = TextSelection
                                                .fromPosition(TextPosition(
                                                    offset:
                                                        (item.discountAmount ??
                                                                0)
                                                            .toStringAsFixed(2)
                                                            .length));
                                          final result = await showDialog<
                                              Map<String, double>>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title:
                                                  const Text('Edit Discount'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextField(
                                                    textCapitalization:
                                                        TextCapitalization
                                                            .sentences,
                                                    controller: percentCtrl,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true,
                                                            signed: true),
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Discount %'),
                                                    autofocus: true,
                                                    onTap: () {
                                                      percentCtrl.selection =
                                                          TextSelection(
                                                              baseOffset: 0,
                                                              extentOffset:
                                                                  percentCtrl
                                                                      .text
                                                                      .length);
                                                    },
                                                  ),
                                                  const SizedBox(height: 16),
                                                  TextField(
                                                    textCapitalization:
                                                        TextCapitalization
                                                            .sentences,
                                                    controller: dollarCtrl,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true,
                                                            signed: true),
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Discount \$'),
                                                    onTap: () {
                                                      dollarCtrl.selection =
                                                          TextSelection(
                                                              baseOffset: 0,
                                                              extentOffset:
                                                                  dollarCtrl
                                                                      .text
                                                                      .length);
                                                    },
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child:
                                                        const Text('Cancel')),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    final percent =
                                                        double.tryParse(
                                                                percentCtrl
                                                                    .text) ??
                                                            0;
                                                    final amt = double.tryParse(
                                                            dollarCtrl.text) ??
                                                        0;
                                                    Navigator.pop(context, {
                                                      'percent': percent,
                                                      'amount': amt
                                                    });
                                                  },
                                                  child: const Text('Save'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (result != null) {
                                            final newItem = item.copyWith(
                                              discountPercent:
                                                  result['percent'],
                                              discountAmount: result['amount'],
                                            );
                                            _updateItemFast(item, newItem);
                                            _saveInProgressEstimate();
                                          }
                                        },
                                        child: Text(
                                          'Discount \$${discountAmount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: discountAmount > 0
                                                ? Colors.blue[800]
                                                : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            decoration:
                                                TextDecoration.underline,
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
                                          final percentCtrl =
                                              TextEditingController(
                                            text: item.purchasePrice != null &&
                                                    item.purchasePrice! > 0
                                                ? (((item.unitPrice -
                                                                item.purchasePrice!) /
                                                            item.purchasePrice!) *
                                                        100)
                                                    .toStringAsFixed(1)
                                                : '0',
                                          );
                                          final dollarCtrl =
                                              TextEditingController(
                                            text: (item.unitPrice -
                                                    (item.purchasePrice ?? 0))
                                                .toStringAsFixed(2),
                                          );
                                          final result = await showDialog<
                                              Map<String, double>>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Edit Profit'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextField(
                                                    textCapitalization:
                                                        TextCapitalization
                                                            .sentences,
                                                    controller: percentCtrl,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true,
                                                            signed: true),
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Profit %'),
                                                    autofocus: true,
                                                    onChanged: (val) {
                                                      final percent =
                                                          double.tryParse(val);
                                                      final base =
                                                          (item.purchasePrice !=
                                                                      null &&
                                                                  item.purchasePrice! >
                                                                      0)
                                                              ? item
                                                                  .purchasePrice!
                                                              : item.unitPrice;
                                                      if (percent != null &&
                                                          base > 0) {
                                                        dollarCtrl
                                                            .text = (base *
                                                                percent /
                                                                100)
                                                            .toStringAsFixed(2);
                                                      }
                                                    },
                                                  ),
                                                  const SizedBox(height: 16),
                                                  TextField(
                                                    textCapitalization:
                                                        TextCapitalization
                                                            .sentences,
                                                    controller: dollarCtrl,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true,
                                                            signed: true),
                                                    decoration:
                                                        const InputDecoration(
                                                            labelText:
                                                                'Profit \$'),
                                                    onChanged: (val) {
                                                      final dollar =
                                                          double.tryParse(val);
                                                      final base =
                                                          (item.purchasePrice !=
                                                                      null &&
                                                                  item.purchasePrice! >
                                                                      0)
                                                              ? item
                                                                  .purchasePrice!
                                                              : item.unitPrice;
                                                      if (dollar != null &&
                                                          base > 0) {
                                                        percentCtrl
                                                            .text = (dollar /
                                                                base *
                                                                100)
                                                            .toStringAsFixed(1);
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, null),
                                                  child: const Text('Cancel'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    final percent =
                                                        double.tryParse(
                                                            percentCtrl.text);
                                                    final dollarAmount =
                                                        double.tryParse(
                                                            dollarCtrl.text);
                                                    double? newUnitPrice;
                                                    final hasPurchasePrice =
                                                        item.purchasePrice !=
                                                                null &&
                                                            item.purchasePrice! >
                                                                0;
                                                    final base =
                                                        hasPurchasePrice
                                                            ? item
                                                                .purchasePrice!
                                                            : item.unitPrice;

                                                    if (percent != null) {
                                                      newUnitPrice = base *
                                                          (1 + percent / 100);
                                                    } else if (dollarAmount !=
                                                        null) {
                                                      newUnitPrice =
                                                          hasPurchasePrice
                                                              ? item.purchasePrice! +
                                                                  dollarAmount
                                                              : item.unitPrice +
                                                                  dollarAmount;
                                                    }

                                                    if (newUnitPrice != null &&
                                                        newUnitPrice.isFinite) {
                                                      Navigator.pop(context, {
                                                        'unitPrice': double
                                                            .parse(newUnitPrice
                                                                .toStringAsFixed(
                                                                    2))
                                                      });
                                                    } else {
                                                      Navigator.pop(
                                                          context, null);
                                                    }
                                                  },
                                                  child: const Text('Save'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (result != null &&
                                              result['unitPrice'] != null) {
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
                                            color: profit < 0
                                                ? Colors.red
                                                : Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            decoration:
                                                TextDecoration.underline,
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
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          if (sectionItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(),
                  if (_showProfit) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Profit',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        Text(
                          '\$${(sectionItems.fold<double>(0, (sum, item) => sum + _lineProfit(item)) - section.extraCost).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (sectionItems.fold<double>(
                                            0,
                                            (sum, item) =>
                                                sum + _lineProfit(item)) -
                                        section.extraCost) <
                                    0
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Internal-only cost (e.g. sub-contractor, travel, etc.)
                    // deducted from this subsection's profit. Never appears
                    // on customer-facing PDFs.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            'Additional Cost (not shown on PDF)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _getSectionExtraCostController(section),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixText: '\$',
                              border: UnderlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                            ),
                            onChanged: (val) {
                              setState(() {
                                section.extraCost =
                                    double.tryParse(val.trim()) ?? 0.0;
                                _hasUnsavedChanges = true;
                              });
                            },
                            onEditingComplete: () {
                              FocusScope.of(context).unfocus();
                              _saveInProgressEstimate();
                            },
                            onSubmitted: (_) => _saveInProgressEstimate(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        '\$${sectionItems.fold<double>(0, (sum, item) => sum + _lineTotal(item)).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_quotedSubsectionTotal(sectionItems) > 0 &&
                      sectionQuoteRemaining != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_documentSourceLabel Remaining',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple[700],
                            ),
                          ),
                          Text(
                            '\$${sectionQuoteRemaining.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: sectionQuoteRemaining < 0
                                  ? Colors.red
                                  : Colors.purple,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Try to find a matching item in the extensive pricebook for PDF receipt import.
  Future<models.PriceBookItem?> _findExtensivePriceBookItemForReceipt(
      String bin, String id, String name) async {
    final extensiveItems = await _loadExtensivePriceBookFromDisk();
    if (extensiveItems.isEmpty) return null;

    final normalizedBin = normalizeCode(bin);
    final normalizedId = normalizeCode(id);
    final normalizedName = normalizeCode(name);

    List<models.PriceBookItem> matches = [];
    if (normalizedBin.isNotEmpty) {
      matches = extensiveItems.where((item) {
        return normalizeCode(item.code) == normalizedBin ||
            normalizeCode(item.barcode ?? '') == normalizedBin;
      }).toList();
    }
    if (matches.isEmpty && normalizedId.isNotEmpty) {
      matches = extensiveItems
          .where((item) => normalizeCode(item.code) == normalizedId)
          .toList();
    }
    if (matches.isEmpty && normalizedName.isNotEmpty) {
      matches = extensiveItems
          .where((item) => normalizeCode(item.name) == normalizedName)
          .toList();
    }

    if (matches.length == 1) return matches.first;
    if (matches.length > 1 && normalizedName.isNotEmpty) {
      final exactNameMatches = matches
          .where((item) => normalizeCode(item.name) == normalizedName)
          .toList();
      if (exactNameMatches.length == 1) return exactNameMatches.first;
    }

    if (matches.isEmpty && normalizedName.isNotEmpty) {
      final searchResults =
          searchPriceBook(extensiveItems, name, maxResults: 10);
      if (searchResults.length == 1) return searchResults.first;
    }

    return null;
  }

// === Helper methods for item management with debounced auto-save ===
}

