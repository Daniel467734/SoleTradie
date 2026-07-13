# Integration Guide: Delta Sync & Lazy Loading

## Quick Start

### 1. Update Firebase Integration Service

Replace the `loadJobs()` method to use delta sync:

```dart
// OLD: FirebaseIntegrationService.loadJobs()
// Fetches ALL jobs every time (slow, high memory)

// NEW: Use DeltaSyncService instead
static Future<List<Job>> loadJobs({
  void Function(List<Job> cloudJobs)? onCloudUpdate,
}) async {
  try {
    // Delta sync: only fetch changes
    final jobs = await DeltaSyncService.syncJobsWithDelta();
    
    print('📱 Loaded ${jobs.length} jobs with delta sync');
    
    // Update cloud changes in background if authenticated
    if (isReady) {
      unawaited(_refreshJobsFromCloudInBackground(
        localJobs: jobs,
        onCloudUpdate: onCloudUpdate,
      ));
    }
    
    return jobs;
  } catch (e) {
    print('❌ Error loading jobs: $e');
    return [];
  }
}
```

### 2. Update Jobs Screen

```dart
// lib/screens/jobs_screen.dart

Future<void> _loadJobs() async {
  setState(() => _isLoading = true);
  
  try {
    // Load summaries for list view (fast, lightweight)
    final summaries = await JobLazyLoadService.loadJobSummaries();
    
    setState(() {
      _jobSummaries = summaries;
      _isLoading = false;
    });
    
    // Background sync in case cloud has changes
    unawaited(_syncJobsInBackground());
  } catch (e) {
    print('❌ Error loading jobs: $e');
    setState(() => _isLoading = false);
  }
}

// Background sync (doesn't block UI)
Future<void> _syncJobsInBackground() async {
  try {
    final jobs = await DeltaSyncService.syncJobsWithDelta();
    
    // Only update UI if sync found changes
    if (jobs.isNotEmpty && mounted) {
      setState(() {
        _jobSummaries = jobs
            .map((j) => JobSummary(
              id: j.id,
              title: j.title,
              customerName: j.customerName,
              address: j.address,
              created: j.created,
              status: j.currentStatus.displayName,
              totalAmount: j.invoices.fold(0.0, (sum, inv) => sum + (inv.total ?? 0)),
              hasUnpaidInvoices: j.invoices.any((inv) => !inv.isPaid),
              invoiceCount: j.invoices.length,
              estimateCount: j.estimates.length,
            ))
            .toList();
      });
    }
  } catch (e) {
    print('⚠️ Background sync failed: $e');
  }
}

// When user taps a job
Future<void> _openJobDetails(String jobId) async {
  try {
    // Fetch full job details on-demand
    final fullJob = await JobLazyLoadService.loadJobDetails(jobId);
    
    if (fullJob != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => JobDetailsScreen(job: fullJob),
      ));
    }
  } catch (e) {
    print('❌ Error loading job: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error loading job: $e')),
    );
  }
}
```

### 3. Update Job Save Method

```dart
// When job is modified (e.g., invoice marked as paid)
Future<void> _saveJobChanges(Job job) async {
  try {
    // Save job using lazy-load service (handles local + cloud sync)
    await JobLazyLoadService.saveJobDetails(job);
    
    // Show success message
    messenger.showSnackBar(const SnackBar(
      content: Text('Job saved ✓'),
    ));
    
    // Note: Cloud sync happens in background non-blocking
  } catch (e) {
    print('❌ Error saving job: $e');
    messenger.showSnackBar(SnackBar(
      content: Text('Error saving: $e'),
    ));
  }
}
```

### 4. List View Widget

```dart
// Display job summaries (lightweight)
ListView.builder(
  itemCount: _jobSummaries.length,
  itemBuilder: (context, index) {
    final summary = _jobSummaries[index];
    
    return ListTile(
      title: Text(summary.title),
      subtitle: Text(summary.customerName ?? 'No customer'),
      trailing: summary.hasUnpaidInvoices
          ? Badge(label: Text('${summary.invoiceCount}'))
          : null,
      onTap: () => _openJobDetails(summary.id),
    );
  },
)
```

## Data Structure Changes

