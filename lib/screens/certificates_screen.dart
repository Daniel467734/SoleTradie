import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../models/certificate.dart';
import '../models/job.dart';
import '../models/customer.dart';
import '../models/estimate_version.dart';

class CertificatesScreen extends StatefulWidget {
  final List<Job> jobs;
  final List<Customer> customers;

  const CertificatesScreen({
    super.key,
    required this.jobs,
    required this.customers,
  });

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Certificate> _allCertificates = [];
  List<Certificate> _filteredCertificates = [];
  String _selectedCertificateType = 'All';
  String _selectedStatus = 'All';
  String _sortBy = 'Date Created';
  bool _sortAscending = false;
  DateTime? _fromDate;
  DateTime? _toDate;

  // Available certificate types for filtering
  final List<String> _certificateTypes = [
    'All',
    'COC',
    'ESC',
    'ROI',
  ];
  final List<String> _statuses = ['All', 'Draft', 'Issued', 'Completed'];
  final List<String> _sortOptions = [
    'Date Created',
    'Date Issued',
    'Customer Name',
    'Certificate Type',
    'Certificate Number'
  ];

  @override
  void initState() {
    super.initState();
    _loadCertificates();
    _searchController.addListener(_filterCertificates);
  }

  @override
  void didUpdateWidget(covariant CertificatesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobs != widget.jobs) {
      _loadCertificates();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCertificates() async {
    final jobsToLoad = await _loadJobsFromLocalIfExists();
    final jobs = jobsToLoad.isNotEmpty ? jobsToLoad : widget.jobs;
    final certificates = <Certificate>[];
    final seenPaths = <String>{};
    final jobById = {for (final job in jobs) job.id: job};

    for (final job in jobs) {
      // Use job's customer information directly, or try to find matching customer
      final documentCustomerName = job.documentCustomerName;
      Customer? customer;
      if (job.customerName != null) {
        customer = widget.customers.firstWhere(
          (c) => c.name == job.customerName,
          orElse: () => Customer(
            id: 'job-${job.id}',
            name: documentCustomerName.isNotEmpty
                ? documentCustomerName
                : 'Unknown Customer',
            email: job.customerEmail ?? '',
            phone: '',
            address: job.address ?? '',
          ),
        );
      } else {
        customer = Customer(
          id: 'job-${job.id}',
          name: documentCustomerName.isNotEmpty
              ? documentCustomerName
              : 'Unknown Customer',
          email: job.customerEmail ?? '',
          phone: '',
          address: job.address ?? '',
        );
      }

      // Find certificate estimate versions
      final certificateVersions = job.estimateVersions.where((version) {
        return _isCertificateVersion(version) ||
            _extractCertificateTypeFromEstimateVersion(version) != null;
      }).toList();

      for (final version in certificateVersions) {
        certificates.add(Certificate.fromEstimateVersion(
          jobId: job.id,
          jobTitle: job.title,
          customerName: documentCustomerName.isNotEmpty
              ? documentCustomerName
              : customer.name,
          customerAddress: customer.address,
          estimateVersion: version,
        ));
      }

      // Add certificate PDF attachments created from job detail screens
      for (final attachmentPath in job.attachments ?? []) {
        if (!attachmentPath.toLowerCase().endsWith('.pdf')) continue;
        if (!seenPaths.add(attachmentPath)) continue;

        final fileName = attachmentPath.split(RegExp(r'[\\/]+')).last;
        final certificateType =
            _extractCertificateTypeFromFileName(fileName) ?? 'Certificate';

        final file = File(attachmentPath);
        final attachmentExists = await file.exists();
        final dateCreated =
            attachmentExists ? await file.lastModified() : DateTime.now();

        certificates.add(Certificate(
          id: attachmentPath,
          jobId: job.id,
          certificateType: certificateType,
          certificateNumber: fileName.replaceAll(RegExp(r'\.pdf\$', caseSensitive: false), ''),
          jobTitle: job.title,
          customerName: documentCustomerName.isNotEmpty
              ? documentCustomerName
              : customer.name,
          customerAddress: customer.address,
          dateCreated: dateCreated,
          dateIssued: attachmentExists ? dateCreated : null,
          filePath: attachmentPath,
          status: attachmentExists ? 'issued' : 'draft',
          notes: null,
        ));
      }
    }

    // Scan the certificates folder for any saved PDFs that are not explicitly attached to jobs
    try {
      final directory = await getApplicationDocumentsDirectory();
      final certificateDir = Directory('${directory.path}/certificates');
      if (await certificateDir.exists()) {
        for (final entity in certificateDir.listSync()) {
          if (entity is! File) continue;
          final path = entity.path;
          if (!path.toLowerCase().endsWith('.pdf')) continue;
          if (!seenPaths.add(path)) continue;

          final fileName = path.split(RegExp(r'[\\/]+')).last;
          final fileType = _extractCertificateTypeFromFileName(fileName);
          if (fileType == null) continue;

          final jobIdFromFile = _extractJobIdFromCertificateFileName(fileName);
          final relatedJob = jobIdFromFile != null ? jobById[jobIdFromFile] : null;
          Customer customer;
          if (relatedJob != null && relatedJob.customerName != null) {
            final job = relatedJob;
            customer = widget.customers.firstWhere(
              (c) => c.name == job.customerName,
              orElse: () => Customer(
                id: 'job-${job.id}',
                name: job.documentCustomerName.isNotEmpty
                    ? job.documentCustomerName
                    : 'Unknown Customer',
                email: job.customerEmail ?? '',
                phone: '',
                address: job.address ?? '',
              ),
            );
          } else {
            customer = Customer(
              id: relatedJob != null ? 'job-${relatedJob.id}' : 'unknown',
              name: relatedJob?.documentCustomerName.isNotEmpty == true
                  ? relatedJob!.documentCustomerName
                  : 'Unknown Customer',
              email: '',
              phone: '',
              address: relatedJob?.address ?? '',
            );
          }

          final file = File(path);
          final attachmentExists = await file.exists();
          final dateCreated =
              attachmentExists ? await file.lastModified() : DateTime.now();

          certificates.add(Certificate(
            id: path,
            jobId: relatedJob?.id ?? 'unknown',
            certificateType: fileType,
            certificateNumber: fileName.replaceAll(RegExp(r'\.pdf\$', caseSensitive: false), ''),
            jobTitle: relatedJob?.title ?? 'Unknown Job',
            customerName: relatedJob?.documentCustomerName.isNotEmpty == true
                ? relatedJob!.documentCustomerName
                : customer.name,
            customerAddress: customer.address,
            dateCreated: dateCreated,
            dateIssued: attachmentExists ? dateCreated : null,
            filePath: path,
            status: attachmentExists ? 'issued' : 'draft',
            notes: null,
          ));
        }
      }
    } catch (e) {
      // Ignore scanning errors, certificates from attachments are still included.
    }

    setState(() {
      _allCertificates = certificates;
      _filterCertificates();
    });
  }

  String? _extractCertificateTypeFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('gas coc') || (lower.contains('gas') && lower.contains('coc'))) {
      return 'COC';
    }
    if (lower.contains('electrical safety certificate') ||
        lower.contains('electrical safety cert') ||
        lower.contains('esc')) {
      return 'ESC';
    }
    if (lower.contains('certificate of compliance') ||
        lower.contains('compliance certificate') ||
        lower.contains('coc')) {
      return 'COC';
    }
    if (lower.contains('record of inspection') || lower.contains('roi')) {
      return 'ROI';
    }
    return null;
  }

  bool _isCertificateVersion(EstimateVersion version) {
    final type = version.type?.toLowerCase() ?? '';
    if (type.contains('esc') ||
        type.contains('roi') ||
        type.contains('coc') ||
        ((type.contains('gas') || type.contains('gas_coc')) && type.contains('coc'))) {
      return true;
    }
    if (version.filePath != null) {
      final fileName =
          version.filePath!.split(RegExp(r'[\\/]+')).last.toLowerCase();
      return _extractCertificateTypeFromFileName(fileName) != null;
    }
    return false;
  }

  String? _extractCertificateTypeFromEstimateVersion(EstimateVersion version) {
    final type = version.type?.toLowerCase();
    if (type != null) {
      if (type.contains('gas coc') || type.contains('gas_coc') || (type.contains('gas') && type.contains('coc'))) {
        return 'COC';
      }
      if (type.contains('electrical safety') || type.contains('esc')) {
        return 'ESC';
      }
      if (type.contains('certificate of compliance') || type.contains('coc')) {
        return 'COC';
      }
      if (type.contains('record of inspection') || type.contains('roi')) {
        return 'ROI';
      }
    }

    if (version.filePath != null) {
      final fileName = version.filePath!.split(RegExp(r'[\\/]+')).last;
      return _extractCertificateTypeFromFileName(fileName);
    }

    final invoiceNumber = version.invoiceNumber?.toLowerCase();
    if (invoiceNumber != null) {
      if (invoiceNumber.contains('coc') || (invoiceNumber.contains('gas') && invoiceNumber.contains('coc'))) return 'COC';
      if (invoiceNumber.contains('esc')) return 'ESC';
      if (invoiceNumber.contains('roi')) return 'ROI';
    }
    return null;
  }

  void _filterCertificates() {
    final query = _searchController.text.toLowerCase();

    List<Certificate> filtered = _allCertificates.where((cert) {
      // Text search
      final createdDate = _formatDate(cert.dateCreated).toLowerCase();
      final issuedDate = cert.dateIssued != null
          ? _formatDate(cert.dateIssued!).toLowerCase()
          : '';
      final matchesSearch = query.isEmpty ||
          cert.customerName.toLowerCase().contains(query) ||
          cert.customerAddress.toLowerCase().contains(query) ||
          cert.jobTitle.toLowerCase().contains(query) ||
          cert.certificateNumber.toLowerCase().contains(query) ||
          cert.certificateType.toLowerCase().contains(query) ||
          (cert.filePath != null
              ? cert.filePath!
                  .split(RegExp(r'[\\/]+'))
                  .last
                  .toLowerCase()
                  .contains(query)
              : false) ||
          createdDate.contains(query) ||
          issuedDate.contains(query);

      // Certificate type filter
      final matchesType = _selectedCertificateType == 'All' ||
          cert.certificateType == _selectedCertificateType;

      // Status filter
      final matchesStatus =
          _selectedStatus == 'All' || cert.statusDisplayName == _selectedStatus;

      final matchesDateRange = (_fromDate == null || !cert.dateCreated.isBefore(_fromDate!)) &&
          (_toDate == null || !cert.dateCreated.isAfter(_toDate!));

      return matchesSearch && matchesType && matchesStatus && matchesDateRange;
    }).toList();

    // Sort results
    filtered.sort((a, b) {
      int comparison = 0;

      switch (_sortBy) {
        case 'Date Created':
          comparison = a.dateCreated.compareTo(b.dateCreated);
          break;
        case 'Date Issued':
          final aDate = a.dateIssued ?? DateTime(1900);
          final bDate = b.dateIssued ?? DateTime(1900);
          comparison = aDate.compareTo(bDate);
          break;
        case 'Customer Name':
          comparison = a.customerName.compareTo(b.customerName);
          break;
        case 'Certificate Type':
          comparison = a.certificateType.compareTo(b.certificateType);
          break;
        case 'Certificate Number':
          comparison = a.certificateNumber.compareTo(b.certificateNumber);
          break;
      }

      return _sortAscending ? comparison : -comparison;
    });

    setState(() {
      _filteredCertificates = filtered;
    });
  }

  Future<void> _openCertificate(Certificate certificate) async {
    if (certificate.hasPdf) {
      try {
        await OpenFile.open(certificate.filePath!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open certificate: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate PDF not available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showCertificateDetails(Certificate certificate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${certificate.certificateType} Certificate Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                  'Certificate Number', certificate.certificateNumber),
              _buildDetailRow('Type', certificate.certificateType),
              _buildDetailRow('Status', certificate.statusDisplayName),
              _buildDetailRow('Job Title', certificate.jobTitle),
              _buildDetailRow('Customer', certificate.customerName),
              _buildDetailRow('Address', certificate.customerAddress),
              _buildDetailRow(
                  'Date Created', _formatDate(certificate.dateCreated)),
              if (certificate.dateIssued != null)
                _buildDetailRow(
                    'Date Issued', _formatDate(certificate.dateIssued!)),
              if (certificate.notes != null && certificate.notes!.isNotEmpty)
                _buildDetailRow('Notes', certificate.notes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (certificate.hasPdf)
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open PDF'),
              onPressed: () {
                Navigator.pop(context);
                _openCertificate(certificate);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }


  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked;
        _filterCertificates();
      });
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _toDate = picked;
        _filterCertificates();
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _filterCertificates();
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificates'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCertificates,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText:
                        'Search by customer, address, job title, certificate number, or date...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),

                // Filter Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Certificate Type Filter
                      _buildFilterDropdown(
                        'Type',
                        _selectedCertificateType,
                        _certificateTypes,
                        (value) => setState(() {
                          _selectedCertificateType = value!;
                          _filterCertificates();
                        }),
                      ),
                      const SizedBox(width: 12),

                      // Status Filter
                      _buildFilterDropdown(
                        'Status',
                        _selectedStatus,
                        _statuses,
                        (value) => setState(() {
                          _selectedStatus = value!;
                          _filterCertificates();
                        }),
                      ),
                      const SizedBox(width: 12),

                      // Sort By
                      _buildFilterDropdown(
                        'Sort by',
                        _sortBy,
                        _sortOptions,
                        (value) => setState(() {
                          _sortBy = value!;
                          _filterCertificates();
                        }),
                      ),
                      const SizedBox(width: 8),

                      // Sort Direction
                      IconButton(
                        icon: Icon(
                          _sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: Colors.indigo.shade700,
                        ),
                        onPressed: () => setState(() {
                          _sortAscending = !_sortAscending;
                          _filterCertificates();
                        }),
                        tooltip: _sortAscending
                            ? 'Sort Ascending'
                            : 'Sort Descending',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(_fromDate == null
                            ? 'From Date'
                            : 'From: ${_formatDate(_fromDate!)}'),
                        onPressed: _selectFromDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(_toDate == null
                            ? 'To Date'
                            : 'To: ${_formatDate(_toDate!)}'),
                        onPressed: _selectToDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                      onPressed: _clearDateRange,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.description, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${_filteredCertificates.length} certificate${_filteredCertificates.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Certificates List
          Expanded(
            child: _filteredCertificates.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredCertificates.length,
                    itemBuilder: (context, index) {
                      final certificate = _filteredCertificates[index];
                      return _buildCertificateCard(certificate);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          onChanged: onChanged,
          items: options.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Text('$label: $option'),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No certificates found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty
                ? 'Try adjusting your search or filters'
                : 'Create certificates from job details to see them here',
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCertificateCard(Certificate certificate) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCertificateDetails(certificate),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Certificate Type Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      certificate.certificateType,
                      style: TextStyle(
                        color: Colors.indigo.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Status Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: certificate.statusColor.withAlpha((0.1 * 255).round()),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      certificate.statusDisplayName,
                      style: TextStyle(
                        color: certificate.statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // PDF indicator
                  if (certificate.hasPdf)
                    IconButton(
                      icon: Icon(
                        Icons.picture_as_pdf,
                        color: Colors.red.shade600,
                        size: 20,
                      ),
                      onPressed: () => _openCertificate(certificate),
                      tooltip: 'Open PDF',
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Certificate Number
              Text(
                certificate.certificateNumber,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              // Customer and Job Info
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      certificate.customerName,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Row(
                children: [
                  Icon(Icons.work, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      certificate.jobTitle,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Row(
                children: [
                  Icon(Icons.location_on,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      certificate.customerAddress,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Dates Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Created',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          _formatDate(certificate.dateCreated),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  if (certificate.dateIssued != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Issued',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            _formatDate(certificate.dateIssued!),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),

                  // Action Button
                  if (certificate.hasPdf)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _openCertificate(certificate),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Job>> _loadJobsFromLocalIfExists() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/jobs.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        return jsonList.map((json) => Job.fromJson(json)).toList();
      }
    } catch (e) {
      // Handle error (e.g., log it)
    }
    return [];
  }

  String? _extractJobIdFromCertificateFileName(String fileName) {
    final lower = fileName.toLowerCase();
    final regex = RegExp(
        r'^(.*)_(?:gas_coc|gas coc|esc|roi|cof|coc|certificate)_certificate_.*\.pdf$');
    final match = regex.firstMatch(lower);
    return match?.group(1);
  }
}
