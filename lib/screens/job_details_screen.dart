import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'dart:async';
import 'estimate_builder_screen.dart';
import 'pricebook_screen.dart';
import 'coc_form_screen.dart';
import 'esc_form_screen.dart';
import 'roi_form_screen.dart';
import 'gas_coc_form_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/job.dart' as job_model;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter/services.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../models/estimate_build.dart';
import '../models/estimate_version.dart';
import '../models/estimate_template.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/voice_text_field.dart';
import '../services/firestore_service.dart';
import '../services/sync_scheduler.dart';
import '../services/storage_strategy_service.dart';
import '../services/in_progress_build_service.dart';
import '../models/in_progress_build.dart';

final Map<String, Map<String, Offset>> certificateFieldPositions = {
  'COC': {
    'Reference': Offset(243, 45),
    'CompanyName': Offset(50, 20),
    'CompanyAddress': Offset(50, 35),
    'Address': Offset(134, 88),
    'CustomerName': Offset(134, 105),
    'Name': Offset(134, 198),
    'LicenceNumber': Offset(300, 198),
    'CompletionDate': Offset(380, 700),
    'SigningDate': Offset(290, 786),
    'Date2': Offset(290, 786),
    'Date1': Offset(380, 700),
    'Date3': Offset(454, 786),
    'Signature': Offset(350, 750),
  },
  'ESC': {
    'Reference': Offset(305, 62),
    'CompanyName': Offset(50, 20),
    'CompanyAddress': Offset(50, 35),
    'Address': Offset(150, 132),
    'CustomerName': Offset(150, 150),
    'Name': Offset(147, 175),
    'LicenceNumber': Offset(300, 175),
    'CompletionDate': Offset(150, 583),
    'SigningDate': Offset(400, 690),
    'Date1': Offset(150, 583),
    'Date2': Offset(400, 690),
    'Signature': Offset(300, 650),
  },
  'ROI': {
    'Reference': Offset(274, 80),
    'CompanyName': Offset(50, 20),
    'CompanyAddress': Offset(50, 35),
    'Address': Offset(128, 183),
    'CustomerName': Offset(128, 200),
    'Name': Offset(128, 220),
    'LicenceNumber': Offset(300, 220),
    'CompletionDate': Offset(427, 780),
    'SigningDate': Offset(427, 800),
    'Date1': Offset(427, 780),
    'Signature': Offset(300, 750),
  },
};

class JobDetailsScreen extends StatefulWidget {
  final job_model.Job job;
  final List<PriceBookItem> priceBook;