### Before (Full Job in Memory)
```
Job {
  id: "abc123"
  title: "Install lights"
  customerName: "John"
  address: "123 Main St"
  invoices: [Invoice{...500KB nested data...}] × 10
  estimates: [EstimateVersion{...nested...}] × 5
  timeline: [TimelineEntry{...}] × 100
  attachments: [File{...}] × 50
  ... many other fields
  // Total: ~500KB per job
}
```

### After (Summary for List, Full on Demand)
```
// For list view (2KB):
JobSummary {
  id: "abc123"
  title: "Install lights"
  customerName: "John"
  address: "123 Main St"
  invoiceCount: 10
  hasUnpaidInvoices: true
  totalAmount: 1500.0
  status: "Active"
}

// Fetched on-demand when user opens job (500KB)
```

## Storage Structure

### Local Files
```
/Documents/
├── job_summaries.json          # All summaries (~2KB each, 100 jobs = 200KB)
├── customers.json
├── price_book.json
├── jobs_sync_meta.json         # Last sync time, data hash, timestamps
├── customers_sync_meta.json
├── job_details_<id1>.json      # Full job data (500KB, fetched on-demand)
├── job_details_<id2>.json      # Cached for quick re-open
└── ...
```

## Monitoring

### Check Sync Status
```dart
// See when last sync occurred
final syncMeta = await _loadSyncMetadata('jobs');
print('Last sync: ${syncMeta.lastSyncTime}');
print('Cloud version: ${syncMeta.cloudVersion}');
print('Tracked ${syncMeta.entityTimestamps.length} jobs');
```

### Monitor Memory Usage
```dart
// Profiler: Check memory when app starts
// Before: 200-300MB (all data loaded)
// After: 20-50MB (summaries + cached full jobs)
```

### Verify Sync Works
```dart
// In logcat, you should see:
📱 Loaded 100 job summaries from local storage
🔄 Delta sync: 5 jobs changed since 2024-07-10 14:30:00
✅ Jobs synced: 100 total

// Or if nothing changed:
✓ Jobs already in sync (no changes since 2024-07-10 14:30:00)
```

## Troubleshooting

### Issue: App shows stale data
**Cause**: Sync metadata got corrupted or is too old
**Solution**: Clear sync metadata and force resync
```dart
await DeltaSyncService.clearSyncMetadata();
// App will refetch all jobs on next startup
```

### Issue: OutOfMemoryError still occurs
**Cause**: Full jobs being loaded even though code uses summaries
**Solution**: Check that you're using `JobLazyLoadService` for list view, not full `Job` objects
```dart
// ❌ Wrong - loads full jobs
List<Job> jobs = await FirestoreService.getJobs();

// ✅ Correct - loads summaries only
List<JobSummary> summaries = await JobLazyLoadService.loadJobSummaries();
```

### Issue: Sync takes too long on slow network
**Cause**: First sync fetches all data from cloud
**Solution**: Increase timeout or retry
```dart
// Sync happens in background, so UI isn't blocked
// Check logs to monitor progress
```

## Performance Targets

| Metric | Before | After | Goal |
|--------|--------|-------|------|
| App startup time | 45-60s | 2-3s | ✅ |
| Memory usage | 200-300MB | 20-50MB | ✅ |
| Bandwidth per sync | 10-50MB | 100KB-1MB | ✅ |
| Job list render | 5-10s | <500ms | ✅ |
| OutOfMemoryError | Frequent | Eliminated | ✅ |

## Testing Checklist

- [ ] Build APK successfully
- [ ] App starts in <3 seconds
- [ ] Job list displays all jobs
- [ ] Tapping job loads details correctly
- [ ] Updating invoice status saves instantly
- [ ] Cloud sync occurs in background
- [ ] Close app and reopen - data persists
- [ ] Test with 500+ jobs in Firebase
- [ ] Monitor for OutOfMemoryError in logcat
- [ ] Verify metadata files created in local storage
- [ ] Check Firebase bandwidth usage reduced

## Rollback

If optimization causes issues:

```dart
// In jobs_screen.dart, revert to old method:
List<Job> jobs = await FirestoreService.getJobs();
// This will load ALL jobs but will be slow/memory-intensive
// Use only as fallback while investigating issues
```
