import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/job.dart' as job_model;
import '../services/firestore_service.dart';
import '../widgets/address_search_field.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class JobDetailsDialog extends StatefulWidget {
  final Customer customer;
  final Function(job_model.Job) onJobCreated;

  const JobDetailsDialog({
    super.key,
    required this.customer,
    required this.onJobCreated,
  });

  @override
  _JobDetailsDialogState createState() => _JobDetailsDialogState();
}

class _JobDetailsDialogState extends State<JobDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _jobNameController = TextEditingController();
  final TextEditingController _jobDescriptionController = TextEditingController();
  final TextEditingController _siteAddressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with customer information
    _siteAddressController.text = widget.customer.address;
    _emailController.text = widget.customer.email;
  }

  @override
  void dispose() {
    _jobNameController.dispose();
    _jobDescriptionController.dispose();
    _siteAddressController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _createJob() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final now = DateTime.now();
      
      final newJob = job_model.Job(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _jobNameController.text.trim(),
        description: _jobDescriptionController.text.trim(),
        customerName: widget.customer.name,
        address: _siteAddressController.text.trim(),
        customerEmail: _emailController.text.trim(),
        status: job_model.JobStatus.active,
        created: now,
        jobType: 'Estimate',
      );

      // Get the current jobs file path
      final directory = await getApplicationDocumentsDirectory();
      final jobsFile = File('${directory.path}/jobs.json');
      
      // Load existing jobs
      List<job_model.Job> jobs = [];
      if (await jobsFile.exists()) {
        final jsonString = await jobsFile.readAsString();
        final jsonList = jsonDecode(jsonString) as List;
        jobs = jsonList.map((json) => job_model.Job.fromJson(json)).toList();
      }
      
      // Add new job
      jobs.add(newJob);
      
      // Save to local file
      final jsonList = jobs.map((job) => job.toJson()).toList();
      await jobsFile.writeAsString(jsonEncode(jsonList));
      
      // Save to cloud
      try {
        await FirestoreService.saveJob(newJob);
        print('✅ Job synced to cloud');
      } catch (e) {
        print('❌ Error syncing job to cloud: $e');
        // Don't throw - local save is still important
      }

      widget.onJobCreated(newJob);
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create job: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Create Job for ${widget.customer.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _jobNameController,
                  decoration: const InputDecoration(
                    labelText: 'Job Name *',
                    hintText: 'Enter a name for this job',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Job name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _jobDescriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Job Description',
                    hintText: 'Describe the work to be done',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                AddressSearchField(
                  controller: _siteAddressController,
                  labelText: 'Site Address *',
                  helperText: 'Start typing to search for addresses',
                  isRequired: true,
                  onAddressSelected: (addressResult) {
                    // Address selected from search results
                    print('Selected job site address: ${addressResult.address}');
                    print('Coordinates: ${addressResult.latitude}, ${addressResult.longitude}');
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Site address is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter customer email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value)) {
                        return 'Please enter a valid email address';
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createJob,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Job'),
        ),
      ],
    );
  }
}