  const JobDetailsScreen({super.key, required this.job, required this.priceBook});

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> {
  List<String> notes = [];
  final noteController = TextEditingController();
  List<EstimateTemplate> _templates = [];
  List<EstimateVersion> inProgressBuilds = [];
  bool _editing = false;
  late TextEditingController _titleController;
  late TextEditingController _descController;
  
  // Auto-save functionality
  Timer? _saveDebounce;

  Future<EstimateTemplate?> showTemplatePickerDialog(BuildContext context, List<EstimateTemplate> templates) async {
    // Always include a blank template option
    final blankTemplate = EstimateTemplate(
      name: 'Blank Template',
      items: [],
      subsections: ['Labour', 'Materials'],
    );
    
    final allTemplates = [blankTemplate, ...templates];
    
    return showDialog<EstimateTemplate>(
      context: context,
      builder: (context) => _TemplatePickerDialog(templates: allTemplates),
    );
  }

  @override
  void initState() {
    super.initState();
    notes = List<String>.from(widget.job.notes ?? []);
    _loadTemplates();
    _loadInProgressBuilds();
    _titleController = TextEditingController(text: widget.job.title);
    _descController = TextEditingController(text: widget.job.description ?? '');
    // Sync invoice data when screen loads
    widget.job.syncInvoices();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _saveTitleAndDescription() async {
    setState(() {
      widget.job.title = _titleController.text;
      widget.job.description = _descController.text;
      _editing = false;
    });
    _markDirtyAndAutoSave();
    if (mounted) Navigator.pop(context, true); // Go back to jobs screen
  }

  Future<void> _loadTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('estimate_templates') ?? [];
    setState(() {
      _templates = jsonList.map((s) => EstimateTemplate.fromJson(jsonDecode(s))).toList();
    });
  }

  void _loadInProgressBuilds() async {
    // Load in-progress builds from the proper service
    try {
      final builds = await InProgressBuildService.getBuildsForJob(widget.job.id);
      setState(() {
        // Convert InProgressBuild to EstimateVersion for compatibility
        inProgressBuilds = builds.map((build) => EstimateVersion(
          id: build.id,
          type: 'in_progress',
          timestamp: build.lastModified,
          items: build.currentVersion.items,
          status: 'in_progress',
          amount: build.currentVersion.totalAmount,
          profit: build.currentVersion.totalProfit,
        )).toList();
      });
    } catch (e) {
      setState(() {
        inProgressBuilds = [];
      });
    }
  }

  Future<void> _saveJob() async {
    try {
      // Sync invoices before saving
      widget.job.syncInvoices();
      widget.job.notes = notes;
      
      // Save to local file for backward compatibility
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/job_${widget.job.id}.json');
      await file.writeAsString(jsonEncode(widget.job.toJson()));
      
      // Save to cloud using hybrid storage system
      await FirestoreService.saveJob(widget.job);
      
      // Trigger sync through scheduler for optimal cloud sync
      await SyncScheduler.syncNow(DataType.jobs);
      
    } catch (e) {
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
    _debouncedSave();
  }

  Future<void> _reloadJob() async {
    try {
      // First try to load from Firestore (cloud) to get the latest data
      final cloudJob = await FirestoreService.getJob(widget.job.id);
      
      if (cloudJob != null) {
        setState(() {
          widget.job.estimateVersions = cloudJob.estimateVersions;
          widget.job.attachments = cloudJob.attachments;
          widget.job.notes = cloudJob.notes;
          // Update other relevant fields
        });
        // Also reload in-progress builds after updating job data
        _loadInProgressBuilds();
        return;
      }
    } catch (e) {
      // Handle error
    }

    // Fallback to local files - try main jobs.json first for consistency
    final dir = await getApplicationDocumentsDirectory();
    final mainJobsFile = File('${dir.path}/jobs.json');
    
    if (await mainJobsFile.exists()) {
      try {
        final jsonString = await mainJobsFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final jobData = jsonList.firstWhere((j) => j['id'] == widget.job.id, orElse: () => null);
        
        if (jobData != null) {
          final updatedJob = job_model.Job.fromJson(jobData);
          setState(() {
            widget.job.estimateVersions = updatedJob.estimateVersions;
            widget.job.attachments = updatedJob.attachments;
            widget.job.notes = updatedJob.notes;
            // Sync invoices to ensure consistency
            widget.job.syncInvoices();
          });
          return;
        }
      } catch (e) {
      }
    }
    
    // Final fallback to individual job file
    final jobFile = File('${dir.path}/job_${widget.job.id}.json');
    if (await jobFile.exists()) {
      final jsonString = await jobFile.readAsString();
      final updatedJob = job_model.Job.fromJson(jsonDecode(jsonString));
      setState(() {
        widget.job.estimateVersions = updatedJob.estimateVersions;
        widget.job.attachments = updatedJob.attachments;
        widget.job.notes = updatedJob.notes;
        widget.job.syncInvoices();
      });
    }
    
    // Always refresh in-progress builds when reloading job
    _loadInProgressBuilds();
  }

  Future<void> _emailCustomer() async {
    final email = widget.job.customerEmail;
    if (email == null || email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email address available for this customer.')),
      );
      return;
    }
    final customerFirstName = (widget.job.customerName ?? '').split(' ').first;
    final attachments = widget.job.attachments ?? [];

    // Pick attachments
    List<String> selectedAttachments = [];
    if (attachments.isNotEmpty) {
      selectedAttachments = await showDialog<List<String>>(
        context: context,
        builder: (context) {
          final selected = <String>{};
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Select Attachments'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: attachments.map((file) {
                    return CheckboxListTile(
                      value: selected.contains(file),
                      title: Text(file.split('/').last),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            selected.add(file);
                          } else {
                            selected.remove(file);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, <String>[]),
                  child: const Text('None'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected.toList()),
                  child: const Text('Attach Selected'),
                ),
              ],
            ),
          );
        },
      ) ?? [];
    }

    // Prefill subject/body
    final emailType = getEmailTypeFromAttachments(selectedAttachments);
    final prefill = await getPrefilledEmail(
      emailType: emailType,
      customerFirstName: customerFirstName,
    );
    final subjectController = TextEditingController(text: prefill['subject']);
    final bodyController = TextEditingController(text: prefill['body']);

    // Edit dialog
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(labelText: 'Body'),
              maxLines: 10,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (shouldSend == true) {
      final delay = await showDelayPickerDialog(context);
      if (delay == null) return;
      if (delay > Duration.zero) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email will be sent in ${delay.inMinutes} minutes')),
        );
        await Future.delayed(delay);
      }
      
      try {
        await sendEmailViaSmtp(
          toEmail: email,
          subject: subjectController.text,
          body: bodyController.text,
          attachmentPaths: selectedAttachments,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email sent successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send email: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _showCertificateTypePicker() async {
    // Check available licenses
    final prefs = await SharedPreferences.getInstance();
    final hasElectricalLicense = (prefs.getString('electrical_license') ?? '').isNotEmpty;
    final hasGasLicense = (prefs.getString('gas_fitting_license') ?? '').isNotEmpty;
    
    // Build list of available certificate options
    List<Widget> certificateOptions = [];
    
    if (hasElectricalLicense) {
      certificateOptions.addAll([
        ListTile(
          leading: const Icon(Icons.assignment),
          title: const Text('ESC'),
          onTap: () => Navigator.pop(context, 'ESC'),
        ),
        ListTile(
          leading: const Icon(Icons.assignment),
          title: const Text('COC'),
          onTap: () => Navigator.pop(context, 'COC'),
        ),
        ListTile(
          leading: const Icon(Icons.assignment),
          title: const Text('ROI'),
          onTap: () => Navigator.pop(context, 'ROI'),
        ),
      ]);
    }
    
    if (hasGasLicense) {
      certificateOptions.add(
        ListTile(
          leading: const Icon(Icons.local_gas_station, color: Colors.orange),
          title: const Text('Gas COC'),
          onTap: () => Navigator.pop(context, 'GAS_COC'),
        ),
      );
    }
    
    // Show message if no licenses are available
    if (certificateOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add your license numbers in Settings to generate certificates'),
        ),
      );
      return;
    }
    
    final certType = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 
                  MediaQuery.of(context).padding.bottom + 16.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: certificateOptions,
        ),
      ),
    );
    if (certType != null) {
      await _showCertificateInfoForm(certType);
    }
  }

  Future<void> _showCertificateInfoForm(String certType) async {
    // Special handling for COC certificates - navigate to dedicated form
    if (certType == 'COC') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CocFormScreen(job: widget.job),
        ),
      );
      
      // Reload job details when returning from COC form to refresh attachments
      await _reloadJob();
      setState(() {}); // Force UI refresh to show new attachments
      
      // Show success message if PDF was generated
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('COC PDF generated and added to job attachments!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                // Scroll to attachments section if possible
                // This could be enhanced to jump to the attachments section
              },
            ),
          ),
        );
      }
      return;
    }
    
    // Special handling for Gas COC certificates - navigate to dedicated form
    if (certType == 'GAS_COC') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GasCocFormScreen(job: widget.job),
        ),
      );
      
      // Reload job details when returning from Gas COC form to refresh attachments
      await _reloadJob();
      setState(() {}); // Force UI refresh to show new attachments
      
      // Show success message if PDF was generated
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gas COC PDF generated and added to job attachments!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                // Scroll to attachments section if possible
              },
            ),
          ),
        );
      }
      return;
    }
    
    // Special handling for ESC certificates - navigate to dedicated form
    if (certType == 'ESC') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EscFormScreen(job: widget.job),
        ),
      );
      
      // Reload job details when returning from ESC form to refresh attachments
      await _reloadJob();
      setState(() {}); // Force UI refresh to show new attachments
      
      // Show success message if PDF was generated
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ESC certificate generated and added to job attachments!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // Could implement opening attachments section
              },
            ),
          ),
        );
      }
      return;
    }
    
    // Special handling for ROI certificates - navigate to dedicated form
    if (certType == 'ROI') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RoiFormScreen(job: widget.job),
        ),
      );
      
      // Reload job details when returning from ROI form to refresh attachments
      await _reloadJob();
      setState(() {}); // Force UI refresh to show new attachments
      
      // Show success message if PDF was generated
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ROI certificate generated and added to job attachments!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // Could implement opening attachments section
              },
            ),
          ),
        );
      }
      return;
    }
    
    // Load settings data for other certificate types
    final prefs = await SharedPreferences.getInstance();
    
    // Auto-generate reference ID based on job number
    final jobNumber = widget.job.id;
    final existingCertificates = widget.job.estimateVersions
        .where((v) => v.type == 'certificate' && v.invoiceNumber?.startsWith(certType) == true)
        .length;
    final referenceId = existingCertificates > 0 
        ? '$jobNumber-$certType-${existingCertificates + 1}'
        : '$jobNumber-$certType';

    // Get company and personal settings
    final companyName = prefs.getString('company_name') ?? '';
    final companyAddress = prefs.getString('company_address') ?? '';
    final firstName = prefs.getString('first_name') ?? '';
    final lastName = prefs.getString('last_name') ?? '';
    
    // Get appropriate license based on certificate type
    String licenceNumber = '';
    if (certType == 'GAS_COC') {
      licenceNumber = prefs.getString('gas_fitting_license') ?? '';
    } else {
      // COC, ESC, ROI use electrical license
      licenceNumber = prefs.getString('electrical_license') ?? '';
    }

    // Controllers with pre-filled data
    final companyNameController = TextEditingController(text: companyName);
    final companyAddressController = TextEditingController(text: companyAddress);
    final fullName = '$firstName $lastName'.trim();
    final nameController = TextEditingController(text: fullName);
    final licenceController = TextEditingController(text: licenceNumber);
    final customerNameController = TextEditingController(text: widget.job.customerName ?? '');
    final customerAddressController = TextEditingController(text: widget.job.address ?? '');
    final referenceController = TextEditingController(text: referenceId);
    final certificateNotesController = TextEditingController(); // Certificate notes controller
    
    // Date controllers with today's date as default
    final today = DateTime.now();
    final todayStr = "${today.day}/${today.month}/${today.year}";
    final completionDateController = TextEditingController(text: todayStr);
    final signingDateController = TextEditingController(text: todayStr);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$certType Certificate Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Company Information Section
              const Text('Company Information', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: companyNameController,
                decoration: const InputDecoration(
                  labelText: 'Company Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: companyAddressController,
                decoration: const InputDecoration(
                  labelText: 'Company Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              
              const SizedBox(height: 16),
              
              // Personal Information Section
              const Text('Personal Information', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: licenceController,
                decoration: const InputDecoration(
                  labelText: 'Licence Number',
                  border: OutlineInputBorder(),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Customer Information Section
              const Text('Customer Information', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: customerNameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: customerAddressController,
                decoration: const InputDecoration(
                  labelText: 'Customer Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  helperText: 'For better GPS tracking, use complete addresses with city/country',
                ),
                maxLines: 2,
              ),
              
              const SizedBox(height: 16),
              
              // Certificate Details Section
              const Text('Certificate Details', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'Reference ID',
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 8),
              
              // Completion Date
              TextField(
                controller: completionDateController,
                decoration: const InputDecoration(
                  labelText: 'Completion Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    completionDateController.text =
                        "${picked.day}/${picked.month}/${picked.year}";
                  }
                },
              ),
              const SizedBox(height: 8),
              
              // Signing Date
              TextField(
                controller: signingDateController,
                decoration: const InputDecoration(
                  labelText: 'Signing Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    signingDateController.text =
                        "${picked.day}/${picked.month}/${picked.year}";
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // Certificate Notes Section
              const Text('Certificate Notes', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              VoiceTextField(
                controller: certificateNotesController,
                labelText: 'Certificate Notes',
                hintText: 'Add any additional notes for this certificate...',
                maxLines: 4,
                continuousListening: true, // Enable continuous listening for certificate notes
                onChanged: () {
                  // Auto-save functionality could go here if needed
                },
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
              Navigator.pop(context, {
                'CompanyName': companyNameController.text,
                'CompanyAddress': companyAddressController.text,
                'Name': nameController.text,
                'LicenceNumber': licenceController.text,
                'CustomerName': customerNameController.text,
                'Address': customerAddressController.text,
                'Reference': referenceController.text,
                'CompletionDate': completionDateController.text,
                'SigningDate': signingDateController.text,
                'CertificateNotes': certificateNotesController.text,
              });
            },
            child: const Text('Generate Certificate'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _generateAndSaveCertificate(certType, result);
    }
  }

  Future<void> _generateAndSaveCertificate(String certType, Map<String, String> result) async {
    try {
      // Get the signature file path for inclusion in PDF
      final prefs = await SharedPreferences.getInstance();
      final signaturePath = prefs.getString('signature_path');
      
      // 1. Load the PDF template from assets
      final assetPath = getCertificateAssetPath(certType);
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      // 2. Load the PDF document
      final document = PdfDocument(inputBytes: bytes);

      // 3. Get the field positions for this certType
      final positions = certificateFieldPositions[certType] ?? {};

      // 4. Draw each field at its position
      final page = document.pages[0];
      final font = PdfStandardFont(PdfFontFamily.helvetica, 12);

      result.forEach((field, value) {
        final offset = positions[field];
        if (offset != null) {
          page.graphics.drawString(
            value,
            font,
            bounds: Rect.fromLTWH(offset.dx, offset.dy, 300, 20),
          );
        }
      });

      // 5. Add signature if available
      if (signaturePath != null && await File(signaturePath).exists()) {
        final signatureOffset = positions['Signature'];
        if (signatureOffset != null) {
          final signatureBytes = await File(signaturePath).readAsBytes();
          final signatureImage = PdfBitmap(signatureBytes);
          page.graphics.drawImage(
            signatureImage,
            Rect.fromLTWH(signatureOffset.dx, signatureOffset.dy, 100, 50),
          );
        }
      }

      // 6. Save to job attachments with proper naming
      final output = await getApplicationDocumentsDirectory();
      final customerName = result['CustomerName'] ?? 'Certificate';
      final address = (result['Address'] ?? 'Unknown').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final jobNumber = widget.job.id;
      
      // Check for existing certificates with same name pattern
      final baseName = '$customerName-$jobNumber-$address';
      int count = 1;
      String filePath;

      do {
        filePath = count == 1 
            ? '${output.path}/$baseName-$certType.pdf'
            : '${output.path}/$baseName-$certType-$count.pdf';
        count++;
      } while (await File(filePath).exists());

      final file = File(filePath);
      await file.writeAsBytes(await document.save());
      document.dispose();

      // 7. Add to job attachments
      setState(() {
        widget.job.attachments ??= [];
        widget.job.attachments!.add(file.path);
      });
      
      // 8. Save job with new attachment
      await _saveJob();

      // 9. Handle certificate notes - add to job notes if provided
      final certificateNotes = result['CertificateNotes'];
      if (certificateNotes != null && certificateNotes.trim().isNotEmpty) {
        final formattedNote = '[$certType Certificate - ${result['CompletionDate'] ?? DateTime.now().toString()}] $certificateNotes';
        setState(() {
          widget.job.notes ??= [];
          widget.job.notes!.add(formattedNote);
        });
        await _saveJob(); // Save again with the updated notes
      }

      // 10. Auto-email certificate if enabled
      await _autoEmailCertificateIfEnabled(file.path, certType, result);

      // 11. Reload job to ensure consistency and refresh attachments display
      await _reloadJob();
      setState(() {}); // Force UI refresh to show new attachments

      // 12. Show success and open file
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Certificate saved to job attachments'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => OpenFile.open(file.path),
            ),
          ),
        );
      }
      
      await OpenFile.open(file.path);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating certificate: $e')),
        );
      }
    }
  }

  Future<void> _autoEmailCertificateIfEnabled(String filePath, String certType, Map<String, String> certificateData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoEmailEnabled = prefs.getBool('auto_email_certificates') ?? false;
      final hasAcceptedTerms = prefs.getBool('has_accepted_terms') ?? false;
      
      if (!autoEmailEnabled || !hasAcceptedTerms) {
        return; // Don't send email if not enabled or terms not accepted
      }

      final personalEmail = prefs.getString('personal_email') ?? '';
      if (personalEmail.isEmpty) {
        return;
      }

      // Prepare email content
      final customerName = certificateData['CustomerName'] ?? 'Unknown';
      final jobNumber = widget.job.id;
      final companyName = prefs.getString('company_name') ?? 'Company';
      
      final subject = '$certType Certificate - $customerName (Job: $jobNumber)';
      final body = '''
Hello,

A new $certType certificate has been generated and is attached to this email.

Certificate Details:
- Customer: $customerName
- Job Number: $jobNumber
- Certificate Type: $certType
- Reference ID: ${certificateData['Reference'] ?? 'N/A'}
- Completion Date: ${certificateData['CompletionDate'] ?? 'N/A'}
- Signing Date: ${certificateData['SigningDate'] ?? 'N/A'}

This email was sent automatically as part of your record keeping preferences.

Best regards,
$companyName
''';

      // Send email with certificate attachment
      await sendEmailViaSmtp(
        toEmail: personalEmail,
        subject: subject,
        body: body,
        attachmentPaths: [filePath],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Certificate emailed to $personalEmail'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Certificate saved but email failed: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _showVersionsDialog() async {
    try {
      // Load in-progress builds for this job
      final builds = await InProgressBuildService.getBuildsForJob(widget.job.id);
      
      if (builds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No estimate versions found for this job')),
        );
        return;
      }

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estimate Versions'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: builds.length,
              itemBuilder: (context, index) {
                final build = builds[index];
                final versions = build.sortedVersions; // Use sortedVersions property
                
                return ExpansionTile(
                  title: Text('Build: ${build.name}'), // Use name property
                  subtitle: Text('${versions.length} version(s) • Current: v${build.currentVersionId}'),
                  children: versions.map((version) {
                    final isLatest = version.id == build.currentVersionId;
                    return ListTile(
                      leading: Icon(
                        isLatest ? Icons.star : Icons.history,
                        color: isLatest ? Colors.amber : null,
                      ),
                      title: Text('Version ${version.id}'),
                      subtitle: Text(
                        'Created: ${DateFormat('MMM dd, yyyy HH:mm').format(version.createdAt)}', // Use createdAt
                      ),
                      trailing: isLatest 
                        ? const Chip(label: Text('Current'))
                        : null,
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EstimateBuilderScreen(
                              job: widget.job,
                              initialItems: version.items,
                            ),
                          ),
                        );
                        await _reloadJob();
                        setState(() {});
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading versions: $e')),
      );
    }
  }

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Job'),
        content: Text('Are you sure you want to delete "${widget.job.title}"?\n\nThis will also delete all estimate versions and cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete all in-progress builds for this job
        await InProgressBuildService.deleteAllBuildsForJob(widget.job.id);
        
        // TODO: Delete the job itself from your job storage
        // This depends on how jobs are stored in your app
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job and all versions deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Go back to previous screen
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting job: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final invoices = job.invoiceVersions; // Use invoiceVersions instead of invoices
    final estimates = job.estimates;
    final attachments = job.attachments ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'versions':
                  await _showVersionsDialog();
                  break;
                case 'delete':
                  await _showDeleteDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'versions',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Versions'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // --- JOB NAME AND DESCRIPTION SECTION ---
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _editing
                          ? TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Job Name',
                              ),
                            )
                          : Text(
                              job.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    IconButton(
                      icon: Icon(_editing ? Icons.close : Icons.edit),
                      tooltip: _editing ? 'Cancel' : 'Edit',
                      onPressed: () {
                        setState(() {
                          if (_editing) {
                            // Cancel editing, reset controllers
                            _titleController.text = job.title;
                            _descController.text = job.description ?? '';
                          }
                          _editing = !_editing;
                        });
                      },
                    ),
                  ],
                ),
                if (_editing)
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Job Description (optional)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  )
                else if ((job.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
                    child: Text(
                      job.description!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                if (_editing)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        onPressed: _saveTitleAndDescription,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () {
                          setState(() {
                            _editing = false;
                            _titleController.text = job.title;
                            _descController.text = job.description ?? '';
                          });
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
            ),
            // --- CUSTOMER DETAILS SECTION ---
            Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text('Customer: ${job.customerName}'),
                subtitle: job.address != null && job.address!.isNotEmpty
                    ? Row(
                        children: [
                          Expanded(child: Text('Address: ${job.address}')),
                          IconButton(
                            icon: const Icon(Icons.map),
                            tooltip: 'Open in Maps',
                            onPressed: () async {
                              final encoded = Uri.encodeComponent(job.address!);
                              final url = 'https://www.google.com/maps/search/?api=1&query=$encoded';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ],
                      )
                    : null,
              ),
            ),

            // 2. BUILDER BUTTON
            ElevatedButton.icon(
              icon: const Icon(Icons.build),
              label: const Text('Builder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: () async {
                // Show template picker dialog
                final selectedTemplate = await showTemplatePickerDialog(context, _templates);
                if (selectedTemplate != null) {
                  // Navigate to builder with selected template
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EstimateBuilderScreen(
                        job: widget.job,
                        initialTemplate: selectedTemplate,
                      ),
                    ),
                  );
                  await _reloadJob();
                  // Refresh the in-progress builds display
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 24),

            // --- In Progress Builds SECTION (styled like Invoices/Estimates) ---
            Row(
              children: [
                Text('In Progress Builds', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh builds',
                  onPressed: () => setState(() {}), // Refresh the FutureBuilder
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Debug builds',
                  onPressed: () async {
                    final builds = await InProgressBuildService.getBuildsForJob(widget.job.id);
                    final allBuilds = await InProgressBuildService.loadAllBuilds();
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Debug Info'),
                        content: SingleChildScrollView(
                          child: Text(
                            'Job ID: ${widget.job.id}\n'
                            'Builds for this job: ${builds.length}\n'
                            'Total builds in system: ${allBuilds.length}\n\n'
                            'Job builds:\n${builds.map((b) => '- ${b.name} (${b.versions.length} versions)').join('\n')}\n\n'
                            'All builds:\n${allBuilds.map((b) => '- Job ${b.jobId}: ${b.name}').join('\n')}',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            FutureBuilder<List<InProgressBuild>>(
              future: InProgressBuildService.getBuildsForJob(widget.job.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Error loading builds: ${snapshot.error}',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }
                
                final builds = snapshot.data ?? [];
                
                if (builds.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No in-progress builds.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                
                return Column(
                  children: builds.map((build) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text('In-Progress Build ${builds.indexOf(build) + 1}'),
                      subtitle: Text(
                        'Last modified: ${DateFormat('MMM dd, yyyy HH:mm').format(build.lastModified)}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') {
                            // Navigate to resume editing this in-progress build
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EstimateBuilderScreen(
                                  job: widget.job,
                                  initialItems: build.currentVersion.items,
                                ),
                              ),
                            );
                            // Refresh job details and in-progress builds display
                            await _reloadJob();
                            setState(() {});
                          } else if (action == 'versions') {
                            // Show versions dialog
                            await showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Build Versions'),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  height: 300,
                                  child: ListView.builder(
                                    itemCount: build.versions.length,
                                    itemBuilder: (context, index) {
                                      final version = build.versions[index];
                                      final isLatest = version.id == build.currentVersionId;
                                      return ListTile(
                                        leading: Icon(
                                          isLatest ? Icons.star : Icons.history,
                                          color: isLatest ? Colors.amber : null,
                                        ),
                                        title: Text('Version ${version.id}'),
                                        subtitle: Text(
                                          'Created: ${DateFormat('MMM dd, yyyy HH:mm').format(version.createdAt)}',
                                        ),
                                        trailing: isLatest 
                                          ? const Chip(label: Text('Current'))
                                          : null,
                                        onTap: () async {
                                          Navigator.pop(context);
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => EstimateBuilderScreen(
                                                job: widget.job,
                                                initialItems: version.items,
                                              ),
                                            ),
                                          );
                                          await _reloadJob();
                                          setState(() {});
                                        },
                                      );
                                    },
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          } else if (action == 'delete') {
                            // Confirm deletion
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Build'),
                                content: const Text('Are you sure you want to delete this in-progress build? This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                await InProgressBuildService.deleteBuild(build.id);
                                await _reloadJob();
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Build deleted successfully')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to delete build: $e')),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'versions',
                            child: Row(
                              children: [
                                Icon(Icons.history),
                                SizedBox(width: 8),
                                Text('Versions'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        // Navigate to resume editing this in-progress build
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EstimateBuilderScreen(
                              job: widget.job,
                              initialItems: build.currentVersion.items,
                            ),
                          ),
                        );
                        // Refresh job details and in-progress builds display
                        await _reloadJob();
                        setState(() {});
                      },
                    ),
                  )).toList(),
                );
              },
            ),
            const Divider(height: 32),

            // 3. INVOICES SECTION
            Text('Invoices', style: Theme.of(context).textTheme.titleLarge),
            ...invoices.map((invoice) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(invoice.invoiceNumber ?? invoice.id ?? "Invoice"),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Due: ${formatDate(invoice.dueDate)}'),
                    Text('Amount: \$${invoice.amount.toStringAsFixed(2)}'),
                    Text('Status: ${invoice.isPaid ? "Paid" : invoice.isArchived ? "Archived" : "Unpaid"}'),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'pdf' && invoice.filePath != null) {
                      OpenFile.open(invoice.filePath!);
                    } else if (action == 'builder') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EstimateBuilderScreen(
                            job: widget.job,
                            initialItems: invoice.items,
                            initialSubsections: invoice.sections,
                          ),
                        ),
                      );
                      await _reloadJob();
                      setState(() {});
                    } else if (action == 'paid') {
                      setState(() => invoice.isPaid = true);
                      _markDirtyAndAutoSave();
                    } else if (action == 'void') {
                      setState(() => invoice.isArchived = true);
                      _markDirtyAndAutoSave();
                    } else if (action == 'archive') {
                      setState(() => invoice.isArchived = true);
                      _markDirtyAndAutoSave();
                    } else if (action == 'due') {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: invoice.dueDate ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                      );
                      setState(() => invoice.dueDate = picked);
                      _markDirtyAndAutoSave();
                    }
                  },
                  itemBuilder: (context) => [
                    if (invoice.filePath != null)
                      const PopupMenuItem(value: 'pdf', child: Text('Open PDF')),
                    const PopupMenuItem(value: 'builder', child: Text('Open in Builder')),
                    if (!invoice.isPaid)
                      const PopupMenuItem(value: 'paid', child: Text('Mark as Paid')),
                    if (!invoice.isArchived)
                      const PopupMenuItem(value: 'void', child: Text('Void Invoice')),
                    if (!invoice.isArchived)
                      const PopupMenuItem(value: 'archive', child: Text('Archive Invoice')),
                    const PopupMenuItem(value: 'due', child: Text('Change Due Date')),
                  ],
                ),
              ),
            )),
            const Divider(height: 32),

            // 4. QUOTES/ESTIMATES SECTION
            Text('Quotes / Estimates', style: Theme.of(context).textTheme.titleLarge),
            ...estimates.map((estimate) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text('${estimate.documentNumber ?? estimate.type}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!estimate.isConverted)
                      Text(
                        'Expires: ${formatDate(estimate.expiryDate)}',
                        style: TextStyle(
                          color: (estimate.expiryDate != null && estimate.expiryDate!.isBefore(DateTime.now()))
                              ? Colors.red
                              : null,
                        ),
                      ),
                    if (estimate.isConverted)
                      const Text('Converted to Invoice', style: TextStyle(color: Colors.green)),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'pdf' && estimate.filePath != null) {
                      OpenFile.open(estimate.filePath!);
                    } else if (action == 'builder') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EstimateBuilderScreen(
                            job: widget.job,
                            initialItems: estimate.items,
                            initialSubsections: estimate.sections,
                          ),
                        ),
                      );
                      await _reloadJob();
                      setState(() {});
                    } else if (action == 'convert') {
                      setState(() => estimate.isConverted = true);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EstimateBuilderScreen(
                            job: widget.job,
                            initialItems: estimate.items,
                            initialSubsections: estimate.sections,
                            convertToInvoice: true,
                          ),
                        ),
                      );
                      await _reloadJob();
                      setState(() {});
                    }
                  },
                  itemBuilder: (context) => [
                    if (estimate.filePath != null)
                      const PopupMenuItem(value: 'pdf', child: Text('Open PDF')),
                    const PopupMenuItem(value: 'builder', child: Text('Open in Builder')),
                    if (!estimate.isConverted)
                      const PopupMenuItem(value: 'convert', child: Text('Convert to Invoice')),
                  ],
                ),
              ),
            )),
            const Divider(height: 32),

            // 5. JOB NOTES SECTION
            Text('Job Notes', style: Theme.of(context).textTheme.titleLarge),
            ...notes.asMap().entries.map((entry) {
  final idx = entry.key;
  final note = entry.value;
  return InkWell(
    onTap: () async {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Note?'),
          content: Text(note),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (shouldDelete == true) {
        setState(() {
          notes.removeAt(idx);
        });
        await _saveJob();
      }
    },
    child: ListTile(
      leading: const Icon(Icons.note),
      title: Text(note),
    ),
  );
}),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      hintText: 'Add a note...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    if (noteController.text.trim().isNotEmpty) {
                      setState(() {
                        notes.add(noteController.text.trim());
                        noteController.clear();
                      });
                      _markDirtyAndAutoSave();
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 32),

            // 6. ATTACHMENTS SECTION
            Text('Attachments', style: Theme.of(context).textTheme.titleLarge),
            ...attachments.map((file) => ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(file.split('/').last),
              onTap: () => OpenFile.open(file),
            )),
            TextButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Add Attachment'),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: false,
                  type: FileType.any,
                );
                if (result != null && result.files.single.path != null) {
                  setState(() {
                    job.attachments ??= [];
                    job.attachments!.add(result.files.single.path!);
                  });
                  await _saveJob();
                }
              },
            ),
            const SizedBox(height: 32),

            // 7. CREATE CERTIFICATE SECTION
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Create Certificate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _showCertificateTypePicker,
            ),

            // --- Add more space between certificate and email button ---
            const SizedBox(height: 40), // Increase this value for more space

            // 8. EMAIL CUSTOMER BUTTON AT BOTTOM
            ElevatedButton.icon(
              icon: const Icon(Icons.email, size: 28),
              label: const Text('Email Customer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _emailCustomer,
            ),

            // Extra bottom padding for better mobile accessibility
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

Future<void> openCertificateAsset(String assetPath) async {
  // Load asset as bytes
  ByteData data = await rootBundle.load(assetPath);
  Uint8List bytes = data.buffer.asUint8List();

  // Save to a temp file
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${assetPath.split('/').last}');
  await file.writeAsBytes(bytes);

  // Open with default PDF app
  await OpenFile.open(file.path);
}

// Map your certType to asset path
String getCertificateAssetPath(String certType) {
  switch (certType) {
    case 'COC':
      return 'assets/certificates/COC EWRB NZ.pdf';
    case 'GAS_COC':
      return 'assets/certificates/GAS COC and GAS SAFTEY NZ.pdf';
    case 'ESC':
      return 'assets/certificates/ESC EWRB NZ.pdf';
    case 'ROI':
      return 'assets/certificates/ROI EWRB NZ.pdf';
    default:
      throw Exception('Unknown certificate type');
  }
}

Future<void> fillAndOpenCertificatePdf(String certType, Map<String, String> fields) async {
  // 1. Load the PDF template from assets
  final assetPath = getCertificateAssetPath(certType);
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List();

  // 2. Load the PDF document
  final document = PdfDocument(inputBytes: bytes);

  // 3. Get the field positions for this certType
  final positions = certificateFieldPositions[certType] ?? {};

  // 4. Draw each field at its position
  final page = document.pages[0];
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);

  fields.forEach((field, value) {
    final offset = positions[field];
    if (offset != null) {
      page.graphics.drawString(
        value,
        font,
        bounds: Rect.fromLTWH(offset.dx, offset.dy, 300, 20),
      );
    }
  });

  // 5. Save to file (in your job's attachments directory)
  final output = await getApplicationDocumentsDirectory();
  final address = (fields['Address'] ?? 'certificate').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'); // sanitize filename
  final baseName = '$certType $address';
  int count = 1;
  String filePath;

  do {
    filePath = '${output.path}/$baseName ($count).pdf';
    count++;
  } while (await File(filePath).exists());

  final file = File(filePath);
  await file.writeAsBytes(await document.save());
  document.dispose();

  // Attach to job, open, etc.
  await OpenFile.open(file.path);
}

