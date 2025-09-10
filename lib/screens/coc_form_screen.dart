import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../models/job.dart';
import '../widgets/web_speech_text_field.dart';
import '../services/firestore_service.dart';
import '../services/sync_scheduler.dart';
import '../services/storage_strategy_service.dart';
import '../mixins/document_naming_mixin.dart';

class CocFormScreen extends StatefulWidget {
  final Job job;

  const CocFormScreen({
    super.key,
    required this.job,
  });

  @override
  State<CocFormScreen> createState() => _CocFormScreenState();
}

class _CocFormScreenState extends State<CocFormScreen> with DocumentNamingMixin {
  // Form controllers
  final _referenceNumberController = TextEditingController();
  final _siteAddressController = TextEditingController();
  final _customerNameAddressController = TextEditingController();
  final _userNameController = TextEditingController();
  final _userLicenseController = TextEditingController();
  final _userPhoneController = TextEditingController();
  final _userEmailController = TextEditingController();
  final _supervisedPersonController = TextEditingController();
  final _workDescriptionController = TextEditingController();
  final _insulationResistanceController = TextEditingController();
  final _earthContinuityController = TextEditingController();
  final _bondingController = TextEditingController();
  final _faultLoopController = TextEditingController();
  final _otherController = TextEditingController();
  final _highRiskSpecifyController = TextEditingController();
  final _additionalStandardsSpecifyController = TextEditingController();
  final _rangeDatesController = TextEditingController();
  final _partsSpecifyController = TextEditingController();
  final _manufacturerInstructionsController = TextEditingController();
  final _certifiedDesignController = TextEditingController();
  final _sdocLinkController = TextEditingController();

  // Form state variables
  String _workType = ''; // Addition, Alteration, New Work - No default selection
  String _riskLevel = ''; // Low Risk, General, High Risk - No default selection
  bool _meansCompliancePart1 = true; // Default true
  bool _meansCompliancePart2 = true; // Default true
  bool _additionalStandardsNo = true; // Default No
  bool _additionalStandardsYes = false;
  bool _fittingsSafeYes = true; // Default Yes
  bool _fittingsSafeNo = false;
  String _supplySystem = 'Low Voltage (230/400v)'; // Default
  bool _earthSystemYes = true; // Default Yes
  bool _earthSystemNo = false;
  bool _certificateAll = false; // Default Parts instead
  bool _certificateParts = true; // Default Parts
  bool _manufacturerInstructionsYes = true; // Default Yes
  bool _manufacturerInstructionsNo = false;
  bool _certifiedDesignYes = false; // Default No
  bool _certifiedDesignNo = true;
  bool _sdocYes = true; // Default Yes
  bool _sdocNo = false;
  bool _polarityCorrect = false; // Checkbox for polarity
  bool _testedNo = false; // Default No
  bool _testedYes = true; // Default Yes

  // Trainee management
  String _selectedTrainee = '';
  List<String> _companyTrainees = [];

  // Date variables
  DateTime _signDate = DateTime.now();
  DateTime _connectionDate = DateTime.now();
  
  // Signature path
  String? _signaturePath;
  
  // Field placement setting
  bool _useExpandedInfoSection = true;
  
  // Auto-save functionality
  Timer? _saveDebounce;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Auto-fill reference number (job-based)
    _referenceNumberController.text = widget.job.id;
    
    // Auto-fill site address
    _siteAddressController.text = widget.job.address ?? '';
    
    // Auto-fill customer name and address
    final customerInfo = '${widget.job.customerName ?? ''}\n${widget.job.address ?? ''}';
    _customerNameAddressController.text = customerInfo;
    
    // Auto-fill user information from settings
    _userNameController.text = '${prefs.getString('first_name') ?? ''} ${prefs.getString('last_name') ?? ''}'.trim();
    _userLicenseController.text = prefs.getString('electrical_license') ?? '';
    
    // Load user signature path
    _signaturePath = prefs.getString('signature_path');
    
    // Load field placement setting
    _useExpandedInfoSection = prefs.getBool('use_expanded_info_section') ?? true;
    
    // Auto-fill phone and email
    final email = prefs.getString('personal_email') ?? '';
    final phone = prefs.getString('phone') ?? '';
    _userPhoneController.text = phone;
    _userEmailController.text = email;
    
    // Auto-fill work date range logic (not displayed in current form but kept for potential future use)
    // Default supply type logic (not displayed in current form but kept for potential future use)
    
    // Initialize test results with empty values (no prefilling as requested)
    _insulationResistanceController.text = '';
    _earthContinuityController.text = '';
    _bondingController.text = '';
    _faultLoopController.text = '';
    _otherController.text = '';
    
    // Initialize range dates
    final today = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _rangeDatesController.text = today;
    
    // Initialize default links from settings
    _manufacturerInstructionsController.text = prefs.getString('main_supplier_link') ?? '';
    _certifiedDesignController.text = prefs.getString('default_design_link') ?? '';
    _sdocLinkController.text = prefs.getString('main_supplier_link') ?? '';
    _partsSpecifyController.text = prefs.getString('default_parts_specify') ?? 'Notes in the description';
    
    // Load company trainees
    final trainees = prefs.getStringList('company_trainees') ?? [];
    setState(() {
      _companyTrainees = trainees;
    });
    
