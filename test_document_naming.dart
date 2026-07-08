import 'package:flutter/material.dart';
import 'lib/models/job.dart';
import 'lib/services/document_naming_service.dart';
import 'lib/mixins/document_naming_mixin.dart';

void main() {
  runApp(const DocumentNamingDemo());
}

class DocumentNamingDemo extends StatelessWidget {
  const DocumentNamingDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Naming Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const DocumentNamingDemoScreen(),
    );
  }
}

class DocumentNamingDemoScreen extends StatefulWidget {
  const DocumentNamingDemoScreen({super.key});

  @override
  State<DocumentNamingDemoScreen> createState() =>
      _DocumentNamingDemoScreenState();
}

class _DocumentNamingDemoScreenState extends State<DocumentNamingDemoScreen>
    with DocumentNamingMixin {
  final List<Job> _demoJobs = [
    Job(
      id: '3664566345',
      title: 'Electrical Installation',
      customerName: 'John Smith',
      address: '22B Campbell Ave',
      attachments: [],
    ),
    Job(
      id: '44555343',
      title: 'Bathroom Renovation',
      customerName: 'Sarah Johnson',
      address: '19A Mamaku Street',
      attachments: ['COC 19A Mamaku Street 44555343.pdf'], // Existing COC
    ),
    Job(
      id: '12345678',
      title: 'Kitchen Upgrade',
      customerName: 'Mike Wilson',
      address: '5 Queen Street',
      attachments: [
        'Invoice 5 Queen Street 12345678.pdf',
        'Invoice 5 Queen Street 12345678 (2).pdf',
        'Estimate 5 Queen Street 12345678.pdf',
        'ESC 5 Queen Street 12345678.pdf',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Naming Convention Demo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PDF Naming Convention',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Format: [Type] [Job Site Address] [Job Number] [(count)] or [YYYY-MM-DD] [Estimate|Quote] [sequence]',
              style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            const Text(
              'Examples:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildExamplesList(),
            const SizedBox(height: 24),
            const Text(
              'Demo Jobs & Generated Names:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildJobsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamplesList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• 2026-07-01 Estimate 1.pdf'),
          Text('• Invoice 19A Mamaku Street 44555343 (2).pdf'),
          Text('• ESC 19A Mamaku Street 4455343.pdf'),
          Text('• COC 5 Queen Street 12345678.pdf'),
          Text('• Gas COC 10 Main Road 98765432.pdf'),
          Text('• ROI 15 High Street 11111111.pdf'),
        ],
      ),
    );
  }

  Widget _buildJobsList() {
    return ListView.builder(
      itemCount: _demoJobs.length,
      itemBuilder: (context, index) {
        final job = _demoJobs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job: ${job.title}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text('Customer: ${job.customerName}'),
                Text('Address: ${job.address}'),
                Text('Job ID: ${job.id}'),
                const SizedBox(height: 12),
                if (job.attachments?.isNotEmpty == true) ...[
                  const Text(
                    'Existing Attachments:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ...job.attachments!.map((attachment) => Text(
                        '• $attachment',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      )),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'Generated Names:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                _buildGeneratedNamesList(job),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGeneratedNamesList(Job job) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGeneratedName('Invoice', generateInvoiceName(job), Colors.red),
          _buildGeneratedName(
              'Estimate', generateEstimateName(job), Colors.blue),
          _buildGeneratedName('Quote', generateQuoteName(job), Colors.purple),
          _buildGeneratedName('ESC', generateEscName(job), Colors.orange),
          _buildGeneratedName('COC', generateCocName(job), Colors.teal),
          _buildGeneratedName('Gas COC', generateGasCocName(job), Colors.brown),
          _buildGeneratedName('ROI', generateRoiName(job), Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildGeneratedName(String type, String fileName, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$type:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Example of how to integrate with existing code
class PdfGenerationExample {
  /// Example method showing how to use the naming service
  static Future<String> generatePdfWithStandardNaming({
    required Job job,
    required String documentType,
    required List<int> pdfBytes,
  }) async {
    // Generate standardized filename
    final fileName = DocumentNamingService.generatePdfFileName(
      documentType: documentType,
      job: job,
      existingAttachments: job.attachments,
    );

    // Save the file
    // (In real app, you'd use path_provider to get the directory)
    final filePath = '/app/documents/$fileName';

    // Add to job attachments
    job.attachments ??= [];
    if (!job.attachments!.contains(filePath)) {
      job.attachments!.add(filePath);
    }

    return filePath;
  }

  /// Example for when using the mixin
  static String exampleWithMixin(DocumentNamingMixin mixin, Job job) {
    // Much simpler when using the mixin
    return mixin.generateInvoiceName(job);
  }
}