Future<void> createCertificateFlow(BuildContext context, job_model.Job job) async {
  // Check available licenses
  final prefs = await SharedPreferences.getInstance();
  final hasElectricalLicense = (prefs.getString('electrical_license') ?? '').isNotEmpty;
  final hasGasLicense = (prefs.getString('gas_fitting_license') ?? '').isNotEmpty;
  
  // Build list of available certificate options
  List<Widget> certificateOptions = [];
  
  if (hasElectricalLicense) {
    certificateOptions.addAll([
      ListTile(
        leading: Icon(Icons.assignment),
        title: Text('ESC'),
        onTap: () => Navigator.pop(context, 'ESC'),
      ),
      ListTile(
        leading: Icon(Icons.assignment),
        title: Text('COC'),
        onTap: () => Navigator.pop(context, 'COC'),
      ),
      ListTile(
        leading: Icon(Icons.assignment),
        title: Text('ROI'),
        onTap: () => Navigator.pop(context, 'ROI'),
      ),
    ]);
  }
  
  if (hasGasLicense) {
    certificateOptions.add(
      ListTile(
        leading: Icon(Icons.local_gas_station, color: Colors.orange),
        title: Text('Gas COC'),
        onTap: () => Navigator.pop(context, 'GAS_COC'),
      ),
    );
  }
  
  // Show message if no licenses are available
  if (certificateOptions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please add your license numbers in Settings to generate certificates'),
      ),
    );
    return;
  }
  
  // 1. Select certificate type
  final certType = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 
                MediaQuery.of(context).padding.bottom + 16.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: certificateOptions,
      ),
    ),
  );
  if (certType == null) return;

  // 2. Confirm/edit customer info (replace with your own UI as needed)
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Confirm Customer Info'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Name: ${job.customerName}'),
          Text('Address: ${job.address}'),
          // Add more fields as needed
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text('Continue')),
      ],
    ),
  );
  if (confirmed != true) return;

  // 3. Prepare fields for PDF
  final fields = {
    'Name': job.customerName ?? '',
    'Address': job.address ?? '',
    // Add more fields as needed, matching your certificateFieldPositions
  };

  // 4. Fill and save PDF
  final pdfPath = await fillAndSaveCertificatePdf(certType, fields, job.id);

  // 5. Attach PDF to job (implement this in your job model/storage)
  await attachPdfToJob(job.id, pdfPath);

  // 6. Open PDF in external editor
  await OpenFile.open(pdfPath);
}

