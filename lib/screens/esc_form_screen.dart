import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:async';
import 'dart:io';
import '../models/job.dart';
import '../services/firestore_service.dart';
import '../services/sync_scheduler.dart';
import '../services/storage_strategy_service.dart';
import '../mixins/document_naming_mixin.dart';
import '../widgets/web_speech_text_field.dart';

class EscFormScreen extends StatefulWidget {
  final Job job;

  const EscFormScreen({
    super.key,
    required this.job,
  });

  @override
  State<EscFormScreen> createState() => _EscFormScreenState();
}

class _EscFormScreenState extends State<EscFormScreen>
    with DocumentNamingMixin {
  // ESC EWRB Form Field Coordinates (based on A4 page format)
  static const Map<String, Map<String, double>> _escFieldCoordinates = {
    // Reference Number
    'referenceNumber': {'x': 297, 'y': 59, 'width': 232, 'height': 17},

    // Site Address
    'siteAddress': {'x': 140, 'y': 127, 'width': 389, 'height': 28},

    // Customer Name and Address
    'customerNameAddress': {'x': 141, 'y': 164, 'width': 388, 'height': 42},

    // Details of work checkboxes
    'wholeInstallation': {'x': 149, 'y': 218},
    'partOfInstall': {'x': 271, 'y': 218},

    // Work Description
    'workDescription': {'x': 141, 'y': 236, 'width': 388, 'height': 324},

    // User Information
    'userName': {'x': 139, 'y': 646, 'width': 200, 'height': 20},
    'userLicense': {'x': 394, 'y': 646, 'width': 200, 'height': 20},

    // Dates
    'connectionDate': {'x': 140, 'y': 576, 'width': 100, 'height': 20},
    'signDate': {'x': 395, 'y': 684, 'width': 100, 'height': 20},

    // Signature
    'signature': {'x': 141, 'y': 683, 'width': 120, 'height': 40},

    // Email (auto fill from user email)
    'userEmail': {'x': 140, 'y': 721, 'width': 200, 'height': 20},

    // Company Name (Organisation/Company) - Bottom right box
    'companyName': {'x': 395, 'y': 740, 'width': 200, 'height': 20},
  };

  // Form controllers - simplified for ESC
  final _referenceNumberController = TextEditingController();
  final _siteAddressController = TextEditingController();
  final _customerNameAddressController = TextEditingController();
  final _userNameController = TextEditingController();
  final _userLicenseController = TextEditingController();
  final _userEmailController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _workDescriptionController = TextEditingController();
  final _userPhoneController = TextEditingController();

  // Form state variables - simplified for ESC
  DateTime _signDate = DateTime.now();
  DateTime _testDate = DateTime.now();

  // Details of work checkboxes
  bool _wholeInstallation = false;
  bool _partOfInstall = true; // default ticked as requested

  // Expanded information section toggle
  bool _useExpandedInfoSection = true;

  // Auto-save functionality
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    final prefs = await SharedPreferences.getInstance();

    // Load expanded info section preference
    _useExpandedInfoSection =
        prefs.getBool('use_expanded_info_section') ?? true;

    // Auto-fill user information from settings
    final firstName = prefs.getString('first_name') ?? '';
    final lastName = prefs.getString('last_name') ?? '';
    final licenseNumber = prefs.getString('electrical_license') ?? '';
    final phoneNumber = prefs.getString('phone_number') ?? '';
    final emailAddress = prefs.getString('personal_email') ?? '';
    final companyName =
        prefs.getString('company_name') ?? widget.job.companyName ?? '';

    // Set default values
    setState(() {
      _userNameController.text = '$firstName $lastName'.trim();
      _userLicenseController.text = licenseNumber;
      _userEmailController.text = emailAddress;
      _companyNameController.text = companyName;
      _userPhoneController.text = phoneNumber;
      _customerNameAddressController.text = widget.job.documentCustomerName;
      _siteAddressController.text = widget.job.address ?? '';

      // Generate reference number
      final jobId = widget.job.id;
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      _referenceNumberController.text = 'ESC-$jobId-$dateStr';
    });
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _userLicenseController.dispose();
    _userEmailController.dispose();
    _companyNameController.dispose();
    _referenceNumberController.dispose();
    _customerNameAddressController.dispose();
    _siteAddressController.dispose();
    _workDescriptionController.dispose();
    _userPhoneController.dispose();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _generatePdf() async {
    try {
      _showLoadingDialog('Generating ESC Certificate...');

      // Load the ESC PDF template
      final data = await rootBundle.load('assets/certificates/ESC EWRB NZ.pdf');
      final bytes = data.buffer.asUint8List();

      // Create a new PDF document from the template
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfPage page = document.pages[0];
      final PdfGraphics graphics = page.graphics;

      // Define fonts
      final font9 = PdfStandardFont(PdfFontFamily.helvetica, 9);
      final font8 = PdfStandardFont(PdfFontFamily.helvetica, 8);
      final font10 = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));

      // Fill in the form fields using the coordinate mapping
      // Reference Number
      graphics.drawString(
        _referenceNumberController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['referenceNumber']!['x']!,
            _escFieldCoordinates['referenceNumber']!['y']!,
            _escFieldCoordinates['referenceNumber']!['width']!,
            _escFieldCoordinates['referenceNumber']!['height']!),
      );

      // Site Address
      graphics.drawString(
        _siteAddressController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['siteAddress']!['x']!,
            _escFieldCoordinates['siteAddress']!['y']!,
            _escFieldCoordinates['siteAddress']!['width']!,
            _escFieldCoordinates['siteAddress']!['height']!),
      );

      // Customer Name and Address
      graphics.drawString(
        _customerNameAddressController.text,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['customerNameAddress']!['x']!,
            _escFieldCoordinates['customerNameAddress']!['y']!,
            _escFieldCoordinates['customerNameAddress']!['width']!,
            _escFieldCoordinates['customerNameAddress']!['height']!),
      );

      // Details of work checkboxes - Draw proper checkmarks
      if (_wholeInstallation) {
        _drawCheckMark(
            graphics,
            _escFieldCoordinates['wholeInstallation']!['x']!,
            _escFieldCoordinates['wholeInstallation']!['y']!);
      }
      if (_partOfInstall) {
        _drawCheckMark(graphics, _escFieldCoordinates['partOfInstall']!['x']!,
            _escFieldCoordinates['partOfInstall']!['y']!);
      }

      // Work Description with text wrapping and overflow handling
      final workDescText = _workDescriptionController.text;
      final workDescBounds = Rect.fromLTWH(
          _escFieldCoordinates['workDescription']!['x']!,
          _escFieldCoordinates['workDescription']!['y']!,
          _escFieldCoordinates['workDescription']!['width']!,
          _escFieldCoordinates['workDescription']!['height']!);

      // Check if text fits on first page (approximately 16 lines at 8pt)
      final lines = _wrapText(workDescText, workDescBounds.width, font8);

      if (lines.length <= 16) {
        // Fits on first page
        graphics.drawString(
          workDescText,
          font8,
          brush: blackBrush,
          bounds: workDescBounds,
        );
      } else {
        // Text overflows to second page
        // Draw what fits on first page (first 16 lines)
        final firstPageLines = lines.sublist(0, 16).join('\n');
        graphics.drawString(
          firstPageLines,
          font8,
          brush: blackBrush,
          bounds: workDescBounds,
        );

        // Create second page for overflow
        final page2 = document.pages.add();
        final graphics2 = page2.graphics;

        // Add header indicating continuation
        graphics2.drawString(
          'Additional Description Notes - Continuation',
          font10,
          brush: blackBrush,
          bounds: Rect.fromLTWH(140, 60, 389, 20),
        );

        // Draw remaining lines on second page
        final remainingLines = lines.sublist(16).join('\n');
        graphics2.drawString(
          remainingLines,
          font8,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
              _escFieldCoordinates['workDescription']!['x']!,
              _escFieldCoordinates['workDescription']!['y']! - 100,
              _escFieldCoordinates['workDescription']!['width']!,
              _escFieldCoordinates['workDescription']!['height']! + 100),
        );
      }

      // Include signature if available
      final prefs = await SharedPreferences.getInstance();
      final signaturePath = prefs.getString('signature_path');
      if (signaturePath != null && await File(signaturePath).exists()) {
        try {
          final signatureBytes = await File(signaturePath).readAsBytes();
          final signatureImage = PdfBitmap(signatureBytes);
          graphics.drawImage(
            signatureImage,
            Rect.fromLTWH(
                _escFieldCoordinates['signature']!['x']!,
                _escFieldCoordinates['signature']!['y']!,
                _escFieldCoordinates['signature']!['width']!,
                _escFieldCoordinates['signature']!['height']!),
          );
        } catch (e) {
          print('Error loading signature: $e');
        }
      }

      // User information
      final userName = _userNameController.text;
      final userLicense = _userLicenseController.text;
      final companyName = _companyNameController.text;
      final userEmail = _userEmailController.text;
      final connectionDateStr = DateFormat('dd/MM/yyyy').format(_testDate);

      graphics.drawString(
        userName,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['userName']!['x']!,
            _escFieldCoordinates['userName']!['y']!,
            _escFieldCoordinates['userName']!['width']!,
            _escFieldCoordinates['userName']!['height']!),
      );

      graphics.drawString(
        userLicense,
        font8,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['userLicense']!['x']!,
            _escFieldCoordinates['userLicense']!['y']!,
            _escFieldCoordinates['userLicense']!['width']!,
            _escFieldCoordinates['userLicense']!['height']!),
      );

      graphics.drawString(
        companyName,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['companyName']!['x']!,
            _escFieldCoordinates['companyName']!['y']!,
            _escFieldCoordinates['companyName']!['width']!,
            _escFieldCoordinates['companyName']!['height']!),
      );

      graphics.drawString(
        userEmail,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['userEmail']!['x']!,
            _escFieldCoordinates['userEmail']!['y']!,
            _escFieldCoordinates['userEmail']!['width']!,
            _escFieldCoordinates['userEmail']!['height']!),
      );

      // Dates
      final signDateStr = DateFormat('dd/MM/yyyy').format(_signDate);

      graphics.drawString(
        signDateStr,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['signDate']!['x']!,
            _escFieldCoordinates['signDate']!['y']!,
            _escFieldCoordinates['signDate']!['width']!,
            _escFieldCoordinates['signDate']!['height']!),
      );

      graphics.drawString(
        connectionDateStr,
        font9,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
            _escFieldCoordinates['connectionDate']!['x']!,
            _escFieldCoordinates['connectionDate']!['y']!,
            _escFieldCoordinates['connectionDate']!['width']!,
            _escFieldCoordinates['connectionDate']!['height']!),
      );

      // Save the PDF
      final output = await getApplicationDocumentsDirectory();
      final fileName = generateEscName(widget.job);
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(await document.save());
      document.dispose();
      print('ESC PDF saved at: \'${file.path}\'');
      print('File exists after save: \'${await file.exists()}\'');

      // Add to job attachments
      setState(() {
        widget.job.attachments ??= [];
        if (!widget.job.attachments!.contains(file.path)) {
          widget.job.attachments!.add(file.path);
        }
      });

      // Save job with new attachment
      await _saveJob();

      // Hide loading dialog and show success
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ESC Certificate generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Force parent screen to reload job after returning
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating ESC: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save job method with hybrid storage integration
  Future<void> _saveJob() async {
    try {
      // Persist the job and update the main jobs index file
      await widget.job.save();

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

  /// Debounced auto-save to avoid frequent saves (30 second delay)
  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 30), () {
      _saveJob();
    });
  }

  /// Mark as having unsaved changes and trigger auto-save
  void _markDirtyAndAutoSave() {
    _debouncedSave();
  }

  Future<void> _selectDate(BuildContext context, bool isSignDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isSignDate ? _signDate : _testDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isSignDate) {
          _signDate = picked;
        } else {
          _testDate = picked;
        }
      });
    }
  }

  Widget _buildDetailedFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reference Number
        TextFormField(
          textCapitalization: TextCapitalization.sentences,
          controller: _referenceNumberController,
          decoration: const InputDecoration(
            labelText: 'Reference Number',
            prefixIcon: Icon(Icons.numbers),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Site Address
        TextFormField(
          textCapitalization: TextCapitalization.sentences,
          controller: _siteAddressController,
          decoration: const InputDecoration(
            labelText: 'Site Address',
            prefixIcon: Icon(Icons.location_on),
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // Customer Name and Address
        TextFormField(
          textCapitalization: TextCapitalization.sentences,
          controller: _customerNameAddressController,
          decoration: const InputDecoration(
            labelText: 'Customer Name and Address',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        // User Details
        Row(
          children: [
            Expanded(
              child: TextFormField(
                textCapitalization: TextCapitalization.sentences,
                controller: _userNameController,
                decoration: const InputDecoration(
                  labelText: 'Electrician Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                textCapitalization: TextCapitalization.sentences,
                controller: _userLicenseController,
                decoration: const InputDecoration(
                  labelText: 'License Number',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        TextFormField(
          textCapitalization: TextCapitalization.words,
          controller: _companyNameController,
          decoration: const InputDecoration(
            labelText: 'Company Name',
            prefixIcon: Icon(Icons.business),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                textCapitalization: TextCapitalization.sentences,
                controller: _userPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                textCapitalization: TextCapitalization.sentences,
                controller: _userEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDetailOfWorkGroup() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Details of Work',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Whole Installation'),
              value: _wholeInstallation,
              onChanged: (value) => setState(() {
                _wholeInstallation = value!;
                if (value) _partOfInstall = false;
                _markDirtyAndAutoSave();
              }),
            ),
            CheckboxListTile(
              title: const Text('Part of Installation'),
              value: _partOfInstall,
              onChanged: (value) => setState(() {
                _partOfInstall = value!;
                if (value) _wholeInstallation = false;
                _markDirtyAndAutoSave();
              }),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to draw check marks for checkboxes
  void _drawCheckMark(PdfGraphics graphics, double x, double y) {
    final pen = PdfPen(PdfColor(0, 0, 0), width: 2.5);

    // Draw a proper check mark with better visibility
    // First line of check (downward-left diagonal)
    graphics.drawLine(pen, Offset(x + 3, y + 8), Offset(x + 6, y + 12));
    // Second line of check (upward-right diagonal)
    graphics.drawLine(pen, Offset(x + 6, y + 12), Offset(x + 13, y + 3));
  }

  /// Wraps text to fit within a specified width
  List<String> _wrapText(String text, double maxWidth, PdfFont font) {
    if (text.isEmpty) return [];

    final words = text.split(' ');
    final lines = <String>[];
    String currentLine = '';

    for (final word in words) {
      final testLine = currentLine.isEmpty ? word : '$currentLine $word';
      // Approximate character width for helvetica 8pt (~2 pixels per character)
      final estimatedWidth = testLine.length * 2.2;

      if (estimatedWidth <= maxWidth * 0.95) {
        // Keep 5% margin for safety
        currentLine = testLine;
      } else {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
        }
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }

  /// Show loading dialog during PDF generation
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Electrical Safety Certificate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ESC form saved')),
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
                title: const Text('Expanded Information',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                initiallyExpanded: false,
                children: [
                  const SizedBox(height: 8),
                  _buildDetailedFields(),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              // Show detailed fields in main flow
              _buildDetailedFields(),
            ],

            // Details of Work Group
            _buildDetailOfWorkGroup(),
            const SizedBox(height: 16),

            // Work Description
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Work Description',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    WebSpeechTextField(
                      controller: _workDescriptionController,
                      labelText: 'Describe the electrical work performed',
                      hintText: 'Tap microphone icon to speak or type description',
                      maxLines: 4,
                      continuousListening: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dates',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Test Date'),
                      subtitle:
                          Text(DateFormat('dd/MM/yyyy').format(_testDate)),
                      onTap: () => _selectDate(context, false),
                      trailing: const Icon(Icons.edit),
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Sign Date'),
                      subtitle:
                          Text(DateFormat('dd/MM/yyyy').format(_signDate)),
                      onTap: () => _selectDate(context, true),
                      trailing: const Icon(Icons.edit),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Generate PDF Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generatePdf,
                icon: const Icon(Icons.picture_as_pdf, size: 24),
                label: const Text('Generate ESC Certificate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
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
}
