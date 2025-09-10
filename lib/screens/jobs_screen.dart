import 'package:flutter/material.dart';
import '../models/job.dart';
import '../widgets/job_details_dialog.dart';
import 'job_details_screen.dart';
import '../models/customer.dart';
import 'pricebook_screen.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';

class JobsScreen extends StatefulWidget {
  final List<Customer> customers;
  final void Function(Customer) onAdd;
  final void Function(Customer) onUpdate;
  final void Function(String) onRemove;

  const JobsScreen({
    required this.customers,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    super.key,
  });

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<JobStatus> _selectedStatuses = [JobStatus.active]; // Multi-select statuses
  List<Job> jobs = [];
  String search = '';
  List<PriceBookItem> priceBook = <PriceBookItem>[];

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _loadPriceBook();
  }

  Future<File> get _jobsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/jobs.json');
  }

  Future<void> _loadJobs() async {
    try {
      final file = await _jobsFile;
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        setState(() {
          jobs = jsonList.map((e) => Job.fromJson(e)).toList();
        });
      }
    } catch (e) {
      // If error, start with empty list
      setState(() => jobs = []);
    }
  }

  Future<void> _saveJobs() async {
    // Save to local file for backward compatibility
    final file = await _jobsFile;
    final jsonList = jobs.map((job) => job.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
    
    // Save to cloud - sync all jobs
    try {
      for (final job in jobs) {
        await FirestoreService.saveJob(job);
      }
      print('✅ All jobs synced to cloud');
    } catch (e) {
      print('❌ Error syncing jobs to cloud: $e');
      // Don't throw - local save is still important
    }
  }

  Future<void> _addJob(Job job) async {
    setState(() {
      jobs.add(job);
    });
    await _saveJobs();
  }

  Future<void> _loadPriceBook() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/price_book.json');
    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        priceBook = jsonList.map((e) => PriceBookItem.fromJson(e)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sync all job statuses from their documents before filtering
    for (final job in jobs) {
      job.syncStatusFromDocuments();
    }

    final filtered = jobs.where((job) {
      // Filter by selected statuses
      final matchesStatus = job.matchesStatuses(_selectedStatuses);
      
      // Filter by search term
      final matchesSearch = (job.title.toLowerCase().contains(search.toLowerCase()) ||
       (job.customerName ?? '').toLowerCase().contains(search.toLowerCase()) ||
       (job.address ?? '').toLowerCase().contains(search.toLowerCase()) ||
       (job.description ?? '').toLowerCase().contains(search.toLowerCase()) ||
       job.statusDisplayName.toLowerCase().contains(search.toLowerCase())
      );
      
      return matchesStatus && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Job',
            onPressed: _showAddJobDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search jobs',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => search = val),
            ),
            const SizedBox(height: 12),
            
            // Status filter section - now as a compact dropdown
            Row(
              children: [
                const Icon(Icons.filter_list),
                const SizedBox(width: 8),
                const Text('Filter by Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    initialValue: _getDropdownValue(),
                    hint: const Text('Select statuses...'),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      const DropdownMenuItem(value: 'none', child: Text('No Filter')),
                      ...JobStatus.values.map((status) => DropdownMenuItem(
                        value: status.name,
                        child: Text(status.displayName),
                      )),
                      const DropdownMenuItem(value: 'multiple', child: Text('Multiple Selected')),
                    ],
                    onChanged: (value) {
                      if (value == 'all') {
                        setState(() => _selectedStatuses = JobStatus.values.toList());
                      } else if (value == 'none') {
                        setState(() => _selectedStatuses = []);
                      } else if (value != 'multiple') {
                        final status = JobStatus.values.firstWhere((s) => s.name == value);
                        setState(() => _selectedStatuses = [status]);
                      } else {
                        _showMultiSelectDialog();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Results summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${filtered.length} job${filtered.length != 1 ? 's' : ''} found',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 12),
            
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final job = filtered[index];
                  return Card(
                    child: ListTile(
                      title: GestureDetector(
                        onTap: () => _handleJobTap(job),
                        child: Text(
                          job.title,
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _handleJobTap(job),
                            child: Text('Customer: ${job.customerName ?? 'No customer'}'),
                          ),
                          if (job.description?.isNotEmpty == true)
                            Text('Description: ${job.description}'),
                          Row(
                            children: [
                              Expanded(
                                child: Text('Address: ${job.address ?? "No address"}'),
                              ),
                              if (job.address?.isNotEmpty == true)
                                IconButton(
                                  icon: const Icon(Icons.map, color: Colors.blue),
                                  tooltip: 'Open in Maps',
                                  onPressed: () => _openInMaps(job.address!),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(job.currentStatus),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              job.statusDisplayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => _handleJobAction(value, job),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'update_status',
                            child: Text('Update Status'),
                          ),
                          const PopupMenuItem(
                            value: 'view_history',
                            child: Text('Status History'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'open',
                            child: Text('Open Job'),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => JobDetailsScreen(
                              job: job,
                              priceBook: priceBook,
                            ),
                          ),
                        );
                      },
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

  /// Get color for job status
  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.active:
        return Colors.blue;
      case JobStatus.estimateCreated:
        return Colors.orange;
      case JobStatus.estimateSent:
        return Colors.purple;
      case JobStatus.invoiceCreated:
        return Colors.amber;
      case JobStatus.invoiceSent:
        return Colors.indigo;
      case JobStatus.invoicePaid:
        return Colors.green;
      case JobStatus.jobComplete:
        return Colors.teal;
      case JobStatus.archived:
        return Colors.grey;
    }
  }

  /// Get the dropdown value based on selected statuses
  String _getDropdownValue() {
    if (_selectedStatuses.isEmpty) return 'none';
    if (_selectedStatuses.length == JobStatus.values.length) return 'all';
    if (_selectedStatuses.length == 1) return _selectedStatuses.first.name;
    return 'multiple';
  }

  /// Show multi-select dialog for statuses
  void _showMultiSelectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Job Statuses'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6, // Limit height to 60% of screen
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _selectedStatuses = JobStatus.values.toList()),
                    child: const Text('Select All'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedStatuses = []),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: JobStatus.values.map((status) {
                    final isSelected = _selectedStatuses.contains(status);
                    return CheckboxListTile(
                      title: Text(status.displayName),
                      value: isSelected,
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedStatuses = [..._selectedStatuses, status];
                          } else {
                            _selectedStatuses = _selectedStatuses.where((s) => s != status).toList();
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
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

  /// Handle job tap to view details
  void _handleJobTap(Job job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailsScreen(
          job: job,
          priceBook: priceBook,
        ),
      ),
    );
  }

  /// Open customer address in maps
  void _openInMaps(String address) async {
    // Add "New Zealand" to the address for better search results
    final searchAddress = address.contains('New Zealand') || address.contains('NZ') 
        ? address 
        : '$address, New Zealand';
    
    final encoded = Uri.encodeComponent(searchAddress);
    final url = 'https://www.google.com/maps/search/?api=1&query=$encoded';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps')),
        );
      }
    }
  }

  /// Handle job action menu selections
  void _handleJobAction(String action, Job job) {
    switch (action) {
      case 'update_status':
        _showUpdateStatusDialog(job);
        break;
      case 'view_history':
        _showStatusHistoryDialog(job);
        break;
      case 'open':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobDetailsScreen(
              job: job,
              priceBook: priceBook,
            ),
          ),
        );
        break;
    }
  }

  /// Show dialog to manually update job status
  void _showUpdateStatusDialog(Job job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status: ${job.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Current Status: ${job.statusDisplayName}'),
                const SizedBox(height: 16),
                const Text('Select new status:'),
                const SizedBox(height: 8),
                ...JobStatus.values.map((status) => RadioListTile<JobStatus>(
                  title: Text(status.displayName),
                  value: status,
                  groupValue: job.currentStatus,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        job.updateStatus(value, reason: 'Manually updated');
                      });
                      _saveJobs();
                      Navigator.pop(context);
                    }
                  },
                )),
              ],
            ),
          ),
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

  /// Show status history dialog
  void _showStatusHistoryDialog(Job job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Status History - ${job.title}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: job.statusHistory.isEmpty
              ? const Center(child: Text('No status history available'))
              : ListView.builder(
                  itemCount: job.statusHistory.length,
                  itemBuilder: (context, index) {
                    final history = job.statusHistory[index];
                    return ListTile(
                      title: Text(history.status.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Date: ${history.timestamp.toString().substring(0, 16)}'),
                          if (history.reason != null) Text('Reason: ${history.reason}'),
                          if (history.documentId != null) Text('Document: ${history.documentId}'),
                        ],
                      ),
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
  }

  /// Show job details dialog after customer selection
  Future<void> _showJobDetailsDialog(Customer customer) async {
    final job = await showDialog<Job>(
      context: context,
      builder: (context) => JobDetailsDialog(
        customer: customer,
        onJobCreated: (job) {
          // Add to local jobs list
          _addJob(job);
          Navigator.pop(context, job);
        },
      ),
    );
    
    if (job != null) {
      // Navigate to job details screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => JobDetailsScreen(
            job: job, 
            priceBook: priceBook,
          ),
        ),
      );
    }
  }

  Future<void> _showAddJobDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AddJobDialog(
        customers: widget.customers,
        onJobCreated: (job) async {
          await _addJob(job);
          await _loadJobs();
          // Close the dialog
          Navigator.pop(context);
          // Navigate to job details screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => JobDetailsScreen(
                job: job, 
                priceBook: priceBook,
              ),
            ),
          );
        },
        onCustomerSelected: (customer) async {
          await _showJobDetailsDialog(customer);
        },
      ),
    );
  }
}