// Helper: Fill and save PDF, return file path
Future<String> fillAndSaveCertificatePdf(String certType, Map<String, String> fields, String jobId) async {
  try {
    
    // Get the documents directory
    final directory = await getApplicationDocumentsDirectory();
    final certificatesDir = Directory('${directory.path}/certificates');
    if (!await certificatesDir.exists()) {
      await certificatesDir.create(recursive: true);
    }
    
    // Create a simple PDF document using syncfusion_flutter_pdf
    final PdfDocument document = PdfDocument();
    final PdfPage page = document.pages.add();
    final PdfGraphics graphics = page.graphics;
    
    // Set up fonts and layout
    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 24, style: PdfFontStyle.bold);
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
    
    double yPosition = 50;
    
    // Title
    graphics.drawString(
      '$certType Certificate',
      titleFont,
      bounds: Rect.fromLTWH(0, yPosition, page.getClientSize().width, 30),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );
    yPosition += 60;
    
    // Job Information
    graphics.drawString(
      'Job Information',
      headerFont,
      bounds: Rect.fromLTWH(20, yPosition, 200, 20),
    );
    yPosition += 30;
    
    graphics.drawString(
      'Job ID: $jobId',
      bodyFont,
      bounds: Rect.fromLTWH(20, yPosition, 300, 15),
    );
    yPosition += 20;
    
    graphics.drawString(
      'Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
      bodyFont,
      bounds: Rect.fromLTWH(20, yPosition, 300, 15),
    );
    yPosition += 40;
    
    // Certificate Fields
    graphics.drawString(
      'Certificate Details',
      headerFont,
      bounds: Rect.fromLTWH(20, yPosition, 200, 20),
    );
    yPosition += 30;
    
    // Add all the fields from the form
    fields.forEach((key, value) {
      if (value.isNotEmpty) {
        graphics.drawString(
          '$key: $value',
          bodyFont,
          bounds: Rect.fromLTWH(20, yPosition, page.getClientSize().width - 40, 15),
        );
        yPosition += 20;
      }
    });
    
    // Add signature area
    yPosition += 40;
    graphics.drawString(
      'Authorized Signature',
      headerFont,
      bounds: Rect.fromLTWH(20, yPosition, 200, 20),
    );
    yPosition += 40;
    
    // Draw signature line
    graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0)),
      Offset(20, yPosition),
      Offset(300, yPosition),
    );
    yPosition += 20;
    
    graphics.drawString(
      'Date: _________________',
      bodyFont,
      bounds: Rect.fromLTWH(20, yPosition, 200, 15),
    );
    
    // Generate timestamp-based filename
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${jobId}_${certType}_$timestamp.pdf';
    final file = File('${certificatesDir.path}/$fileName');
    
    // Save the document
    final List<int> bytes = await document.save();
    await file.writeAsBytes(bytes);
    
    // Clean up
    document.dispose();
    
    return file.path;
    
  } catch (e) {
    throw Exception('Failed to create certificate PDF: $e');
  }
}

