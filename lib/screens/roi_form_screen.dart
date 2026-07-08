import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/job.dart';
import '../widgets/web_speech_text_field.dart';
import '../services/firestore_service.dart';
import '../services/sync_scheduler.dart';
import '../services/storage_strategy_service.dart';
import '../mixins/document_naming_mixin.dart';

class RoiFormScreen extends StatefulWidget {
  final Job job;

  const RoiFormScreen({
    super.key,
    required this.job,
  });

  @override
  State<RoiFormScreen> createState() => _RoiFormScreenState();
}

class _RoiFormScreenState extends State<RoiFormScreen> with DocumentNamingMixin {
  // ROI EWRB Form Field Coordinates (based on A4 page format)
  static const Map<String, Map<String, double>> _roiFieldCoordinates = {
    // Reference Number
    'referenceNumber': {'x': 266, 'y': 72, 'width': 200, 'height': 17},
    
    // Inspector Information
    'inspectorName': {'x': 123, 'y': 115, 'width': 250, 'height': 20},
    'inspectorEmail': {'x': 123, 'y': 135, 'width': 250, 'height': 20},
    'inspectorLicense': {'x': 421, 'y': 115, 'width': 150, 'height': 20},
    'inspectorPhone': {'x': 421, 'y': 133, 'width': 150, 'height': 20},
    
    // Location Address (separate field, not auto-filled)
    'locationAddress': {'x': 421, 'y': 153, 'width': 150, 'height': 40},
    
    // Property Type Checkboxes
    'domestic': {'x': 117, 'y': 195},
    'nonDomesticAccommodation': {'x': 199, 'y': 196},
    'industrial': {'x': 347, 'y': 196},
    'commercial': {'x': 452, 'y': 196},
    'educational': {'x': 117, 'y': 212},
    'healthCare': {'x': 199, 'y': 213},
    'miscellaneous': {'x': 348, 'y': 213},
    
    // CoC Details
    'cocDetails': {'x': 123, 'y': 204, 'width': 300, 'height': 20},
    
    // Electrical Worker 2
    'electricalWorker2Name': {'x': 123, 'y': 265, 'width': 250, 'height': 20},
    'electricalWorker2License': {'x': 420, 'y': 265, 'width': 150, 'height': 20},
    
    // CoC Attached
    'cocAttached': {'x': 450, 'y': 284},
    
    // Text Areas
    'whatWasInspected': {'x': 33, 'y': 350, 'width': 524, 'height': 78},
    'regulationsDesign': {'x': 32, 'y': 444, 'width': 524, 'height': 79},
    'resultsOfInspection': {'x': 33, 'y': 540, 'width': 523, 'height': 81},
    
    // High Risk Category Checkboxes
    'notToAsNzs3000': {'x': 33, 'y': 650},
    'highVoltage': {'x': 33, 'y': 665},
    'mainParallelGeneration': {'x': 33, 'y': 679},
    'photovoltaicSystem': {'x': 198, 'y': 648},
    'hazardousArea': {'x': 198, 'y': 665},
    'animalStunning': {'x': 197, 'y': 679},
    'electricalMedicalArea': {'x': 363, 'y': 649},
    'mainWork': {'x': 363, 'y': 666},
    'other': {'x': 34, 'y': 696},
    'otherSpecify': {'x': 147, 'y': 694, 'width': 409, 'height': 15},
    
    // Signature and Date
    'signature': {'x': 95, 'y': 767, 'width': 120, 'height': 40},
    'signDate': {'x': 421, 'y': 768, 'width': 100, 'height': 20},
  };

