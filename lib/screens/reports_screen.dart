import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/job.dart';

class ReportsScreen extends StatelessWidget {
  final List<Job> jobs;

  const ReportsScreen({
    super.key,
    required this.jobs,
  });

  @override
  Widget build(BuildContext context) {
    // Gather all invoices and estimates/quotes
    final allInvoices = jobs
        .expand((job) => job.estimateVersions
            .where((v) => v.type == 'invoice' && v.status == 'final'))
        .toList();

    final year = DateTime.now().year;

    final totalRevenue = allInvoices
        .where((v) => !v.isArchived)
        .fold<double>(0, (sum, v) => sum + (v.amount));

    final totalOutstanding = allInvoices
        .where((v) => !v.isPaid && !v.isArchived)
        .fold<double>(0, (sum, v) => sum + (v.amount));

    final totalProfit = allInvoices
        .where((v) => !v.isArchived)
        .fold<double>(0, (sum, v) => sum + (v.profit));

    final profitYTD = allInvoices
        .where((v) => v.timestamp != null && v.timestamp!.year == year && !v.isArchived)
        .fold<double>(0, (sum, v) => sum + (v.profit));

    final revenueYTD = allInvoices
        .where((v) => v.timestamp != null && v.timestamp!.year == year && !v.isArchived)
        .fold<double>(0, (sum, v) => sum + (v.amount));

    final completedJobs = jobs.where((j) => j.currentStatus == JobStatus.jobComplete).length;
    final activeJobs = jobs.where((j) => j.currentStatus == JobStatus.active).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: ListTile(
              title: const Text('Total Revenue'),
              trailing: Text('\$${totalRevenue.toStringAsFixed(2)}'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Outstanding Invoices'),
              trailing: Text('\$${totalOutstanding.toStringAsFixed(2)}'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Estimated Profit'),
              trailing: Text('\$${totalProfit.toStringAsFixed(2)}'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Estimated Profit YTD'),
              trailing: Text('\$${profitYTD.toStringAsFixed(2)}'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Revenue YTD'),
              trailing: Text('\$${revenueYTD.toStringAsFixed(2)}'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Completed Jobs'),
              trailing: Text('$completedJobs'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Active Jobs'),
              trailing: Text('$activeJobs'),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Export CSV'),
            onPressed: () async {
              final csv = _generateCsv(jobs);
              final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/report_export.csv');
              await file.writeAsString(csv);
              await Share.shareXFiles([XFile(file.path)], text: 'Jobs/Invoices/Estimates Export');
            },
          ),
        ],
      ),
    );
  }

  String _generateCsv(List<Job> jobs) {
    final buffer = StringBuffer();
    buffer.writeln('Job Title,Customer,Type,Number,Status,Due Date,Amount,Profit,Paid,Archived,Generated At,Address');
    for (final job in jobs) {
      for (int i = 0; i < job.estimateVersions.length; i++) {
        final v = job.estimateVersions[i];
        if (v.status == 'final') {
          // Use file name as number if available, else fallback to index
          final number = v.filePath != null
              ? v.filePath!.split('/').last.replaceAll('.pdf', '')
              : '${v.type ?? ''} ${i + 1}';
          buffer.writeln([
            _csv(job.title),
            _csv(job.customerName ?? ''),
            _csv(v.type ?? ''),
            _csv(number),
            _csv(v.status ?? ''),
            _csv(v.dueDate != null
                ? '${v.dueDate!.day}/${v.dueDate!.month}/${v.dueDate!.year}'
                : ''),
            _csv(v.amount.toStringAsFixed(2)),
            _csv(v.profit.toStringAsFixed(2)),
            _csv(v.isPaid ? 'Yes' : 'No'),
            _csv(v.isArchived ? 'Yes' : 'No'),
            _csv(v.timestamp != null
                ? '${v.timestamp!.day}/${v.timestamp!.month}/${v.timestamp!.year}'
                : ''),
            _csv(job.address ?? ''),
          ].join(','));
        }
      }
    }
    return buffer.toString();
  }

  String _csv(String s) {
    if (s.contains(',') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}