// Attach PDF to job by adding it to job attachments
Future<void> attachPdfToJob(String jobId, String pdfPath) async {
  try {
    
    // Load all jobs to find and update the specific job
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/jobs.json');
    
    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final jobs = jsonList.map((e) => job_model.Job.fromJson(e)).toList();
      
      // Find the job and update its attachments
      final jobIndex = jobs.indexWhere((job) => job.id == jobId);
      if (jobIndex != -1) {
        final currentJob = jobs[jobIndex];
        final currentAttachments = currentJob.attachments ?? [];
        final updatedJob = currentJob.copyWith(
          attachments: [...currentAttachments, pdfPath],
        );
        jobs[jobIndex] = updatedJob;
        
        // Save the updated jobs list
        final updatedJsonList = jobs.map((job) => job.toJson()).toList();
        await file.writeAsString(jsonEncode(updatedJsonList));
        
      } else {
        throw Exception('Job not found: $jobId');
      }
    } else {
      throw Exception('Jobs file not found');
    }
    
  } catch (e) {
    throw Exception('Failed to attach PDF to job: $e');
  }
}

// Example usage in a button:
// ElevatedButton(
//   onPressed: () async {
//     await sendEmail(
//       to: 'test@example.com',
//       subject: 'Test Subject',
//       body: 'Hello from Flutter!',
//       // attachments: ['/path/to/file.pdf'],
//     );
//   },
//   child: Text('Send Email'),
// )
Future<void> sendEmailViaSmtp({
  required String toEmail,
  required String subject,
  required String body,
  List<String>? attachmentPaths, // Pass file paths here if needed
}) async {
  
  // Load SMTP settings from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final smtpEmail = prefs.getString('smtp_email') ?? '';
  final smtpPassword = prefs.getString('smtp_password') ?? '';
  final smtpServer = (prefs.getString('smtp_server') ?? 'smtp.gmail.com').trim();
  final smtpPort = int.tryParse(prefs.getString('smtp_port') ?? '587') ?? 587;
  final companyName = prefs.getString('company_name') ?? 'Company';
  final mainEmail = prefs.getString('main_email') ?? '';


  if (smtpEmail.isEmpty || smtpPassword.isEmpty) {
    final errorMsg = 'SMTP settings incomplete. Missing: ${smtpEmail.isEmpty ? 'email ' : ''}${smtpPassword.isEmpty ? 'password' : ''}';
    throw Exception('$errorMsg Please configure SMTP settings in Settings.');
  }

  final server = SmtpServer(
    smtpServer,
    port: smtpPort,
    username: smtpEmail,
    password: smtpPassword,
    ssl: smtpPort == 465,
    allowInsecure: false,
  );

  final message = Message()
    ..from = Address(smtpEmail, companyName)
    ..recipients.add(toEmail);

  // Always BCC the main company email if it's different from SMTP email
  if (mainEmail.isNotEmpty && mainEmail != smtpEmail) {
    message.bccRecipients.add(mainEmail);
  }

  message.subject = subject;
  message.text = body;

  // Add attachments if provided
  if (attachmentPaths != null && attachmentPaths.isNotEmpty) {
    for (final path in attachmentPaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          message.attachments.add(FileAttachment(file));
        } else {
        }
      } catch (e) {
      }
    }
  }

  try {
    await send(message, server);
  } on MailerException catch (e) {
    
    // Provide more specific error messages
    String userFriendlyError = 'Failed to send email';
    if (e.message.contains('authentication') || e.message.contains('Invalid login')) {
      userFriendlyError = 'Email authentication failed. Please check your SMTP username and password.';
    } else if (e.message.contains('connection') || e.message.contains('timeout')) {
      userFriendlyError = 'Could not connect to email server. Please check your internet connection and SMTP server settings.';
    } else if (e.message.contains('TLS') || e.message.contains('SSL')) {
      userFriendlyError = 'Secure connection failed. Please verify your SMTP port and security settings.';
    } else if (e.message.contains('recipient')) {
      userFriendlyError = 'Invalid recipient email address.';
    }
    
    throw Exception('$userFriendlyError\n\nTechnical details: ${e.message}');
  } catch (e) {
    throw Exception('Unexpected error sending email: $e');
  }
}

