import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../models/certificate.dart';
import '../models/job.dart';
import '../models/customer.dart';

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

  // Available certificate types for filtering
  final List<String> _certificateTypes = ['All', 'COC', 'ESC', 'ROI', 'Gas COC', 'COF'];
  final List<String> _statuses = ['All', 'Draft', 'Issued', 'Completed'];
  final List<String> _sortOptions = ['Date Created', 'Date Issued', 'Customer Name', 'Certificate Type', 'Certificate Number'];

  @override
  void initState() {
    super.initState();
    _loadCertificates();
    _searchController.addListener(_filterCertificates);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadCertificates() {
    final certificates = <Certificate>[];
    
    for (final job in widget.jobs) {
      // Use job's customer information directly, or try to find matching customer
      Customer? customer;
      if (job.customerName != null) {
        customer = widget.customers.firstWhere(
          (c) => c.name == job.customerName,
          orElse: () => Customer(
            id: 'job-${job.id}',
            name: job.customerName ?? 'Unknown Customer',
            email: job.customerEmail ?? '',
            phone: '',
            address: job.address ?? '',
          ),
        );
      } else {
        customer = Customer(
          id: 'unknown',
          name: 'Unknown Customer',
          email: '',
          phone: '',
          address: job.address ?? '',
        );
      }
      
      // Find certificate estimate versions
      final certificateVersions = job.estimateVersions
          .where((version) => version.type == 'certificate')
          .toList();
      
      for (final version in certificateVersions) {
        certificates.add(Certificate.fromEstimateVersion(
          jobId: job.id,
          jobTitle: job.title,
          customerName: customer.name,
          customerAddress: customer.address,
          estimateVersion: version,
        ));
      }
    }
    
    setState(() {
      _allCertificates = certificates;
      _filterCertificates();
    });
  }

  void _filterCertificates() {
    final query = _searchController.text.toLowerCase();
    
    List<Certificate> filtered = _allCertificates.where((cert) {
      // Text search
      final matchesSearch = query.isEmpty ||
          cert.customerName.toLowerCase().contains(query) ||
          cert.customerAddress.toLowerCase().contains(query) ||
          cert.jobTitle.toLowerCase().contains(query) ||
          cert.certificateNumber.toLowerCase().contains(query) ||
          cert.certificateType.toLowerCase().contains(query);
      
      // Certificate type filter
      final matchesType = _selectedCertificateType == 'All' ||
          cert.certificateType == _selectedCertificateType;
      
      // Status filter
      final matchesStatus = _selectedStatus == 'All' ||
          cert.statusDisplayName == _selectedStatus;
      
      return matchesSearch && matchesType && matchesStatus;
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
              _buildDetailRow('Certificate Number', certificate.certificateNumber),
              _buildDetailRow('Type', certificate.certificateType),
              _buildDetailRow('Status', certificate.statusDisplayName),
              _buildDetailRow('Job Title', certificate.jobTitle),
              _buildDetailRow('Customer', certificate.customerName),
              _buildDetailRow('Address', certificate.customerAddress),
              _buildDetailRow('Date Created', _formatDate(certificate.dateCreated)),
              if (certificate.dateIssued != null)
                _buildDetailRow('Date Issued', _formatDate(certificate.dateIssued!)),
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
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by customer, address, job title, or certificate number...',
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
                          _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          color: Colors.indigo.shade700,
                        ),
                        onPressed: () => setState(() {
                          _sortAscending = !_sortAscending;
                          _filterCertificates();
                        }),
                        tooltip: _sortAscending ? 'Sort Ascending' : 'Sort Descending',
                      ),
                    ],
                  ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: certificate.statusColor.withOpacity(0.1),
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
                    Icon(
                      Icons.picture_as_pdf,
                      color: Colors.red.shade600,
                      size: 20,
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
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
}
