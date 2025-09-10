import 'package:flutter/material.dart';
import 'lib/models/job.dart';
import 'lib/utils/job_status_automation.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Job Status System Demo',
      home: JobStatusDemoScreen(),
    );
  }
}

class JobStatusDemoScreen extends StatefulWidget {
  const JobStatusDemoScreen({super.key});

  @override
  JobStatusDemoScreenState createState() => JobStatusDemoScreenState();
}

class JobStatusDemoScreenState extends State<JobStatusDemoScreen> {
  late Job demoJob;
  String demoOutput = '';

  @override
  void initState() {
    super.initState();
    demoJob = Job(
      id: 'demo-001',
      title: 'Kitchen Renovation - Smith Residence',
      customerName: 'John Smith',
      customerEmail: 'john.smith@email.com',
      address: '123 Main Street, Springfield',
      description: 'Complete kitchen electrical renovation including new outlets, lighting, and panel upgrade',
      status: JobStatus.active,
      created: DateTime.now(),
      dueDate: DateTime.now().add(Duration(days: 14)),
      jobType: 'Electrical',
      paymentTerms: '14 days',
    );
  }

  void _runStatusDemo() {
    setState(() {
      demoOutput = '';
      // Reset job status
      demoJob = Job(
        id: 'demo-001',
        title: 'Kitchen Renovation - Smith Residence',
        customerName: 'John Smith',
        customerEmail: 'john.smith@email.com',
        address: '123 Main Street, Springfield',
        description: 'Complete kitchen electrical renovation',
        status: JobStatus.active,
        created: DateTime.now(),
        dueDate: DateTime.now().add(Duration(days: 14)),
        jobType: 'Electrical',
        paymentTerms: '14 days',
      );
    });

    // Capture print output
    List<String> output = [];
    
    // Simulate the normal flow
    output.add('=== Job Status Flow Demo ===');
    output.add('Initial status: ${demoJob.statusDisplayName}');
    
    // Create estimate
    JobStatusAutomation.onPdfCreated(demoJob, 'estimate', 'EST-001');
    output.add('After estimate created: ${demoJob.statusDisplayName}');
    
    // Send estimate
    JobStatusAutomation.onEmailSent(demoJob, ['estimate'], 'EST-001');
    output.add('After estimate sent: ${demoJob.statusDisplayName}');
    
    // Create invoice
    JobStatusAutomation.onPdfCreated(demoJob, 'invoice', 'INV-001');
    output.add('After invoice created: ${demoJob.statusDisplayName}');
    
    // Send invoice
    JobStatusAutomation.onEmailSent(demoJob, ['invoice'], 'INV-001');
    output.add('After invoice sent: ${demoJob.statusDisplayName}');
    
    // Payment received
    JobStatusAutomation.onInvoicePaymentReceived(demoJob, 'INV-001');
    output.add('After invoice paid: ${demoJob.statusDisplayName}');
    
    // Job complete
    demoJob.onJobComplete();
    output.add('After job completed: ${demoJob.statusDisplayName}');
    
    output.add('\n=== Status History ===');
    for (int i = 0; i < demoJob.statusHistory.length; i++) {
      final history = demoJob.statusHistory[i];
      output.add('${i + 1}. ${history.status.displayName}');
      if (history.reason != null) {
        output.add('   Reason: ${history.reason}');
      }
      output.add('   Time: ${_formatDateTime(history.timestamp)}');
    }

    setState(() {
      demoOutput = output.join('\n');
    });
  }

  void _runSpecialCaseDemo() {
    setState(() {
      demoOutput = '';
      // Reset job status
      demoJob = Job(
        id: 'demo-002',
        title: 'Office Lighting Upgrade',
        customerName: 'ABC Corporation',
        customerEmail: 'facilities@abc.com',
        address: '456 Business Park Dr',
        description: 'LED lighting upgrade for office building',
        status: JobStatus.active,
        created: DateTime.now(),
      );
    });

    List<String> output = [];
    
    output.add('=== Special Case: Estimate + Invoice Together ===');
    output.add('Initial status: ${demoJob.statusDisplayName}');
    
    // Send both estimate and invoice together
    JobStatusAutomation.onEmailSent(demoJob, ['estimate', 'invoice'], 'COMBINED-001');
    output.add('After sending both together: ${demoJob.statusDisplayName}');
    output.add('Note: Estimate status takes priority when both are sent together');
    
    output.add('\n=== Status History ===');
    for (int i = 0; i < demoJob.statusHistory.length; i++) {
      final history = demoJob.statusHistory[i];
      output.add('${i + 1}. ${history.status.displayName}');
      if (history.reason != null) {
        output.add('   Reason: ${history.reason}');
      }
    }

    setState(() {
      demoOutput = output.join('\n');
    });
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Job Status System Demo'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current job info
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Job: ${demoJob.title}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Status: '),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(demoJob.currentStatus),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            demoJob.statusDisplayName,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text('Customer: ${demoJob.customerName}'),
                    Text('Address: ${demoJob.address}'),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Demo buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _runStatusDemo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Run Normal Flow Demo'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _runSpecialCaseDemo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Run Special Case Demo'),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 16),
            
            // Status reference card
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status Flow Reference:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    ...JobStatus.values.map((status) => Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getStatusColor(status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(status.displayName),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Output area
            Expanded(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Demo Output:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              demoOutput.isEmpty
                                  ? 'Click a demo button above to see how job statuses automatically update based on system events.'
                                  : demoOutput,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