String getEmailTypeFromAttachments(List<String>? attachmentPaths) {
  if (attachmentPaths == null || attachmentPaths.isEmpty) return 'message';

  final lowerNames = attachmentPaths.map((e) => e.toLowerCase()).toList();
  final hasInvoice = lowerNames.any((f) => f.contains('invoice'));
  final hasEstimate = lowerNames.any((f) => f.contains('estimate'));
  final hasQuote = lowerNames.any((f) => f.contains('quote'));

  if (hasInvoice) return 'invoice';
  if (hasEstimate && hasQuote) return 'estimate'; // treat as estimate if both
  if (hasEstimate) return 'estimate';
  if (hasQuote) return 'quote';
  return 'message';
}

Future<Map<String, String>> getPrefilledEmail({
  required String emailType,
  required String customerFirstName,
  String? companyName,
  String? firstName,
  String? lastName,
  String? mainEmail,
}) async {
  // Load settings if not provided
  final prefs = await SharedPreferences.getInstance();
  final finalCompanyName = companyName ?? prefs.getString('company_name') ?? 'Company';
  final finalFirstName = firstName ?? prefs.getString('first_name') ?? 'Team';
  final finalLastName = lastName ?? prefs.getString('last_name') ?? '';
  final finalMainEmail = mainEmail ?? prefs.getString('main_email') ?? '';
  final reviewLink = prefs.getString('review_link') ?? '';
  
  // Load custom message templates
  final invoiceTemplate = prefs.getString('invoice_message') ?? '''Hi {customerName}

Find attached your invoice and electrical certificate.

{reviewText}Many Thanks
{fullName}

{companyName}
{mainEmail}''';

  final estimateTemplate = prefs.getString('estimate_message') ?? '''Hi {customerName}

Great to meet you and look at your project.

Find attached the estimate for the discussed work.

Many Thanks
{fullName}

{companyName}
{mainEmail}''';

  final quoteTemplate = prefs.getString('quote_message') ?? '''Hi {customerName}

Great to meet you and look at your project.

Find attached the quote for the discussed work.

Many Thanks
{fullName}

{companyName}
{mainEmail}''';

  final messageTemplate = prefs.getString('message_template') ?? '''Hi {customerName}



Many Thanks
{fullName}

{companyName}
{mainEmail}''';
  
  final fullName = '$finalFirstName $finalLastName'.trim();

  // Add review text if link is provided
  final reviewText = reviewLink.isNotEmpty 
      ? 'If you would like to leave a review, here is our link: $reviewLink\n\n'
      : '';

  // Helper function to replace placeholders
  String replacePlaceholders(String template) {
    return template
        .replaceAll('{customerName}', customerFirstName)
        .replaceAll('{fullName}', fullName)
        .replaceAll('{companyName}', finalCompanyName)
        .replaceAll('{mainEmail}', finalMainEmail.isNotEmpty ? finalMainEmail : '')
        .replaceAll('{reviewText}', reviewText);
  }

  switch (emailType) {
    case 'invoice':
      return {
        'subject': 'Invoice from $finalCompanyName',
        'body': replacePlaceholders(invoiceTemplate),
      };
    case 'estimate':
      return {
        'subject': 'Estimate from $finalCompanyName',
        'body': replacePlaceholders(estimateTemplate),
      };
    case 'quote':
      return {
        'subject': 'Quote from $finalCompanyName',
        'body': replacePlaceholders(quoteTemplate),
      };
    default:
      return {
        'subject': 'Message from $finalCompanyName',
        'body': replacePlaceholders(messageTemplate),
      };
  }
}

