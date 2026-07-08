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

class GasCocFormScreen extends StatefulWidget {
  final Job job;

  const GasCocFormScreen({
    super.key,
    required this.job,
  });

  @override
  State<GasCocFormScreen> createState() => _GasCocFormScreenState();
}

class _GasCocFormScreenState extends State<GasCocFormScreen>
    with DocumentNamingMixin {
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
  final _gasPressureTestController = TextEditingController();
  final _gasLeakTestController = TextEditingController();
  final _ventilationController = TextEditingController();
  final _applianceCommissioningController = TextEditingController();
  final _otherController = TextEditingController();
  final _highRiskSpecifyController = TextEditingController();
  final _additionalStandardsSpecifyController = TextEditingController();
  final _rangeDatesController = TextEditingController();
  final _partsSpecifyController = TextEditingController();
  final _manufacturerInstructionsController = TextEditingController();
  final _certifiedDesignController = TextEditingController();
  final _sdocLinkController = TextEditingController();
  final _gasTypeController = TextEditingController();
  final _gasSupplierController = TextEditingController();
  final _meterLocationController = TextEditingController();

  // Form state variables
  String _workType =
      ''; // Installation, Alteration, Maintenance - No default selection
  String _riskLevel = ''; // Low Risk, General, High Risk - No default selection
  DateTime? _testStartDate;
  DateTime? _testEndDate;

  // Gas specific options
  String _gasType = 'Natural Gas'; // Natural Gas, LPG
  bool _hasGasMeter = false;
  bool _hasRegulator = false;
  bool _hasShutoffValve = false;

  // Testing checkboxes
  bool _gasPressureTestDone = false;
  bool _gasLeakTestDone = false;
  bool _ventilationTestDone = false;
  bool _applianceTestDone = false;

  // Auto-save functionality
  Timer? _saveDebounce;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadFormData();
    _autoFillFromJob();
  }

  @override
  void dispose() {
    // Dispose all controllers
    _referenceNumberController.dispose();
    _siteAddressController.dispose();
    _customerNameAddressController.dispose();
    _userNameController.dispose();
    _userLicenseController.dispose();
    _userPhoneController.dispose();
    _userEmailController.dispose();
    _supervisedPersonController.dispose();
    _workDescriptionController.dispose();
    _gasPressureTestController.dispose();
    _gasLeakTestController.dispose();
    _ventilationController.dispose();
    _applianceCommissioningController.dispose();
    _otherController.dispose();
    _highRiskSpecifyController.dispose();
    _additionalStandardsSpecifyController.dispose();
    _rangeDatesController.dispose();
    _partsSpecifyController.dispose();
    _manufacturerInstructionsController.dispose();
    _certifiedDesignController.dispose();
    _sdocLinkController.dispose();
    _gasTypeController.dispose();
    _gasSupplierController.dispose();
    _meterLocationController.dispose();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _userNameController.text = prefs.getString('gas_coc_user_name') ?? '';
      _userLicenseController.text =
          prefs.getString('gas_fitting_license') ?? '';
      _userPhoneController.text = prefs.getString('gas_coc_user_phone') ?? '';
      _userEmailController.text = prefs.getString('gas_coc_user_email') ?? '';
    });
  }

  Future<void> _saveFormData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('gas_coc_user_name', _userNameController.text);
    await prefs.setString('gas_coc_user_license', _userLicenseController.text);
    await prefs.setString('gas_coc_user_phone', _userPhoneController.text);
    await prefs.setString('gas_coc_user_email', _userEmailController.text);
  }

  void _autoFillFromJob() {
    setState(() {
      _siteAddressController.text = widget.job.address ?? '';
      final customerName = widget.job.documentCustomerName;
      final address = widget.job.address ?? '';
      _customerNameAddressController.text = [customerName, address]
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
      _workDescriptionController.text = widget.job.description ?? '';
      _referenceNumberController.text = widget.job.id;
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (_testStartDate ?? DateTime.now())
          : (_testEndDate ?? _testStartDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _testStartDate = picked;
        } else {
          _testEndDate = picked;
        }
        _updateDateRangeText();
      });
    }
  }

  void _updateDateRangeText() {
    final dateFormat = DateFormat('dd/MM/yyyy');
    String dateText = '';

    if (_testStartDate != null) {
      dateText = dateFormat.format(_testStartDate!);
      if (_testEndDate != null) {
        dateText += ' - ${dateFormat.format(_testEndDate!)}';
      }
    }

    _rangeDatesController.text = dateText;
  }

  Future<void> _generateGasCocCertificate() async {
    try {
      // Validate required fields
      if (_referenceNumberController.text.isEmpty ||
          _siteAddressController.text.isEmpty ||
          _customerNameAddressController.text.isEmpty ||
          _userNameController.text.isEmpty ||
          _userLicenseController.text.isEmpty ||
          _workType.isEmpty ||
          _riskLevel.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Save form data for future use
      await _saveFormData();

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating Gas COC Certificate...'),
            ],
          ),
        ),
      );

      // Load the Gas COC PDF template
      final ByteData data = await rootBundle
          .load('assets/certificates/GAS COC and GAS SAFTEY NZ.pdf');
      final Uint8List bytes = data.buffer.asUint8List();

      // Create PDF document
      final sfpdf.PdfDocument document = sfpdf.PdfDocument(inputBytes: bytes);
      final sfpdf.PdfPage page = document.pages[0];
      final sfpdf.PdfGraphics graphics = page.graphics;
      final sfpdf.PdfFont font =
          sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 10);

      // Note: These coordinates are placeholders - you'll need to adjust based on the actual Gas COC PDF
      // Fill in the form fields with appropriate coordinates

      // Reference Number
      graphics.drawString(
        _referenceNumberController.text,
        font,
        bounds: const Rect.fromLTWH(450, 50, 100, 20),
      );

      // Site Address
      graphics.drawString(
        _siteAddressController.text,
        font,
        bounds: const Rect.fromLTWH(150, 100, 300, 40),
      );

      // Customer Name and Address
      graphics.drawString(
        _customerNameAddressController.text,
        font,
        bounds: const Rect.fromLTWH(150, 140, 300, 40),
      );

      // User Name
      graphics.drawString(
        _userNameController.text,
        font,
        bounds: const Rect.fromLTWH(150, 220, 200, 20),
      );

      // License Number
      graphics.drawString(
        _userLicenseController.text,
        font,
        bounds: const Rect.fromLTWH(350, 220, 100, 20),
      );

      // Phone
      graphics.drawString(
        _userPhoneController.text,
        font,
        bounds: const Rect.fromLTWH(150, 240, 150, 20),
      );

      // Email
      graphics.drawString(
        _userEmailController.text,
        font,
        bounds: const Rect.fromLTWH(320, 240, 200, 20),
      );

      // Work Description
      graphics.drawString(
        _workDescriptionController.text,
        font,
        bounds: const Rect.fromLTWH(150, 300, 400, 60),
      );

      // Gas Type
      graphics.drawString(
        _gasType,
        font,
        bounds: const Rect.fromLTWH(150, 380, 200, 20),
      );

      // Test results
      if (_gasPressureTestDone) {
        graphics.drawString(
          _gasPressureTestController.text,
          font,
          bounds: const Rect.fromLTWH(200, 420, 300, 20),
        );
      }

      if (_gasLeakTestDone) {
        graphics.drawString(
          _gasLeakTestController.text,
          font,
          bounds: const Rect.fromLTWH(200, 440, 300, 20),
        );
      }

      // Date range
      if (_rangeDatesController.text.isNotEmpty) {
        graphics.drawString(
          _rangeDatesController.text,
          font,
          bounds: const Rect.fromLTWH(150, 500, 200, 20),
        );
      }

      // Save the document
      final List<int> pdfBytes = await document.save();
      document.dispose();

      // Save to app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final fileName = generateGasCocName(widget.job);
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      // Update job with the new attachment
      widget.job.attachments = [...(widget.job.attachments ?? []), filePath];

      // Save updated job using hybrid storage
      await _saveJob();

      // Close loading dialog
      Navigator.of(context).pop();

      // Auto-return to job details with success indicator
      Navigator.pop(context, true);
    } catch (e) {
      // Close loading dialog if open
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating Gas COC: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_gas_station, color: Colors.orange),
            SizedBox(width: 8),
            Text('Gas COC Certificate'),
          ],
        ),
        backgroundColor: Colors.orange.shade100,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.local_gas_station,
                                  color: Colors.orange),
                              const SizedBox(width: 8),
                              const Text(
                                'Gas Certificate of Compliance',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Complete this form to generate a Gas COC certificate for gas fitting work.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Basic Information Section
                  _buildSectionCard(
                    title: 'Basic Information',
                    icon: Icons.info_outline,
                    children: [
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _referenceNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Reference Number *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      WebSpeechTextField(
                        controller: _siteAddressController,
                        labelText: 'Site Address *',
                      ),
                      const SizedBox(height: 16),
                      WebSpeechTextField(
                        controller: _customerNameAddressController,
                        labelText: 'Customer Name & Address *',
                        maxLines: 3,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Work Classification Section
                  _buildSectionCard(
                    title: 'Work Classification',
                    icon: Icons.work_outline,
                    children: [
                      const Text('Type of Work *',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildChoiceChip('Installation', _workType,
                              (value) => setState(() => _workType = value)),
                          _buildChoiceChip('Alteration', _workType,
                              (value) => setState(() => _workType = value)),
                          _buildChoiceChip('Maintenance', _workType,
                              (value) => setState(() => _workType = value)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Risk Level *',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildChoiceChip('Low Risk', _riskLevel,
                              (value) => setState(() => _riskLevel = value)),
                          _buildChoiceChip('General', _riskLevel,
                              (value) => setState(() => _riskLevel = value)),
                          _buildChoiceChip('High Risk', _riskLevel,
                              (value) => setState(() => _riskLevel = value)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      WebSpeechTextField(
                        controller: _workDescriptionController,
                        labelText: 'Work Description *',
                        maxLines: 3,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Gas Information Section
                  _buildSectionCard(
                    title: 'Gas Information',
                    icon: Icons.local_gas_station,
                    children: [
                      const Text('Gas Type',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildChoiceChip('Natural Gas', _gasType,
                              (value) => setState(() => _gasType = value)),
                          _buildChoiceChip('LPG', _gasType,
                              (value) => setState(() => _gasType = value)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _gasSupplierController,
                        decoration: const InputDecoration(
                          labelText: 'Gas Supplier',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _meterLocationController,
                        decoration: const InputDecoration(
                          labelText: 'Meter Location',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Gas Meter Installed'),
                        value: _hasGasMeter,
                        onChanged: (value) =>
                            setState(() => _hasGasMeter = value!),
                      ),
                      CheckboxListTile(
                        title: const Text('Regulator Installed'),
                        value: _hasRegulator,
                        onChanged: (value) =>
                            setState(() => _hasRegulator = value!),
                      ),
                      CheckboxListTile(
                        title: const Text('Shut-off Valve Installed'),
                        value: _hasShutoffValve,
                        onChanged: (value) =>
                            setState(() => _hasShutoffValve = value!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Testing & Commissioning Section
                  _buildSectionCard(
                    title: 'Testing & Commissioning',
                    icon: Icons.check_circle_outline,
                    children: [
                      CheckboxListTile(
                        title: const Text('Gas Pressure Test'),
                        value: _gasPressureTestDone,
                        onChanged: (value) =>
                            setState(() => _gasPressureTestDone = value!),
                      ),
                      if (_gasPressureTestDone) ...[
                        const SizedBox(height: 8),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: _gasPressureTestController,
                          decoration: const InputDecoration(
                            labelText: 'Gas Pressure Test Results',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      CheckboxListTile(
                        title: const Text('Gas Leak Test'),
                        value: _gasLeakTestDone,
                        onChanged: (value) =>
                            setState(() => _gasLeakTestDone = value!),
                      ),
                      if (_gasLeakTestDone) ...[
                        const SizedBox(height: 8),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: _gasLeakTestController,
                          decoration: const InputDecoration(
                            labelText: 'Gas Leak Test Results',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      CheckboxListTile(
                        title: const Text('Ventilation Check'),
                        value: _ventilationTestDone,
                        onChanged: (value) =>
                            setState(() => _ventilationTestDone = value!),
                      ),
                      if (_ventilationTestDone) ...[
                        const SizedBox(height: 8),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: _ventilationController,
                          decoration: const InputDecoration(
                            labelText: 'Ventilation Check Results',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      CheckboxListTile(
                        title: const Text('Appliance Commissioning'),
                        value: _applianceTestDone,
                        onChanged: (value) =>
                            setState(() => _applianceTestDone = value!),
                      ),
                      if (_applianceTestDone) ...[
                        const SizedBox(height: 8),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: _applianceCommissioningController,
                          decoration: const InputDecoration(
                            labelText: 'Appliance Commissioning Details',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Practitioner Details Section
                  _buildSectionCard(
                    title: 'Gas Fitter Details',
                    icon: Icons.person,
                    children: [
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _userNameController,
                        decoration: const InputDecoration(
                          labelText: 'Gas Fitter Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _userLicenseController,
                        decoration: const InputDecoration(
                          labelText: 'License Number *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _userPhoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: _userEmailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Date Information Section
                  _buildSectionCard(
                    title: 'Date Information',
                    icon: Icons.calendar_today,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Work Start Date',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _selectDate(context, true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today,
                                            size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Text(
                                          _testStartDate != null
                                              ? DateFormat('dd/MM/yyyy')
                                                  .format(_testStartDate!)
                                              : 'Select Date',
                                          style: TextStyle(
                                            color: _testStartDate != null
                                                ? Colors.black
                                                : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Work End Date',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _selectDate(context, false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today,
                                            size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Text(
                                          _testEndDate != null
                                              ? DateFormat('dd/MM/yyyy')
                                                  .format(_testEndDate!)
                                              : 'Select Date',
                                          style: TextStyle(
                                            color: _testEndDate != null
                                                ? Colors.black
                                                : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Extra bottom padding for better scrolling
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),

          // Bottom button area within SafeArea to avoid system nav overlap
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 28),
                    label: const Text('Generate Gas COC Certificate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      textStyle: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    onPressed: _generateGasCocCertificate,
                  ),
                  const SizedBox(height: 16), // Extra space at bottom
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceChip(
      String label, String selectedValue, ValueChanged<String> onSelected) {
    final isSelected = selectedValue == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          onSelected(label);
        }
      },
      selectedColor: Colors.orange.withOpacity(0.3),
      backgroundColor: Colors.grey.withOpacity(0.1),
      labelStyle: TextStyle(
        color: isSelected ? Colors.orange.shade700 : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
}
