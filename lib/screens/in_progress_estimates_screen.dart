import 'package:flutter/material.dart';
import '../models/job.dart' as job_model;
import '../models/in_progress_build.dart';
import '../services/in_progress_build_service.dart';
import 'estimate_builder_screen.dart' as estimate_builder;
import 'package:intl/intl.dart';

class InProgressEstimatesScreen extends StatefulWidget {
  final List<job_model.Job> jobs;

  const InProgressEstimatesScreen({
    super.key,
    required this.jobs,
  });

  @override
  State<InProgressEstimatesScreen> createState() => _InProgressEstimatesScreenState();
}

class _InProgressEstimatesScreenState extends State<InProgressEstimatesScreen> {
  String search = '';
  List<InProgressBuild> allBuilds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllBuilds();
  }

  Future<void> _loadAllBuilds() async {
    setState(() => _isLoading = true);
    
    try {
      final builds = <InProgressBuild>[];
      
      // Load in-progress builds for all jobs
      for (final job in widget.jobs) {
        try {
          final jobBuilds = await InProgressBuildService.getBuildsForJob(job.id);
          builds.addAll(jobBuilds);
        } catch (e) {
          print('Error loading builds for job ${job.id}: $e');
        }
      }
      
      setState(() {
        allBuilds = builds;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading all builds: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter builds based on search
    final filteredBuilds = allBuilds.where((build) {
      final job = widget.jobs.firstWhere(
        (j) => j.id == build.jobId,
        orElse: () => job_model.Job(
          id: build.jobId,
          title: 'Unknown Job',
          customerName: 'Unknown Customer',
          address: 'Unknown Address',
          estimateVersions: [],
        ),
      );
      
      final searchTerm = search.toLowerCase();
      return job.title.toLowerCase().contains(searchTerm) ||
             job.customerName?.toLowerCase().contains(searchTerm) == true ||
             job.address?.toLowerCase().contains(searchTerm) == true ||
             build.name.toLowerCase().contains(searchTerm);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('In Progress Builds'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllBuilds,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search by job name, customer, or address',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => search = val),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredBuilds.isEmpty
                    ? const Center(child: Text('No in-progress builds found.'))
                    : ListView.builder(
                        itemCount: filteredBuilds.length,
                        itemBuilder: (context, index) {
                          final build = filteredBuilds[index];
                          final job = widget.jobs.firstWhere(
                            (j) => j.id == build.jobId,
                            orElse: () => job_model.Job(
                              id: build.jobId,
                              title: 'Unknown Job',
                              customerName: 'Unknown Customer',
                              address: 'Unknown Address',
                              estimateVersions: [],
                            ),
                          );

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.build_circle, color: Colors.orange),
                              title: Text('In-Progress Build ${index + 1}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Job: ${job.title}'),
                                  Text('Customer: ${job.customerName ?? 'Unknown'}'),
                                  Text('Site: ${job.address ?? 'No address'}'),
                                  Text('Job #: ${job.id}'),
                                  Text('Last modified: ${DateFormat('MMM dd, yyyy HH:mm').format(build.lastModified)}'),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => estimate_builder.EstimateBuilderScreen(
                                          job: job,
                                          initialItems: build.currentVersion.items,
                                        ),
                                      ),
                                    );
                                    await _loadAllBuilds(); // Refresh the list
                                  } else if (action == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Build'),
                                        content: const Text('Are you sure you want to delete this in-progress build? This cannot be undone.'),
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
                                      try {
                                        await InProgressBuildService.deleteBuild(build.id);
                                        await _loadAllBuilds(); // Refresh the list
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Build deleted successfully')),
                                        );
                                      } catch (e) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to delete build: $e')),
                                        );
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => estimate_builder.EstimateBuilderScreen(
                                      job: job,
                                      initialItems: build.currentVersion.items,
                                    ),
                                  ),
                                );
                                await _loadAllBuilds(); // Refresh the list
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