// Add this helper somewhere in your file:
Future<Duration?> showDelayPickerDialog(BuildContext context) async {
  return showDialog<Duration>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Send Email When?'),
      children: [
        SimpleDialogOption(
          child: const Text('Now'),
          onPressed: () => Navigator.pop(context, Duration.zero),
        ),
        SimpleDialogOption(
          child: const Text('In 5 minutes'),
          onPressed: () => Navigator.pop(context, const Duration(minutes: 5)),
        ),
        SimpleDialogOption(
          child: const Text('In 30 minutes'),
          onPressed: () => Navigator.pop(context, const Duration(minutes: 30)),
        ),
        SimpleDialogOption(
          child: const Text('In 1 hour'),
          onPressed: () => Navigator.pop(context, const Duration(hours: 1)),
        ),
        SimpleDialogOption(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, null),
        ),
      ],
    ),
  );
}

String formatDate(DateTime? date) {
  if (date == null) return "Not set";
  return "${date.day}/${date.month}/${date.year}";
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

class _TemplatePickerDialog extends StatefulWidget {
  final List<EstimateTemplate> templates;
  const _TemplatePickerDialog({required this.templates});

  @override
  State<_TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<_TemplatePickerDialog> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.templates
        .where((t) => t.name.toLowerCase().contains(search.toLowerCase()))
        .toList();

    return AlertDialog(
      title: const Text('Select Estimate Template'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search templates',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) => setState(() => search = val),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No templates found.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final template = filtered[index];
                        return ListTile(
                          title: Text(template.name),
                          onTap: () => Navigator.pop(context, template),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