class AddJobDialog extends StatefulWidget {
  final List<Customer> customers;
  final void Function(Job)? onJobCreated;
  final void Function(Customer)? onCustomerSelected;

  const AddJobDialog({
    required this.customers, 
    this.onJobCreated, 
    this.onCustomerSelected,
    super.key
  });

  @override
  State<AddJobDialog> createState() => _AddJobDialogState();
}

class _AddJobDialogState extends State<AddJobDialog> {
  String search = '';
  Customer? selectedCustomer;
  late TextEditingController searchController;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = widget.customers.where((c) =>
      c.name.toLowerCase().contains(search.toLowerCase()) ||
      c.address.toLowerCase().contains(search.toLowerCase()) ||
      c.email.toLowerCase().contains(search.toLowerCase())
    ).toList();

    return AlertDialog(
      title: const Text('Add Job'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'Search customer',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) => setState(() => search = val),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add New Customer'),
                  onPressed: () async {
                    // Show your add customer dialog here
                    // Example:
                    final newCustomer = await showDialog<Customer>(
                      context: context,
                      builder: (context) => AddCustomerDialog(), // Dialog implemented below
                    );
                    if (newCustomer != null) {
                      setState(() {
                        widget.customers.add(newCustomer);
                        selectedCustomer = newCustomer;
                      });
                    }
                  },
                ),
              ),
              SizedBox(
                height: 200,
                child: filteredCustomers.isEmpty
                    ? const Center(child: Text('No customers found.'))
                    : ListView.builder(
                        itemCount: filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = filteredCustomers[index];
                          final isSelected = customer == selectedCustomer;
                          return Card(
                            color: isSelected ? Colors.blue.shade50 : null,
                            child: ListTile(
                              title: Text(customer.name),
                              subtitle: Text(customer.address),
                              onTap: () => setState(() => selectedCustomer = customer),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Colors.blue)
                                  : null,
                            ),
                          );
                        },
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
        if (selectedCustomer != null)
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (widget.onCustomerSelected != null) {
                widget.onCustomerSelected!(selectedCustomer!);
              }
            },
            child: const Text('Select Customer'),
          ),
      ],
    );
  }
}

