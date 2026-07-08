import 'package:flutter/material.dart';
import '../models/job.dart' as job_model;
import '../models/estimate_version.dart';
import 'pricebook_extensive_screen.dart' show PriceBookItem;
import 'job_details_screen.dart';
import 'estimate_builder_screen.dart';
import '../services/firestore_service.dart';

class EstimatesQuotesScreen extends StatefulWidget {
  final List<job_model.Job> jobs;
  final List<PriceBookItem> priceBook;

  const EstimatesQuotesScreen({
    super.key,
    required this.jobs,
    required this.priceBook,
  });

  @override
  State<EstimatesQuotesScreen> createState() => _EstimatesQuotesScreenState();
}

class _EstimatesQuotesScreenState extends State<EstimatesQuotesScreen> {
  String search = '';
  String filterType = 'all'; // 'all', 'estimates', 'quotes'
  String sortBy = 'date'; // 'date', 'customer', 'amount'

  @override
  Widget build(BuildContext context) {
    // Gather all final estimates and quotes from all jobs
    final allEstimatesQuotes = widget.jobs
        .expand((job) => job.estimateVersions
            .where((v) => 
                v.status != 'in_progress' && 
                (v.type == 'estimate' || v.type == 'quote'))
            .map((v) => {'job': job, 'version': v}))
        .where((entry) {
          final job = entry['job'] as job_model.Job;
          final version = entry['version'] as EstimateVersion;
          
          // Filter by search term
          final matchesSearch = job.title.toLowerCase().contains(search.toLowerCase()) ||
              (job.customerName?.toLowerCase().contains(search.toLowerCase()) ?? false) ||
              (version.documentNumber?.toLowerCase().contains(search.toLowerCase()) ?? false);
          
          // Filter by type
          final matchesType = filterType == 'all' || 
              (filterType == 'estimates' && version.type == 'estimate') ||
              (filterType == 'quotes' && version.type == 'quote');
          
          return matchesSearch && matchesType;
        })
        .toList();

    // Sort the results
    allEstimatesQuotes.sort((a, b) {
      final jobA = a['job'] as job_model.Job;
      final jobB = b['job'] as job_model.Job;
      final versionA = a['version'] as EstimateVersion;
      final versionB = b['version'] as EstimateVersion;
      
      switch (sortBy) {
        case 'customer':
          return (jobA.customerName ?? '').compareTo(jobB.customerName ?? '');
        case 'amount':
          return versionB.amount.compareTo(versionA.amount);
        case 'date':
        default:
          return (versionB.timestamp ?? DateTime(1970))
              .compareTo(versionA.timestamp ?? DateTime(1970));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estimates & Quotes'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => sortBy = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'date', child: Text('Sort by Date')),
              const PopupMenuItem(value: 'customer', child: Text('Sort by Customer')),
              const PopupMenuItem(value: 'amount', child: Text('Sort by Amount')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(textCapitalization: TextCapitalization.sentences, 
                  decoration: const InputDecoration(
                    labelText: 'Search by job, customer, or document number',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) => setState(() => search = val),
                ),
                const SizedBox(height: 16),
                // Filter chips
                Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: filterType == 'all',
                      onSelected: (_) => setState(() => filterType = 'all'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Estimates'),
                      selected: filterType == 'estimates',
                      onSelected: (_) => setState(() => filterType = 'estimates'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Quotes'),
                      selected: filterType == 'quotes',
                      onSelected: (_) => setState(() => filterType = 'quotes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Results summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  '${allEstimatesQuotes.length} ${filterType == 'all' ? 'documents' : filterType} found',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const Spacer(),
                if (allEstimatesQuotes.isNotEmpty)
                  Text(
                    'Total: \$${allEstimatesQuotes.fold<double>(0, (sum, entry) => sum + (entry['version'] as EstimateVersion).amount).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          // List of estimates and quotes
          Expanded(
            child: allEstimatesQuotes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No ${filterType == 'all' ? 'estimates or quotes' : filterType} found',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        if (search.isNotEmpty)
                          Text(
                            'Try adjusting your search criteria',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: allEstimatesQuotes.length,
                    itemBuilder: (context, index) {
                      final job = allEstimatesQuotes[index]['job'] as job_model.Job;
                      final version = allEstimatesQuotes[index]['version'] as EstimateVersion;
                      
                      final isExpired = version.dueDate != null && 
                          version.dueDate!.isBefore(DateTime.now());
                      final isConverted = version.isConverted;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: version.type == 'quote' 
                                ? Colors.blue[100] 
                                : Colors.green[100],
                            child: Icon(
                              version.type == 'quote' 
                                  ? Icons.request_quote 
                                  : Icons.description,
                              color: version.type == 'quote' 
                                  ? Colors.blue[700] 
                                  : Colors.green[700],
                            ),
                          ),
                          title: Text(
                            '${version.type?.capitalize() ?? 'Document'} #${version.documentNumber ?? version.estimateNumber ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${job.customerName ?? 'Unknown Customer'} - ${job.title}'),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '\$${version.amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  if (version.dueDate != null) ...[
                                    const SizedBox(width: 16),
                                    Text(
                                      'Expires: ${version.dueDate!.day}/${version.dueDate!.month}/${version.dueDate!.year}',
                                      style: TextStyle(
                                        color: isExpired ? Colors.red : Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  if (isConverted) ...[
                                    const SizedBox(width: 16),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Converted',
                                        style: TextStyle(
                                          color: Colors.orange[800],
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (version.timestamp != null)
                                Text(
                                  'Created: ${version.timestamp!.day}/${version.timestamp!.month}/${version.timestamp!.year}',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                version.emailSent ? 'Sent' : 'Not sent',
                                style: TextStyle(
                                  color: version.emailSent ? Colors.green : Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              switch (value) {
                                case 'view_job':
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => JobDetailsScreen(
                                        job: job,
                                        priceBook: widget.priceBook,
                                      ),
                                    ),
                                  );
                                  break;
                                case 'edit':
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EstimateBuilderScreen(
                                        job: job,
                                        initialItems: version.items,
                                        initialSubsections: version.sections,
                                        initialDepositAmount: version.depositAmount,
                                        initialDepositPercentage: version.depositPercentage,
                                        initialIsDepositPercentage: version.isDepositPercentage,
                                      ),
                                    ),
                                  );
                                  break;
                                case 'convert':
                                  if (!isConverted) {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Convert to Invoice'),
                                        content: Text(
                                          'Convert this ${version.type} to an invoice?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Convert'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setState(() {
                                        version.isConverted = true;
                                      });
                                      print('🔧 Convert action: version.id=${version.id} invoiceNumber=${version.invoiceNumber} type=${version.type}');
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EstimateBuilderScreen(
                                            job: job,
                                            initialItems: version.items,
                                            initialSubsections: version.sections,
                                            convertToInvoice: true,
                                            initialSourceType: version.type,
                                            initialSourceTimestamp: version.timestamp,
                                            initialDepositAmount: version.depositAmount,
                                            initialDepositPercentage: version.depositPercentage,
                                            initialIsDepositPercentage: version.isDepositPercentage,
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                  break;
                                case 'void':
                                  final confirmVoid = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Void Document'),
                                      content: Text(
                                        'Void this ${version.type}? This will archive it and mark it as voided.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Void'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmVoid == true) {
                                    setState(() {
                                      version.isArchived = true;
                                    });
                                    await FirestoreService.saveJob(job);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${version.type?.capitalize() ?? 'Document'} voided'),
                                        ),
                                      );
                                    }
                                  }
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'view_job',
                                child: ListTile(
                                  leading: Icon(Icons.visibility),
                                  title: Text('View Job Details'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit),
                                  title: Text('Edit in Builder'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (!isConverted)
                                const PopupMenuItem(
                                  value: 'convert',
                                  child: ListTile(
                                    leading: Icon(Icons.transform),
                                    title: Text('Convert to Invoice'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              if (!version.isArchived)
                                const PopupMenuItem(
                                  value: 'void',
                                  child: ListTile(
                                    leading: Icon(Icons.cancel, color: Colors.red),
                                    title: Text('Void Document', style: TextStyle(color: Colors.red)),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JobDetailsScreen(
                                  job: job,
                                  priceBook: widget.priceBook,
                                ),
                              ),
                            ).then((_) => setState(() {}));
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Extension to capitalize strings
extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
