import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import '../services/myob_service.dart';
import '../services/xero_service.dart';
import '../services/xero_invoice_repository_impl.dart';
import '../services/sync_scheduler.dart';
import '../services/storage_strategy_service.dart' show DataType;
import '../services/demo_mode_service.dart';
import '../services/firestore_service.dart';
import '../services/openai_key_service.dart';
import '../services/cloud_sync_throttled_service.dart';
import 'data_management_screen.dart';
import 'storage_settings_screen.dart';
import 'cloud_status_debug_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Company Settings
  final _companyNameController = TextEditingController();
  final _gstNumberController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _bankDetailsController = TextEditingController();
  final _mainEmailController = TextEditingController();
  final _secondaryEmailController = TextEditingController();
  final _smtpEmailController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _smtpServerController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _reviewLinkController = TextEditingController();
  String? _logoPath;
  bool _smtpVerified = false;
  bool _smtpTestingInProgress = false;
  String? _contactFormLink;
  Color _pdfBannerColor = const Color(0xFF2196F3); // Default blue for PDF banner
  Color _pdfLineItemColor = const Color(0xFF2196F3); // Default blue for line items
  Color _pdfTotalsColor = const Color(0xFF2196F3); // Default blue for totals box
  
  // PDF Receipt Scanner Settings
  List<String> _selectedSupplierTemplates = [];
  final List<Map<String, String>> _availableTemplates = [
    {'name': 'JA Russell', 'file': 'ja_russell.txt'},
    // Add more templates here as they become available
  ];

  // AI Features (receipt scanner, PDF-to-Build conversion) - the OpenAI
  // API key used at runtime. Stored on-device so it works on an installed
  // phone build without needing to rebuild the app with --dart-define.
  final _openAiApiKeyController = TextEditingController();
  bool _openAiApiKeyObscured = true;
  
  // Accounting Integration Settings
  bool _myobEnabled = false;
  final _myobApiKeyController = TextEditingController();
  final _myobCompanyFileController = TextEditingController();
  final _myobUserController = TextEditingController();
  final _myobPasswordController = TextEditingController();
  bool _xeroEnabled = false;
  final _xeroClientIdController = TextEditingController();
  final _xeroClientSecretController = TextEditingController();
  String? _xeroTenantId;
  String? _xeroAccessToken;
  String? _xeroRefreshToken;
  String? _xeroBankAccountCode;
  String? _xeroSalesAccountCode;
  List<Map<String, dynamic>> _xeroBankAccountOptions = [];
  List<Map<String, dynamic>> _xeroSalesAccountOptions = [];
  
  // Personal Settings
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _gasFittingLicenseController = TextEditingController();
  final _electricalLicenseController = TextEditingController();
  final _personalEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _signaturePath;
  bool _autoEmailCertificates = false;
  bool _hasAcceptedTerms = false;
  String? _termsSignaturePath;
  
  // App Settings
  bool _showLineItemPricesDefault = false;
  bool _isDarkMode = false;
  bool _autoBackup = false;
  bool _isCloudSyncing = false;
  bool _isThrottledSyncActive = false;
  double _throttledSyncProgress = 0.0;
  String _throttledSyncOperation = '';
  bool _isGstRegistered = true; // Default to GST registered
  Color _appColor = const Color(0xFF2196F3); // Default blue
  Color _accentColor = const Color(0xFF4CAF50); // Default green accent (secondary colour used app-wide for highlights/success)
  String _selectedCountry = 'New Zealand'; // Default country for address search
  bool _isDemoMode = DemoModeService.instance.isDemoMode;

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _loadXeroAccountOptions());
    _loadColor();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (DemoModeService.instance.isDemoMode) {
        // DEMO MODE: show the mock company profile instead of real settings.
        final profile = DemoModeService.instance.companyProfile;
        _companyNameController.text = profile['companyName'] ?? '';
        _gstNumberController.text = profile['gstNumber'] ?? '';
        _companyAddressController.text = profile['address'] ?? '';
        _bankDetailsController.text = 'Demo Bank · 00-0000-0000000-00';
        _mainEmailController.text = profile['email'] ?? '';
        _secondaryEmailController.text = '';
        _smtpEmailController.text = profile['email'] ?? '';
        _smtpPasswordController.text = '';
        _smtpServerController.text = '';
        _smtpPortController.text = '587';
        _reviewLinkController.text = '';
        _logoPath = null;
        return;
      }
      // Company Settings
      _companyNameController.text = prefs.getString('company_name') ?? '';
      _gstNumberController.text = prefs.getString('gst_number') ?? '';
      _companyAddressController.text = prefs.getString('company_address') ?? '';
      _bankDetailsController.text = prefs.getString('bank_details') ?? '';
      _mainEmailController.text = prefs.getString('main_email') ?? '';
      _secondaryEmailController.text = prefs.getString('secondary_email') ?? '';
      _smtpEmailController.text = prefs.getString('smtp_email') ?? '';
      _smtpPasswordController.text = prefs.getString('smtp_password') ?? '';
      _smtpServerController.text = prefs.getString('smtp_server') ?? '';
      _smtpPortController.text = prefs.getString('smtp_port') ?? '587';
      _reviewLinkController.text = prefs.getString('review_link') ?? '';
      _logoPath = prefs.getString('company_logo_path');
      _smtpVerified = prefs.getBool('smtp_verified') ?? false;
      final uid = FirestoreService.currentUserId;
      if (_smtpVerified && uid != null) {
        _contactFormLink = 'https://soletradie-ab850.web.app/contact.html?u=$uid';
      } else {
        _contactFormLink = null;
      }
      
      // Accounting Integration Settings
      _myobEnabled = prefs.getBool('myob_enabled') ?? false;
      _myobApiKeyController.text = prefs.getString('myob_api_key') ?? '';
      _myobCompanyFileController.text = prefs.getString('myob_company_file') ?? '';
      _myobUserController.text = prefs.getString('myob_user') ?? '';
      _myobPasswordController.text = prefs.getString('myob_password') ?? '';
      _xeroEnabled = prefs.getBool('xero_enabled') ?? false;
      _xeroClientIdController.text = prefs.getString('xero_client_id') ?? '';
      _xeroClientSecretController.text = prefs.getString('xero_client_secret') ?? '';
      _xeroTenantId = prefs.getString('xero_tenant_id');
      _xeroAccessToken = prefs.getString('xero_access_token');
      _xeroRefreshToken = prefs.getString('xero_refresh_token');
      _xeroBankAccountCode = prefs.getString('xero_bank_account_code');
      _xeroSalesAccountCode = prefs.getString('xero_sales_account_code');
      
      // Personal Settings
      _firstNameController.text = prefs.getString('first_name') ?? '';
      _lastNameController.text = prefs.getString('last_name') ?? '';
      _gasFittingLicenseController.text = prefs.getString('gas_fitting_license') ?? '';
      _electricalLicenseController.text = prefs.getString('electrical_license') ?? '';
      // Default personal email to main email if not set
      _personalEmailController.text = prefs.getString('personal_email') ?? 
                                     prefs.getString('main_email') ?? '';
      _phoneController.text = prefs.getString('phone') ?? '';
      _signaturePath = prefs.getString('signature_path');
      _autoEmailCertificates = prefs.getBool('auto_email_certificates') ?? false;
      _hasAcceptedTerms = prefs.getBool('has_accepted_terms') ?? false;
      _termsSignaturePath = prefs.getString('terms_signature_path');
      
      // App Settings
      _showLineItemPricesDefault = prefs.getBool('showLineItemPricesDefault') ?? false;
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _autoBackup = prefs.getBool('auto_backup') ?? false;
      _isGstRegistered = prefs.getBool('is_gst_registered') ?? true; // Default to GST registered
      _selectedCountry = prefs.getString('selected_country') ?? 'New Zealand';
      
      // PDF Receipt Scanner Settings
      final selectedTemplatesString = prefs.getString('selected_supplier_templates') ?? '';
      _selectedSupplierTemplates = selectedTemplatesString.isNotEmpty 
          ? selectedTemplatesString.split(',')
          : [];
    });
    _openAiApiKeyController.text = await OpenAiKeyService.getStoredKeyForDisplay();
  }

  String _fixSmtpServer(String server) {
    String fixed = server.trim();
    
    // Fix common hostname issues
    if (fixed.contains('smtp.gmail com')) {
      fixed = fixed.replaceAll('smtp.gmail com', 'smtp.gmail.com');
    }
    if (fixed.contains('smtp.outlook com')) {
      fixed = fixed.replaceAll('smtp.outlook com', 'smtp.outlook.com');
    }
    if (fixed.contains('smtp.live com')) {
      fixed = fixed.replaceAll('smtp.live com', 'smtp.live.com');
    }
    
    return fixed;
  }

  Future<void> _testAndSaveSmtpSettings() async {
    final email = _smtpEmailController.text.trim();
    final password = _smtpPasswordController.text.trim();
    final server = _fixSmtpServer(_smtpServerController.text);
    final portText = _smtpPortController.text.trim();
    final companyName = _companyNameController.text.trim();

    if (email.isEmpty || password.isEmpty || server.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in your SMTP email, password and server first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to be signed in to verify your email settings.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _smtpTestingInProgress = true;
    });

    try {
      final idToken = await user.getIdToken();
      final port = int.tryParse(portText) ?? 587;

      final res = await http
          .post(
            Uri.parse('https://soletradie-ab850.web.app/api/testAndSaveSmtpSettings'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'smtpEmail': email,
              'smtpPassword': password,
              'smtpServer': server,
              'smtpPort': port,
              'companyName': companyName,
            }),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}

      if (res.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('smtp_verified', true);
        final uid = FirestoreService.currentUserId ?? user.uid;
        if (mounted) {
          setState(() {
            _smtpVerified = true;
            _contactFormLink = 'https://soletradie-ab850.web.app/contact.html?u=$uid';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Success! A test email was sent and your website contact form link is ready below.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('smtp_verified', false);
        if (mounted) {
          setState(() {
            _smtpVerified = false;
            _contactFormLink = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error']?.toString() ??
                  'Could not verify your email settings. Please check them and try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not reach the server: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _smtpTestingInProgress = false;
        });
      }
    }
  }


  Future<void> _saveSettings() async {
    if (DemoModeService.instance.isDemoMode) {
      // DEMO MODE: never persist company/SMTP settings to real storage.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Demo Mode: company settings are mock data and can\'t be saved.'),
            backgroundColor: Colors.deepPurple,
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();

    // Company Settings
    await prefs.setString('company_name', _companyNameController.text);
    await prefs.setString('gst_number', _gstNumberController.text);

    // If the company address changed, clear the cached geocoded
    // coordinates so the office weather card (and anything else relying on
    // AddressSearchService.getCompanyCoordinates()) re-geocodes against the
    // new address instead of showing weather for the old location.
    final previousAddress = prefs.getString('company_address') ?? '';
    final newAddress = _companyAddressController.text;
    if (previousAddress.trim() != newAddress.trim()) {
      await prefs.remove('company_latitude');
      await prefs.remove('company_longitude');
    }
    await prefs.setString('company_address', newAddress);
    await prefs.setString('bank_details', _bankDetailsController.text);
    await prefs.setString('main_email', _mainEmailController.text);
    await prefs.setString('secondary_email', _secondaryEmailController.text);
    await prefs.setString('smtp_email', _smtpEmailController.text.trim());
    await prefs.setString('smtp_password', _smtpPasswordController.text.trim());
    await prefs.setString('smtp_server', _fixSmtpServer(_smtpServerController.text));
    await prefs.setString('smtp_port', _smtpPortController.text.trim());
    await prefs.setString('review_link', _reviewLinkController.text.trim());
    if (_logoPath != null) {
      await prefs.setString('company_logo_path', _logoPath!);
    }
    
    // Accounting Integration Settings
    await prefs.setBool('myob_enabled', _myobEnabled);
    await prefs.setString('myob_api_key', _myobApiKeyController.text);
    await prefs.setString('myob_company_file', _myobCompanyFileController.text);
    await prefs.setString('myob_user', _myobUserController.text);
    await prefs.setString('myob_password', _myobPasswordController.text);
    await prefs.setBool('xero_enabled', _xeroEnabled);
    await prefs.setString('xero_client_id', _xeroClientIdController.text);
    await prefs.setString('xero_client_secret', _xeroClientSecretController.text);
    if (_xeroTenantId != null) {
      await prefs.setString('xero_tenant_id', _xeroTenantId!);
    }
    if (_xeroAccessToken != null) {
      await prefs.setString('xero_access_token', _xeroAccessToken!);
    }
    if (_xeroRefreshToken != null) {
      await prefs.setString('xero_refresh_token', _xeroRefreshToken!);
    }
    if (_xeroBankAccountCode != null) {
      await prefs.setString('xero_bank_account_code', _xeroBankAccountCode!);
    }
    if (_xeroSalesAccountCode != null) {
      await prefs.setString('xero_sales_account_code', _xeroSalesAccountCode!);
    }
    
    // Personal Settings
    await prefs.setString('first_name', _firstNameController.text);
    await prefs.setString('last_name', _lastNameController.text);
    await prefs.setString('gas_fitting_license', _gasFittingLicenseController.text);
    await prefs.setString('electrical_license', _electricalLicenseController.text);
    await prefs.setString('personal_email', _personalEmailController.text);
    await prefs.setString('phone', _phoneController.text);
    if (_signaturePath != null) {
      await prefs.setString('signature_path', _signaturePath!);
    }
    await prefs.setBool('auto_email_certificates', _autoEmailCertificates);
    await prefs.setBool('has_accepted_terms', _hasAcceptedTerms);
    if (_termsSignaturePath != null) {
      await prefs.setString('terms_signature_path', _termsSignaturePath!);
    }
    
    // App Settings
    await prefs.setBool('showLineItemPricesDefault', _showLineItemPricesDefault);
    await prefs.setBool('is_gst_registered', _isGstRegistered);
    await prefs.setString('selected_country', _selectedCountry);
    
    // PDF Receipt Scanner Settings
    await prefs.setString('selected_supplier_templates', _selectedSupplierTemplates.join(','));

    // AI Features - OpenAI API key (used at runtime by receipt scanner and
    // PDF-to-Build conversion; stored via OpenAiKeyService so it works on
    // an installed phone build without needing a --dart-define rebuild).
    await OpenAiKeyService.setKey(_openAiApiKeyController.text);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved!')),
      );
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _logoPath = result.files.single.path!;
      });
    }
  }
  
  Future<void> _drawSignature() async {
    final SignatureController controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    final signature = await showDialog<Uint8List>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Draw Your Signature'),
        content: SizedBox(
          width: 300,
          height: 200,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Signature(
              controller: controller,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => controller.clear(),
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () async {
              final signatureData = await controller.toPngBytes();
              Navigator.pop(context, signatureData);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (signature != null) {
      // Save signature to local storage
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/signature.png');
      await file.writeAsBytes(signature);
      
      setState(() {
        _signaturePath = file.path;
      });
    }
  }

  Future<void> setShowLineItemPricesDefault(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showLineItemPricesDefault', value);
  }

  Future<bool> getShowLineItemPricesDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('showLineItemPricesDefault') ?? false; // Default to false (off)
  }

  Future<void> _loadColor() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load app color
    final appColorString = prefs.getString('app_color');
    if (appColorString != null && appColorString.length == 9) {
      setState(() {
        _appColor = Color(int.parse(appColorString.substring(1), radix: 16));
      });
    }
    
    // Load accent color (secondary colour used app-wide for highlights/success states)
    final accentColorString = prefs.getString('accent_color');
    if (accentColorString != null && accentColorString.length == 9) {
      setState(() {
        _accentColor = Color(int.parse(accentColorString.substring(1), radix: 16));
      });
    }
    
    // Load PDF banner color
    final pdfColorString = prefs.getString('pdf_banner_color');
    if (pdfColorString != null && pdfColorString.length == 9) {
      setState(() {
        _pdfBannerColor = Color(int.parse(pdfColorString.substring(1), radix: 16));
      });
    }
    
    // Load PDF line item color
    final pdfLineItemColorString = prefs.getString('pdf_line_item_color');
    if (pdfLineItemColorString != null && pdfLineItemColorString.length == 9) {
      setState(() {
        _pdfLineItemColor = Color(int.parse(pdfLineItemColorString.substring(1), radix: 16));
      });
    }
    
    // Load PDF totals color
    final pdfTotalsColorString = prefs.getString('pdf_totals_color');
    if (pdfTotalsColorString != null && pdfTotalsColorString.length == 9) {
      setState(() {
        _pdfTotalsColor = Color(int.parse(pdfTotalsColorString.substring(1), radix: 16));
      });
    }
  }

  Future<void> _saveColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    await prefs.setString('app_color', colorString);
  }

  Future<void> _saveAccentColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    await prefs.setString('accent_color', colorString);
  }
  
  Future<void> _savePdfColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    await prefs.setString('pdf_banner_color', colorString);
  }
  
  Future<void> _savePdfLineItemColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    await prefs.setString('pdf_line_item_color', colorString);
  }
  
  Future<void> _savePdfTotalsColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    await prefs.setString('pdf_totals_color', colorString);
  }

  /// Show an enhanced color picker with Wheel, Spectrum, and Swatches tabs
  Future<Color?> _showColorPickerDialog(Color initialColor, String title) async {
    Color pickedColor = initialColor;

    return showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TabBar(
                        labelColor: Colors.blue,
                        unselectedLabelColor: Colors.grey,
                        tabs: [
                          Tab(text: 'Wheel'),
                          Tab(text: 'Spectrum'),
                          Tab(text: 'Swatches'),
                        ],
                      ),
                      SizedBox(
                        height: 320,
                        child: TabBarView(
                          children: [
                            // Color wheel picker
                            SingleChildScrollView(
                              child: HueRingPicker(
                                pickerColor: pickedColor,
                                onColorChanged: (color) {
                                  setDialogState(() => pickedColor = color);
                                },
                                enableAlpha: false,
                                displayThumbColor: true,
                              ),
                            ),
                            // Full spectrum HSV picker
                            SingleChildScrollView(
                              child: ColorPicker(
                                pickerColor: pickedColor,
                                onColorChanged: (color) {
                                  setDialogState(() => pickedColor = color);
                                },
                                enableAlpha: false,
                                displayThumbColor: true,
                                paletteType: PaletteType.hsv,
                                pickerAreaHeightPercent: 0.7,
                              ),
                            ),
                            // Quick swatch blocks
                            SingleChildScrollView(
                              child: BlockPicker(
                                pickerColor: pickedColor,
                                onColorChanged: (color) {
                                  setDialogState(() => pickedColor = color);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        height: 40,
                        decoration: BoxDecoration(
                          color: pickedColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(
                            '#${pickedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                            style: TextStyle(
                              color: ThemeData.estimateBrightnessForColor(pickedColor) == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, pickedColor),
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSmtpHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SMTP Setup Help'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Important:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              Text('This email will be used to send ALL business communications including invoices, estimates, quotes, certificates, and messages to customers.'),
              SizedBox(height: 16),
              Text('Gmail Setup:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• SMTP Server: smtp.gmail.com'),
              Text('• Port: 587'),
              Text('• Use App Password (not regular password)'),
              Text('• Enable 2-factor authentication first'),
              SizedBox(height: 16),
              Text('Outlook/Hotmail:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• SMTP Server: smtp-mail.outlook.com'),
              Text('• Port: 587'),
              Text('• Use your regular email password'),
              SizedBox(height: 16),
              Text('Other Providers:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Check your email provider\'s SMTP settings'),
              Text('• Most use port 587 or 465'),
              Text('• Enable "Less secure app access" if required'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showTermsDialog() {
    final termsController = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Certificate Email Agreement'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'By enabling automatic certificate emailing, you agree that:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'I agree that I won\'t contact customers from the documentation for work outside of the company. This is purely for my own record keeping as legally required.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Please sign below to accept these terms:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Signature(
                  controller: termsController,
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _autoEmailCertificates = false;
              });
            },
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () => termsController.clear(),
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (termsController.isNotEmpty) {
                // Save terms signature
                final signature = await termsController.toPngBytes();
                if (signature != null) {
                  final directory = await getApplicationDocumentsDirectory();
                  final file = File('${directory.path}/terms_signature.png');
                  await file.writeAsBytes(signature);
                  
                  setState(() {
                    _termsSignaturePath = file.path;
                    _hasAcceptedTerms = true;
                    _autoEmailCertificates = true;
                  });
                  
                  Navigator.pop(context);
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Terms accepted. Certificates will be emailed automatically.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide your signature to accept the terms.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Accept & Sign'),
          ),
        ],
      ),
    );
  }

  void _showEmailTemplatesDialog() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load current templates or use defaults
    final invoiceController = TextEditingController(
      text: prefs.getString('invoice_message') ?? '''Hi {customerName}

Find attached your invoice.

{reviewText}Many Thanks
{fullName}

{companyName}
{mainEmail}''',
    );

    final invoiceCertController = TextEditingController(
      text: prefs.getString('invoice_certificate_message') ?? '''Hi {customerName}

Find attached your invoice and electrical certificate.

{reviewText}Many Thanks
{fullName}

{companyName}
{mainEmail}''',
    );

    final estimateController = TextEditingController(
      text: prefs.getString('estimate_message') ?? '''Hi {customerName}

Great to meet you and look at your project.

Find attached the estimate for the discussed work.

Many Thanks
{fullName}

{companyName}
{mainEmail}''',
    );

    final quoteController = TextEditingController(
      text: prefs.getString('quote_message') ?? '''Hi {customerName}

Great to meet you and look at your project.

Find attached the quote for the discussed work.

Many Thanks
{fullName}

{companyName}
{mainEmail}''',
    );

    final messageController = TextEditingController(
      text: prefs.getString('message_template') ?? '''Hi {customerName}



Many Thanks
{fullName}

{companyName}
{mainEmail}''',
    );

    final followUpController = TextEditingController(
      text: prefs.getString('followup_message') ?? '''Hi {customerName}

Just a friendly follow-up regarding invoice {invoiceNumber} for {invoiceAmount}, sent on {invoiceDate}.

If you've already made payment, please disregard this message. Otherwise, please let us know if you have any questions.

Many Thanks
{fullName}

{companyName}
{mainEmail}''',
    );

    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 6,
        child: AlertDialog(
          title: const Text('Email Templates'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                const Text(
                  'Use placeholders: {customerName}, {fullName}, {companyName}, {mainEmail}, {reviewText}, {invoiceNumber}, {invoiceAmount}, {invoiceDate}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Invoice'),
                    Tab(text: 'Invoice + Cert'),
                    Tab(text: 'Estimate'),
                    Tab(text: 'Quote'),
                    Tab(text: 'Message'),
                    Tab(text: 'Follow Up'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Invoice Template (no certificate)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: invoiceController,
                          decoration: const InputDecoration(
                            labelText: 'Invoice Email Template',
                            border: OutlineInputBorder(),
                            helperText: 'Used when sending an invoice without a certificate',
                          ),
                          maxLines: 15,
                        ),
                      ),
                      // Invoice + Certificate Template
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: invoiceCertController,
                          decoration: const InputDecoration(
                            labelText: 'Invoice + Certificate Email Template',
                            border: OutlineInputBorder(),
                            helperText: 'Used when sending an invoice with an electrical certificate attached',
                          ),
                          maxLines: 15,
                        ),
                      ),
                      // Estimate Template
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: estimateController,
                          decoration: const InputDecoration(
                            labelText: 'Estimate Email Template',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 15,
                        ),
                      ),
                      // Quote Template
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: quoteController,
                          decoration: const InputDecoration(
                            labelText: 'Quote Email Template',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 15,
                        ),
                      ),
                      // Message Template
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: messageController,
                          decoration: const InputDecoration(
                            labelText: 'General Message Template',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 15,
                        ),
                      ),
                      // Follow Up Template
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(textCapitalization: TextCapitalization.sentences, 
                          controller: followUpController,
                          decoration: const InputDecoration(
                            labelText: 'Invoice Follow-Up Email Template',
                            border: OutlineInputBorder(),
                            helperText: 'Used when sending a payment reminder from the Invoices screen',
                          ),
                          maxLines: 15,
                        ),
                      ),
                    ],
                  ),
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
              onPressed: () async {
                // Save templates
                await prefs.setString('invoice_message', invoiceController.text);
                await prefs.setString('invoice_certificate_message', invoiceCertController.text);
                await prefs.setString('estimate_message', estimateController.text);
                await prefs.setString('quote_message', quoteController.text);
                await prefs.setString('message_template', messageController.text);
                await prefs.setString('followup_message', followUpController.text);
                
                Navigator.pop(context);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Email templates saved!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Save Templates'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountingHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accounting Integration Setup'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MYOB AccountRight Setup:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Enable MYOB API access in your MYOB file'),
              Text('2. Get your API key from MYOB Developer Portal'),
              Text('3. Find your Company File GUID in MYOB settings'),
              Text('4. Use your MYOB username and password'),
              SizedBox(height: 16),
              Text(
                'Xero Setup:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Create an app at developer.xero.com'),
              Text('2. Get your Client ID and Client Secret'),
              Text('3. Add redirect URI: https://localhost:8080/callback'),
              Text('4. Select scopes: accounting.transactions, accounting.contacts'),
              SizedBox(height: 16),
              Text(
                'Bank Feed Features:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Automatically sync transactions'),
              Text('• Create invoices from bank feeds'),
              Text('• Match payments to existing invoices'),
              Text('• Export job data to accounting software'),
            ],
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
  }

  Future<void> _testMyobConnection() async {
    if (_myobApiKeyController.text.isEmpty || 
        _myobCompanyFileController.text.isEmpty ||
        _myobUserController.text.isEmpty ||
        _myobPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all MYOB credentials'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing MYOB connection...'),
          ],
        ),
      ),
    );

    try {
      final myobService = MyobService();
      final success = await myobService.testConnection(
        apiKey: _myobApiKeyController.text,
        companyFileId: _myobCompanyFileController.text,
        username: _myobUserController.text,
        password: _myobPasswordController.text,
      );
      
      Navigator.pop(context); // Close loading dialog
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MYOB connection successful!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MYOB connection failed. Please check your credentials.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MYOB connection failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _connectToXero() async {
    if (_xeroClientIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your Xero Client ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog while the OAuth browser flow runs.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
                child: Text(
                    'Sign in to Xero in the browser window that just opened...')),
          ],
        ),
      ),
    );

    try {
      final xeroService = XeroService();
      // Client secret is optional: leave it blank if your Xero app is
      // registered as a "Mobile or desktop app" (the correct type for
      // this app) - Xero doesn't issue a secret for that app type, and
      // the service will automatically use PKCE instead.
      final secretText = _xeroClientSecretController.text.trim();
      await xeroService.connect(
        clientId: _xeroClientIdController.text.trim(),
        clientSecret: secretText.isEmpty ? null : secretText,
      );

      final stored = await XeroService.getStoredCredentials();

      if (mounted) Navigator.pop(context); // Close loading dialog

      setState(() {
        _xeroTenantId = stored['tenantId'];
        _xeroAccessToken = stored['accessToken'];
        _xeroRefreshToken = stored['refreshToken'];
      });

      await _loadXeroAccountOptions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully connected to Xero!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading dialog

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Xero connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Loads the Chart of Accounts (via the repository's cache) and splits
  /// it into bank accounts (for payment reconciliation) and revenue/sales
  /// accounts (for invoice line item account codes), so the user can map
  /// which Xero account each should use.
  Future<void> _loadXeroAccountOptions() async {
    if (_xeroAccessToken == null) return;
    try {
      final repository = XeroInvoiceRepositoryImpl();
      final accounts = await repository.getAccounts();
      if (!mounted) return;
      setState(() {
        _xeroBankAccountOptions = accounts
            .where((a) => a.type == 'BANK')
            .map((a) => {'code': a.code, 'name': a.name})
            .toList();
        _xeroSalesAccountOptions = accounts
            .where((a) => a.type == 'REVENUE' || a.type == 'SALES')
            .map((a) => {'code': a.code, 'name': a.name})
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load Xero accounts: $e');
    }
  }

  Future<void> _syncXeroBankFeeds() async {
    if (_xeroAccessToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to Xero first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Syncing bank feeds...'),
          ],
        ),
      ),
    );

    try {
      final xeroService = XeroService();
      
      // Test connection first
      final connectionValid = await xeroService.testConnection(_xeroAccessToken!);
      
      if (!connectionValid) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Xero connection is invalid. Please reconnect.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // Get bank accounts
      final bankAccounts = await xeroService.getBankAccounts(_xeroAccessToken!);
      
      // Simulate bank feed sync
      await Future.delayed(const Duration(seconds: 3));
      
      Navigator.pop(context); // Close loading dialog
      
      // Show success dialog with sync details
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bank Feed Sync Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✓ Found ${bankAccounts.length} bank accounts'),
              const Text('✓ Downloaded 25 new transactions'),
              const Text('✓ Matched 12 payments to invoices'),
              const Text('✓ Created 8 new expense entries'),
              const Text('✓ Updated account balances'),
              const SizedBox(height: 16),
              const Text(
                'Note: This is demo mode. Real implementation would sync actual bank transaction data.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showBankFeedOptions();
              },
              child: const Text('View Options'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bank feed sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showBankFeedOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bank Feed Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Auto-sync Settings'),
              subtitle: const Text('Configure automatic bank feed sync'),
              onTap: () {
                Navigator.pop(context);
                _showAutoSyncSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt),
              title: const Text('Transaction Matching'),
              subtitle: const Text('Set up automatic invoice matching'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction matching settings coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('Bank Account Mapping'),
              subtitle: const Text('Map accounts to categories'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bank account mapping coming soon!')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAutoSyncSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto-sync Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Enable Daily Sync'),
              subtitle: const Text('Automatically sync bank feeds daily'),
              value: true,
              onChanged: (value) {
                // Implement auto-sync toggle
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Daily sync ${value ? 'enabled' : 'disabled'}')),
                );
              },
            ),
            const Divider(),
            ListTile(
              title: const Text('Sync Time'),
              subtitle: const Text('Daily sync at 6:00 AM'),
              trailing: const Icon(Icons.schedule),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Time picker coming soon!')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: _appColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          // Company Settings Section
          _buildSectionHeader('Company Settings', Icons.business),
          _buildCompanySettingsCard(),
          
          const SizedBox(height: 24),

          // Customer Intake Form Section
          _buildSectionHeader('Customer Intake Form', Icons.person_add_alt_1),
          _buildCustomerIntakeFormCard(),

          const SizedBox(height: 24),
          
          // Personal Settings Section
          _buildSectionHeader('Personal Settings', Icons.person),
          _buildPersonalSettingsCard(),
          
          const SizedBox(height: 24),
          
          // App Settings Section
          _buildSectionHeader('App Settings', Icons.settings),
          _buildAppSettingsCard(),
          
          const SizedBox(height: 24),
          
          // GPS Timeline Import Section
          _buildSectionHeader('GPS Timeline Import', Icons.location_history),
          _buildGpsLocationCard(),
          
          const SizedBox(height: 24),
          
          // Cloud Sync Section
          _buildSectionHeader('Cloud Sync & Storage', Icons.cloud_sync),
          _buildCloudSyncCard(),
          
          const SizedBox(height: 32),
          
          // Debug Button (for troubleshooting cloud issues)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CloudStatusDebugScreen(),
                ),
              );
            },
            icon: const Icon(Icons.bug_report),
            label: const Text('☁️ Cloud Status Debug'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepPurple,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Save Button
          ElevatedButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('Save All Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _appColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: _appColor, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _appColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _companyNameController,
            decoration: const InputDecoration(
              labelText: 'Company Name',
              prefixIcon: Icon(Icons.business),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _gstNumberController,
            decoration: InputDecoration(
              labelText: 'GST Number',
              prefixIcon: Icon(Icons.receipt_long),
              border: OutlineInputBorder(),
              enabled: _isGstRegistered, // Disable if not GST registered
            ),
          ),
          const SizedBox(height: 16),
          
          // GST Registration Toggle
          SwitchListTile(
            title: const Text('GST Registered'),
            subtitle: const Text('Include GST calculations in estimates and invoices'),
            value: _isGstRegistered,
            onChanged: (value) async {
              setState(() {
                _isGstRegistered = value;
                // Keep GST number even when disabled - don't clear it
              });
              await _saveSettings();
            },
            activeThumbColor: _appColor,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _companyAddressController,
            decoration: const InputDecoration(
              labelText: 'Company Address',
              prefixIcon: Icon(Icons.location_on),
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _bankDetailsController,
            decoration: const InputDecoration(
              labelText: 'Bank Details',
              prefixIcon: Icon(Icons.account_balance),
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _mainEmailController,
            decoration: const InputDecoration(
              labelText: 'Main Email Address',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _secondaryEmailController,
            decoration: const InputDecoration(
              labelText: 'Secondary Email Address',
              prefixIcon: Icon(Icons.alternate_email),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          
          // SMTP Settings Section
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.mail_outline, color: _appColor),
              const SizedBox(width: 8),
              const Text(
                'SMTP Email Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: _showSmtpHelpDialog,
                tooltip: 'SMTP Setup Help',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _smtpEmailController,
            decoration: const InputDecoration(
              labelText: 'SMTP Email Address',
              prefixIcon: Icon(Icons.outgoing_mail),
              border: OutlineInputBorder(),
              hintText: 'Email used for all communications (invoices, estimates, certificates)',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _smtpPasswordController,
            decoration: const InputDecoration(
              labelText: 'SMTP Password/App Password',
              prefixIcon: Icon(Icons.password),
              border: OutlineInputBorder(),
              hintText: 'Use app password for Gmail',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: _smtpServerController,
                  decoration: const InputDecoration(
                    labelText: 'SMTP Server',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                    hintText: 'e.g. smtp.gmail.com',
                    helperText: 'Enter the full SMTP server hostname',
                  ),
                  onChanged: (value) {
                    // Auto-fix common mistakes
                    final fixed = _fixSmtpServer(value);
                    if (fixed != value) {
                      _smtpServerController.text = fixed;
                      _smtpServerController.selection = TextSelection.fromPosition(
                        TextPosition(offset: fixed.length),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: _smtpPortController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                    hintText: '587',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Test SMTP + Website Contact Form Link
          ElevatedButton.icon(
            icon: _smtpTestingInProgress
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
            label: Text(_smtpTestingInProgress
                ? 'Sending test email...'
                : 'Send Test Email & Enable Website Contact Form'),
            onPressed: _smtpTestingInProgress ? null : _testAndSaveSmtpSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: _appColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (_smtpVerified && _contactFormLink != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Website contact form is ready!',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share this link on your website so customers can contact you directly:',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _contactFormLink!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy link',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _contactFormLink!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied to clipboard')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _reviewLinkController,
            decoration: const InputDecoration(
              labelText: 'Review Link (Optional)',
              prefixIcon: Icon(Icons.star_outline),
              border: OutlineInputBorder(),
              hintText: 'Google review link or website URL for invoices',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          
          // Email Templates Button
          ElevatedButton.icon(
            icon: const Icon(Icons.email),
            label: const Text('Customize Email Templates'),
            onPressed: _showEmailTemplatesDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: _appColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // PDF Banner Color Section
          const Text(
            'PDF Banner Color',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final color = await _showColorPickerDialog(_pdfBannerColor, 'Pick PDF Banner Color');
              if (color != null) {
                setState(() => _pdfBannerColor = color);
                await _savePdfColor(color);
              }
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: _pdfBannerColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  'Tap to change PDF banner color',
                  style: TextStyle(
                    color: ThemeData.estimateBrightnessForColor(_pdfBannerColor) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // PDF Line Item Color Section
          const Text(
            'PDF Line Item Color',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final color = await _showColorPickerDialog(_pdfLineItemColor, 'Pick PDF Line Item Color');
              if (color != null) {
                setState(() => _pdfLineItemColor = color);
                await _savePdfLineItemColor(color);
              }
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: _pdfLineItemColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  'Tap to change line item table color',
                  style: TextStyle(
                    color: ThemeData.estimateBrightnessForColor(_pdfLineItemColor) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // PDF Totals Color Section
          const Text(
            'PDF Totals Box Color',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final color = await _showColorPickerDialog(_pdfTotalsColor, 'Pick PDF Totals Box Color');
              if (color != null) {
                setState(() => _pdfTotalsColor = color);
                await _savePdfTotalsColor(color);
              }
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: _pdfTotalsColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  'Tap to change totals box color',
                  style: TextStyle(
                    color: ThemeData.estimateBrightnessForColor(_pdfTotalsColor) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // PDF Receipt Scanner Section
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.document_scanner, color: _appColor),
              const SizedBox(width: 8),
              const Text(
                'PDF Receipt Scanner',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: _showPdfScannerHelpDialog,
                tooltip: 'PDF Scanner Setup Help',
              ),
            ],
          ),
          const SizedBox(height: 8),

          // AI Features - OpenAI API Key
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.smart_toy, color: Colors.teal),
                      const SizedBox(width: 8),
                      const Text(
                        'AI Features (OpenAI API Key)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Required for the receipt scanner and PDF-to-Build conversion. '
                    'Get a key at platform.openai.com/account/api-keys, then paste it here.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openAiApiKeyController,
                    obscureText: _openAiApiKeyObscured,
                    decoration: InputDecoration(
                      labelText: 'OpenAI API Key',
                      prefixIcon: const Icon(Icons.vpn_key),
                      suffixIcon: IconButton(
                        icon: Icon(_openAiApiKeyObscured
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(
                            () => _openAiApiKeyObscured = !_openAiApiKeyObscured),
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Supplier Template Selection
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Supplier Templates',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select supplier templates you use for receipt scanning:',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  ..._availableTemplates.map((template) => CheckboxListTile(
                    title: Text(template['name']!),
                    value: _selectedSupplierTemplates.contains(template['name']),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedSupplierTemplates.add(template['name']!);
                        } else {
                          _selectedSupplierTemplates.remove(template['name']!);
                        }
                      });
                    },
                    dense: true,
                  )),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Request New Template'),
                          onPressed: _requestNewTemplate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Accounting Integrations Section
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.account_balance_wallet, color: _appColor),
              const SizedBox(width: 8),
              const Text(
                'Accounting Software Integration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: _showAccountingHelpDialog,
                tooltip: 'Integration Setup Help',
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // MYOB Integration
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.business_center, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Text(
                        'MYOB AccountRight',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Switch(
                        value: _myobEnabled,
                        onChanged: (value) {
                          setState(() => _myobEnabled = value);
                        },
                      ),
                    ],
                  ),
                  if (_myobEnabled) ...[
                    const SizedBox(height: 12),
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _myobApiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'MYOB API Key',
                        prefixIcon: Icon(Icons.vpn_key),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _myobCompanyFileController,
                      decoration: const InputDecoration(
                        labelText: 'Company File GUID',
                        prefixIcon: Icon(Icons.folder),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _myobUserController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(textCapitalization: TextCapitalization.sentences, 
                            controller: _myobPasswordController,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            obscureText: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Test MYOB Connection'),
                      onPressed: _testMyobConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Xero Integration
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Xero Accounting',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Switch(
                        value: _xeroEnabled,
                        onChanged: (value) {
                          setState(() => _xeroEnabled = value);
                        },
                      ),
                    ],
                  ),
                  if (_xeroEnabled) ...[
                    const SizedBox(height: 12),
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _xeroClientIdController,
                      decoration: const InputDecoration(
                        labelText: 'Xero Client ID',
                        prefixIcon: Icon(Icons.fingerprint),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: _xeroClientSecretController,
                      decoration: const InputDecoration(
                        labelText: 'Xero Client Secret (optional)',
                        helperText: 'Leave blank if your Xero app is a '
                            '"Mobile or desktop app" - Xero doesn\'t issue '
                            'a secret for that type.',
                        helperMaxLines: 3,
                        prefixIcon: Icon(Icons.vpn_key),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login, size: 16),
                            label: const Text('Connect to Xero'),
                            onPressed: _connectToXero,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text('Sync Bank Feeds'),
                            onPressed: _xeroAccessToken != null ? _syncXeroBankFeeds : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_xeroAccessToken != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            const Text(
                              'Connected to Xero',
                              style: TextStyle(fontSize: 12, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _xeroBankAccountOptions.any(
                                (a) => a['code'] == _xeroBankAccountCode)
                            ? _xeroBankAccountCode
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Bank account for payments',
                          helperText:
                              'Used when a marked-paid invoice is pushed to Xero as a Payment.',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _xeroBankAccountOptions
                            .map((a) => DropdownMenuItem<String>(
                                  value: a['code'] as String,
                                  child: Text('${a['name']} (${a['code']})'),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() => _xeroBankAccountCode = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _xeroSalesAccountOptions.any(
                                (a) => a['code'] == _xeroSalesAccountCode)
                            ? _xeroSalesAccountCode
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Sales account for invoice line items',
                          helperText:
                              'Xero AccountCode used for each invoice line item pushed from this app.',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _xeroSalesAccountOptions
                            .map((a) => DropdownMenuItem<String>(
                                  value: a['code'] as String,
                                  child: Text('${a['name']} (${a['code']})'),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() => _xeroSalesAccountCode = value);
                        },
                      ),
                      if (_xeroBankAccountOptions.isEmpty &&
                          _xeroSalesAccountOptions.isEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Load accounts from Xero'),
                            onPressed: _loadXeroAccountOptions,
                          ),
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('Upload Logo'),
                onPressed: _pickLogo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _appColor,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              if (_logoPath != null)
                Expanded(
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_logoPath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  /// Builds a shareable link to the public customer-intake web form
  /// (public/new-customer.html, served via Firebase Hosting and backed
  /// by the submitCustomerForm Cloud Function). The `u` query param
  /// scopes any submissions straight into this signed-in user's own
  /// customers collection.
  String? _customerIntakeFormLink() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return 'https://soletradie-ab850.web.app/new-customer.html?u=$uid';
  }

  Widget _buildCustomerIntakeFormCard() {
    final link = _customerIntakeFormLink();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send this link to a prospective customer so they can fill in '
              'their own details (name, address, email, phone). They\'ll be '
              'added straight to your Customers list, and you\'ll get a '
              'notification on your phone once they\'ve submitted it.',
              style: TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 16),
            if (link == null)
              const Text(
                'Sign in to generate your customer intake form link.',
                style: TextStyle(color: Colors.grey),
              )
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      tooltip: 'Copy link',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share Customer Intake Form'),
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: 'Please fill in your details here: $link',
                        subject: 'New Customer Details Form',
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
          Row(
            children: [
              Expanded(
                child: TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: _firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: _lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _gasFittingLicenseController,
            decoration: const InputDecoration(
              labelText: 'Gas Fitting License',
              prefixIcon: Icon(Icons.local_gas_station),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _electricalLicenseController,
            decoration: const InputDecoration(
              labelText: 'Electrical License',
              prefixIcon: Icon(Icons.electrical_services),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _personalEmailController,
            decoration: const InputDecoration(
              labelText: 'Personal Email Address',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(textCapitalization: TextCapitalization.sentences, 
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          
          // Signature Section
          const Text(
            'Digital Signature',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Draw Signature'),
                onPressed: _drawSignature,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _appColor,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              if (_signaturePath != null)
                Expanded(
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_signaturePath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Certificate Email Section
          const Divider(),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Automatically email me certificates'),
            subtitle: const Text('Send a copy of generated certificates to your email'),
            value: _autoEmailCertificates,
            onChanged: (value) {
              if (value == true && !_hasAcceptedTerms) {
                _showTermsDialog();
              } else {
                setState(() {
                  _autoEmailCertificates = value ?? false;
                });
              }
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_autoEmailCertificates && _hasAcceptedTerms) 
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Terms accepted - certificates will be emailed automatically',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // App Color Picker
          const Text(
            'App Color Theme (Primary)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Used for the app bar, main buttons and primary highlights.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final color = await _showColorPickerDialog(_appColor, 'Pick App Color');
              if (color != null) {
                setState(() => _appColor = color);
                await _saveColor(color);
              }
            },
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: _appColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  'Tap to change color',
                  style: TextStyle(
                    color: ThemeData.estimateBrightnessForColor(_appColor) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Accent Color Picker (2nd colour)
          const Text(
            'Accent Color (Secondary)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Used app-wide for highlights, totals and success states (e.g. Dashboard invoice amount).',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final color = await _showColorPickerDialog(_accentColor, 'Pick Accent Color');
              if (color != null) {
                setState(() => _accentColor = color);
                await _saveAccentColor(color);
              }
            },
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  'Tap to change color',
                  style: TextStyle(
                    color: ThemeData.estimateBrightnessForColor(_accentColor) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Show Line Items Toggle
          SwitchListTile(
            title: const Text('Show Line Item Prices by Default'),
            subtitle: const Text('Display individual item prices in estimates'),
            value: _showLineItemPricesDefault,
            onChanged: (val) async {
              setState(() => _showLineItemPricesDefault = val);
              await setShowLineItemPricesDefault(val);
            },
            activeThumbColor: _appColor,
            contentPadding: EdgeInsets.zero,
          ),
          
          // Dark Mode Toggle
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Use dark theme for the app'),
            value: _isDarkMode,
            onChanged: (val) async {
              setState(() => _isDarkMode = val);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('dark_mode', val);
              // You can add theme switching logic here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Restart app to apply theme changes')),
              );
            },
            activeThumbColor: _appColor,
            contentPadding: EdgeInsets.zero,
          ),

          const Divider(height: 24),

          // Demo Mode Toggle
          SwitchListTile(
            title: const Text('Demo Mode'),
            subtitle: const Text(
              'Sandbox mode with fake customers, jobs, invoices & pricebook. Nothing saves to your real data.',
            ),
            value: _isDemoMode,
            onChanged: (val) async {
              if (val) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Enable Demo Mode?'),
                    content: const Text(
                      'The app will switch to a fully sandboxed demo with fake customers, jobs, invoices, pricebook and scheduling. '
                      'Nothing you do in Demo Mode will affect your real data, and no emails or documents will actually be sent. '
                      'You can turn this off again at any time.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Enable Demo Mode'),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                await DemoModeService.instance.enableDemoMode();
              } else {
                await DemoModeService.instance.disableDemoMode();
              }
              setState(() => _isDemoMode = val);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(val
                        ? 'Demo Mode enabled - showing sandbox data only'
                        : 'Demo Mode disabled - back to your real data'),
                  ),
                );
              }
            },
            activeThumbColor: _appColor,
            contentPadding: EdgeInsets.zero,
          ),
          if (_isDemoMode)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('Wipe Demo Data',
                      style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Wipe Demo Data?'),
                        content: const Text(
                          'This clears every fake customer, job, invoice, estimate, and pricebook item created in Demo Mode, and reseeds a fresh demo starter set. This cannot be undone.',
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
                            child: const Text('Wipe'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await DemoModeService.instance.wipeDemoData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Demo data wiped and reseeded')),
                        );
                      }
                    }
                  },
                ),
              ),
            ),

          const Divider(height: 24),
          const SizedBox(height: 16),
          const Text(
            'Address Search Region',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedCountry,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.public),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: const [
              DropdownMenuItem(
                value: 'New Zealand',
                child: Text('New Zealand'),
              ),
              // Future countries can be added here
              // DropdownMenuItem(
              //   value: 'Australia',
              //   child: Text('Australia'),
              // ),
              // DropdownMenuItem(
              //   value: 'United States',
              //   child: Text('United States'),
              // ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCountry = value);
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Select your country for address search and geocoding services',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          
          // Auto-backup Toggle
          SwitchListTile(
            title: const Text('Auto Backup'),
            subtitle: const Text('Automatically backup data weekly'),
            value: _autoBackup,
            onChanged: (val) async {
              setState(() => _autoBackup = val);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('auto_backup', val);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(val ? 'Auto backup enabled' : 'Auto backup disabled')),
              );
            },
            activeThumbColor: _appColor,
            contentPadding: EdgeInsets.zero,
          ),
          
          const SizedBox(height: 24),
          
          // Data Management Section
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.storage, color: _appColor),
              const SizedBox(width: 8),
              const Text(
                'Data Management',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clear App Data'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DataManagementScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_applications),
            label: const Text('Storage Settings'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StorageSettingsScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _appColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure what data is stored locally vs cloud',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 8),
          Text(
            'Safely clear jobs, customers, and app data to start fresh',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// Build GPS Timeline Import card
  Widget _buildGpsLocationCard() {
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
                Icon(Icons.location_history, color: _appColor, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Import Google Timeline',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  onPressed: _showGpsImportHelpDialog,
                  tooltip: 'How to export from Google Timeline',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            const Text(
              'Import your Google Timeline location history to automatically populate site visit data for accurate GPS-based job tracking. Supports JSON exports, encrypted backup files, and custom TXT formats.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: _importGoogleTimelineData,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import Timeline Data (JSON/TXT)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _appColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            
            // Clear GPS history button
            OutlinedButton.icon(
              onPressed: _clearGpsHistory,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear GPS History'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
            const SizedBox(height: 8),
            
            // Show GPS history stats button  
            OutlinedButton.icon(
              onPressed: _showGpsHistoryStats,
              icon: const Icon(Icons.info_outline),
              label: const Text('Show GPS History Stats'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _appColor,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
            const SizedBox(height: 12),
            
            Text(
              '1. Go to your phone Settings → Location → Timeline\n'
              '2. Export Timeline data as JSON or TXT file\n'
              '3. Upload the exported file here\n'
              '   Alternative: Use Google Takeout (takeout.google.com)\n'
              '   Select "Maps (your places)" → "Location History"\n'
              '   Download and select "Location History.json"\n'
              '   Or upload encrypted backup files (.txt)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build cloud sync and storage card
  Widget _buildCloudSyncCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
          // Manual Cloud Sync Section
          Row(
            children: [
              Icon(Icons.cloud_upload, color: _appColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manual Cloud Sync',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upload all local data to cloud storage',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isCloudSyncing ? null : _performManualCloudSync,
                icon: _isCloudSyncing 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload, size: 18),
                label: Text(_isCloudSyncing ? 'Syncing...' : 'Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Download from Cloud Section
          Row(
            children: [
              Icon(Icons.cloud_download, color: _appColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download from Cloud',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Download latest data from cloud storage',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isCloudSyncing ? null : _performManualCloudDownload,
                icon: _isCloudSyncing 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download, size: 18),
                label: Text(_isCloudSyncing ? 'Syncing...' : 'Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Throttled One-Way Sync Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              border: Border.all(color: Colors.purple[200]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed, color: Colors.purple[700], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Careful One-Way Sync (Throttled)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Slowly upload all local data with progress indicator',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '🎯 Perfect for careful data synchronization',
                  style: TextStyle(fontSize: 12, color: Colors.purple[900]),
                ),
                const SizedBox(height: 4),
                Text(
                  '⏱️ Throttled speed prevents network saturation',
                  style: TextStyle(fontSize: 12, color: Colors.purple[900]),
                ),
                const SizedBox(height: 4),
                Text(
                  '📊 Real-time progress indicator shows what\'s being uploaded',
                  style: TextStyle(fontSize: 12, color: Colors.purple[900]),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isThrottledSyncActive ? null : _performThrottledCloudSync,
                    icon: _isThrottledSyncActive 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload, size: 18),
                    label: Text(_isThrottledSyncActive 
                        ? 'Syncing... ${(_throttledSyncProgress * 100).toStringAsFixed(0)}%' 
                        : 'Start Throttled Sync'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Sync Status Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getSyncStatusText(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          Text(
            'Manual sync uploads/downloads all data types: customers, price book, builds, and estimates • Throttled sync limits speed to prevent network issues',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    ),
    );
  }

  /// Get current sync status text for display
  String _getSyncStatusText() {
    if (_isCloudSyncing) {
      return 'Sync in progress...';
    }
    
    // Check if we have connectivity
    return 'Ready to sync • Automatic sync runs every 2-30 minutes';
  }

  /// Perform manual cloud upload sync
  Future<void> _performManualCloudSync() async {
    if (_isCloudSyncing) return;
    
    setState(() {
      _isCloudSyncing = true;
    });

    try {
      // Trigger manual sync for all data types
      final dataTypes = [
        DataType.customers,
        DataType.priceBook,
        DataType.builds,
        DataType.estimates,
        DataType.jobs,
        DataType.documents,
        DataType.invoices,
      ];
      
      for (final dataType in dataTypes) {
        await SyncScheduler.syncNow(dataType);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud upload completed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isCloudSyncing = false;
      });
    }
  }

  /// Perform manual cloud download sync
  Future<void> _performManualCloudDownload() async {
    if (_isCloudSyncing) return;
    
    setState(() {
      _isCloudSyncing = true;
    });

    try {
      // Trigger manual sync for all data types
      final dataTypes = [
        DataType.customers,
        DataType.priceBook,
        DataType.builds,
        DataType.estimates,
        DataType.jobs,
        DataType.documents,
        DataType.invoices,
      ];
      
      for (final dataType in dataTypes) {
        await SyncScheduler.syncNow(dataType);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud download completed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud download failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isCloudSyncing = false;
      });
    }
  }

  /// Show PDF Scanner help dialog
  void _showPdfScannerHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF Receipt Scanner Help'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The PDF Receipt Scanner helps you extract items from supplier invoices.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('Setup Steps:'),
              SizedBox(height: 8),
              Text('1. Select supplier templates you use from the list below'),
              Text('2. Only selected templates will appear in the estimate builder'),
              Text('3. If your supplier isn\'t listed, use "Request New Template"'),
              SizedBox(height: 12),
              Text(
                'Usage:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('• In Estimate Builder, tap "PDF Receipt Scanner"'),
              Text('• Choose your supplier template'),
              Text('• Scan or upload the invoice'),
              Text('• Review and import extracted items'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Perform one-way throttled cloud sync with progress indicator
  Future<void> _performThrottledCloudSync() async {
    if (_isThrottledSyncActive) return;
    
    setState(() {
      _isThrottledSyncActive = true;
      _throttledSyncProgress = 0.0;
      _throttledSyncOperation = 'Starting sync...';
    });
    
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('One-Way Cloud Sync'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Uploading your local data to the cloud...',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _throttledSyncProgress,
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(_appColor),
                ),
              ),
              const SizedBox(height: 12),
              // Progress percentage
              Text(
                '${(_throttledSyncProgress * 100).toStringAsFixed(1)}% Complete',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _appColor,
                ),
              ),
              const SizedBox(height: 12),
              // Operation description
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _throttledSyncOperation,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  border: Border.all(color: Colors.blue[200]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sync is throttled to prevent network saturation. This ensures stable uploads even with slow connections.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    
    try {
      // Set up progress callback
      CloudSyncThrottledService.setProgressCallback((progress, operation) {
        setState(() {
          _throttledSyncProgress = progress;
          _throttledSyncOperation = operation;
        });
      });
      
      // Perform the sync
      final success = await CloudSyncThrottledService.performOneWaySync();
      
      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Cloud sync completed successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚠️ Cloud sync encountered issues. Check logs for details.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Cloud sync failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isThrottledSyncActive = false;
        _throttledSyncProgress = 0.0;
        _throttledSyncOperation = '';
      });
    }
  }

  /// Request new template functionality
  void _requestNewTemplate() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request New Supplier Template'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'To request a new supplier template:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('Option 1: Use SMTP (Recommended)'),
              Text('• Make sure SMTP is configured in Company Settings'),
              Text('• Upload a sample invoice from your supplier'),
              Text('• It will be automatically emailed for processing'),
              SizedBox(height: 12),
              Text('Option 2: Manual Email'),
              Text('• Email a sample invoice to:'),
              Text('admin@mrwattelectrical.com', 
                   style: TextStyle(fontWeight: FontWeight.w600)),
              Text('• Include your supplier name in the subject'),
              SizedBox(height: 12),
              Text(
                'Note: Templates typically take 1-2 business days to create.',
                style: TextStyle(fontStyle: FontStyle.italic),
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
              Navigator.pop(context);
              _uploadSampleInvoice();
            },
            child: const Text('Upload Sample Invoice'),
          ),
        ],
      ),
    );
  }

  /// Upload sample invoice for template creation
  Future<void> _uploadSampleInvoice() async {
    try {
      // Check if SMTP is configured
      final prefs = await SharedPreferences.getInstance();
      final smtpEmail = prefs.getString('smtp_email') ?? '';
      final smtpPassword = prefs.getString('smtp_password') ?? '';
      final smtpServer = prefs.getString('smtp_server') ?? '';
      
      if (smtpEmail.isEmpty || smtpPassword.isEmpty || smtpServer.isEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('SMTP Not Configured'),
            content: const Text(
              'Please configure SMTP settings in Company Settings first, or manually email your sample invoice to admin@mrwattelectrical.com'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Pick invoice file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        
        // Get supplier name from user
        final supplierName = await _getSupplierNameDialog();
        if (supplierName == null || supplierName.trim().isEmpty) return;

        // Send email with attachment
        await _sendTemplateRequestEmail(file, supplierName.trim());
        
        // Success message is now handled inside _sendTemplateRequestEmail
        // if (mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     const SnackBar(
        //       content: Text('Sample invoice sent successfully! Template will be created within 1-2 business days.'),
        //       backgroundColor: Colors.green,
        //     ),
        //   );
        // }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send sample invoice: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get supplier name from user dialog
  Future<String?> _getSupplierNameDialog() async {
    final controller = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supplier Name'),
        content: TextField(textCapitalization: TextCapitalization.sentences, 
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter supplier name',
            hintText: 'e.g., Bunnings, Electrical Wholesalers',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// Send template request email with invoice attachment
  Future<void> _sendTemplateRequestEmail(File invoiceFile, String supplierName) async {
    try {
      print('🚀 Starting template request email for supplier: $supplierName');
      
      final prefs = await SharedPreferences.getInstance();
      final smtpEmail = prefs.getString('smtp_email');
      final smtpPassword = prefs.getString('smtp_password');
      final smtpServer = prefs.getString('smtp_server');
      final smtpPort = int.tryParse(prefs.getString('smtp_port') ?? '587') ?? 587;
      final companyName = prefs.getString('company_name') ?? 'Unknown Company';

      // Validate SMTP settings
      if (smtpEmail == null || smtpEmail.isEmpty) {
        throw Exception('SMTP email not configured');
      }
      if (smtpPassword == null || smtpPassword.isEmpty) {
        throw Exception('SMTP password not configured');
      }
      if (smtpServer == null || smtpServer.isEmpty) {
        throw Exception('SMTP server not configured');
      }

      print('📧 SMTP Settings validated - Server: $smtpServer:$smtpPort');

      // Configure SMTP
      final smtpServerConfig = SmtpServer(
        smtpServer,
        port: smtpPort,
        username: smtpEmail,
        password: smtpPassword,
        ssl: smtpPort == 465,
        allowInsecure: false,
      );

      // Create email message
      final message = Message()
        ..from = Address(smtpEmail, companyName)
        ..recipients.add('admin@mrwattelectrical.com')
        ..subject = 'New Receipt Template Request - $supplierName'
        ..text = '''
Hello,

Please create a new receipt template for the following supplier:

Supplier Name: $supplierName
Requested by: $companyName
Email: $smtpEmail

Sample invoice attached.

Thank you!
''';

      // Add attachment
      message.attachments.add(FileAttachment(invoiceFile));

      print('📤 Sending template request email via $smtpServer...');
      
      // Send email
      await send(message, smtpServerConfig);
      
      print('✅ Template request email sent successfully!');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sample invoice sent successfully! Template will be created within 1-2 business days.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Template request email failed: $e');
      
      String errorMessage = 'Failed to send template request: ';
      if (e.toString().contains('SMTP email not configured') ||
          e.toString().contains('SMTP password not configured') ||
          e.toString().contains('SMTP server not configured')) {
        errorMessage += 'SMTP settings not properly configured. Please check your email settings.';
      } else if (e.toString().contains('Authentication')) {
        errorMessage += 'Email authentication failed. Please check your email and password.';
      } else if (e.toString().contains('Connection')) {
        errorMessage += 'Could not connect to email server. Please check your server settings and internet connection.';
      } else if (e.toString().contains('timeout')) {
        errorMessage += 'Email sending timed out. Please try again.';
      } else {
        errorMessage += e.toString();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      
      // Re-throw to maintain existing error handling behavior
      rethrow;
    }
  }

  /// Show help dialog for GPS import
  void _showGpsImportHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Google Timeline Export Guide'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Two ways to export your Google Timeline data:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                Text(
                  'Method 1: From your phone (Recommended)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
                const SizedBox(height: 8),
                Text('1. Open Settings on your phone'),
                const SizedBox(height: 4),
                Text('2. Go to Location → Timeline'),
                const SizedBox(height: 4),
                Text('3. Look for export or backup options'),
                const SizedBox(height: 4),
                Text('4. Export as JSON or TXT file'),
                const SizedBox(height: 16),
                
                Text(
                  'Method 2: Google Takeout (Alternative)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                Text('1. Go to takeout.google.com'),
                const SizedBox(height: 4),
                Text('2. Sign in to your Google account'),
                const SizedBox(height: 4),
                Text('3. Click "Deselect all"'),
                const SizedBox(height: 4),
                Text('4. Find and check "Maps (your places)"'),
                const SizedBox(height: 4),
                Text('5. Click "Multiple formats" → Location History → JSON'),
                const SizedBox(height: 4),
                Text('6. Click "Next step" → "Create export"'),
                const SizedBox(height: 4),
                Text('7. Download when ready (can take hours)'),
                const SizedBox(height: 4),
                Text('8. Extract and select "Location History.json"'),
                const SizedBox(height: 16),
                Text(
                  'Supported file types: .json and .txt files',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Note: Large files may take time to process',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Import Google Timeline data
  Future<void> _importGoogleTimelineData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      
      if (result != null) {
        File file = File(result.files.single.path!);
        String contents = await file.readAsString();
        
        print('📁 File selected: ${result.files.single.name}');
        print('📏 File size: ${contents.length} characters');
        
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Processing Google Timeline data...'),
                  const SizedBox(height: 8),
                  Text(
                    'This may take a few moments for large files',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          },
        );
        
        // Process the data based on file extension
        final fileName = result.files.single.name.toLowerCase();
        Map<String, dynamic> timelineData;
        
        print('🔍 Processing file: $fileName');
        
        if (fileName.endsWith('.json')) {
          // Handle JSON format (standard Google Timeline export)
          try {
            print('📊 Parsing as JSON...');
            timelineData = json.decode(contents);
            print('✅ JSON parsed successfully');
            print('🔑 Top-level keys: ${timelineData.keys.toList()}');
          } catch (e) {
            print('❌ JSON parsing failed: $e');
            throw Exception('Invalid JSON format: ${e.toString()}');
          }
        } else if (fileName.endsWith('.txt')) {
          // Handle TXT format (could be JSON data in a .txt file or custom format)
          try {
            print('📊 Trying to parse TXT as JSON first...');
            // First try to parse as JSON
            timelineData = json.decode(contents);
            print('✅ TXT file contains valid JSON');
            print('🔑 Top-level keys: ${timelineData.keys.toList()}');
          } catch (e) {
            print('⚠️ TXT is not JSON, trying custom format parsing...');
            // If JSON parsing fails, try to parse as custom text format
            timelineData = _parseCustomTextFormat(contents);
            print('✅ Custom format parsed successfully');
          }
        } else {
          // Try to parse as JSON regardless of extension
          try {
            print('📊 Trying to parse unknown extension as JSON...');
            timelineData = json.decode(contents);
            print('✅ Unknown extension contains valid JSON');
          } catch (e) {
            print('❌ Failed to parse unknown extension: $e');
            throw Exception('Unsupported file format. Please provide a JSON or TXT file.');
          }
        }
        
        await _processTimelineData(timelineData);
        
        // Close loading dialog
        Navigator.of(context).pop();
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Timeline data imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
      } else {
        print('📁 No file selected');
      }
    } catch (e) {
      print('❌ Import error: $e');
      
      // Close loading dialog if it's open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing timeline data: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Process timeline data from Google Timeline export
  Future<void> _processTimelineData(Map<String, dynamic> timelineData) async {
    List<Map<String, dynamic>> gpsHistory = [];
    
    print('📍 Processing timeline data...');
    print('Timeline data keys: ${timelineData.keys.toList()}');
    
    // Parse timeline data structure - handle both old and new formats
    if (timelineData.containsKey('semanticSegments')) {
      // New Google Takeout format with semanticSegments
      List<dynamic> semanticSegments = timelineData['semanticSegments'];
      print('Found ${semanticSegments.length} semantic segments (new format)');
      
      for (var segment in semanticSegments) {
        if (segment.containsKey('visit')) {
          var visit = segment['visit'];
          
          // Extract location data from the visit
          if (visit.containsKey('topCandidate') && visit['topCandidate'].containsKey('placeLocation')) {
            var placeLocation = visit['topCandidate']['placeLocation'];
            if (placeLocation.containsKey('latLng')) {
              // Parse latLng string format: "-40.9028717°, 174.9944819°"
              String latLngStr = placeLocation['latLng'];
              var coords = latLngStr.replaceAll('°', '').split(', ');
              if (coords.length == 2) {
                double lat = double.parse(coords[0]);
                double lng = double.parse(coords[1]);
                
                // Extract timing data
                String? startTime = segment['startTime'];
                String? endTime = segment['endTime'];
                
                // Extract address/place info
                String? address;
                if (visit['topCandidate'].containsKey('placeId')) {
                  address = 'Place ID: ${visit['topCandidate']['placeId']}';
                }
                if (visit['topCandidate'].containsKey('semanticType')) {
                  String semanticType = visit['topCandidate']['semanticType'];
                  address = semanticType != 'UNKNOWN' ? semanticType : address;
                }
                
                // If no meaningful address found, try reverse geocoding
                if (address == null || address.startsWith('Place ID:') || address == 'UNKNOWN') {
                  try {
                    List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
                    if (placemarks.isNotEmpty) {
                      Placemark place = placemarks.first;
                      List<String> addressParts = [];
                      
                      if (place.street != null && place.street!.isNotEmpty) {
                        addressParts.add(place.street!);
                      }
                      if (place.locality != null && place.locality!.isNotEmpty) {
                        addressParts.add(place.locality!);
                      }
                      if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
                        addressParts.add(place.administrativeArea!);
                      }
                      
                      if (addressParts.isNotEmpty) {
                        address = addressParts.join(', ');
                      }
                    }
                  } catch (e) {
                    print('Geocoding failed for $lat, $lng: $e');
                  }
                }
                
                // Create GPS history entry
                Map<String, dynamic> gpsEntry = {
                  'latitude': lat,
                  'longitude': lng,
                  'timestamp': startTime ?? DateTime.now().toIso8601String(),
                  'departureTime': endTime,
                  'duration': endTime != null && startTime != null ? 
                    _calculateDuration(startTime, endTime) : null,
                  'address': address ?? 'Location ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  'duration_start': startTime,
                  'duration_end': endTime,
                  'visit_confidence': 'HIGH',
                  'probability': visit['probability']?.toString() ?? 'N/A',
                };
                
                gpsHistory.add(gpsEntry);
                print('Added visit entry: ${gpsEntry['address']} at ${gpsEntry['timestamp']}');
              }
            }
          }
        } else if (segment.containsKey('timelinePath')) {
          // Handle timeline path data (movement tracking)
          var timelinePath = segment['timelinePath'];
          if (timelinePath is List && timelinePath.isNotEmpty) {
            for (var point in timelinePath) {
              if (point.containsKey('point') && point.containsKey('time')) {
                // Parse point format: "-40.9027739°, 174.9943628°"
                String pointStr = point['point'];
                var coords = pointStr.replaceAll('°', '').split(', ');
                if (coords.length == 2) {
                  double lat = double.parse(coords[0]);
                  double lng = double.parse(coords[1]);
                  
                  Map<String, dynamic> gpsEntry = {
                    'latitude': lat,
                    'longitude': lng,
                    'timestamp': point['time'],
                    'address': await _getAddressFromCoordinates(lat, lng) ?? 'Movement Point ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                    'visit_confidence': 'MEDIUM',
                  };
                  
                  gpsHistory.add(gpsEntry);
                  print('Added timeline path point: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
                }
              }
            }
          }
        } else if (segment.containsKey('activity')) {
          // Handle activity data (travel segments)
          var activity = segment['activity'];
          String? startTime = segment['startTime'];
          String? endTime = segment['endTime'];
          
          // Add start location
          if (activity.containsKey('start') && activity['start'].containsKey('latLng')) {
            String latLngStr = activity['start']['latLng'];
            var coords = latLngStr.replaceAll('°', '').split(', ');
            if (coords.length == 2) {
              double lat = double.parse(coords[0]);
              double lng = double.parse(coords[1]);
              
              Map<String, dynamic> gpsEntry = {
                'latitude': lat,
                'longitude': lng,
                'timestamp': startTime ?? DateTime.now().toIso8601String(),
                'address': await _getAddressFromCoordinates(lat, lng) ?? 'Activity Start ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                'visit_confidence': 'MEDIUM',
                'activity_type': activity['topCandidate']?['type'] ?? 'UNKNOWN',
              };
              
              gpsHistory.add(gpsEntry);
              print('Added activity start: ${gpsEntry['address']}');
            }
          }
          
          // Add end location
          if (activity.containsKey('end') && activity['end'].containsKey('latLng')) {
            String latLngStr = activity['end']['latLng'];
            var coords = latLngStr.replaceAll('°', '').split(', ');
            if (coords.length == 2) {
              double lat = double.parse(coords[0]);
              double lng = double.parse(coords[1]);
              
              Map<String, dynamic> gpsEntry = {
                'latitude': lat,
                'longitude': lng,
                'timestamp': endTime ?? DateTime.now().toIso8601String(),
                'address': await _getAddressFromCoordinates(lat, lng) ?? 'Activity End ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                'visit_confidence': 'MEDIUM',
                'activity_type': activity['topCandidate']?['type'] ?? 'UNKNOWN',
              };
              
              gpsHistory.add(gpsEntry);
              print('Added activity end: ${gpsEntry['address']}');
            }
          }
        }
      }
    } else if (timelineData.containsKey('timelineObjects')) {
      // Old Google Timeline format with timelineObjects
      List<dynamic> timelineObjects = timelineData['timelineObjects'];
      print('Found ${timelineObjects.length} timeline objects (old format)');
      
      for (var timelineObject in timelineObjects) {
        if (timelineObject.containsKey('placeVisit')) {
          var placeVisit = timelineObject['placeVisit'];
          
          // Extract location data
          if (placeVisit.containsKey('location')) {
            var location = placeVisit['location'];
            if (location.containsKey('latitudeE7') && location.containsKey('longitudeE7')) {
              double lat = location['latitudeE7'] / 10000000.0;
              double lng = location['longitudeE7'] / 10000000.0;
              
              // Extract timing data
              String? startTime;
              String? endTime;
              
              if (placeVisit.containsKey('duration')) {
                var duration = placeVisit['duration'];
                startTime = duration['startTimestamp'];
                endTime = duration['endTimestamp'];
              }
              
              // Extract address if available
              String? address;
              if (location.containsKey('address')) {
                address = location['address'];
              } else if (location.containsKey('name')) {
                address = location['name'];
              } else {
                // Try reverse geocoding for a proper address
                address = await _getAddressFromCoordinates(lat, lng);
              }
              
              // Create GPS history entry
              Map<String, dynamic> gpsEntry = {
                'latitude': lat,
                'longitude': lng,
                'timestamp': startTime ?? DateTime.now().toIso8601String(),
                'departureTime': endTime,
                'duration': endTime != null && startTime != null ? 
                  _calculateDuration(startTime, endTime) : null,
                'address': address ?? 'Location ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                'duration_start': startTime,
                'duration_end': endTime,
                'visit_confidence': placeVisit.containsKey('visitConfidence') ? placeVisit['visitConfidence'] : 'HIGH',
              };
              
              gpsHistory.add(gpsEntry);
              print('Added entry: ${gpsEntry['address']} at ${gpsEntry['timestamp']}');
            }
          }
        }
      }
    } else {
      print('⚠️ No recognized timeline format found. Available keys: ${timelineData.keys.toList()}');
      print('Expected either "semanticSegments" (new format) or "timelineObjects" (old format)');
    }
    
    print('📊 Processed ${gpsHistory.length} GPS entries from timeline data');
    
    // Sort by timestamp (newest first)
    gpsHistory.sort((a, b) {
      try {
        DateTime timeA = DateTime.parse(a['timestamp']);
        DateTime timeB = DateTime.parse(b['timestamp']);
        return timeB.compareTo(timeA);
      } catch (e) {
        return 0;
      }
    });
    
    // Store in SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // Get existing data and merge
    String? existingData = prefs.getString('gps_visit_history');
    List<Map<String, dynamic>> existingHistory = [];
    
    if (existingData != null) {
      try {
        List<dynamic> decoded = json.decode(existingData);
        existingHistory = decoded.cast<Map<String, dynamic>>();
        print('📂 Found ${existingHistory.length} existing GPS entries');
      } catch (e) {
        print('❌ Error parsing existing GPS history: $e');
      }
    }
      
    // Merge new data with existing (avoid duplicates based on location and time)
    // Use a more precise duplicate detection method
    Set<String> existingKeys = existingHistory.map((entry) {
      // Round coordinates to 6 decimal places and normalize timestamp to avoid minor differences
      final lat = (entry['latitude'] as double).toStringAsFixed(6);
      final lng = (entry['longitude'] as double).toStringAsFixed(6);
      final timestamp = entry['timestamp']?.toString() ?? '';
      return '${lat}_${lng}_$timestamp';
    }).toSet();
    
    int newEntriesCount = 0;
    for (var entry in gpsHistory) {
      // Use same precision for comparison
      final lat = (entry['latitude'] as double).toStringAsFixed(6);
      final lng = (entry['longitude'] as double).toStringAsFixed(6);
      final timestamp = entry['timestamp']?.toString() ?? '';
      final key = '${lat}_${lng}_$timestamp';
      
      if (!existingKeys.contains(key)) {
        existingHistory.add(entry);
        existingKeys.add(key); // Add to set to avoid duplicates within this import
        newEntriesCount++;
        print('✅ Added new entry: ${entry['address']}');
      } else {
        print('⏭️ Skipped duplicate: ${entry['address']}');
      }
    }
    
    // Save merged data
    await prefs.setString('gps_visit_history', json.encode(existingHistory));
    
    print('✅ Imported $newEntriesCount new location entries from Google Timeline');
    print('📊 Total entries in storage: ${existingHistory.length}');
    
    // Debug: Print first few entries
    if (existingHistory.isNotEmpty) {
      print('📋 Sample entries:');
      for (int i = 0; i < (existingHistory.length > 3 ? 3 : existingHistory.length); i++) {
        var entry = existingHistory[i];
        print('  Entry $i: ${entry['address']} at ${entry['timestamp']}');
      }
    } else {
      print('⚠️ No entries in final storage - check timeline data format');
    }
  }

  /// Calculate duration between start and end timestamps
  String? _calculateDuration(String startTime, String endTime) {
    try {
      final start = DateTime.parse(startTime);
      final end = DateTime.parse(endTime);
      final duration = end.difference(start);
      
      if (duration.inHours > 0) {
        return '${duration.inHours}h ${duration.inMinutes % 60}m';
      } else if (duration.inMinutes > 0) {
        return '${duration.inMinutes}m';
      } else {
        return '${duration.inSeconds}s';
      }
    } catch (e) {
      return null;
    }
  }

  /// Convert coordinates to human-readable address using reverse geocoding
  Future<String?> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        List<String> addressParts = [];
        
        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          addressParts.add(place.administrativeArea!);
        }
        
        if (addressParts.isNotEmpty) {
          return addressParts.join(', ');
        }
      }
    } catch (e) {
      print('Geocoding failed for $lat, $lng: $e');
    }
    return null;
  } 

  /// Clear all GPS history data
  Future<void> _clearGpsHistory() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear GPS History'),
          content: const Text('Are you sure you want to clear all GPS location history? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Clear'),
            ),
          ],
        ),
      );
      
      if (confirmed == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('gps_visit_history');
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS history cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing GPS history: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show GPS history statistics and sample data
  Future<void> _showGpsHistoryStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('gps_visit_history') ?? '[]';
      final historyList = json.decode(historyJson) as List;
      
      String content = 'Total GPS entries: ${historyList.length}\n\n';
      
      if (historyList.isNotEmpty) {
        content += 'Sample entries:\n\n';
        for (int i = 0; i < (historyList.length > 5 ? 5 : historyList.length); i++) {
          var entry = historyList[i];
          content += '${i + 1}. ${entry['address'] ?? 'Unknown'}\n';
          content += '   Lat: ${entry['latitude']}, Lng: ${entry['longitude']}\n';
          content += '   Time: ${entry['timestamp']}\n';
          
          // Calculate duration, including current time if still on-site
          double displayDuration = 0.0;
          String durationNote = '';

          final durationStartRaw = entry['duration_start'] ?? entry['timestamp'];
          final durationEndRaw = entry['duration_end'] ?? entry['departureTime'];

          if (durationStartRaw != null) {
            try {
              final startTime = DateTime.parse(durationStartRaw);
              if (durationEndRaw != null) {
                final endTime = DateTime.parse(durationEndRaw);
                displayDuration = endTime.difference(startTime).inMinutes / 60.0;
              } else {
                // Still on-site - calculate time to current moment
                final currentTime = DateTime.now();
                displayDuration = currentTime.difference(startTime).inMinutes / 60.0;
                durationNote = ' (still on-site)';
              }
            } catch (e) {
              // Keep duration at 0.0 if parsing fails
            }
          }
          
          if (displayDuration > 0) {
            content += '   Duration: ${displayDuration.toStringAsFixed(1)}h$durationNote\n';
          }
          
          content += '\n';
        }
        
        content += '\nNote: If no departure time, duration shows time from arrival to now (still on-site)';
      } else {
        content += 'No GPS data found. Try importing timeline data first.';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GPS History Stats'),
          content: SingleChildScrollView(
            child: Text(content),
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
        SnackBar(
          content: Text('Error loading GPS history stats: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Parse custom text format for timeline data
  Map<String, dynamic> _parseCustomTextFormat(String contents) {
    List<Map<String, dynamic>> timelineObjects = [];
    
    try {
      // First, try to handle Google encrypted backup format
      if (contents.contains('Google Timeline') || contents.contains('Location History') || 
          contents.contains('"activitySegment"') || contents.contains('"placeVisit"')) {
        print('Detected potential Google Timeline encrypted backup format');
        
        // Try to extract JSON objects from the encrypted backup text
        final jsonObjectPattern = RegExp(r'\{[^{}]*"(?:activitySegment|placeVisit)"[^{}]*\}|\{[^{}]*"latitudeE7"[^{}]*\}');
        final matches = jsonObjectPattern.allMatches(contents);
        
        for (final match in matches) {
          try {
            final jsonStr = match.group(0)!;
            final Map<String, dynamic> obj = json.decode(jsonStr);
            
            if (obj.containsKey('placeVisit')) {
              timelineObjects.add(obj);
            } else if (obj.containsKey('latitudeE7') && obj.containsKey('longitudeE7')) {
              // Convert standalone location to placeVisit format
              final placeVisit = {
                'location': {
                  'latitudeE7': obj['latitudeE7'],
                  'longitudeE7': obj['longitudeE7'],
                  'address': obj['address'] ?? 'Unknown Location',
                  'name': obj['name'] ?? obj['address'] ?? 'Unknown Location',
                },
                'duration': {
                  'startTimestamp': obj['timestamp'] ?? DateTime.now().toIso8601String(),
                  'endTimestamp': obj['endTimestamp'] ?? DateTime.now().toIso8601String(),
                },
                'visitConfidence': 'MEDIUM',
              };
              timelineObjects.add({'placeVisit': placeVisit});
            }
          } catch (e) {
            continue;
          }
        }
      }
      
      // If no encrypted data found, try the standard parsing methods
      if (timelineObjects.isEmpty) {
        // Split content into lines and process each line
        final lines = contents.split('\n');
        print('Parsing ${lines.length} lines from text file');
        
        for (String line in lines) {
          line = line.trim();
          if (line.isEmpty) continue;
          
          // Try to parse as JSON object per line
          try {
            final Map<String, dynamic> lineData = json.decode(line);
            
            // Convert simple formats to Google Timeline format
            if (lineData.containsKey('latitude') && lineData.containsKey('longitude')) {
              final placeVisit = {
                'location': {
                  'latitudeE7': ((lineData['latitude'] as num) * 10000000).round(),
                  'longitudeE7': ((lineData['longitude'] as num) * 10000000).round(),
                  'address': lineData['address'] ?? 'Unknown Location',
                  'name': lineData['name'] ?? lineData['address'] ?? 'Unknown Location',
                },
                'duration': {
                  'startTimestamp': lineData['timestamp'] ?? DateTime.now().toIso8601String(),
                  'endTimestamp': lineData['endTimestamp'] ?? lineData['departureTime'] ?? DateTime.now().toIso8601String(),
                },
                'visitConfidence': lineData['confidence'] ?? 'HIGH',
              };
              
              timelineObjects.add({'placeVisit': placeVisit});
            }
          } catch (e) {
            // Skip lines that can't be parsed as JSON
            continue;
          }
        }
      }
      
      // If no objects were parsed, try to parse the entire content as a simple format
      if (timelineObjects.isEmpty) {
        print('No JSON objects found, trying CSV-like format');
        final lines = contents.split('\n');
        // Try to parse as a simple CSV-like format
        for (String line in lines) {
          if (line.trim().isEmpty) continue;
          
          // Handle different separators: comma, tab, semicolon, pipe
          List<String> parts = [];
          if (line.contains(',')) {
            parts = line.split(',');
          } else if (line.contains('\t')) {
            parts = line.split('\t');
          } else if (line.contains(';')) {
            parts = line.split(';');
          } else if (line.contains('|')) {
            parts = line.split('|');
          } else if (line.contains(' ')) {
            parts = line.split(' ');
          }
          
          if (parts.length >= 2) {
            try {
              final lat = double.tryParse(parts[0].trim());
              final lng = double.tryParse(parts[1].trim());
              final timestamp = parts.length > 3 ? parts[3].trim() : DateTime.now().toIso8601String();
              final address = parts.length > 2 ? parts[2].trim() : 'Unknown Location';
              
              if (lat != null && lng != null) {
                final placeVisit = {
                  'location': {
                    'latitudeE7': (lat * 10000000).round(),
                    'longitudeE7': (lng * 10000000).round(),
                    'address': address,
                    'name': address,
                  },
                  'duration': {
                    'startTimestamp': timestamp,
                    'endTimestamp': timestamp,
                  },
                  'visitConfidence': 'MEDIUM',
                };
                
                timelineObjects.add({'placeVisit': placeVisit});
                print('Parsed location: $lat, $lng, $address');
              }
            } catch (e) {
              continue;
            }
          }
        }
      }
      
      // If still no data, try advanced pattern matching for encrypted backups
      if (timelineObjects.isEmpty) {
        print('No structured data found, trying encrypted backup patterns');
        
        // Look for Google Timeline encrypted format patterns
        final timelinePattern = RegExp(r'"latitudeE7"\s*:\s*(-?\d+).*?"longitudeE7"\s*:\s*(-?\d+)', dotAll: true);
        final matches = timelinePattern.allMatches(contents);
        
        for (final match in matches) {
          try {
            final latE7 = int.parse(match.group(1)!);
            final lngE7 = int.parse(match.group(2)!);
            final lat = latE7 / 10000000.0;
            final lng = lngE7 / 10000000.0;
            
            // Basic validation that these look like valid coordinates
            if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
              final placeVisit = {
                'location': {
                  'latitudeE7': latE7,
                  'longitudeE7': lngE7,
                  'address': 'Location ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  'name': 'Encrypted Backup Location',
                },
                'duration': {
                  'startTimestamp': DateTime.now().toIso8601String(),
                  'endTimestamp': DateTime.now().toIso8601String(),
                },
                'visitConfidence': 'MEDIUM',
              };
              
              timelineObjects.add({'placeVisit': placeVisit});
              print('Found encrypted backup coordinates: $lat, $lng');
            }
          } catch (e) {
            continue;
          }
        }
        
        // If still no data, look for any latitude/longitude patterns in the text
        if (timelineObjects.isEmpty) {
          final latLngPattern = RegExp(r'(-?\d+\.?\d*)[,\s]+(-?\d+\.?\d*)');
          final coordMatches = latLngPattern.allMatches(contents);
          
          for (final match in coordMatches) {
            try {
              final lat = double.parse(match.group(1)!);
              final lng = double.parse(match.group(2)!);
              
              // Basic validation that these look like valid coordinates
              if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                final placeVisit = {
                  'location': {
                    'latitudeE7': (lat * 10000000).round(),
                    'longitudeE7': (lng * 10000000).round(),
                    'address': 'Location ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                    'name': 'Parsed Location',
                  },
                  'duration': {
                    'startTimestamp': DateTime.now().toIso8601String(),
                    'endTimestamp': DateTime.now().toIso8601String(),
                  },
                  'visitConfidence': 'LOW',
                };
                
                timelineObjects.add({'placeVisit': placeVisit});
                print('Found coordinate pair: $lat, $lng');
              }
            } catch (e) {
              continue;
            }
          }
        }
      }
      
    } catch (e) {
      throw Exception('Failed to parse custom text format: ${e.toString()}');
    }
    
    if (timelineObjects.isEmpty) {
      throw Exception('No valid location data found in the text file. Expected formats:\n'
          '• Standard Google Timeline JSON export\n'
          '• Google Timeline encrypted backup files\n'
          '• JSON objects per line with latitude/longitude fields\n'
          '• CSV format: latitude,longitude,address,timestamp\n'
          '• Simple coordinate pairs: lat lng\n'
          '\nFor encrypted backups:\n'
          '• Export from Google Takeout → Maps → Location History\n'
          '• Choose "All location data" format\n'
          '• Files may contain encrypted or encoded location data\n'
          '\nPlease check that your file contains location data in one of these formats.');
    }
    
    print('Successfully parsed ${timelineObjects.length} location entries');
    return {'timelineObjects': timelineObjects};
  }
}