class JobDetailsEntryForm extends StatefulWidget {
  final Customer customer;
  final void Function(Job) onJobCreated;

  const JobDetailsEntryForm({
    required this.customer,
    required this.onJobCreated,
    super.key,
  });

  @override
  State<JobDetailsEntryForm> createState() => _JobDetailsEntryFormState();
}

class _JobDetailsEntryFormState extends State<JobDetailsEntryForm> {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  late TextEditingController addressController;

  /// Generate a short job ID starting with 4 digits
  String _generateShortJobId() {
    final now = DateTime.now();
    // Use last 2 digits of year + day of year + random 2 digits for uniqueness
    final year = now.year % 100; // Last 2 digits of year (e.g., 25 for 2025)
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final random = (now.millisecond % 100).toString().padLeft(2, '0');
    
    return '$year${dayOfYear.toString().padLeft(3, '0')}$random'; // e.g., 2524501 for Sept 1, 2025
  }

  @override
  void initState() {
    super.initState();
    addressController = TextEditingController(text: widget.customer.address);
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Job Name'),
        ),
        TextField(
          controller: descriptionController,
          decoration: const InputDecoration(labelText: 'Job Description (optional)'),
        ),
        TextField(
          controller: addressController,
          decoration: const InputDecoration(labelText: 'Site Address'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.email, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.customer.email.isNotEmpty
                    ? widget.customer.email
                    : 'No email provided',
                style: TextStyle(
                  color: widget.customer.email.isNotEmpty ? Colors.black87 : Colors.grey,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            // Validate required fields
            if (nameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Job name is required')),
              );
              return;
            }
            
            if (addressController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Site address is required')),
              );
              return;
            }

            try {
              final newJob = Job(
                id: _generateShortJobId(),
                title: nameController.text.trim(),
                description: descriptionController.text.trim().isEmpty 
                    ? null 
                    : descriptionController.text.trim(),
                address: addressController.text.trim(),
                customerName: widget.customer.companyName.isNotEmpty
                    ? widget.customer.companyName
                    : widget.customer.name,
                customerEmail: widget.customer.email.isNotEmpty 
                    ? widget.customer.email 
                    : null,
                status: JobStatus.active,
                created: DateTime.now(),
                dueDate: DateTime.now().add(const Duration(days: 7)),
                jobType: 'General',
                paymentTerms: widget.customer.paymentTerms.isNotEmpty 
                    ? widget.customer.paymentTerms 
                    : '7 days',
              );
              widget.onJobCreated(newJob);
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to create job: $e')),
              );
              print('Error creating job: $e');
            }
          },
          child: const Text('Save Job'),
        ),
      ],
    );
  }
}

