import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../services/customer_storage_strategy_service.dart';

class CustomersScreen extends StatefulWidget {
  final List<Customer> customers;
  final void Function(Customer) onAdd;
  final void Function(Customer) onUpdate;
  final void Function(String) onRemove;

  const CustomersScreen({
    required this.customers,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    super.key,
  });

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String search = '';

  @override
  void initState() {
    super.initState();
    // Ensure the widget rebuilds when customers change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _showAddEditDialog(BuildContext context, {Customer? customer}) async {
    final companyController = TextEditingController();
    final nameController = TextEditingController(text: customer?.name ?? '');
    final emailController = TextEditingController(text: customer?.email ?? '');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final addressController = TextEditingController(text: customer?.address ?? '');
    final pasteController = TextEditingController();
    final bodyCorporateController = TextEditingController(text: customer?.bodyCorporateNumber ?? '');
    final paymentTermsOptions = [
      '7 days',
      '14 days',
      '21 days',
      '20th of this month',
      '20th of next month',
    ];
    String selectedPaymentTerm = customer?.paymentTerms ?? '7 days';
    bool isRemoteCustomer = customer?.isRemote ?? false;

    // Additional email addresses management
    List<String> additionalEmails = List.from(customer?.additionalEmails ?? []);
    
    // For showing paste buttons
    ValueNotifier<TextSelection?> selectionNotifier = ValueNotifier(null);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(customer == null ? 'Add Customer' : 'Edit Customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Paste box
                Stack(
                  children: [
                    TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: pasteController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Paste text here',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      onTap: () => setState(() {}),
                      onChanged: (_) => setState(() {}),
                      // Removed onSelectionChanged: not supported by TextField
                    ),
                    // Floating paste buttons
                    ValueListenableBuilder<TextSelection?>(
                      valueListenable: selectionNotifier,
                      builder: (context, selection, _) {
                        final text = pasteController.text;
                        final hasSelection = selection != null && selection.baseOffset != selection.extentOffset;
                        if (!hasSelection) return SizedBox.shrink();
                        final selectedText = text.substring(
                          selection.start < selection.end ? selection.start : selection.end,
                          selection.start < selection.end ? selection.end : selection.start,
                        );
                        return Positioned(
                          right: 0,
                          top: 0,
                          child: Material(
                            color: Colors.transparent,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Paste to Name',
                                  icon: Icon(Icons.person),
                                  onPressed: () {
                                    nameController.text = selectedText;
                                    selectionNotifier.value = null;
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Paste to Address',
                                  icon: Icon(Icons.home),
                                  onPressed: () {
                                    addressController.text = selectedText;
                                    selectionNotifier.value = null;
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Paste to Email',
                                  icon: Icon(Icons.email),
                                  onPressed: () {
                                    emailController.text = selectedText;
                                    selectionNotifier.value = null;
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Paste to Phone',
                                  icon: Icon(Icons.phone),
                                  onPressed: () {
                                    phoneController.text = selectedText;
                                    selectionNotifier.value = null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: companyController,
                  decoration: const InputDecoration(labelText: 'Company Name (if applicable)'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Primary Email Address'),
                ),
                
                // Additional Email Addresses Section
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.email_outlined, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    const Text(
                      'Additional Email Addresses',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      tooltip: 'Add Email Address',
                      onPressed: () async {
                        final newEmail = await _showAddEmailDialog(context);
                        if (newEmail != null && newEmail.trim().isNotEmpty) {
                          setState(() {
                            additionalEmails.add(newEmail.trim());
                          });
                        }
                      },
                    ),
                  ],
                ),
                
                // Display additional emails with remove option
                ...additionalEmails.asMap().entries.map((entry) {
                  final index = entry.key;
                  final email = entry.value;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.email, size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            email,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                          tooltip: 'Remove Email',
                          onPressed: () {
                            setState(() {
                              additionalEmails.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }),
                
                const SizedBox(height: 16),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedPaymentTerm,
                  decoration: const InputDecoration(labelText: 'Payment Terms'),
                  items: paymentTermsOptions
                      .map((term) => DropdownMenuItem(
                            value: term,
                            child: Text(term),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedPaymentTerm = val);
                  },
                ),
                
                const SizedBox(height: 16),
                // Remote Customer Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: isRemoteCustomer,
                            onChanged: (value) {
                              setState(() => isRemoteCustomer = value ?? false);
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'Remote Customer',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline, color: Colors.blue),
                            tooltip: 'Learn about Remote Customers',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Row(
                                    children: [
                                      Icon(Icons.cloud_sync, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('Remote Customer'),
                                    ],
                                  ),
                                  content: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'When you mark a customer as "Remote":',
                                        style: TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      SizedBox(height: 8),
                                      Text('• All customer data is saved to both device and cloud'),
                                      Text('• Jobs, documents, and builds for this customer use hybrid storage'),
                                      Text('• Data is accessible even when offline'),
                                      Text('• Automatically syncs when online'),
                                      SizedBox(height: 12),
                                      Text(
                                        'Perfect for customers you visit frequently or work with remotely.',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Got it'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      if (isRemoteCustomer)
                        const Padding(
                          padding: EdgeInsets.only(left: 48),
                          child: Text(
                            'This customer\'s data will use hybrid storage for optimal access.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: bodyCorporateController,
                  decoration: const InputDecoration(
                    labelText: 'Body Corporate Number (Optional)',
                    prefixIcon: Icon(Icons.account_balance),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (customer != null)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Customer'),
                      content: const Text('Are you sure you want to delete this customer?'),
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
                    widget.onRemove(customer.id);
                    Navigator.pop(context);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ElevatedButton(
              onPressed: () async {
                // Validation: at least one of company or name
                if (companyController.text.trim().isEmpty && nameController.text.trim().isEmpty) return;
                final newCustomer = Customer(
                  id: customer?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  companyName: companyController.text.trim(),
                  email: emailController.text.trim(),
                  additionalEmails: additionalEmails,
                  phone: phoneController.text.trim(),
                  address: addressController.text.trim(),
                  paymentTerms: selectedPaymentTerm,
                  bodyCorporateNumber: bodyCorporateController.text.trim(),
                  isRemote: isRemoteCustomer,
                );
                
                // Apply remote customer storage strategies if needed
                if (isRemoteCustomer) {
                  await CustomerStorageStrategyService.applyRemoteCustomerStrategies(newCustomer);
                } else if (customer?.isRemote == true && !isRemoteCustomer) {
                  // Customer was remote but is no longer, revert strategies
                  await CustomerStorageStrategyService.removeRemoteCustomerStrategies(newCustomer);
                }
                
                if (customer == null) {
                  widget.onAdd(newCustomer);
                } else {
                  widget.onUpdate(newCustomer);
                }
                Navigator.pop(context);
              },
              child: Text(customer == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> importFromCsv(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;

    if (!context.mounted) return;

    try {
      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      final rows = const CsvToListConverter().convert(csvString, eol: '\n');

      if (rows.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV file is empty')),
          );
        }
        return;
      }

      // Check if this is a Fergus format CSV
      final headers = rows.first.map((e) => e.toString().toLowerCase()).toList();
      print('CSV Headers detected: $headers');
      
      // Use fixed column format for all customer CSVs
      print('Processing all CSVs with fixed column format...');
      
      int importedCount = 0;
      
      // Use fixed column format for all CSVs
      importedCount = await _importFixedColumnFormat(rows, context);

      if (context.mounted) {
        // Wait a moment for all state updates to complete
        await Future.delayed(const Duration(milliseconds: 500));
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $importedCount customers. Current customer count: ${widget.customers.length}'),
            duration: const Duration(seconds: 5),
          ),
        );
        
        // Force refresh of the screen after a short delay
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading CSV file: $e')),
        );
      }
    }
  }

  Future<int> _importFixedColumnFormat(List<List<dynamic>> rows, BuildContext context) async {
    print('=== FIXED COLUMN FORMAT IMPORT START ===');
    
    final headers = rows.first.map((e) => e.toString().toLowerCase()).toList();
    print('Headers: $headers');
    
    // Fixed column mapping as specified:
    // Column A (0): Name
    // Column D (3): Address  
    // Column G (6): End of address (add to address)
    // Column J (9): Email
    // Column L (11): Phone number
    
    final nameIdx = 0;        // Column A
    final addressIdx = 3;     // Column D  
    final addressEndIdx = 6;  // Column G
    final emailIdx = 9;       // Column J
    final phoneIdx = 11;      // Column L

    print('Fixed Column Mapping:');
    print('  name: $nameIdx (Column A)');
    print('  address: $addressIdx (Column D)');
    print('  addressEnd: $addressEndIdx (Column G)');
    print('  email: $emailIdx (Column J)');
    print('  phone: $phoneIdx (Column L)');
    print('Total columns in CSV: ${rows.first.length}');

    int importedCount = 0;
    final List<Customer> customersToAdd = [];

    // Skip header row and process data
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      print('\n--- Processing row $i ---');
      print('Row data: $row');
      print('Row length: ${row.length}');
      
      try {
        if (row.length < 10) { // Need at least 10 columns to access column J
          print('Skipping row $i: insufficient columns (need at least 10, got ${row.length})');
          continue;
        }

        // Extract data using fixed column positions
        final customerName = nameIdx < row.length ? row[nameIdx]?.toString().trim() ?? '' : '';
        
        // Build full address from Column D and Column G
        final addressParts = <String>[];
        if (addressIdx < row.length && row[addressIdx]?.toString().trim().isNotEmpty == true) {
          addressParts.add(row[addressIdx].toString().trim());
        }
        if (addressEndIdx < row.length && row[addressEndIdx]?.toString().trim().isNotEmpty == true) {
          addressParts.add(row[addressEndIdx].toString().trim());
        }
        final address = addressParts.join(', ');
        
        // Extract email from Column J
        String email = '';
        if (emailIdx < row.length) {
          email = row[emailIdx]?.toString().trim() ?? '';
          // Remove any quotes or extra whitespace
          email = email.replaceAll(RegExp(r'^["\s]+|["\s]+$'), '');
        }
        
        // Extract phone from Column L
        final phone = phoneIdx < row.length ? row[phoneIdx]?.toString().trim() ?? '' : '';
        
        print('Extracted data:');
        print('  Name (col $nameIdx): "$customerName"');
        print('  Address (col $addressIdx + $addressEndIdx): "$address"');
        print('  Email (col $emailIdx): "$email"');
        print('  Phone (col $phoneIdx): "$phone"');
        
        // Debug: Print raw column data
        print('  Raw name data: "${nameIdx < row.length ? row[nameIdx] : 'OUT_OF_BOUNDS'}"');
        print('  Raw address data: "${addressIdx < row.length ? row[addressIdx] : 'OUT_OF_BOUNDS'}"');
        print('  Raw address end data: "${addressEndIdx < row.length ? row[addressEndIdx] : 'OUT_OF_BOUNDS'}"');
        print('  Raw email data: "${emailIdx < row.length ? row[emailIdx] : 'OUT_OF_BOUNDS'}"');
        print('  Raw phone data: "${phoneIdx < row.length ? row[phoneIdx] : 'OUT_OF_BOUNDS'}"');

        // Skip if no name and no email
        if (customerName.isEmpty && email.isEmpty) {
          print('Skipping row $i: no name or email');
          continue;
        }

        print('Fixed format row $i: name="$customerName", email="$email", phone="$phone", address="$address"');

        customersToAdd.add(Customer(
          id: '${DateTime.now().millisecondsSinceEpoch}_fixed_$i',
          name: customerName,
          companyName: '', // No company field in fixed format
          email: email,
          additionalEmails: [],
          phone: phone,
          address: address,
          paymentTerms: '7 days', // Default
        ));
        
        print('  Created customer with email: "${customersToAdd.last.email}"');
        print('  Customer JSON: ${customersToAdd.last.toJson()}');
        importedCount++;
      } catch (e) {
        print('Error importing Fergus row $i: $e');
      }
    }
    
    // Show progress dialog for adding customers
    if (context.mounted && customersToAdd.isNotEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adding Customers'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Found ${customersToAdd.length} customers to import'),
                  const Text('Adding customers...'),
                ],
              ),
            );
          },
        ),
      );
    }

    // Add all customers with progress updates
    for (int i = 0; i < customersToAdd.length; i++) {
      final customer = customersToAdd[i];
      print('CSV Import: Adding customer ${i + 1}/${customersToAdd.length}: ${customer.name}');
      print('Customer data: ${customer.toJson()}');
      print('Before add - widget.customers.length: ${widget.customers.length}');
      
      // Try calling the callback
      try {
        widget.onAdd(customer);
        print('Called widget.onAdd for customer: ${customer.name}');
      } catch (e) {
        print('ERROR calling widget.onAdd: $e');
      }
      
      print('After add - widget.customers.length: ${widget.customers.length}');
      
      // Small delay to show progress and allow state updates
      if (i % 10 == 0 || i == customersToAdd.length - 1) {
        // Update progress less frequently to avoid dialog spam
        if (context.mounted) {
          Navigator.of(context).pop(); // Close current dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Adding Customers'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Added ${i + 1}/${customersToAdd.length} customers'),
                  Text(customer.name.isEmpty ? customer.companyName : customer.name,
                       style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    // Close progress dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    
    return importedCount;
  }

  void _showAddCustomerDialog(BuildContext context) async {
    final newCustomer = await showDialog<Customer>(
      context: context,
      builder: (context) {
        final companyController = TextEditingController();
        final nameController = TextEditingController();
        final emailController = TextEditingController();
        final phoneController = TextEditingController();
        final addressController = TextEditingController();
        String selectedPaymentTerm = '7 days';

        return AlertDialog(
          title: const Text('Add Customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: companyController,
                  decoration: const InputDecoration(labelText: 'Company Name (if applicable)'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                TextField(textCapitalization: TextCapitalization.sentences, 
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedPaymentTerm,
                  decoration: const InputDecoration(labelText: 'Payment Terms'),
                  items: [
                    '7 days',
                    '14 days',
                    '21 days',
                    '20th of this month',
                    '20th of next month',
                  ]
                      .map((term) => DropdownMenuItem(
                            value: term,
                            child: Text(term),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) selectedPaymentTerm = val;
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
                final newCustomer = Customer(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  companyName: companyController.text.trim(),
                  email: emailController.text.trim(),
                  additionalEmails: [], // Empty for new customer dialog
                  phone: phoneController.text.trim(),
                  address: addressController.text.trim(),
                  paymentTerms: selectedPaymentTerm,
                );
                Navigator.pop(context, newCustomer);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (newCustomer != null) {
      widget.onAdd(newCustomer);
    }
  }

  Future<void> _showDeleteAllDialog(BuildContext context) async {
    // First confirmation
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Customers'),
        content: Text(
          'Are you sure you want to delete all ${widget.customers.length} customers?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (firstConfirm != true) return;

    // Second confirmation (double confirm)
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Final Warning'),
        content: const Text(
          'This will permanently delete ALL customer data including:\n\n'
          '• All customer contact information\n'
          '• All customer addresses\n'
          '• All payment terms\n\n'
          'Type "DELETE ALL" to confirm:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Show text input dialog for typing confirmation
              final confirmText = await showDialog<String>(
                context: context,
                builder: (context) {
                  final controller = TextEditingController();
                  return AlertDialog(
                    title: const Text('Type DELETE ALL'),
                    content: TextField(textCapitalization: TextCapitalization.sentences, 
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Type "DELETE ALL" to confirm',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, controller.text),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Confirm'),
                      ),
                    ],
                  );
                },
              );
              
              if (confirmText == 'DELETE ALL') {
                Navigator.pop(context, true);
              } else {
                Navigator.pop(context, false);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );

    if (secondConfirm == true) {
      // Delete all customers
      final customersToDelete = List<Customer>.from(widget.customers);
      for (final customer in customersToDelete) {
        widget.onRemove(customer.id);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully deleted ${customersToDelete.length} customers'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<String?> _showAddEmailDialog(BuildContext context) async {
    final emailController = TextEditingController();
    
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Email Address'),
        content: TextField(textCapitalization: TextCapitalization.sentences, 
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'example@email.com',
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isNotEmpty) {
                // Basic email validation
                if (email.contains('@') && email.contains('.')) {
                  Navigator.pop(context, email);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email address')),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers.where((c) {
      final searchLower = search.toLowerCase();
      return c.name.toLowerCase().contains(searchLower) ||
             c.companyName.toLowerCase().contains(searchLower) ||
             c.email.toLowerCase().contains(searchLower) ||
             c.address.toLowerCase().contains(searchLower) ||
             c.additionalEmails.any((email) => email.toLowerCase().contains(searchLower)) ||
             c.phone.contains(search);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Customer',
            onPressed: () => _showAddCustomerDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import CSV',
            onPressed: () => importFromCsv(context),
          ),
          if (widget.customers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete All Customers',
              onPressed: () => _showDeleteAllDialog(context),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(textCapitalization: TextCapitalization.sentences, 
              decoration: const InputDecoration(
                labelText: 'Search customers',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => search = val),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final customer = filtered[index];
                  final allEmails = customer.getAllEmails();
                  final emailsText = allEmails.length > 1 
                    ? '${customer.email} (+${allEmails.length - 1} more)'
                    : customer.email;
                  
                  return Card(
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(customer.displayName)),
                          if (customer.isRemote)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_sync, size: 12, color: Colors.blue.shade600),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Remote',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('$emailsText\n${customer.phone}\n${customer.address}${customer.isRemote ? '\n💾 Hybrid storage enabled' : ''}'),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (customer.address.trim().isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.map),
                              tooltip: 'Open in Maps',
                              onPressed: () async {
                                final encoded = Uri.encodeComponent(customer.address);
                                final url = 'https://www.google.com/maps/search/?api=1&query=$encoded';
                                if (await canLaunchUrl(Uri.parse(url))) {
                                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                }
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showAddEditDialog(context, customer: customer),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