    // Load default supervised person
    final defaultSupervised = prefs.getString('default_supervised_person') ?? '';
    if (defaultSupervised.isNotEmpty) {
      _supervisedPersonController.text = defaultSupervised;
      _selectedTrainee = _companyTrainees.contains(defaultSupervised) ? defaultSupervised : 'custom';
    }
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _siteAddressController.dispose();
    _customerNameAddressController.dispose();
    _userNameController.dispose();
    _userLicenseController.dispose();
    _userPhoneController.dispose();
    _userEmailController.dispose();
    _supervisedPersonController.dispose();
    _workDescriptionController.dispose();
    _insulationResistanceController.dispose();
    _earthContinuityController.dispose();
    _bondingController.dispose();
    _faultLoopController.dispose();
    _otherController.dispose();
    _highRiskSpecifyController.dispose();
    _additionalStandardsSpecifyController.dispose();
    _rangeDatesController.dispose();
    _partsSpecifyController.dispose();
    _manufacturerInstructionsController.dispose();
    _certifiedDesignController.dispose();
    _sdocLinkController.dispose();
    _saveDebounce?.cancel();
    super.dispose();
  }

  // COC EWRB Form Field Coordinates (based on A4 page format)
  static const Map<String, Map<String, double>> _cocFieldCoordinates = {
    // Reference/Address Information
    'referenceNumber': {'x': 239, 'y': 46},
    'siteAddress': {'x': 130, 'y': 85, 'width': 400},
    'customerNameAddress': {'x': 129, 'y': 108, 'width': 400},
    'phoneEmail': {'x': 181, 'y': 180, 'width': 551, 'height': 211},
    'supervisedPerson': {'x': 178, 'y': 192.5},
    
    // Work Type checkboxes - Exact coordinates specified by user - DO NOT MOVE
    'workTypeAddition': {'x': 192, 'y': 232},
    'workTypeAlteration': {'x': 307, 'y': 234},
    'workTypeNewWork': {'x': 391, 'y': 233},
    
    // Risk Level checkboxes - Exact coordinates specified by user - DO NOT MOVE
    'riskLevelLow': {'x': 192, 'y': 246},
    'riskLevelGeneral': {'x': 307, 'y': 246},
    'riskLevelHigh': {'x': 391, 'y': 247},
    'highRiskSpecify': {'x': 32, 'y': 257},
    
    // Means of Compliance
    'meansCompliancePart1': {'x': 191, 'y': 270},
    'meansCompliancePart2': {'x': 305, 'y': 271},
    
    // Additional Standards
    'additionalStandardsNo': {'x': 317, 'y': 283},
    'additionalStandardsYes': {'x': 350, 'y': 283},
    'additionalStandardsSpecify': {'x': 418, 'y': 279, 'width': 127, 'height': 12},
    
    // Range of Dates
    'rangeDates': {'x': 310, 'y': 294},
    
    // Fittings Safe to Connect
    'fittingsSafeYes': {'x': 327, 'y': 309},
    'fittingsSafeNo': {'x': 358, 'y': 310},
    
    // Supply System
    'supplySystem': {'x': 161, 'y': 321},
    
    // Earth System
    'earthSystemYes': {'x': 383, 'y': 338},
    'earthSystemNo': {'x': 454, 'y': 338},
    
    // Certificate Relates To
    'certificateAll': {'x': 35, 'y': 366},
    'certificateParts': {'x': 67, 'y': 365},
    'partsSpecify': {'x': 165, 'y': 361},
    
    // Manufacturer Instructions
    'manufacturerInstructionsYes': {'x': 309, 'y': 378},
    'manufacturerInstructionsNo': {'x': 382, 'y': 379},
    'manufacturerInstructionsLink': {'x': 73, 'y': 417},
    
    // Certified Design
    'certifiedDesignYes': {'x': 329, 'y': 438},
    'certifiedDesignNo': {'x': 397, 'y': 438},
    'certifiedDesignLink': {'x': 73, 'y': 475},
    
    // SDoC
    'sdocYes': {'x': 325, 'y': 495},
    'sdocNo': {'x': 395, 'y': 495},
    'sdocLink': {'x': 73, 'y': 510},
    
    // Installation Testing
    'testedNo': {'x': 446, 'y': 554},
    'testedYes': {'x': 485, 'y': 553},
    
    // Test Results
    'polarityCorrect': {'x': 467, 'y': 580},
    'insulationResistance': {'x': 469, 'y': 601},
    'earthContinuity': {'x': 469, 'y': 613},
    'bonding': {'x': 469, 'y': 625},
    'faultLoop': {'x': 469, 'y': 637},
    'otherTests': {'x': 469, 'y': 652},
    
    // Work Description
    'workDescription': {'x': 36, 'y': 580, 'width': 366, 'height': 80},
    
    // User Information
    'userName': {'x': 116, 'y': 760},
    'userName2': {'x': 126, 'y': 146},
    'userLicense': {'x': 448, 'y': 760},
    'userLicense2': {'x': 390, 'y': 146},
    'userSignature1': {'x': 113, 'y': 786},
    'userSignature2': {'x': 122, 'y': 698},
    
    // Dates
    'signDate': {'x': 285, 'y': 787},
    'signDate2': {'x': 374, 'y': 697},
    'connectionDate': {'x': 446, 'y': 787},
  };

  /// Validate required fields and return list of missing field names
  List<String> _validateRequiredFields() {
    final List<String> missingFields = [];
    
    // Check all required text fields (excluding supervised person, manufacturer link, and SDoC link)
    if (_referenceNumberController.text.trim().isEmpty) {
      missingFields.add('Reference Number');
    }
    if (_siteAddressController.text.trim().isEmpty) {
      missingFields.add('Site Address');
    }
    if (_customerNameAddressController.text.trim().isEmpty) {
      missingFields.add('Customer Name & Address');
    }
    if (_userNameController.text.trim().isEmpty) {
      missingFields.add('Licensed Person Name');
    }
    if (_userLicenseController.text.trim().isEmpty) {
      missingFields.add('License Number');
    }
    if (_userPhoneController.text.trim().isEmpty) {
      missingFields.add('Phone Number');
    }
    if (_userEmailController.text.trim().isEmpty) {
      missingFields.add('Email Address');
    }
    if (_rangeDatesController.text.trim().isEmpty) {
      missingFields.add('Range Dates');
    }
    if (_partsSpecifyController.text.trim().isEmpty && _certificateParts) {
      missingFields.add('Parts Specify (required when Parts is selected)');
    }
    if (_certifiedDesignController.text.trim().isEmpty && _certifiedDesignYes) {
      missingFields.add('Certified Design Link (required when Yes is selected)');
    }
    
    // Check test result fields
    if (_insulationResistanceController.text.trim().isEmpty) {
      missingFields.add('Insulation Resistance');
    }
    if (_earthContinuityController.text.trim().isEmpty) {
      missingFields.add('Earth Continuity');
    }
    if (_bondingController.text.trim().isEmpty) {
      missingFields.add('Bonding');
    }
    if (_faultLoopController.text.trim().isEmpty) {
      missingFields.add('Fault Loop');
    }
    
    return missingFields;
  }

  /// Show validation warning dialog to user
  Future<void> _showValidationWarning(List<String> missingFields) async {
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Missing Required Fields'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The following required fields are empty:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...missingFields.map((field) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.red)),
                    Expanded(child: Text(field)),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              const Text(
                'Do you want to generate the PDF anyway?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: The PDF may appear incomplete or unprofessional with missing information.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Generate Anyway'),
          ),
        ],
      ),
    );
    
    // If user didn't choose to continue, we won't generate the PDF
    if (shouldContinue != true) {
      throw Exception('PDF generation cancelled by user');
    }
  }

  Future<void> _generatePdf() async {
    // Validate required fields before generating PDF
    final validationErrors = _validateRequiredFields();
    if (validationErrors.isNotEmpty) {
      await _showValidationWarning(validationErrors);
      return; // Don't generate PDF if user chooses not to continue
    }
    
    try {
      // Load the COC EWRB template from assets
      final ByteData templateData = await rootBundle.load('assets/certificates/COC EWRB NZ.pdf');
      final Uint8List templateBytes = templateData.buffer.asUint8List();

      // Load the existing PDF template using Syncfusion
      final sfpdf.PdfDocument existingDocument = sfpdf.PdfDocument(inputBytes: templateBytes);
      
      // Get the first page to overlay text on
      final sfpdf.PdfPage page = existingDocument.pages[0];
      
      // Get the graphics object to draw on the page
      final sfpdf.PdfGraphics graphics = page.graphics;
      
      // Create fonts for different text sizes
      final sfpdf.PdfFont font10 = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 10);
      final sfpdf.PdfFont font9 = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 9);
      final sfpdf.PdfFont font8 = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 8);
      
      // Create brush for text color
      final sfpdf.PdfBrush blackBrush = sfpdf.PdfSolidBrush(sfpdf.PdfColor(0, 0, 0));
      
      // Add text at specific coordinates based on the EWRB form layout
      // Reference Number (top right)
      graphics.drawString(
        _referenceNumberController.text,
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['referenceNumber']!['x']!, 
                              _cocFieldCoordinates['referenceNumber']!['y']!, 
                              100, 20),
      );
      
      // Site Address
      graphics.drawString(
        _siteAddressController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['siteAddress']!['x']!, 
                              _cocFieldCoordinates['siteAddress']!['y']!, 
                              _cocFieldCoordinates['siteAddress']!['width']!, 
                              60),
        format: sfpdf.PdfStringFormat(lineAlignment: sfpdf.PdfVerticalAlignment.top, wordWrap: sfpdf.PdfWordWrapType.word),
      );
      
      // Customer Name and Address
      graphics.drawString(
        _customerNameAddressController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['customerNameAddress']!['x']!, 
                              _cocFieldCoordinates['customerNameAddress']!['y']!, 
                              _cocFieldCoordinates['customerNameAddress']!['width']!, 
                              60),
        format: sfpdf.PdfStringFormat(lineAlignment: sfpdf.PdfVerticalAlignment.top, wordWrap: sfpdf.PdfWordWrapType.word),
      );
      
      // Work Type Checkboxes - Amazing visible tick marks! (Only draw if selected)
      if (_workType == 'Addition') {
        print('Drawing amazing tick mark for Addition at ${_cocFieldCoordinates['workTypeAddition']!['x']}, ${_cocFieldCoordinates['workTypeAddition']!['y']}');
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['workTypeAddition']!['x']!, _cocFieldCoordinates['workTypeAddition']!['y']!);
      }
      if (_workType == 'Alteration') {
        print('Drawing amazing tick mark for Alteration at ${_cocFieldCoordinates['workTypeAlteration']!['x']}, ${_cocFieldCoordinates['workTypeAlteration']!['y']}');
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['workTypeAlteration']!['x']!, _cocFieldCoordinates['workTypeAlteration']!['y']!);
      }
      if (_workType == 'New Work') {
        print('Drawing amazing tick mark for New Work at ${_cocFieldCoordinates['workTypeNewWork']!['x']}, ${_cocFieldCoordinates['workTypeNewWork']!['y']}');
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['workTypeNewWork']!['x']!, _cocFieldCoordinates['workTypeNewWork']!['y']!);
      }
      
      // Risk Level Checkboxes - Amazing visible tick marks! (Only draw if selected)
      if (_riskLevel == 'Low Risk') {
        print('Drawing amazing tick mark for Low Risk at ${_cocFieldCoordinates['riskLevelLow']!['x']}, ${_cocFieldCoordinates['riskLevelLow']!['y']}');
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['riskLevelLow']!['x']!, _cocFieldCoordinates['riskLevelLow']!['y']!);
      }
      if (_riskLevel == 'General') {
        print('Drawing amazing tick mark for General at ${_cocFieldCoordinates['riskLevelGeneral']!['x']}, ${_cocFieldCoordinates['riskLevelGeneral']!['y']}');
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['riskLevelGeneral']!['x']!, _cocFieldCoordinates['riskLevelGeneral']!['y']!);
      }
      if (_riskLevel == 'High Risk') {
        print('Drawing amazing tick mark for High Risk at ${_cocFieldCoordinates['riskLevelHigh']!['x']}, ${_cocFieldCoordinates['riskLevelHigh']!['y']}');
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['riskLevelHigh']!['x']!, _cocFieldCoordinates['riskLevelHigh']!['y']!);
        
        // High Risk specify text
        if (_highRiskSpecifyController.text.isNotEmpty) {
          graphics.drawString(
            _highRiskSpecifyController.text,
            font9,
            brush: blackBrush,
            bounds: Rect.fromLTWH(_cocFieldCoordinates['highRiskSpecify']!['x']!, 
                                  _cocFieldCoordinates['highRiskSpecify']!['y']!, 
                                  200, 20),
          );
        }
      }
      
      // Supervised Person
      if (_supervisedPersonController.text.isNotEmpty) {
        graphics.drawString(
          _supervisedPersonController.text,
          font9,
          brush: blackBrush,
          bounds: Rect.fromLTWH(_cocFieldCoordinates['supervisedPerson']!['x']!, 
                                _cocFieldCoordinates['supervisedPerson']!['y']!, 
                                200, 20),
        );
      }
      
      // Means of Compliance checkboxes
      if (_meansCompliancePart1) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['meansCompliancePart1']!['x']!, _cocFieldCoordinates['meansCompliancePart1']!['y']!);
      }
      if (_meansCompliancePart2) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['meansCompliancePart2']!['x']!, _cocFieldCoordinates['meansCompliancePart2']!['y']!);
      }
      
      // Additional Standards checkboxes
      if (_additionalStandardsNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['additionalStandardsNo']!['x']!, _cocFieldCoordinates['additionalStandardsNo']!['y']!);
      }
      if (_additionalStandardsYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['additionalStandardsYes']!['x']!, _cocFieldCoordinates['additionalStandardsYes']!['y']!);
        
        // Additional standards specify text
        if (_additionalStandardsSpecifyController.text.isNotEmpty) {
          graphics.drawString(
            _additionalStandardsSpecifyController.text,
            font8,
            brush: blackBrush,
            bounds: Rect.fromLTWH(_cocFieldCoordinates['additionalStandardsSpecify']!['x']!, 
                                  _cocFieldCoordinates['additionalStandardsSpecify']!['y']!, 
                                  _cocFieldCoordinates['additionalStandardsSpecify']!['width']!,
                                  _cocFieldCoordinates['additionalStandardsSpecify']!['height']!),
          );
        }
      }
      
      // Range of Dates
      graphics.drawString(
        _rangeDatesController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['rangeDates']!['x']!, 
                              _cocFieldCoordinates['rangeDates']!['y']!, 
                              150, 20),
      );
      
      // Fittings Safe to Connect
      if (_fittingsSafeYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['fittingsSafeYes']!['x']!, _cocFieldCoordinates['fittingsSafeYes']!['y']!);
      }
      if (_fittingsSafeNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['fittingsSafeNo']!['x']!, _cocFieldCoordinates['fittingsSafeNo']!['y']!);
      }
      
      // Supply System
      graphics.drawString(
        _supplySystem,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['supplySystem']!['x']!, 
                              _cocFieldCoordinates['supplySystem']!['y']!, 
                              200, 20),
      );
      
      // Earth System
      if (_earthSystemYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['earthSystemYes']!['x']!, _cocFieldCoordinates['earthSystemYes']!['y']!);
      }
      if (_earthSystemNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['earthSystemNo']!['x']!, _cocFieldCoordinates['earthSystemNo']!['y']!);
      }
      
      // Certificate Relates To
      if (_certificateAll) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['certificateAll']!['x']!, _cocFieldCoordinates['certificateAll']!['y']!);
      }
      if (_certificateParts) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['certificateParts']!['x']!, _cocFieldCoordinates['certificateParts']!['y']!);
        
        // Parts specify text
        if (_partsSpecifyController.text.isNotEmpty) {
          graphics.drawString(
            _partsSpecifyController.text,
            font9,
            brush: blackBrush,
            bounds: Rect.fromLTWH(_cocFieldCoordinates['partsSpecify']!['x']!, 
                                  _cocFieldCoordinates['partsSpecify']!['y']!, 
                                  200, 20),
          );
        }
      }
      
      // Manufacturer Instructions
      if (_manufacturerInstructionsYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['manufacturerInstructionsYes']!['x']!, _cocFieldCoordinates['manufacturerInstructionsYes']!['y']!);
      }
      if (_manufacturerInstructionsNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['manufacturerInstructionsNo']!['x']!, _cocFieldCoordinates['manufacturerInstructionsNo']!['y']!);
      }
      
      // Manufacturer Instructions Link
      if (_manufacturerInstructionsController.text.isNotEmpty) {
        graphics.drawString(
          _manufacturerInstructionsController.text,
          font8,
          brush: blackBrush,
          bounds: Rect.fromLTWH(_cocFieldCoordinates['manufacturerInstructionsLink']!['x']!, 
                                _cocFieldCoordinates['manufacturerInstructionsLink']!['y']!, 
                                300, 20),
        );
      }
      
      // Certified Design
      if (_certifiedDesignYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['certifiedDesignYes']!['x']!, _cocFieldCoordinates['certifiedDesignYes']!['y']!);
        
        // Certified Design Link
        if (_certifiedDesignController.text.isNotEmpty) {
          graphics.drawString(
            _certifiedDesignController.text,
            font8,
            brush: blackBrush,
            bounds: Rect.fromLTWH(_cocFieldCoordinates['certifiedDesignLink']!['x']!, 
                                  _cocFieldCoordinates['certifiedDesignLink']!['y']!, 
                                  300, 20),
          );
        }
      }
      if (_certifiedDesignNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['certifiedDesignNo']!['x']!, _cocFieldCoordinates['certifiedDesignNo']!['y']!);
      }
      
      // SDoC
      if (_sdocYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['sdocYes']!['x']!, _cocFieldCoordinates['sdocYes']!['y']!);
        
        // SDoC Link
        if (_sdocLinkController.text.isNotEmpty) {
          graphics.drawString(
            _sdocLinkController.text,
            font8,
            brush: blackBrush,
            bounds: Rect.fromLTWH(_cocFieldCoordinates['sdocLink']!['x']!, 
                                  _cocFieldCoordinates['sdocLink']!['y']!, 
                                  300, 20),
          );
        }
      }
      if (_sdocNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['sdocNo']!['x']!, _cocFieldCoordinates['sdocNo']!['y']!);
      }
      
      // Installation Testing
      if (_testedYes) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['testedYes']!['x']!, _cocFieldCoordinates['testedYes']!['y']!);
      }
      if (_testedNo) {
        _drawAmazingTickMark(graphics, _cocFieldCoordinates['testedNo']!['x']!, _cocFieldCoordinates['testedNo']!['y']!);
      }
      
      // Polarity Correct
      if (_polarityCorrect) {
        graphics.drawString(
          'Correct',
          font9,
          brush: blackBrush,
          bounds: Rect.fromLTWH(_cocFieldCoordinates['polarityCorrect']!['x']!, 
                                _cocFieldCoordinates['polarityCorrect']!['y']!, 
                                100, 20),
        );
      }
      
      // Work Description
      graphics.drawString(
        _workDescriptionController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['workDescription']!['x']!, 
                              _cocFieldCoordinates['workDescription']!['y']!, 
                              _cocFieldCoordinates['workDescription']!['width']!, 
                              _cocFieldCoordinates['workDescription']!['height']!),
        format: sfpdf.PdfStringFormat(lineAlignment: sfpdf.PdfVerticalAlignment.top, wordWrap: sfpdf.PdfWordWrapType.word),
      );
      
      // User Information
      graphics.drawString(
        _userNameController.text,
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['userName']!['x']!, 
                              _cocFieldCoordinates['userName']!['y']!, 
                              150, 20),
      );
      
      // Second user name location
      graphics.drawString(
        _userNameController.text,
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['userName2']!['x']!, 
                              _cocFieldCoordinates['userName2']!['y']!, 
                              150, 20),
      );
      
      graphics.drawString(
        _userLicenseController.text,
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['userLicense']!['x']!, 
                              _cocFieldCoordinates['userLicense']!['y']!, 
                              100, 20),
      );
      
      // Second user license location
      graphics.drawString(
        _userLicenseController.text,
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['userLicense2']!['x']!, 
                              _cocFieldCoordinates['userLicense2']!['y']!, 
                              100, 20),
      );
      
      // User Signatures at both locations
      // Use actual signature image if available, otherwise fallback to name
      await _drawUserSignature(graphics, _cocFieldCoordinates['userSignature1']!['x']!, _cocFieldCoordinates['userSignature1']!['y']!);
      
      await _drawUserSignature(graphics, _cocFieldCoordinates['userSignature2']!['x']!, _cocFieldCoordinates['userSignature2']!['y']!);
      
      // Test Results with proper unit formatting
      graphics.drawString(
        _insulationResistanceController.text.isNotEmpty 
          ? '${_insulationResistanceController.text} MΩ' 
          : '',
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['insulationResistance']!['x']!, 
                              _cocFieldCoordinates['insulationResistance']!['y']!, 
                              100, 20),
      );
      
      graphics.drawString(
        _earthContinuityController.text.isNotEmpty 
          ? '${_earthContinuityController.text} Ω' 
          : '',
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['earthContinuity']!['x']!, 
                              _cocFieldCoordinates['earthContinuity']!['y']!, 
                              100, 20),
      );
      
      graphics.drawString(
        _bondingController.text.isNotEmpty 
          ? '${_bondingController.text} Ω' 
          : '',
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['bonding']!['x']!, 
                              _cocFieldCoordinates['bonding']!['y']!, 
                              100, 20),
      );
      
      graphics.drawString(
        _faultLoopController.text.isNotEmpty 
          ? '${_faultLoopController.text} Ω' 
          : '',
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['faultLoop']!['x']!, 
                              _cocFieldCoordinates['faultLoop']!['y']!, 
                              100, 20),
      );
      
      graphics.drawString(
        _otherController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['otherTests']!['x']!, 
                              _cocFieldCoordinates['otherTests']!['y']!, 
                              100, 20),
      );
      
      // Dates
      graphics.drawString(
        DateFormat('dd/MM/yyyy').format(_signDate),
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['signDate']!['x']!, 
                              _cocFieldCoordinates['signDate']!['y']!, 
                              100, 20),
      );
      
      // Second sign date location
      graphics.drawString(
        DateFormat('dd/MM/yyyy').format(_signDate),
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['signDate2']!['x']!, 
                              _cocFieldCoordinates['signDate2']!['y']!, 
                              100, 20),
      );
      
      graphics.drawString(
        DateFormat('dd/MM/yyyy').format(_connectionDate),
        font10,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['connectionDate']!['x']!, 
                              _cocFieldCoordinates['connectionDate']!['y']!, 
                              100, 20),
      );
      
      // Contact Information
      final phoneEmailText = '${_userPhoneController.text} ${_userEmailController.text}';
      graphics.drawString(
        phoneEmailText,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(_cocFieldCoordinates['phoneEmail']!['x']!, 
                              _cocFieldCoordinates['phoneEmail']!['y']!, 
                              _cocFieldCoordinates['phoneEmail']!['width']!, 
                              _cocFieldCoordinates['phoneEmail']!['height']!),
        format: sfpdf.PdfStringFormat(lineAlignment: sfpdf.PdfVerticalAlignment.top, wordWrap: sfpdf.PdfWordWrapType.word),
      );

      // Generate standardized filename using the naming service
      final fileName = generateCocName(widget.job);

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      
      // Save the modified PDF
      final List<int> bytes = await existingDocument.save();
      await file.writeAsBytes(bytes);
      
      // Dispose the document
      existingDocument.dispose();

      // Add PDF to job attachments
      widget.job.attachments ??= [];
      if (!widget.job.attachments!.contains(file.path)) {
        widget.job.attachments!.add(file.path);
      }

      // Save the job to persist the attachment
      await _saveJob();

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('COC EWRB PDF generated and saved to job attachments!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Wait a moment for the user to see the success message
        await Future.delayed(const Duration(milliseconds: 500));

        // Automatically return to job details screen
        Navigator.pop(context, true); // Pass true to indicate PDF was generated
      }
    } catch (e) {
      if (mounted) {
        // Don't show error message if user cancelled PDF generation
        if (e.toString().contains('PDF generation cancelled by user')) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating COC EWRB PDF: $e')),
        );
      }
    }
  }

  // Method to show settings dialog for defaults
  Future<void> _showDefaultSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('COC Default Settings'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Set default values for COC form fields:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              // Supervised Person Default
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Default Supervised Person',
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: prefs.getString('default_supervised_person') ?? ''),
                onChanged: (value) => prefs.setString('default_supervised_person', value),
              ),
              const SizedBox(height: 16),
              
              // Default Risk Level
              DropdownButtonFormField<String>(
                initialValue: prefs.getString('default_risk_level') ?? 'General',
                decoration: const InputDecoration(
                  labelText: 'Default Risk Level',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Low Risk', child: Text('Low Risk')),
                  DropdownMenuItem(value: 'General', child: Text('General')),
                  DropdownMenuItem(value: 'High Risk', child: Text('High Risk')),
                ],
                onChanged: (value) => prefs.setString('default_risk_level', value!),
              ),
              const SizedBox(height: 16),
              
              // Means of Compliance defaults
              CheckboxListTile(
                title: const Text('Part 1 Default'),
                value: prefs.getBool('default_part1') ?? true,
                onChanged: (value) => prefs.setBool('default_part1', value!),
              ),
              
              CheckboxListTile(
                title: const Text('Part 2 Default'),
                value: prefs.getBool('default_part2') ?? false,
                onChanged: (value) => prefs.setBool('default_part2', value!),
              ),
              
              // Additional Standards Default
              CheckboxListTile(
                title: const Text('Additional Standards - No (Default)'),
                value: prefs.getBool('default_additional_standards_no') ?? true,
                onChanged: (value) => prefs.setBool('default_additional_standards_no', value!),
              ),
              
              // Fittings Safe Default
              CheckboxListTile(
                title: const Text('Fittings Safe to Connect - Yes (Default)'),
                value: prefs.getBool('default_fittings_safe') ?? true,
                onChanged: (value) => prefs.setBool('default_fittings_safe', value!),
              ),
              
              // Supply System Default
              DropdownButtonFormField<String>(
                initialValue: prefs.getString('default_supply_system') ?? 'Low Voltage (230/400v)',
                decoration: const InputDecoration(
                  labelText: 'Default Supply System',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Low Voltage (230/400v)', child: Text('Low Voltage (230/400v)')),
                  DropdownMenuItem(value: 'Medium Voltage', child: Text('Medium Voltage')),
                  DropdownMenuItem(value: 'High Voltage', child: Text('High Voltage')),
                ],
                onChanged: (value) => prefs.setString('default_supply_system', value!),
              ),
              const SizedBox(height: 16),
              
              // Earth System Default
              CheckboxListTile(
                title: const Text('Earth System Correctly Rated - Yes (Default)'),
                value: prefs.getBool('default_earth_system') ?? true,
                onChanged: (value) => prefs.setBool('default_earth_system', value!),
              ),
              
              // Certificate Relates To Default
              CheckboxListTile(
                title: const Text('Certificate Relates to Parts (Default)'),
                value: prefs.getBool('default_certificate_parts') ?? true,
                onChanged: (value) => prefs.setBool('default_certificate_parts', value!),
              ),
              
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Default Parts Specify Text',
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: prefs.getString('default_parts_specify') ?? 'Notes in the description'),
                onChanged: (value) => prefs.setString('default_parts_specify', value),
              ),
              const SizedBox(height: 16),
              
              // Manufacturer Instructions Default
              CheckboxListTile(
                title: const Text('Work Relies on Manufacturer Instructions - Yes (Default)'),
                value: prefs.getBool('default_manufacturer_instructions') ?? true,
                onChanged: (value) => prefs.setBool('default_manufacturer_instructions', value!),
              ),
              
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Default Main Supplier URL (for SDoC & Manufacturer Instructions)',
                  border: OutlineInputBorder(),
                  helperText: 'This URL will be used for both SDoC and Manufacturer Instructions',
                ),
                controller: TextEditingController(text: prefs.getString('main_supplier_link') ?? ''),
                onChanged: (value) => prefs.setString('main_supplier_link', value),
              ),
              const SizedBox(height: 16),
              
              // Certified Design Default
              CheckboxListTile(
                title: const Text('Certified Design - No (Default)'),
                value: prefs.getBool('default_certified_design_no') ?? true,
                onChanged: (value) => prefs.setBool('default_certified_design_no', value!),
              ),
              
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Default Design Link',
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: prefs.getString('default_design_link') ?? ''),
                onChanged: (value) => prefs.setString('default_design_link', value),
              ),
              const SizedBox(height: 16),
              
              // SDoC Default
              CheckboxListTile(
                title: const Text('Relies on SDoC - No (Default)'),
                value: prefs.getBool('default_sdoc_no') ?? true,
                onChanged: (value) => prefs.setBool('default_sdoc_no', value!),
              ),
              
              // Installation Testing Default
              CheckboxListTile(
                title: const Text('Installation Satisfactorily Tested - Yes (Default)'),
                value: prefs.getBool('default_tested_yes') ?? true,
                onChanged: (value) => prefs.setBool('default_tested_yes', value!),
              ),
              
              const SizedBox(height: 24),
              const Divider(),
              const Text('Field Layout Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              
              // Field placement setting
              CheckboxListTile(
                title: const Text('Show detailed fields in Expanded Information area'),
                subtitle: const Text('When checked, Reference Number, Site Address, User details, Customer Name & Address, and Supervised Person will appear in the expandable section'),
                value: prefs.getBool('use_expanded_info_section') ?? true,
                onChanged: (value) => prefs.setBool('use_expanded_info_section', value!),
              ),
              
              const SizedBox(height: 16),
              const Text('Note: These defaults will be pre-filled but can be changed in each form.', 
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
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
              Navigator.pop(context);
              // Reload form with new defaults and trigger rebuild
              setState(() {
                _initializeForm();
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Save job method with hybrid storage integration
  Future<void> _saveJob() async {
    try {
      // Save to local file for backward compatibility
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/job_${widget.job.id}.json');
      await file.writeAsString(jsonEncode(widget.job.toJson()));
      
      // Save to cloud using hybrid storage system
      await FirestoreService.saveJob(widget.job);
      
      // Trigger sync through scheduler for optimal cloud sync
      await SyncScheduler.syncNow(DataType.jobs);
      
      setState(() {
        _hasUnsavedChanges = false;
      });
      
    } catch (e) {
      print('Error saving job: $e');
      // Still show success for local save even if cloud fails
    }
  }

  /// Debounced auto-save to avoid frequent saves (30 second delay)
  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 30), () {
      _saveJob();
    });
  }

  /// Mark as having unsaved changes and trigger auto-save
  void _markDirtyAndAutoSave() {
    setState(() {
      _hasUnsavedChanges = true;
    });
    _debouncedSave();
  }

  // Trainee management method
  Future<void> _showTraineeManagement() async {
    final prefs = await SharedPreferences.getInstance();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Company Trainees'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current Company Trainees:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              if (_companyTrainees.isEmpty)
                const Text('No trainees added yet.', style: TextStyle(fontStyle: FontStyle.italic)),
              
              ..._companyTrainees.map((trainee) => ListTile(
                title: Text(trainee),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _companyTrainees.remove(trainee);
                      prefs.setStringList('company_trainees', _companyTrainees);
                    });
                    Navigator.pop(context);
                    _showTraineeManagement(); // Refresh dialog
                  },
                ),
              )),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              const Text('Add New Trainee:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Trainee Name and Registration',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., John Smith - REG123456',
                ),
                onFieldSubmitted: (value) {
                  if (value.trim().isNotEmpty && !_companyTrainees.contains(value.trim())) {
                    setState(() {
                      _companyTrainees.add(value.trim());
                      prefs.setStringList('company_trainees', _companyTrainees);
                    });
                    Navigator.pop(context);
                    _showTraineeManagement(); // Refresh dialog
                  }
                },
              ),
              
              const SizedBox(height: 16),
              const Text('Press Enter to add trainee', 
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isSignDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isSignDate ? _signDate : _connectionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isSignDate) {
          _signDate = picked;
        } else {
          _connectionDate = picked;
        }
      });
    }
  }

  Widget _buildWorkTypeGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Work Type', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Radio<String>(
                    value: 'Addition',
                    groupValue: _workType,
                    onChanged: (value) {
                      setState(() => _workType = value!);
                      _markDirtyAndAutoSave();
                    },
                  ),
                  const Text('Addition', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Radio<String>(
                    value: 'Alteration',
                    groupValue: _workType,
                    onChanged: (value) => setState(() => _workType = value!),
                  ),
                  const Text('Alteration', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Radio<String>(
                    value: 'New Work',
                    groupValue: _workType,
                    onChanged: (value) => setState(() => _workType = value!),
                  ),
                  const Text('New Work', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRiskLevelGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Risk Level', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Radio<String>(
                    value: 'Low Risk',
                    groupValue: _riskLevel,
                    onChanged: (value) => setState(() => _riskLevel = value!),
                  ),
                  const Text('Low Risk', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Radio<String>(
                    value: 'General',
                    groupValue: _riskLevel,
                    onChanged: (value) => setState(() => _riskLevel = value!),
                  ),
                  const Text('General', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Radio<String>(
                    value: 'High Risk',
                    groupValue: _riskLevel,
                    onChanged: (value) => setState(() => _riskLevel = value!),
                  ),
                  const Text('High Risk', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate of Compliance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showDefaultSettings,
            tooltip: 'Default Settings',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('COC form saved')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _generatePdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Conditionally show Expanded Information section or detailed fields in main flow
            if (_useExpandedInfoSection) ...[
              // Expanded Information section
              ExpansionTile(
                title: const Text('Expanded Information', style: TextStyle(fontWeight: FontWeight.bold)),
                initiallyExpanded: false,
                children: [
                  const SizedBox(height: 8),
                  _buildDetailedFields(),
                  
                  // Signature placeholder
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('Signature Area\n(Auto-filled from settings)', 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              // Show detailed fields in main flow
              _buildDetailedFields(),
            ],

            // Work Type Group
            _buildWorkTypeGroup(),
            const SizedBox(height: 16),

            // Risk Level Group
            _buildRiskLevelGroup(),
            const SizedBox(height: 16),

            // High Risk Specify (conditional)
            if (_riskLevel == 'High Risk') ...[
              TextField(
                controller: _highRiskSpecifyController,
                decoration: const InputDecoration(
                  labelText: 'Specify High Risk Details',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Means of Compliance
            _buildMeansComplianceGroup(),
            const SizedBox(height: 16),

            // Additional Standards
            _buildAdditionalStandardsGroup(),
            const SizedBox(height: 16),

            // Range of Dates
            TextField(
              controller: _rangeDatesController,
              decoration: const InputDecoration(
                labelText: 'Range of Dates',
                border: OutlineInputBorder(),
                hintText: 'Auto-filled with job dates',
              ),
            ),
            const SizedBox(height: 16),

            // Fittings Safe to Connect
            _buildFittingsSafeGroup(),
            const SizedBox(height: 16),

            // Supply System
            _buildSupplySystemDropdown(),
            const SizedBox(height: 16),

            // Earth System
            _buildEarthSystemGroup(),
            const SizedBox(height: 16),

            // Certificate Relates To
            _buildCertificateRelatesGroup(),
            const SizedBox(height: 16),

            // Manufacturer Instructions
            _buildManufacturerInstructionsGroup(),
            const SizedBox(height: 16),

            // Certified Design
            _buildCertifiedDesignGroup(),
            const SizedBox(height: 16),

            // SDoC
            _buildSdocGroup(),
            const SizedBox(height: 16),

            // Installation Testing
            _buildInstallationTestingGroup(),
            const SizedBox(height: 24),

            // Description of Work with Voice Text
            const Text('Description of Work', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            WebSpeechTextField(
              controller: _workDescriptionController,
              labelText: 'Description of Work',
              hintText: 'Describe the work carried out in detail',
              maxLines: 5,
              continuousListening: true,
            ),
            const SizedBox(height: 24),

            // Test Results Section
            const Text('Test Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            // Polarity Checkbox
            Row(
              children: [
                Checkbox(
                  value: _polarityCorrect,
                  onChanged: (value) => setState(() => _polarityCorrect = value!),
                ),
                const Text('Polarity Correct'),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _insulationResistanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Insulation Resistance (MΩ)',
                      hintText: 'Enter value',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('MΩ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _earthContinuityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Earth Continuity (Ω)',
                      hintText: 'Enter value',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Ω', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _bondingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bonding (Ω)',
                      hintText: 'Enter value',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Ω', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _faultLoopController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Fault Loop (Ω)',
                      hintText: 'Enter value',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Ω', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _otherController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Other',
                hintText: 'P = Pass, F = Fail, N/A = Not Applicable',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z/\s]')),
              ],
            ),
            const SizedBox(height: 24),

            // Date Section
            const Text('Dates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            // Sign Date
            ListTile(
              title: const Text('Sign Date'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_signDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, true),
            ),
            
            // Connection Date
            ListTile(
              title: const Text('Connection Date'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_connectionDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, false),
            ),
            const SizedBox(height: 32),

            // Generate PDF Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generatePdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Generate COC PDF'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),

            // Extra bottom padding for better mobile accessibility
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  /// Build detailed fields that can be shown in expanded section or main flow
  Widget _buildDetailedFields() {
    return Column(
      children: [
        // Reference Number
        TextField(
          controller: _referenceNumberController,
          decoration: const InputDecoration(
            labelText: 'Reference Number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Site Address
        TextField(
          controller: _siteAddressController,
          decoration: const InputDecoration(
            labelText: 'Site Address',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // User Name
        TextField(
          controller: _userNameController,
          decoration: const InputDecoration(
            labelText: 'User Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // User License
        TextField(
          controller: _userLicenseController,
          decoration: const InputDecoration(
            labelText: 'User License',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // User Phone and Email
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _userPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _userEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Customer Name and Address (if different to site address)
        TextField(
          controller: _customerNameAddressController,
          decoration: const InputDecoration(
            labelText: 'Customer Name and Address (if different to site address)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        // Supervised Person
        _buildSupervisedPersonField(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSupervisedPersonField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Name and Registration Number of Person Supervised', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedTrainee,
                decoration: const InputDecoration(
                  labelText: 'Select Company Trainee',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Select Trainee')),
                  ..._companyTrainees.map((trainee) => 
                    DropdownMenuItem(value: trainee, child: Text(trainee))),
                  const DropdownMenuItem(value: 'custom', child: Text('Custom Entry')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTrainee = value!;
                    if (value != 'custom' && value.isNotEmpty) {
                      _supervisedPersonController.text = value;
                    } else if (value == 'custom') {
                      _supervisedPersonController.clear();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _showTraineeManagement,
                icon: const Icon(Icons.people, size: 18),
                label: const Text('Manage'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[100],
                  foregroundColor: Colors.blue[800],
                ),
              ),
            ),
          ],
        ),
        if (_selectedTrainee == 'custom' || _selectedTrainee == '') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _supervisedPersonController,
            decoration: const InputDecoration(
              labelText: 'Custom Supervised Person Details',
              border: OutlineInputBorder(),
              hintText: 'Enter name and registration number',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMeansComplianceGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Means of Compliance', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _meansCompliancePart1,
                    onChanged: (value) => setState(() => _meansCompliancePart1 = value!),
                  ),
                  const Text('Part 1', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _meansCompliancePart2,
                    onChanged: (value) => setState(() => _meansCompliancePart2 = value!),
                  ),
                  const Text('Part 2', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdditionalStandardsGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Additional Standards', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _additionalStandardsNo,
                    onChanged: (value) => setState(() {
                      _additionalStandardsNo = value!;
                      if (value) _additionalStandardsYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _additionalStandardsYes,
                    onChanged: (value) => setState(() {
                      _additionalStandardsYes = value!;
                      if (value) _additionalStandardsNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        if (_additionalStandardsYes) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _additionalStandardsSpecifyController,
            decoration: const InputDecoration(
              labelText: 'Specify',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFittingsSafeGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fittings are safe to connect', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _fittingsSafeYes,
                    onChanged: (value) => setState(() {
                      _fittingsSafeYes = value!;
                      if (value) _fittingsSafeNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _fittingsSafeNo,
                    onChanged: (value) => setState(() {
                      _fittingsSafeNo = value!;
                      if (value) _fittingsSafeYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupplySystemDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Supply System', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _supplySystem,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Low Voltage (230/400v)', child: Text('Low Voltage (230/400v)')),
            DropdownMenuItem(value: 'Medium Voltage', child: Text('Medium Voltage')),
            DropdownMenuItem(value: 'High Voltage', child: Text('High Voltage')),
          ],
          onChanged: (value) => setState(() => _supplySystem = value!),
        ),
      ],
    );
  }

  Widget _buildEarthSystemGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Earth System is correctly rated', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _earthSystemYes,
                    onChanged: (value) => setState(() {
                      _earthSystemYes = value!;
                      if (value) _earthSystemNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _earthSystemNo,
                    onChanged: (value) => setState(() {
                      _earthSystemNo = value!;
                      if (value) _earthSystemYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCertificateRelatesGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Certificate relates to as safe to connect', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _certificateAll,
                    onChanged: (value) => setState(() {
                      _certificateAll = value!;
                      if (value) _certificateParts = false;
                    }),
                  ),
                  const Text('All', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _certificateParts,
                    onChanged: (value) => setState(() {
                      _certificateParts = value!;
                      if (value) _certificateAll = false;
                    }),
                  ),
                  const Text('Parts', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        if (_certificateParts) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _partsSpecifyController,
            decoration: const InputDecoration(
              labelText: 'Specify',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildManufacturerInstructionsGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Work relies on manufacturer instructions', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _manufacturerInstructionsYes,
                    onChanged: (value) => setState(() {
                      _manufacturerInstructionsYes = value!;
                      if (value) _manufacturerInstructionsNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _manufacturerInstructionsNo,
                    onChanged: (value) => setState(() {
                      _manufacturerInstructionsNo = value!;
                      if (value) _manufacturerInstructionsYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _manufacturerInstructionsController,
          decoration: const InputDecoration(
            labelText: 'Manufacturer Instructions Link',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildCertifiedDesignGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Certified Design', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _certifiedDesignYes,
                    onChanged: (value) => setState(() {
                      _certifiedDesignYes = value!;
                      if (value) _certifiedDesignNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _certifiedDesignNo,
                    onChanged: (value) => setState(() {
                      _certifiedDesignNo = value!;
                      if (value) _certifiedDesignYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        if (_certifiedDesignYes) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _certifiedDesignController,
            decoration: const InputDecoration(
              labelText: 'Identify/Link',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSdocGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Relies on SDoC', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _sdocYes,
                    onChanged: (value) => setState(() {
                      _sdocYes = value!;
                      if (value) _sdocNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _sdocNo,
                    onChanged: (value) => setState(() {
                      _sdocNo = value!;
                      if (value) _sdocYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        if (_sdocYes) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _sdocLinkController,
            decoration: const InputDecoration(
              labelText: 'Link',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInstallationTestingGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Installation satisfactorily tested in accordance with Electrical Regs', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _testedYes,
                    onChanged: (value) => setState(() {
                      _testedYes = value!;
                      if (value) _testedNo = false;
                    }),
                  ),
                  const Text('Yes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Checkbox(
                    value: _testedNo,
                    onChanged: (value) => setState(() {
                      _testedNo = value!;
                      if (value) _testedYes = false;
                    }),
                  ),
                  const Text('No', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Draws an amazing, highly visible X mark at the exact specified coordinates
  void _drawAmazingTickMark(sfpdf.PdfGraphics graphics, double x, double y) {
    // Create thick pens for bold, highly visible X mark
    final extraBoldPen = sfpdf.PdfPen(sfpdf.PdfColor(0, 0, 0), width: 4);
    final boldPen = sfpdf.PdfPen(sfpdf.PdfColor(0, 0, 0), width: 3);
    
    // Draw main X lines with extra thickness
    graphics.drawLine(
      extraBoldPen,
      Offset(x, y),           // Top-left to bottom-right
      Offset(x + 10, y + 10)
    );
    graphics.drawLine(
      extraBoldPen,
      Offset(x + 10, y),      // Top-right to bottom-left  
      Offset(x, y + 10)
    );
    
    // Add overlapping lines for maximum visibility
    graphics.drawLine(
      boldPen,
      Offset(x + 0.5, y),     // Slightly offset for extra thickness
      Offset(x + 10.5, y + 10)
    );
    graphics.drawLine(
      boldPen,
      Offset(x + 10.5, y),    // Slightly offset for extra thickness
      Offset(x + 0.5, y + 10)
    );
  }

  /// Draw user signature at specified coordinates
  /// Uses actual signature image if available, otherwise falls back to user name
  Future<void> _drawUserSignature(sfpdf.PdfGraphics graphics, double x, double y) async {
    final font10 = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 10);
    final blackBrush = sfpdf.PdfSolidBrush(sfpdf.PdfColor(0, 0, 0));
    
    if (_signaturePath != null && _signaturePath!.isNotEmpty) {
      try {
        // Load signature image
        final signatureFile = File(_signaturePath!);
        if (await signatureFile.exists()) {
          final signatureBytes = await signatureFile.readAsBytes();
          final signatureImage = sfpdf.PdfBitmap(signatureBytes);
          
          // Draw signature image with appropriate size
          graphics.drawImage(
            signatureImage,
            Rect.fromLTWH(x, y - 15, 120, 30) // Adjusted size and position for signature
          );
          return;
        }
      } catch (e) {
        print('Error loading signature image: $e');
        // Fall through to text fallback
      }
    }
    
    // Fallback to drawing user name as text signature
    graphics.drawString(
      _userNameController.text,
      font10,
      brush: blackBrush,
      bounds: Rect.fromLTWH(x, y, 150, 20),
    );
  }
}