// Simple dialog for adding a new customer
class AddCustomerDialog extends StatefulWidget {
  const AddCustomerDialog({super.key});

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final nameController = TextEditingController();
  final companyNameController = TextEditingController();
  final addressController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final pasteController = TextEditingController();

  // Payment terms options
  final List<String> paymentTermsOptions = [
    '7 days',
    '14 days',
    '21 days',
    '20th this month',
    '20th next month',
  ];
  String selectedPaymentTerm = '7 days'; // Default

  // For showing paste buttons
  ValueNotifier<TextSelection?> selectionNotifier = ValueNotifier(null);

  @override
  void dispose() {
    nameController.dispose();
    companyNameController.dispose();
    addressController.dispose();
    emailController.dispose();
    phoneController.dispose();
    pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Customer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Paste box with floating paste buttons
            Stack(
              children: [
                TextField(
                  controller: pasteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Paste text here',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  onTap: () => setState(() {}),
                  onChanged: (_) => setState(() {}),
                  // onSelectionChanged is not available for TextField
                ),
                ValueListenableBuilder<TextSelection?>(
                  valueListenable: selectionNotifier,
                  builder: (context, selection, _) {
                    final text = pasteController.text;
                    final hasSelection = selection != null && selection.baseOffset != selection.extentOffset;
                    if (!hasSelection) return const SizedBox.shrink();
                    final start = selection.start < selection.end ? selection.start : selection.end;
                    final end = selection.start < selection.end ? selection.end : selection.start;
                    final selectedText = text.substring(start, end);
                    return Positioned(
                      right: 0,
                      top: 0,
                      child: Material(
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Paste to Name',
                              icon: const Icon(Icons.person),
                              onPressed: () {
                                nameController.text = selectedText;
                                selectionNotifier.value = null;
                              },
                            ),
                            IconButton(
                              tooltip: 'Paste to Address',
                              icon: const Icon(Icons.home),
                              onPressed: () {
                                addressController.text = selectedText;
                                selectionNotifier.value = null;
                              },
                            ),
                            IconButton(
                              tooltip: 'Paste to Email',
                              icon: const Icon(Icons.email),
                              onPressed: () {
                                emailController.text = selectedText;
                                selectionNotifier.value = null;
                              },
                            ),
                            IconButton(
                              tooltip: 'Paste to Phone',
                              icon: const Icon(Icons.phone),
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
            TextField(
              controller: companyNameController,
              decoration: const InputDecoration(labelText: 'Company Name (if applicable)'),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            DropdownButtonFormField<String>(
              initialValue: selectedPaymentTerm,
              decoration: const InputDecoration(labelText: 'Payment Terms'),
              items: paymentTermsOptions
                  .map((term) => DropdownMenuItem(value: term, child: Text(term)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => selectedPaymentTerm = val);
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
              name: nameController.text,
              companyName: companyNameController.text,
              address: addressController.text,
              email: emailController.text,
              phone: phoneController.text,
              paymentTerms: selectedPaymentTerm,
            );
            Navigator.pop(context, newCustomer);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}