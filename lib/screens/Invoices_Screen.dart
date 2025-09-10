import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import '../models/job.dart';
import '../screens/pricebook_screen.dart' show PriceBookItem;
import 'job_details_screen.dart';

enum InvoiceStatus { all, due, overdue, paid }

class InvoicesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> invoices; // Each: {'job': Job, 'invoice': Invoice} or {'job': Job, 'estimateVersion': EstimateVersion}
  final List<PriceBookItem> priceBook; // Add priceBook for JobDetailsScreen

  const InvoicesScreen({super.key, required this.invoices, this.priceBook = const []});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String _searchQuery = '';
  InvoiceStatus _selectedStatus = InvoiceStatus.all;
  final TextEditingController _searchController = TextEditingController();

  /// Save job changes to persistent storage
  Future<void> _saveJobChanges(Job job) async {
    try {
      // Save to local storage
      final directory = await getApplicationDocumentsDirectory();
      
      // Save individual job file
      final jobFile = File('${directory.path}/job_${job.id}.json');
      await jobFile.writeAsString(jsonEncode(job.toJson()));
      
      // Update main jobs.json file
      final mainJobsFile = File('${directory.path}/jobs.json');
      List<Job> allJobs = [];
      
      if (await mainJobsFile.exists()) {
        final jsonString = await mainJobsFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);
        allJobs = jsonList.map((e) => Job.fromJson(e)).toList();
        
        // Update the specific job in the list
        final jobIndex = allJobs.indexWhere((j) => j.id == job.id);
        if (jobIndex != -1) {
          allJobs[jobIndex] = job;
        } else {
          allJobs.add(job);
        }
      } else {
        allJobs = [job];
      }
      
      // Save updated jobs list
      final jsonList = allJobs.map((j) => j.toJson()).toList();
      await mainJobsFile.writeAsString(jsonEncode(jsonList));
      
      print('✅ Job saved successfully: ${job.id}');
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment status saved successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error saving job: $e');
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save payment status: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredInvoices {
    List<Map<String, dynamic>> filtered = widget.invoices;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final job = item['job'] as Job;
        final invoice = item['invoice'];
        final estimateVersion = item['estimateVersion'];
        
        final customerName = (job.customerName ?? '').toLowerCase();
        final jobTitle = job.title.toLowerCase();
        final address = (job.address ?? '').toLowerCase();
        final searchLower = _searchQuery.toLowerCase();
        
        // Get amount and invoice number for search
        double amount;
        String invoiceNumber;
        
        if (invoice != null) {
          amount = invoice.amount;
          invoiceNumber = invoice.id;
        } else if (estimateVersion != null) {
          amount = estimateVersion.amount;
          invoiceNumber = estimateVersion.invoiceNumber ?? estimateVersion.id ?? '';
        } else {
          return false;
        }
        
        return customerName.contains(searchLower) ||
               jobTitle.contains(searchLower) ||
               address.contains(searchLower) ||
               amount.toString().contains(searchLower) ||
               invoiceNumber.toLowerCase().contains(searchLower);
      }).toList();
    }

    // Apply status filter
    if (_selectedStatus != InvoiceStatus.all) {
      filtered = filtered.where((item) {
        final invoice = item['invoice'];
        final estimateVersion = item['estimateVersion'];
        
        bool isPaid;
        DateTime? dueDate;
        
        if (invoice != null) {
          isPaid = invoice.isPaid;
          dueDate = invoice.dueDate;
        } else if (estimateVersion != null) {
          isPaid = estimateVersion.isPaid;
          dueDate = estimateVersion.dueDate;
        } else {
          return false;
        }

        switch (_selectedStatus) {
          case InvoiceStatus.paid:
            return isPaid;
          case InvoiceStatus.overdue:
            if (isPaid) return false;
            if (dueDate == null) return false;
            return DateTime.now().isAfter(dueDate);
          case InvoiceStatus.due:
            if (isPaid) return false;
            if (dueDate == null) return true; // Consider invoices without due dates as "due"
            return DateTime.now().isBefore(dueDate) || DateTime.now().isAtSameMomentAs(dueDate);
          case InvoiceStatus.all:
            return true;
        }
      }).toList();
    }

    return filtered;
  }

  void _onInvoiceTap(Job job, dynamic invoice, dynamic estimateVersion) async {
    // Check if there's a PDF to open
    String? pdfPath;
    
    if (invoice != null && invoice.filePath != null) {
      pdfPath = invoice.filePath;
    } else if (estimateVersion != null && estimateVersion.filePath != null) {
      pdfPath = estimateVersion.filePath;
    }

    if (pdfPath != null) {
      // Try to open the PDF first
      try {
        await OpenFile.open(pdfPath);
        return;
      } catch (e) {
        // If PDF opening fails, fall back to job details
        print('Failed to open PDF: $e');
      }
    }

    // Navigate to job details screen
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => JobDetailsScreen(
            job: job, 
            priceBook: widget.priceBook,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredInvoices = _filteredInvoices;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by customer, job, address, amount, or invoice #',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Status filter dropdown
                Row(
                  children: [
                    const Text('Filter: ', style: TextStyle(fontWeight: FontWeight.w500)),
                    Expanded(
                      child: DropdownButtonFormField<InvoiceStatus>(
                        initialValue: _selectedStatus,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: InvoiceStatus.all,
                            child: Text('All Invoices'),
                          ),
                          DropdownMenuItem(
                            value: InvoiceStatus.due,
                            child: Text('Due'),
                          ),
                          DropdownMenuItem(
                            value: InvoiceStatus.overdue,
                            child: Text('Overdue'),
                          ),
                          DropdownMenuItem(
                            value: InvoiceStatus.paid,
                            child: Text('Paid'),
                          ),
                        ],
                        onChanged: (InvoiceStatus? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedStatus = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: filteredInvoices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty || _selectedStatus != InvoiceStatus.all
                        ? 'No invoices match your search criteria'
                        : 'No invoices found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (_searchQuery.isNotEmpty || _selectedStatus != InvoiceStatus.all) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                          _selectedStatus = InvoiceStatus.all;
                        });
                      },
                      child: const Text('Clear filters'),
                    ),
                  ],
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: filteredInvoices.length,
              itemBuilder: (context, index) {
                final job = filteredInvoices[index]['job'] as Job;
                final invoice = filteredInvoices[index]['invoice'];
                final estimateVersion = filteredInvoices[index]['estimateVersion'];
                
                // Determine if this is an Invoice object or EstimateVersion
                DateTime? dueDate;
                double amount;
                bool isPaid;
                String invoiceNumber;
                String? filePath;
                
                if (invoice != null) {
                  // Handle Invoice object
                  dueDate = invoice.dueDate;
                  amount = invoice.amount;
                  isPaid = invoice.isPaid;
                  invoiceNumber = invoice.id;
                  filePath = invoice.filePath;
                } else if (estimateVersion != null) {
                  // Handle EstimateVersion invoice
                  dueDate = estimateVersion.dueDate;
                  amount = estimateVersion.amount;
                  isPaid = estimateVersion.isPaid;
                  invoiceNumber = estimateVersion.invoiceNumber ?? estimateVersion.id ?? 'N/A';
                  filePath = estimateVersion.filePath;
                } else {
                  return const SizedBox.shrink(); // Skip invalid entries
                }
                
                final daysPastDue = dueDate != null
                    ? DateTime.now().difference(dueDate).inDays
                    : null;
                
                final isOverdue = !isPaid && daysPastDue != null && daysPastDue > 0;
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  elevation: 2,
                  child: InkWell(
                    onTap: () => _onInvoiceTap(job, invoice, estimateVersion),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Status indicator
                          Container(
                            width: 4,
                            height: 60,
                            decoration: BoxDecoration(
                              color: isPaid
                                  ? Colors.green
                                  : isOverdue
                                      ? Colors.red
                                      : Colors.orange,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Invoice details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Invoice #$invoiceNumber',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (filePath != null)
                                      const Icon(
                                        Icons.picture_as_pdf,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Customer: ${job.customerName ?? "Unknown"}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  'Job: ${job.title}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                if (job.address != null)
                                  Text(
                                    'Address: ${job.address}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      '\$${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.green,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (isPaid)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'PAID',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else if (isOverdue)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '$daysPastDue DAYS OVERDUE',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          dueDate != null
                                              ? 'DUE ${dueDate.day}/${dueDate.month}/${dueDate.year}'
                                              : 'DUE DATE NOT SET',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Action button
                          Column(
                            children: [
                              if (!isPaid)
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(80, 32),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  onPressed: () async {
                                    try {
                                      // Show loading indicator
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Row(
                                            children: [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                              SizedBox(width: 12),
                                              Text('Marking as paid...'),
                                            ],
                                          ),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                      
                                      // Update the payment status
                                      setState(() {
                                        if (invoice != null) {
                                          // Update Invoice object
                                          filteredInvoices[index]['invoice'] = invoice.copyWith(isPaid: true);
                                          
                                          // CRITICAL: Also update the corresponding EstimateVersion to keep them in sync
                                          try {
                                            final correspondingEstimate = job.estimateVersions.firstWhere(
                                              (v) => v.id == invoice.id,
                                              orElse: () => job.estimateVersions.firstWhere(
                                                (v) => v.invoiceNumber == invoice.id,
                                                orElse: () => job.estimateVersions.firstWhere(
                                                  (v) => v.type == 'invoice' && v.amount == invoice.total,
                                                  orElse: () => throw StateError('No matching EstimateVersion found')
                                                )
                                              )
                                            );
                                            correspondingEstimate.isPaid = true;
                                            print('✅ Synced payment status to EstimateVersion: ${correspondingEstimate.id}');
                                          } catch (e) {
                                            print('⚠️ Could not find corresponding EstimateVersion for Invoice: ${invoice.id}');
                                          }
                                        } else if (estimateVersion != null) {
                                          // Update EstimateVersion
                                          estimateVersion.isPaid = true;
                                          
                                          // CRITICAL: Also update the corresponding Invoice object to keep them in sync
                                          try {
                                            final correspondingInvoice = job.invoices.firstWhere(
                                              (inv) => inv.id == estimateVersion.id || inv.id == estimateVersion.invoiceNumber,
                                              orElse: () => job.invoices.firstWhere(
                                                (inv) => inv.total == estimateVersion.amount,
                                                orElse: () => throw StateError('No matching Invoice found')
                                              )
                                            );
                                            final updatedInvoice = correspondingInvoice.copyWith(isPaid: true);
                                            final invoiceIndex = job.invoices.indexWhere((inv) => inv.id == correspondingInvoice.id);
                                            if (invoiceIndex != -1) {
                                              job.invoices[invoiceIndex] = updatedInvoice;
                                              print('✅ Synced payment status to Invoice: ${updatedInvoice.id}');
                                            }
                                          } catch (e) {
                                            print('⚠️ Could not find corresponding Invoice for EstimateVersion: ${estimateVersion.id}');
                                          }
                                        }
                                      });
                                      
                                      // Ensure invoices stay in sync after payment status change
                                      job.syncInvoices();
                                      
                                      // Save changes to persistent storage
                                      await _saveJobChanges(job);
                                      
                                    } catch (e) {
                                      print('Error marking invoice as paid: $e');
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Failed to mark as paid: ${e.toString()}'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text(
                                    'Mark Paid',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}