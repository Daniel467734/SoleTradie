import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../models/job.dart';
import '../models/job_summary.dart';
import 'firestore_service.dart';

/// Handles lazy loading of job details on-demand.
/// Loads job summaries first (lightweight) then fetches full details only when needed.
/// This prevents OutOfMemoryError from loading 100+ jobs with all nested data at once.
class JobLazyLoadService {
  static final _cache = <String, Job>{};
  static const _maxCacheSize = 20; // Keep last 20 full jobs in memory

  /// Load all job summaries (lightweight - ~2KB per job vs 500KB+ for full job)
  /// Returns summaries for list view without loading full nested data
  static Future<List<JobSummary>> loadJobSummaries() async {
    try {
      // Try local cache first
      final local = await _loadJobSummariesFromLocal();
      if (local.isNotEmpty) {
        print('📱 Loaded ${local.length} job summaries from local storage');
      }

      // Background refresh from cloud
      if (FirebaseAuth.instance.currentUser != null) {
        _refreshJobSummariesFromCloud();
      }

      return local;
    } catch (e) {
      print('❌ Error loading job summaries: $e');
      return [];
    }
  }

  /// Load a single job's full details on-demand
  /// Check cache first, then load from cloud/local
  static Future<Job?> loadJobDetails(String jobId) async {
    // Check in-memory cache first
    if (_cache.containsKey(jobId)) {
      print('✅ Job $jobId loaded from memory cache');
      return _cache[jobId];
    }

    try {
      // Try local storage first
      Job? job = await _loadJobDetailsFromLocal(jobId);
      if (job != null) {
        print('📱 Job $jobId loaded from local storage');
        _addToCache(jobId, job);
        return job;
      }

      // Load from cloud
      if (FirebaseAuth.instance.currentUser != null) {
        job = await FirestoreService.getJob(jobId);
        if (job != null) {
          print('☁️ Job $jobId loaded from Firebase');
          await _saveJobDetailsToLocal(job);
          _addToCache(jobId, job);
          return job;
        }
      }

      print('⚠️ Job $jobId not found');
      return null;
    } catch (e) {
      print('❌ Error loading job details for $jobId: $e');
      return null;
    }
  }

  /// Save a job's full details (called when job is modified)
  static Future<void> saveJobDetails(Job job) async {
    try {
      // Save locally
      await _saveJobDetailsToLocal(job);

      // Sync to cloud if authenticated
      if (FirebaseAuth.instance.currentUser != null) {
        await FirestoreService.saveJob(job);
        print('☁️ Job ${job.id} synced to Firebase');
      }

      // Update cache
      _addToCache(job.id, job);

      // Update job summary in local summaries list
      await _updateJobSummaryInLocal(job);
    } catch (e) {
      print('❌ Error saving job details: $e');
      rethrow;
    }
  }

  /// Refresh job summaries from cloud in background
  static Future<void> _refreshJobSummariesFromCloud() async {
    if (FirebaseAuth.instance.currentUser == null) return;

    try {
      final jobs = await FirestoreService.getJobs();
      if (jobs.isNotEmpty) {
        // Convert full jobs to summaries (extract essential fields)
        final summaries = jobs
            .map((job) => JobSummary(
                  id: job.id,
                  title: job.title,
                  customerName: job.customerName,
                  address: job.address,
                  created: job.created,
                  updated: DateTime.now(),
                  status: job.currentStatus.displayName,
                  totalAmount: job.invoices.isEmpty
                      ? null
                      : job.invoices.fold<double>(
                          0.0, (sum, inv) => sum + inv.total),
                  hasUnpaidInvoices:
                      job.invoices.any((inv) => !inv.isPaid),
                  invoiceCount: job.invoices.length,
                  estimateCount: job.estimates.length,
                ))
            .toList();

        await _saveJobSummariesToLocal(summaries);
        print('✅ Synced ${summaries.length} job summaries from Firebase');
      }
    } catch (e) {
      print('❌ Error refreshing job summaries from cloud: $e');
    }
  }

  // PRIVATE: Cache management

  static void _addToCache(String jobId, Job job) {
    _cache[jobId] = job;

    // Prevent cache from growing unbounded - remove oldest entry if needed
    if (_cache.length > _maxCacheSize) {
      final keyToRemove = _cache.keys.first;
      _cache.remove(keyToRemove);
      print('🗑️ Evicted $keyToRemove from job cache (max size: $_maxCacheSize)');
    }
  }

  static void clearCache() {
    _cache.clear();
    print('🧹 Cleared job details cache');
  }

  // PRIVATE: Local storage

  static Future<List<JobSummary>> _loadJobSummariesFromLocal() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/job_summaries.json');

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(jsonString);
          return jsonList.map((e) => JobSummary.fromJson(e)).toList();
        }
      }
    } catch (e) {
      print('❌ Error loading job summaries from local: $e');
    }
    return [];
  }

  static Future<void> _saveJobSummariesToLocal(List<JobSummary> summaries) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/job_summaries.json');
      final jsonList = summaries.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
      print('💾 Saved ${summaries.length} job summaries to local storage');
    } catch (e) {
      print('❌ Error saving job summaries to local: $e');
    }
  }

  static Future<Job?> _loadJobDetailsFromLocal(String jobId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/job_details_$jobId.json');

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final json = jsonDecode(jsonString);
          return Job.fromJson(json);
        }
      }
    } catch (e) {
      print('❌ Error loading job details from local for $jobId: $e');
    }
    return null;
  }

  static Future<void> _saveJobDetailsToLocal(Job job) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/job_details_${job.id}.json');
      await file.writeAsString(jsonEncode(job.toJson()));
    } catch (e) {
      print('⚠️ Could not save job details to local for ${job.id} (expected on web): $e');
    }
  }

  static Future<void> _updateJobSummaryInLocal(Job job) async {
    try {
      final summaries = await _loadJobSummariesFromLocal();
      final index = summaries.indexWhere((s) => s.id == job.id);

      // Build summary from full job data
      final newSummary = JobSummary(
        id: job.id,
        title: job.title,
        customerName: job.customerName,
        address: job.address,
        created: job.created,
        updated: DateTime.now(),
        status: job.currentStatus.displayName,
        totalAmount: job.invoices.isNotEmpty
            ? job.invoices.fold<double>(0, (sum, inv) {
                final value = ((inv.total) as double?) ?? 0;
                return sum + value;
              })
            : null,
        hasUnpaidInvoices: job.invoices.any((inv) => !inv.isPaid),
        invoiceCount: job.invoices.length,
        estimateCount: job.estimates.length,
      );

      if (index >= 0) {
        summaries[index] = newSummary;
      } else {
        summaries.add(newSummary);
      }

      await _saveJobSummariesToLocal(summaries);
    } catch (e) {
      print('⚠️ Error updating job summary in local: $e');
    }
  }
}