  // Form controllers - comprehensive for ROI
  final _referenceNumberController = TextEditingController();
  final _inspectorNameController = TextEditingController();
  final _inspectorEmailController = TextEditingController();
  final _inspectorLicenseController = TextEditingController();
  final _inspectorPhoneController = TextEditingController();
  final _locationAddressController = TextEditingController();
  final _cocDetailsController = TextEditingController();
  final _electricalWorker2NameController = TextEditingController();
  final _electricalWorker2LicenseController = TextEditingController();
  final _electricalWorker2EmailController = TextEditingController(); // Not on form but for emailing
  final _whatWasInspectedController = TextEditingController();
  final _regulationsDesignController = TextEditingController();
  final _resultsOfInspectionController = TextEditingController();
  final _otherSpecifyController = TextEditingController();

  // Form state variables - comprehensive for ROI
  DateTime _signDate = DateTime.now();
  
  // Property Type checkboxes (only one can be selected)
  String _propertyType = '';
  
  // CoC Attached checkbox
  bool _cocAttached = false;
  
  // High Risk Category checkboxes (multiple can be selected)
  bool _notToAsNzs3000 = false;
  bool _highVoltage = false;
  bool _mainParallelGeneration = false;
  bool _photovoltaicSystem = false;
  bool _hazardousArea = false;
  bool _animalStunning = false;
  bool _electricalMedicalArea = false;
  bool _mainWork = false;
  bool _other = false;
  
  // Licensed workers list and search
  List<Map<String, String>> _licensedWorkers = [];
  String _selectedWorkerName = '';
  
  // Signature path
  String? _signaturePath;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Auto-fill user information from settings
    final firstName = prefs.getString('first_name') ?? '';
    final lastName = prefs.getString('last_name') ?? '';
    final licenseNumber = prefs.getString('electrical_license') ?? '';
    final emailAddress = prefs.getString('personal_email') ?? '';
    final phoneNumber = prefs.getString('phone_number') ?? '';

    // Set default values
    setState(() {
      _inspectorNameController.text = '$firstName $lastName'.trim();
      _inspectorLicenseController.text = licenseNumber;
      _inspectorEmailController.text = emailAddress;
      _inspectorPhoneController.text = phoneNumber;
      
      // Generate reference number
      final jobId = widget.job.id;
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      _referenceNumberController.text = 'ROI-$jobId-$dateStr';
    });
    
    // Load user signature path
    _signaturePath = prefs.getString('signature_path');
    
