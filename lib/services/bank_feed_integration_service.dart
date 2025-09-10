import 'package:shared_preferences/shared_preferences.dart';
import 'myob_service.dart';
import 'xero_service.dart';
import '../models/job.dart';
import '../models/customer.dart';

class BankFeedIntegrationService {
  static const String _lastSyncKey = 'last_bank_feed_sync';
  static const String _autoSyncEnabledKey = 'auto_sync_enabled';
  static const String _syncTimeKey = 'sync_time';

  // Convert job invoices to accounting software format
  static Future<void> syncJobInvoiceToAccounting({
    required Job job,
    required Customer customer,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final myobEnabled = prefs.getBool('myob_enabled') ?? false;
    final xeroEnabled = prefs.getBool('xero_enabled') ?? false;

    if (myobEnabled) {
      await _syncToMyob(job, customer);
    }

    if (xeroEnabled) {
      await _syncToXero(job, customer);
    }
  }

  static Future<void> _syncToMyob(Job job, Customer customer) async {
    try {
      final credentials = await MyobService.getStoredCredentials();
      if (credentials['apiKey'] == null || credentials['companyFileId'] == null) {
        print('MYOB credentials not found');
        return;
      }

      final myobService = MyobService();

      // For each paid invoice in the job, create accounting entry
      final invoiceVersions = job.estimateVersions.where((version) => 
        version.type == 'invoice' && version.isPaid);
        
      for (final invoice in invoiceVersions) {
        final invoiceData = {
          'Customer': {
            'UID': 'customer-${customer.id}',
          },
          'InvoiceNumber': invoice.invoiceNumber ?? 'INV-${invoice.id}',
          'Date': invoice.dueDate?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'InvoiceDeliveryStatus': 'Email',
          'Lines': [
            {
              'Description': job.title,
              'UnitPrice': invoice.amount,
              'Quantity': 1,
              'Account': {
                'UID': 'income-account-uid',
              },
              'TaxCode': {
                'UID': 'gst-tax-code-uid',
              },
            }
          ],
        };

        await myobService.createInvoice(
          apiKey: credentials['apiKey']!,
          companyFileId: credentials['companyFileId']!,
          username: credentials['username']!,
          password: credentials['password']!,
          invoiceData: invoiceData,
        );
      }

      print('Successfully synced job ${job.id} to MYOB');
    } catch (e) {
      print('Failed to sync to MYOB: $e');
    }
  }

  static Future<void> _syncToXero(Job job, Customer customer) async {
    try {
      final credentials = await XeroService.getStoredCredentials();
      if (credentials['accessToken'] == null) {
        print('Xero access token not found');
        return;
      }

      final xeroService = XeroService();

      // Create or update customer contact
      final contactData = {
        'Name': customer.name,
        'FirstName': customer.name.split(' ').first,
        'LastName': customer.name.split(' ').last,
        'EmailAddress': customer.email,
        'Addresses': [
          {
            'AddressType': 'STREET',
            'AddressLine1': customer.address,
            'City': '',
            'Region': '',
            'PostalCode': '',
            'Country': '',
          }
        ],
        'Phones': [
          {
            'PhoneType': 'DEFAULT',
            'PhoneNumber': customer.phone,
          }
        ],
        'IsCustomer': true,
      };

      await xeroService.createContact(
        accessToken: credentials['accessToken']!,
        contactData: contactData,
      );

      // For each paid invoice in the job, create Xero invoice
      final invoiceVersions = job.estimateVersions.where((version) => 
        version.type == 'invoice' && version.isPaid);
        
      for (final invoice in invoiceVersions) {
        final invoiceData = {
          'Type': 'ACCREC',
          'Contact': {
            'Name': customer.name,
          },
          'InvoiceNumber': invoice.invoiceNumber ?? 'INV-${invoice.id}',
          'Date': invoice.dueDate?.toIso8601String().split('T').first ?? 
                 DateTime.now().toIso8601String().split('T').first,
          'DueDate': invoice.dueDate?.toIso8601String().split('T').first ?? 
                    DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first,
          'LineItems': [
            {
              'Description': job.title,
              'UnitAmount': invoice.amount,
              'Quantity': 1,
              'AccountCode': '200', // Income account
              'TaxType': 'OUTPUT', // GST
            }
          ],
          'Status': invoice.isPaid ? 'PAID' : 'DRAFT',
        };

        await xeroService.createInvoice(
          accessToken: credentials['accessToken']!,
          invoiceData: invoiceData,
        );
      }

      print('Successfully synced job ${job.id} to Xero');
    } catch (e) {
      print('Failed to sync to Xero: $e');
    }
  }

  // Bank feed matching utilities
  static Future<List<Map<String, dynamic>>> matchBankTransactionsToJobs(
    List<Map<String, dynamic>> transactions,
    List<Job> jobs,
  ) async {
    List<Map<String, dynamic>> matches = [];

    for (final transaction in transactions) {
      final amount = transaction['Amount'] ?? transaction['Total'] ?? 0.0;
      final description = transaction['Description'] ?? transaction['Reference'] ?? '';
      
      // Try to match by amount and description
      for (final job in jobs) {
        final invoiceVersions = job.estimateVersions.where((version) => 
          version.type == 'invoice');
          
        for (final invoice in invoiceVersions) {
          if (_isAmountMatch(amount, invoice.amount) && 
              _isDescriptionMatch(description, job, invoice)) {
            matches.add({
              'transaction': transaction,
              'job': job,
              'invoice': invoice,
              'confidence': _calculateMatchConfidence(transaction, job, invoice),
            });
          }
        }
      }
    }

    // Sort by confidence score
    matches.sort((a, b) => b['confidence'].compareTo(a['confidence']));
    return matches;
  }

  static bool _isAmountMatch(double transactionAmount, double invoiceAmount) {
    // Allow for small differences (e.g., bank fees)
    const tolerance = 5.0;
    return (transactionAmount - invoiceAmount).abs() <= tolerance;
  }

  static bool _isDescriptionMatch(String description, Job job, invoice) {
    final searchTerms = [
      job.title.toLowerCase(),
      (job.customerName ?? '').toLowerCase(),
      invoice.invoiceNumber?.toLowerCase() ?? '',
    ];

    final descLower = description.toLowerCase();
    return searchTerms.any((term) => term.isNotEmpty && (descLower.contains(term) || term.contains(descLower)));
  }

  static double _calculateMatchConfidence(
    Map<String, dynamic> transaction, 
    Job job, 
    invoice,
  ) {
    double confidence = 0.0;
    
    final amount = transaction['Amount'] ?? transaction['Total'] ?? 0.0;
    final description = transaction['Description'] ?? transaction['Reference'] ?? '';
    
    // Exact amount match = 50 points
    if (amount == invoice.amount) {
      confidence += 50.0;
    } else if (_isAmountMatch(amount, invoice.amount)) {
      confidence += 30.0;
    }
    
    // Description matches = 30 points
    if (_isDescriptionMatch(description, job, invoice)) {
      confidence += 30.0;
    }
    
    // Invoice number match = 20 points
    if (invoice.invoiceNumber != null && 
        description.toLowerCase().contains(invoice.invoiceNumber!.toLowerCase())) {
      confidence += 20.0;
    }
    
    return confidence;
  }

  // Auto-sync settings
  static Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncEnabledKey, enabled);
  }

  static Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSyncEnabledKey) ?? false;
  }

  static Future<void> setSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncTimeKey, time);
  }

  static Future<String> getSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_syncTimeKey) ?? '06:00';
  }

  static Future<void> updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    return lastSync != null ? DateTime.parse(lastSync) : null;
  }
}