    // Load licensed workers from settings
    await _loadLicensedWorkers();
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _inspectorNameController.dispose();
    _inspectorEmailController.dispose();
    _inspectorLicenseController.dispose();
    _inspectorPhoneController.dispose();
    _locationAddressController.dispose();
    _cocDetailsController.dispose();
    _electricalWorker2NameController.dispose();
    _electricalWorker2LicenseController.dispose();
    _electricalWorker2EmailController.dispose();
    _whatWasInspectedController.dispose();
    _regulationsDesignController.dispose();
    _resultsOfInspectionController.dispose();
    _otherSpecifyController.dispose();
    super.dispose();
  }

  Future<void> _loadLicensedWorkers() async {
    // Load licensed workers from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final workersJson = prefs.getStringList('licensed_workers') ?? [];
    
    setState(() {
      _licensedWorkers = workersJson.map((jsonStr) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        return {
          'name': data['name']?.toString() ?? '',
          'license': data['license']?.toString() ?? '',
          'email': data['email']?.toString() ?? '',
        };
      }).toList();
    });
  }

  Future<void> _saveLicensedWorker(String name, String license, String email) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if worker already exists
    final existingWorker = _licensedWorkers.firstWhere(
      (worker) => worker['license'] == license,
      orElse: () => {},
    );
    
    if (existingWorker.isEmpty) {
      // Add new worker
      final newWorker = {
        'name': name,
        'license': license,
        'email': email,
      };
      
      _licensedWorkers.add(newWorker);
      
      // Save to SharedPreferences
      final workersJson = _licensedWorkers.map((worker) => jsonEncode(worker)).toList();
      await prefs.setStringList('licensed_workers', workersJson);
    }
  }

  Future<void> _generatePdf() async {
    try {
      // Load the ROI PDF template
      final data = await rootBundle.load('assets/certificates/ROI EWRB NZ.pdf');
      final bytes = data.buffer.asUint8List();

      // Create a new PDF document from the template
      final sfpdf.PdfDocument document = sfpdf.PdfDocument(inputBytes: bytes);
      final sfpdf.PdfPage page = document.pages[0];
      final sfpdf.PdfGraphics graphics = page.graphics;

      // Define fonts
      final font9 = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 9);
      final font8 = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 8);
      final blackBrush = sfpdf.PdfSolidBrush(sfpdf.PdfColor(0, 0, 0));

      // Fill in the form fields using the coordinate mapping
      // Reference Number
      graphics.drawString(
        _referenceNumberController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['referenceNumber']!['x']!, 
          _roiFieldCoordinates['referenceNumber']!['y']!, 
          _roiFieldCoordinates['referenceNumber']!['width']!, 
          _roiFieldCoordinates['referenceNumber']!['height']!
        ),
      );

      // Inspector Information
      graphics.drawString(
        _inspectorNameController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['inspectorName']!['x']!, 
          _roiFieldCoordinates['inspectorName']!['y']!, 
          _roiFieldCoordinates['inspectorName']!['width']!, 
          _roiFieldCoordinates['inspectorName']!['height']!
        ),
      );

      graphics.drawString(
        _inspectorEmailController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['inspectorEmail']!['x']!, 
          _roiFieldCoordinates['inspectorEmail']!['y']!, 
          _roiFieldCoordinates['inspectorEmail']!['width']!, 
          _roiFieldCoordinates['inspectorEmail']!['height']!
        ),
      );

      graphics.drawString(
        _inspectorLicenseController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['inspectorLicense']!['x']!, 
          _roiFieldCoordinates['inspectorLicense']!['y']!, 
          _roiFieldCoordinates['inspectorLicense']!['width']!, 
          _roiFieldCoordinates['inspectorLicense']!['height']!
        ),
      );

      graphics.drawString(
        _inspectorPhoneController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['inspectorPhone']!['x']!, 
          _roiFieldCoordinates['inspectorPhone']!['y']!, 
          _roiFieldCoordinates['inspectorPhone']!['width']!, 
          _roiFieldCoordinates['inspectorPhone']!['height']!
        ),
      );

      // Location Address
      graphics.drawString(
        _locationAddressController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['locationAddress']!['x']!, 
          _roiFieldCoordinates['locationAddress']!['y']!, 
          _roiFieldCoordinates['locationAddress']!['width']!, 
          _roiFieldCoordinates['locationAddress']!['height']!
        ),
      );

      // Property Type Checkboxes (draw check mark for selected type)
      if (_propertyType == 'Domestic') {
        _drawCheckMark(graphics, _roiFieldCoordinates['domestic']!['x']!, _roiFieldCoordinates['domestic']!['y']!);
      } else if (_propertyType == 'Non-Domestic Accommodation') {
        _drawCheckMark(graphics, _roiFieldCoordinates['nonDomesticAccommodation']!['x']!, _roiFieldCoordinates['nonDomesticAccommodation']!['y']!);
      } else if (_propertyType == 'Industrial') {
        _drawCheckMark(graphics, _roiFieldCoordinates['industrial']!['x']!, _roiFieldCoordinates['industrial']!['y']!);
      } else if (_propertyType == 'Commercial') {
        _drawCheckMark(graphics, _roiFieldCoordinates['commercial']!['x']!, _roiFieldCoordinates['commercial']!['y']!);
      } else if (_propertyType == 'Educational') {
        _drawCheckMark(graphics, _roiFieldCoordinates['educational']!['x']!, _roiFieldCoordinates['educational']!['y']!);
      } else if (_propertyType == 'Health Care') {
        _drawCheckMark(graphics, _roiFieldCoordinates['healthCare']!['x']!, _roiFieldCoordinates['healthCare']!['y']!);
      } else if (_propertyType == 'Miscellaneous') {
        _drawCheckMark(graphics, _roiFieldCoordinates['miscellaneous']!['x']!, _roiFieldCoordinates['miscellaneous']!['y']!);
      }

      // CoC Details
      graphics.drawString(
        _cocDetailsController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['cocDetails']!['x']!, 
          _roiFieldCoordinates['cocDetails']!['y']!, 
          _roiFieldCoordinates['cocDetails']!['width']!, 
          _roiFieldCoordinates['cocDetails']!['height']!
        ),
      );

      // Electrical Worker 2
      if (_electricalWorker2NameController.text.isNotEmpty) {
        graphics.drawString(
          _electricalWorker2NameController.text,
          font8,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            _roiFieldCoordinates['electricalWorker2Name']!['x']!, 
            _roiFieldCoordinates['electricalWorker2Name']!['y']!, 
            _roiFieldCoordinates['electricalWorker2Name']!['width']!, 
            _roiFieldCoordinates['electricalWorker2Name']!['height']!
          ),
        );
      }

      if (_electricalWorker2LicenseController.text.isNotEmpty) {
        graphics.drawString(
          _electricalWorker2LicenseController.text,
          font8,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            _roiFieldCoordinates['electricalWorker2License']!['x']!, 
            _roiFieldCoordinates['electricalWorker2License']!['y']!, 
            _roiFieldCoordinates['electricalWorker2License']!['width']!, 
            _roiFieldCoordinates['electricalWorker2License']!['height']!
          ),
        );
      }

      // CoC Attached checkbox
      if (_cocAttached) {
        _drawCheckMark(graphics, _roiFieldCoordinates['cocAttached']!['x']!, _roiFieldCoordinates['cocAttached']!['y']!);
      }

      // Text areas
      graphics.drawString(
        _whatWasInspectedController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['whatWasInspected']!['x']!, 
          _roiFieldCoordinates['whatWasInspected']!['y']!, 
          _roiFieldCoordinates['whatWasInspected']!['width']!, 
          _roiFieldCoordinates['whatWasInspected']!['height']!
        ),
      );

      graphics.drawString(
        _regulationsDesignController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['regulationsDesign']!['x']!, 
          _roiFieldCoordinates['regulationsDesign']!['y']!, 
          _roiFieldCoordinates['regulationsDesign']!['width']!, 
          _roiFieldCoordinates['regulationsDesign']!['height']!
        ),
      );

      graphics.drawString(
        _resultsOfInspectionController.text,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['resultsOfInspection']!['x']!, 
          _roiFieldCoordinates['resultsOfInspection']!['y']!, 
          _roiFieldCoordinates['resultsOfInspection']!['width']!, 
          _roiFieldCoordinates['resultsOfInspection']!['height']!
        ),
      );

      // High Risk Category checkboxes
      if (_notToAsNzs3000) {
        _drawCheckMark(graphics, _roiFieldCoordinates['notToAsNzs3000']!['x']!, _roiFieldCoordinates['notToAsNzs3000']!['y']!);
      }
      if (_highVoltage) {
        _drawCheckMark(graphics, _roiFieldCoordinates['highVoltage']!['x']!, _roiFieldCoordinates['highVoltage']!['y']!);
      }
      if (_mainParallelGeneration) {
        _drawCheckMark(graphics, _roiFieldCoordinates['mainParallelGeneration']!['x']!, _roiFieldCoordinates['mainParallelGeneration']!['y']!);
      }
      if (_photovoltaicSystem) {
        _drawCheckMark(graphics, _roiFieldCoordinates['photovoltaicSystem']!['x']!, _roiFieldCoordinates['photovoltaicSystem']!['y']!);
      }
      if (_hazardousArea) {
        _drawCheckMark(graphics, _roiFieldCoordinates['hazardousArea']!['x']!, _roiFieldCoordinates['hazardousArea']!['y']!);
      }
      if (_animalStunning) {
        _drawCheckMark(graphics, _roiFieldCoordinates['animalStunning']!['x']!, _roiFieldCoordinates['animalStunning']!['y']!);
      }
      if (_electricalMedicalArea) {
        _drawCheckMark(graphics, _roiFieldCoordinates['electricalMedicalArea']!['x']!, _roiFieldCoordinates['electricalMedicalArea']!['y']!);
      }
      if (_mainWork) {
        _drawCheckMark(graphics, _roiFieldCoordinates['mainWork']!['x']!, _roiFieldCoordinates['mainWork']!['y']!);
      }
      if (_other) {
        _drawCheckMark(graphics, _roiFieldCoordinates['other']!['x']!, _roiFieldCoordinates['other']!['y']!);
        // Add "Other" specification text
        graphics.drawString(
          _otherSpecifyController.text,
          font8,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            _roiFieldCoordinates['otherSpecify']!['x']!, 
            _roiFieldCoordinates['otherSpecify']!['y']!, 
            _roiFieldCoordinates['otherSpecify']!['width']!, 
            _roiFieldCoordinates['otherSpecify']!['height']!
          ),
        );
      }

      // Sign Date
      final signDateStr = DateFormat('dd/MM/yyyy').format(_signDate);
      graphics.drawString(
        signDateStr,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          _roiFieldCoordinates['signDate']!['x']!, 
          _roiFieldCoordinates['signDate']!['y']!, 
          _roiFieldCoordinates['signDate']!['width']!, 
          _roiFieldCoordinates['signDate']!['height']!
        ),
      );

      // Add signature if available
      if (_signaturePath != null && await File(_signaturePath!).exists()) {
        final signatureBytes = await File(_signaturePath!).readAsBytes();
        final signatureImage = sfpdf.PdfBitmap(signatureBytes);
        graphics.drawImage(
          signatureImage,
          Rect.fromLTWH(
            _roiFieldCoordinates['signature']!['x']!,
            _roiFieldCoordinates['signature']!['y']!,
            _roiFieldCoordinates['signature']!['width']!,
            _roiFieldCoordinates['signature']!['height']!,
          ),
        );
      }

      // Save the PDF
      final output = await getApplicationDocumentsDirectory();
      final fileName = generateRoiName(widget.job);
      
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(await document.save());
      document.dispose();

      // Add to job attachments
      widget.job.attachments ??= [];
      if (!widget.job.attachments!.contains(file.path)) {
        widget.job.attachments!.add(file.path);
      }
      
      // Save job with new attachment
      await _saveJob();

      // Show post-generation dialogs
      final address = widget.job.address ?? 'Unknown Address';
      await _showPostGenerationDialogs(file.path, address);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating ROI certificate: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to draw check marks
  void _drawCheckMark(sfpdf.PdfGraphics graphics, double x, double y) {
    final font = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 10);
    final brush = sfpdf.PdfSolidBrush(sfpdf.PdfColor(0, 0, 0));
    graphics.drawString('✓', font, brush: brush, bounds: Rect.fromLTWH(x, y, 10, 10));
  }

  Future<void> _showPostGenerationDialogs(String filePath, String address) async {
    // 1. Ask to add electrical worker to licensed customer book
    if (_electricalWorker2NameController.text.isNotEmpty && 
        _electricalWorker2LicenseController.text.isNotEmpty) {
      
      // Check if worker is already in licensed workers
      final existingWorker = _licensedWorkers.firstWhere(
        (worker) => worker['license'] == _electricalWorker2LicenseController.text,
        orElse: () => {},
      );
      
      if (existingWorker.isEmpty) {
        final shouldAddWorker = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add Electrical Worker'),
            content: Text('Would you like to add ${_electricalWorker2NameController.text} to your Licensed Customer Book?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        
        if (shouldAddWorker == true) {
          await _saveLicensedWorker(
            _electricalWorker2NameController.text,
            _electricalWorker2LicenseController.text,
            _electricalWorker2EmailController.text,
          );
        }
      }
    }

    // 2. Ask to email ROI to electrician
    if (_electricalWorker2EmailController.text.isNotEmpty) {
      final shouldEmailElectrician = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Email ROI to Electrician'),
          content: Text('Would you like to email the ROI to ${_electricalWorker2NameController.text}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      
      if (shouldEmailElectrician == true) {
        await _emailRoiToElectrician(filePath, address);
      }
    }

    // 3. Ask to upload to High Risk Database
    final shouldUploadToDatabase = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload to High Risk Database'),
        content: const Text('Would you like to upload this ROI to the WorkSafe High Risk Database?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    
    if (shouldUploadToDatabase == true) {
      await _openWorkSafePortal();
    }

    // Auto-return to job details with success indicator
    if (mounted) {
      Navigator.pop(context, true); // Go back to job details with success indicator
    }
  }

  Future<void> _emailRoiToElectrician(String filePath, String address) async {
    try {
      // Load SMTP settings
      final prefs = await SharedPreferences.getInstance();
      final smtpEmail = prefs.getString('smtp_email') ?? '';
      final smtpPassword = prefs.getString('smtp_password') ?? '';
      
      if (smtpEmail.isEmpty || smtpPassword.isEmpty) {
        throw Exception('SMTP settings not configured');
      }

      // Use existing SMTP method from job_details_screen
      // This would need to be imported or implemented
      // await sendEmailViaSmtp(
      //   toEmail: _electricalWorker2EmailController.text,
      //   subject: subject,
      //   body: body,
      //   attachmentPaths: [filePath],
      // );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ROI emailed to ${_electricalWorker2NameController.text}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to email ROI: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openWorkSafePortal() async {
    try {
      // Open WorkSafe portal in web browser
      final url = 'https://portal.worksafe.govt.nz/signin/';
      await Process.run('open', [url]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open WorkSafe portal: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save job method with hybrid storage integration
  Future<void> _saveJob() async {
    try {
      // Save to local file for backward compatibility
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/job_${widget.job.id}.json');
      await file.writeAsString(jsonEncode(widget.job.toJson()));
      // Try to sync to cloud, but ignore errors
      try {
        await FirestoreService.saveJob(widget.job);
        await SyncScheduler.syncNow(DataType.jobs);
      } catch (e) {
        print('Cloud sync failed: $e');
      }
    } catch (e) {
      print('Error saving job locally: $e');
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _signDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _signDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ROI Certificate'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _generatePdf,
            tooltip: 'Generate PDF',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Record of Inspection (ROI)',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Job: ${widget.job.title}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Reference Number
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: _referenceNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Inspector Information Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inspector Information',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _inspectorNameController,
                            decoration: const InputDecoration(
                              labelText: 'Inspector Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _inspectorLicenseController,
                            decoration: const InputDecoration(
                              labelText: 'Registration/License',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.badge),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _inspectorEmailController,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _inspectorPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Location Address
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: _locationAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Location Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Property Type Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Property Type (Select One)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Domestic',
                        'Non-Domestic Accommodation',
                        'Industrial',
                        'Commercial',
                        'Educational',
                        'Health Care',
                        'Miscellaneous',
                      ].map((type) => ChoiceChip(
                        label: Text(type),
                        selected: _propertyType == type,
                        onSelected: (selected) {
                          setState(() {
                            _propertyType = selected ? type : '';
                          });
                        },
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // CoC Details and Electrical Worker Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Certificate Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _cocDetailsController,
                      decoration: const InputDecoration(
                        labelText: 'CoC Details',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    CheckboxListTile(
                      title: const Text('CoC Attached'),
                      value: _cocAttached,
                      onChanged: (value) {
                        setState(() {
                          _cocAttached = value ?? false;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Text(
                      'Electrical Worker (Search and Add)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Search bar for electrical workers
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Search Electrical Worker',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      initialValue: _selectedWorkerName.isEmpty ? null : _selectedWorkerName,
                      items: [
                        const DropdownMenuItem(value: 'new', child: Text('Add New Worker')),
                        ..._licensedWorkers.map((worker) => DropdownMenuItem(
                          value: worker['name'],
                          child: Text('${worker['name']} (${worker['license']})'),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedWorkerName = value ?? '';
                          if (value != null && value != 'new') {
                            final worker = _licensedWorkers.firstWhere(
                              (w) => w['name'] == value,
                              orElse: () => {},
                            );
                            if (worker.isNotEmpty) {
                              _electricalWorker2NameController.text = worker['name'] ?? '';
                              _electricalWorker2LicenseController.text = worker['license'] ?? '';
                              _electricalWorker2EmailController.text = worker['email'] ?? '';
                            }
                          } else if (value == 'new') {
                            _electricalWorker2NameController.clear();
                            _electricalWorker2LicenseController.clear();
                            _electricalWorker2EmailController.clear();
                          }
                        });
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _electricalWorker2NameController,
                            decoration: const InputDecoration(
                              labelText: 'Electrical Worker Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _electricalWorker2LicenseController,
                            decoration: const InputDecoration(
                              labelText: 'Registration/License',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _electricalWorker2EmailController,
                      decoration: const InputDecoration(
                        labelText: 'Email (for PDF notification)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Inspection Details Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inspection Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    WebSpeechTextField(
                      controller: _whatWasInspectedController,
                      labelText: 'What Was Inspected',
                      hintText: 'Describe what was inspected...',
                      maxLines: 4,
                      continuousListening: true,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    WebSpeechTextField(
                      controller: _regulationsDesignController,
                      labelText: 'Specify Regulations, Certified Design Followed',
                      hintText: 'Describe regulations and designs followed...',
                      maxLines: 4,
                      continuousListening: true,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    WebSpeechTextField(
                      controller: _resultsOfInspectionController,
                      labelText: 'Results of Inspection',
                      hintText: 'Describe the inspection results...',
                      maxLines: 4,
                      continuousListening: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // High Risk Category Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'High Risk Category (Multiple Selection Allowed)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    CheckboxListTile(
                      title: const Text('Not to AS/NZS 3000 Part 2'),
                      value: _notToAsNzs3000,
                      onChanged: (value) {
                        setState(() {
                          _notToAsNzs3000 = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('High Voltage'),
                      value: _highVoltage,
                      onChanged: (value) {
                        setState(() {
                          _highVoltage = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Main Parallel Generation'),
                      value: _mainParallelGeneration,
                      onChanged: (value) {
                        setState(() {
                          _mainParallelGeneration = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Photovoltaic System'),
                      value: _photovoltaicSystem,
                      onChanged: (value) {
                        setState(() {
                          _photovoltaicSystem = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Hazardous Area'),
                      value: _hazardousArea,
                      onChanged: (value) {
                        setState(() {
                          _hazardousArea = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Animal Stunning or Meat Conditioning'),
                      value: _animalStunning,
                      onChanged: (value) {
                        setState(() {
                          _animalStunning = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Electrical Medical Area'),
                      value: _electricalMedicalArea,
                      onChanged: (value) {
                        setState(() {
                          _electricalMedicalArea = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Main Work'),
                      value: _mainWork,
                      onChanged: (value) {
                        setState(() {
                          _mainWork = value ?? false;
                        });
                      },
                    ),
                    
                    CheckboxListTile(
                      title: const Text('Other'),
                      value: _other,
                      onChanged: (value) {
                        setState(() {
                          _other = value ?? false;
                        });
                      },
                    ),
                    
                    if (_other) ...[
                      const SizedBox(height: 8),
                      TextField(textCapitalization: TextCapitalization.sentences, 
                        controller: _otherSpecifyController,
                        decoration: const InputDecoration(
                          labelText: 'Specify Other',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Signature and Date Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signature and Date',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Signing Date'),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(_signDate)),
                      trailing: const Icon(Icons.edit),
                      onTap: _selectDate,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Generate PDF Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 24),
                label: const Text('Generate ROI Certificate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: _generatePdf,
              ),
            ),

            // Extra bottom padding for better mobile accessibility
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
