import 'package:flutter/material.dart';
import '../models/job.dart';
import '../widgets/job_details_dialog.dart';
import 'job_details_screen.dart';
import '../models/customer.dart';
import 'pricebook_extensive_screen.dart' show PriceBookItem;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../services/firebase_integration_service.dart';
import '../widgets/address_search_field.dart';
import '../services/job_number_service.dart';
import '../widgets/multi_date_picker_dialog.dart';
import '../services/weather_service.dart';
import '../services/address_search_service.dart';
import '../services/demo_mode_service.dart';
import '../widgets/weather_summary_tile.dart';
import '../route_observer.dart';

class JobsScreen extends StatefulWidget {
  final List<Customer> customers;
  final void Function(Customer) onAdd;
  final void Function(Customer) onUpdate;
  final void Function(String) onRemove;
  // Jobs/price book already loaded (local-first + Firestore-synced) by
  // main.dart. These are used to seed the screen's state immediately so
  // that on platforms where dart:io/path_provider isn't available (e.g.
  // web), the screen doesn't reset to an empty list every time it's
  // opened - previously this screen ONLY read from disk via
  // getApplicationDocumentsDirectory(), which silently fails on web and
  // made it look like Firestore data "disappeared" when navigating here.
  final List<Job>? jobs;
  final List<PriceBookItem>? priceBook;

  const JobsScreen({
    super.key,
    required this.customers,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    this.jobs,
    this.priceBook,
  });

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> with RouteAware {
  List<Job> jobs = [];
  List<PriceBookItem> priceBook = [];
  String search = '';
  String _statusFilter = 'active';

  @override
  void initState() {
    super.initState();
    // Seed immediately from whatever main.dart already has (local-first +
    // Firestore-synced), so the UI never shows an empty list while the
    // (possibly unsupported, e.g. on web) disk read below completes.
    jobs = List.from(widget.jobs ?? []);
    priceBook = List.from(widget.priceBook ?? []);
    search = '';
    _statusFilter = 'active';
    _loadJobsFromDisk();
    _loadPriceBook();
    // Also fetch directly from Firestore ourselves. widget.jobs/priceBook
    // are just a snapshot taken at the moment this screen was pushed - if
    // main.dart's own background Firestore sync (kicked off on sign-in)
    // hadn't finished yet at that moment, this screen would otherwise be
    // stuck showing an empty list forever, since (unlike main.dart's
    // DashboardScreen) this pushed route is never rebuilt when main.dart's
    // state updates later. This is especially important on web, where
    // there's no local disk cache to bridge the gap while waiting.
    _refreshJobsAndPriceBookFromCloud();
  }

  Future<void> _refreshJobsAndPriceBookFromCloud() async {
    try {
      final cloudJobs = await FirebaseIntegrationService.loadJobs(
        onCloudUpdate: (updatedJobs) {
          if (mounted) setState(() => jobs = updatedJobs);
        },
      );
      if (mounted && cloudJobs.isNotEmpty) {
        setState(() => jobs = cloudJobs);
      }
    } catch (e) {
      print('⚠️ JobsScreen: failed to refresh jobs from cloud: $e');
    }
    try {
      final cloudPriceBook = await FirebaseIntegrationService.loadPriceBook(
        onCloudUpdate: (updatedItems) {
          if (mounted) setState(() => priceBook = updatedItems);
        },
      );
      if (mounted && cloudPriceBook.isNotEmpty) {
        setState(() => priceBook = cloudPriceBook);
      }
    } catch (e) {
      print('⚠️ JobsScreen: failed to refresh price book from cloud: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Reload jobs (and pricebook) from disk every time the user returns to
    // this screen (e.g. after viewing/editing a job in JobDetailsScreen),
    // so the list always reflects the latest status/changes.
    _loadJobsFromDisk();
    _loadPriceBook();
  }

  bool _matchesStatusFilter(Job job) {
    switch (_statusFilter) {
      case 'all':
        return true;
      case 'completed':
        return job.currentStatus == JobStatus.jobComplete;
      case 'archived':
        return job.currentStatus == JobStatus.archived;
      case 'active':
      default:
        return job.currentStatus != JobStatus.jobComplete &&
            job.currentStatus != JobStatus.archived;
    }
  }

  Future<File> get _jobsFile async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/jobs.json');
    } catch (e) {
      print('⚠️ JobsScreen._jobsFile: could not access application documents directory (expected on web): $e');
      // Return a dummy file path that won't actually be accessible on web
      // The caller's try/catch will catch the error when attempting I/O
      return File('/tmp/jobs.json');
    }
  }

  Future<void> _loadJobs() async {
    if (DemoModeService.instance.isDemoMode) {
      setState(() {
        jobs = DemoModeService.instance.getJobs();
      });
      return;
    }
    try {
      final file = await _jobsFile;
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(jsonString);

        setState(() {
          jobs = jsonList.map((e) => Job.fromJson(e)).toList();
        });
      }
    } catch (e) {
      // Local disk access isn't available on some platforms (e.g. web,
      // where getApplicationDocumentsDirectory() throws a
      // MissingPluginException). Previously this reset `jobs` to an empty
      // list on any error, which wiped out the perfectly good
      // Firestore-synced data that main.dart had already seeded into this
      // screen via widget.jobs - making it look like jobs "disappeared"
      // every time this screen was opened on web. Just log and keep
      // whatever data is already in memory instead.
      print('⚠️ Could not load jobs from local disk (expected on web): $e');
    }
  }

  Future<void> _saveJobs() async {
    if (DemoModeService.instance.isDemoMode) {
      // Demo jobs are already stored in DemoModeService's in-memory list;
      // nothing to persist to real disk/cloud storage while in demo mode.
      return;
    }
    // Save to local file for backward compatibility. This throws a
    // MissingPluginException on web (no path_provider implementation
    // there), so it must not be allowed to abort the cloud sync below,
    // which is the actual source of truth on web.
    try {
      final file = await _jobsFile;
      final jsonList = jobs.map((job) => job.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('⚠️ Could not save jobs to local disk (expected on web): $e');
    }

    // Sync to cloud in background so job creation can continue immediately
    _syncJobsToCloud();
  }

  Future<void> _syncJobsToCloud() async {
    try {
      for (final job in jobs) {
        await FirestoreService.saveJob(job);
      }
      print('✅ All jobs synced to cloud');
    } catch (e) {
      print('❌ Error syncing jobs to cloud: $e');
      // Do not rethrow so local save stays successful
    }
  }

  /// Sync a single job to cloud (used for status updates)
  Future<void> _syncJobToCloud(Job job) async {
    try {
      await FirestoreService.saveJob(job);
      print('✅ Job ${job.id} synced to cloud (status: ${job.currentStatus.displayName})');
    } catch (e) {
      print('⚠️ Error syncing job ${job.id} to cloud: $e');
    }
  }

  Future<void> _addJob(Job job) async {
    if (DemoModeService.instance.isDemoMode) {
      await DemoModeService.instance.createJob(job);
      setState(() {
        jobs = DemoModeService.instance.getJobs();
      });
      return;
    }
    setState(() {
      jobs.add(job);
    });
    await _saveJobs();
  }

  Future<void> _loadPriceBook() async {
    if (DemoModeService.instance.isDemoMode) {
      // Demo mode uses its own in-memory pricebook (see DemoModeService);
      // the jobs screen's PriceBookItem list isn't needed for the demo
      // sandbox flows, so just leave it empty rather than reading real
      // pricebook data from disk.
      setState(() => priceBook = []);
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final decoded = jsonDecode(jsonString);
        final List<dynamic> jsonList;
        if (decoded is Map<String, dynamic> && decoded.containsKey('items')) {
          jsonList = decoded['items'] as List<dynamic>;
        } else if (decoded is List<dynamic>) {
          jsonList = decoded;
        } else {
          throw Exception('Unexpected pricebook JSON structure');
        }
        setState(() {
          priceBook = jsonList.map((e) => PriceBookItem.fromJson(e)).toList();
        });
      }
    } catch (e) {
      // Local disk access isn't available on some platforms (e.g. web).
      // Keep whatever price book data was already seeded from
      // widget.priceBook instead of leaving/forcing an empty list.
      print('⚠️ Could not load price book from local disk (expected on web): $e');
    }
  }

  Future<void> _loadJobsFromDisk() async {
    await _loadJobs();
  }

  @override
  Widget build(BuildContext context) {
    // Sync all job statuses from their documents before filtering
    for (final job in jobs) {
      job.syncStatusFromDocuments();
    }

    final filtered = jobs.where((job) {
      // Filter by selected statuses
      final matchesStatus = _matchesStatusFilter(job);

      // Filter by search term
      final matchesSearch = (job.title
              .toLowerCase()
              .contains(search.toLowerCase()) ||
          (job.customerName ?? '')
              .toLowerCase()
              .contains(search.toLowerCase()) ||
          (job.address ?? '').toLowerCase().contains(search.toLowerCase()) ||
          (job.description ?? '')
              .toLowerCase()
              .contains(search.toLowerCase()) ||
          job.statusDisplayName.toLowerCase().contains(search.toLowerCase()));

      return matchesStatus && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      final aCreated = a.created ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bCreated = b.created ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bCreated.compareTo(aCreated);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(DemoModeService.instance.isDemoMode ? 'Jobs (Demo Mode)' : 'Jobs'),
        backgroundColor:
            DemoModeService.instance.isDemoMode ? Colors.deepPurple : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Job',
            onPressed: _showAddJobDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Search jobs',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => search = val),
            ),
            const SizedBox(height: 12),

            // Status filter section - now as a compact dropdown
            Row(
              children: [
                const Icon(Icons.filter_list),
                const SizedBox(width: 8),
                Flexible(
                  child: const Text(
                    'Filter by Status:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    value: _statusFilter,
                    hint: const Text('Select status...'),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All')),
                      const DropdownMenuItem(
                          value: 'active', child: Text('Active')),
                      const DropdownMenuItem(
                          value: 'completed', child: Text('Completed')),
                      const DropdownMenuItem(
                          value: 'archived', child: Text('Archived')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _statusFilter = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Results summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${filtered.length} job${filtered.length != 1 ? 's' : ''} found',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final job = filtered[index];
                  return Card(
                    child: ListTile(
                      title: GestureDetector(
                        onTap: () => _handleJobTap(job),
                        child: Text(
                          job.title,
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _handleJobTap(job),
                            child: Text(
                                'Customer: ${job.customerName ?? 'No customer'}'),
                          ),
                          if (job.description?.isNotEmpty == true)
                            Text('Description: ${job.description}'),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                    'Address: ${job.address ?? "No address"}'),
                              ),
                              if (job.address?.isNotEmpty == true)
                                IconButton(
                                  icon:
                                      const Icon(Icons.map, color: Colors.blue),
                                  tooltip: 'Open in Maps',
                                  onPressed: () => _openInMaps(job.address!),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(job.currentStatus),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              job.statusDisplayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => _handleJobAction(value, job),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'reschedule',
                            child: Text('schdule'),
                          ),
                          const PopupMenuItem(
                            value: 'update_status',
                            child: Text('Update Status'),
                          ),
                          const PopupMenuItem(
                            value: 'view_history',
                            child: Text('Status History'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'open',
                            child: Text('Open Job'),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => JobDetailsScreen(
                              job: job,
                              priceBook: priceBook,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get color for job status
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

  /// Handle job tap to view details
  Future<void> _handleJobTap(Job job) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailsScreen(
          job: job,
          priceBook: priceBook,
        ),
      ),
    );

    if (deleted == true) {
      await _loadJobs();
    }
  }

  /// Open customer address in maps
  void _openInMaps(String address) async {
    final trimmedAddress = address.trim();
    if (trimmedAddress.isEmpty) return;

    final encoded = Uri.encodeComponent(trimmedAddress);
    final googleMapsUri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    final geoUri = Uri.parse('geo:0,0?q=$encoded');

    debugPrint('Jobs screen map debug: address="$address"');
    debugPrint('Jobs screen map debug: googleMapsUri=$googleMapsUri');
    debugPrint('Jobs screen map debug: geoUri=$geoUri');

    bool launched = false;
    String failureDetails = '';

    Future<bool> _attemptLaunch(Uri uri, String label) async {
      try {
        final canLaunch = await canLaunchUrl(uri);
        debugPrint('Jobs screen map debug: canLaunchUrl($label)=$canLaunch');
        if (canLaunch) {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          debugPrint(
              'Jobs screen map debug: launchUrl($label, externalApplication) returned $launched');
          if (launched) {
            return true;
          }
        }

        debugPrint(
            'Jobs screen map debug: attempting direct launch for $label even though canLaunchUrl=$canLaunch');
        launched = await launchUrl(uri);
        debugPrint(
            'Jobs screen map debug: direct launchUrl($label) returned $launched');
        return launched;
      } catch (e, stackTrace) {
        debugPrint('Jobs screen map debug: Failed to launch $label: $e');
        debugPrint(stackTrace.toString());
        failureDetails += '$label launch error: $e\n';
        return false;
      }
    }

    launched = await _attemptLaunch(googleMapsUri, 'googleMapsUri');
    if (!launched) {
      debugPrint('Jobs screen map debug: failing over to geoUri');
      launched = await _attemptLaunch(geoUri, 'geoUri');
    }

    if (!launched) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Could not open maps. Please check the address and your device settings.'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      debugPrint(
          'Jobs screen map debug: failed to open maps. Details:\n$failureDetails');
    }
  }

  /// Handle job action menu selections
  Future<void> _handleJobAction(String action, Job job) async {
    switch (action) {
      case 'reschedule':
        await _showScheduleCalendarForJob(job);
        break;
      case 'update_status':
        _showUpdateStatusDialog(job);
        break;
      case 'view_history':
        _showStatusHistoryDialog(job);
        break;
      case 'open':
        final deleted = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => JobDetailsScreen(
              job: job,
              priceBook: priceBook,
            ),
          ),
        );
        if (deleted == true) {
          await _loadJobs();
        }
        break;
    }
  }

  /// Opens the scheduling calendar for an existing job ("Schedule" action
  /// from the Jobs list popup menu). Lets the user pick one or more days,
  /// then optionally set a time for each day, and saves the result onto
  /// the job.
  Future<void> _showScheduleCalendarForJob(Job job) async {
    final now = DateTime.now();

    // Kick off a weather lookup for the job's address (if it has one) so
    // the "Select schedule days" dialog can show a forecast per day. This
    // runs in the background - if it doesn't resolve in time, or the job
    // has no address, the dialog simply won't show weather.
    List<DailyForecast> jobSiteForecast = [];
    if (job.address != null && job.address!.trim().isNotEmpty) {
      try {
        final geocoded =
            await AddressSearchService.geocodeAddress(job.address!);
        if (geocoded?.latitude != null && geocoded?.longitude != null) {
          jobSiteForecast = await WeatherService.getSevenDayForecast(
            latitude: geocoded!.latitude!,
            longitude: geocoded.longitude!,
          );
        }
      } catch (e) {
        print('⚠️ JobsScreen: failed to fetch weather for job address: $e');
      }
      if (!mounted) return;
    }

    final pickedDates = await showMultiDatePickerDialog(
      context: context,
      initialSelectedDates: job.scheduleDates ?? const <DateTime>[],
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (pickedDates == null) return; // Cancelled - keep existing schedule.
    if (!mounted) return;

    Job updatedJob;
    if (pickedDates.isEmpty) {
      // "Flexible Day" shortcut chosen on the calendar - no fixed date or
      // time (midnight dueDate is how this app marks a flexible job, see
      // scheduling_screen.dart's _isFlexibleForDay).
      updatedJob = job.copyWith(
        dueDate: DateTime(now.year, now.month, now.day),
        scheduleDates: const [],
      );
    } else {
      // Let the user add/edit a time for each picked day, mirroring the
      // "Create & Schedule" flow used when creating a new job.
      final finalizedDates = await _showJobScheduleDaysDialog(
        pickedDates,
        siteForecast: jobSiteForecast,
      );
      if (finalizedDates == null) return; // Cancelled on the time step.

      final sorted = [...finalizedDates]..sort((a, b) => a.compareTo(b));
      updatedJob = job.copyWith(
        dueDate: sorted.first,
        scheduleDates: sorted,
      );
    }

    final index = jobs.indexWhere((existing) => existing.id == job.id);
    if (index != -1) {
      setState(() {
        jobs[index] = updatedJob;
      });
    }
    await _saveJobs();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${updatedJob.title} schedule updated.')),
      );
    }
  }

  /// Shows a "Select schedule days" dialog (mirrors the one shown when
  /// creating a job in JobDetailsDialog) so the user can add/edit a time
  /// for each picked day. Returns the finalized list of dates (with times
  /// where set) or null if the user cancels.
  ///
  /// [siteForecast], if provided, is used to show the weather for each day
  /// within the next 7 days (see WeatherService.isWithinForecastWindow).
  Future<List<DateTime>?> _showJobScheduleDaysDialog(
      List<DateTime> initialDates,
      {List<DailyForecast> siteForecast = const []}) async {
    final selectedDates = [...initialDates];
    selectedDates.sort((a, b) => a.compareTo(b));

    const dayAbbrev = ['Mon', 'Tues', 'Wed', 'Thurs', 'Fri', 'Sat', 'Sun'];

    return showDialog<List<DateTime>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select schedule days'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (selectedDates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No dates selected yet.'),
                        )
                      else
                        ...selectedDates.map((date) {
                          final dayName = dayAbbrev[date.weekday - 1];
                          final dateStr =
                              '${date.day}/${date.month}/${date.year % 100}';
                          final hasTime = date.hour != 0 || date.minute != 0;
                          final timeLabel = hasTime
                              ? TimeOfDay.fromDateTime(date).format(context)
                              : 'Add time';
                          final dayForecast =
                              WeatherService.isWithinForecastWindow(date)
                                  ? WeatherService.forecastForDate(
                                      siteForecast, date)
                                  : null;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$dayName $dateStr',
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      icon: Icon(
                                        hasTime
                                            ? Icons.access_time
                                            : Icons.add_alarm,
                                        size: 16,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                      ),
                                      onPressed: () async {
                                        final pickedTime =
                                            await showTimePicker(
                                          context: context,
                                          initialTime: hasTime
                                              ? TimeOfDay.fromDateTime(date)
                                              : const TimeOfDay(
                                                  hour: 9, minute: 0),
                                        );
                                        if (pickedTime == null) return;
                                        setDialogState(() {
                                          final index =
                                              selectedDates.indexWhere(
                                                  (existing) =>
                                                      existing.year ==
                                                          date.year &&
                                                      existing.month ==
                                                          date.month &&
                                                      existing.day ==
                                                          date.day);
                                          if (index != -1) {
                                            selectedDates[index] = DateTime(
                                              date.year,
                                              date.month,
                                              date.day,
                                              pickedTime.hour,
                                              pickedTime.minute,
                                            );
                                          }
                                        });
                                      },
                                      label: Text(timeLabel),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      splashRadius: 18,
                                      tooltip: 'Remove day',
                                      onPressed: () {
                                        setDialogState(() {
                                          selectedDates.removeWhere(
                                              (existing) =>
                                                  existing.year ==
                                                      date.year &&
                                                  existing.month ==
                                                      date.month &&
                                                  existing.day == date.day);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                if (dayForecast != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: WeatherSummaryTile(
                                      forecast: dayForecast,
                                      dense: true,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: const Text('Edit days'),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showMultiDatePickerDialog(
                              context: context,
                              initialSelectedDates: selectedDates,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 2),
                            );
                            if (picked == null) return;
                            setDialogState(() {
                              final updated = <DateTime>[];
                              for (final date in picked) {
                                final existingIndex = selectedDates.indexWhere(
                                    (existing) =>
                                        existing.year == date.year &&
                                        existing.month == date.month &&
                                        existing.day == date.day);
                                if (existingIndex != -1) {
                                  updated.add(selectedDates[existingIndex]);
                                } else {
                                  updated.add(date);
                                }
                              }
                              selectedDates
                                ..clear()
                                ..addAll(updated)
                                ..sort((a, b) => a.compareTo(b));
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedDates.isEmpty
                      ? null
                      : () => Navigator.pop(context, selectedDates),
                  child: const Text('Save Schedule'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Delete any files that belong to a job and remove local metadata files
  Future<void> _deleteJobFiles(Job job) async {
    print('🔴 _deleteJobFiles() called for job: ${job.id}');
    
    final filePaths = <String>{
      ...(job.attachments ?? []),
      ...job.estimateVersions
          .map((version) => version.filePath)
          .whereType<String>(),
      ...job.invoices.map((invoice) => invoice.filePath).whereType<String>(),
    };

    print('📋 Files to delete: ${filePaths.length}');
    
    for (final path in filePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          print('🗑️ Deleting: $path');
          await file.delete();
        }
      } catch (e) {
        print('Error deleting job file $path: $e');
      }
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final jobFile = File('${dir.path}/job_${job.id}.json');
      if (await jobFile.exists()) {
        await jobFile.delete();
      }
    } catch (e) {
      print('Error deleting local job metadata for ${job.id}: $e');
    }
  }

  /// Delete job document from cloud if authenticated
  Future<void> _deleteJobFromCloud(Job job) async {
    if (!FirestoreService.isAuthenticated) return;
    try {
      await FirestoreService.deleteJob(job.id);
    } catch (e) {
      print('Error deleting cloud job ${job.id}: $e');
    }
  }

  /// Show dialog to manually update job status
  void _showUpdateStatusDialog(Job job) {
    final statusOptions = JobStatus.values
        .where((status) => status != JobStatus.invoicePaid)
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status: ${job.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Current Status: ${job.statusDisplayName}'),
                const SizedBox(height: 16),
                const Text('Select new status:'),
                const SizedBox(height: 8),
                ...statusOptions.map((status) => RadioListTile<JobStatus>(
                      title: Text(status.displayName),
                      value: status,
                      groupValue: job.currentStatus,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            job.updateStatus(value, reason: 'Manually updated');
                          });
                          // Save locally AND sync to cloud
                          _saveJobs();
                          _syncJobToCloud(job);
                          Navigator.pop(context);
                        }
                      },
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final deleted = await _confirmDeleteJob(job);
              if (deleted) {
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Job'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDeleteJob(Job job) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (firstConfirm != true) return false;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete Job'),
        content:
            const Text('This action cannot be undone. Do you want to proceed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, delete'),
          ),
        ],
      ),
    );

    if (secondConfirm != true) return false;

    await _deleteJobFiles(job);
    await _deleteJobFromCloud(job);

    setState(() {
      jobs.removeWhere((existing) => existing.id == job.id);
    });
    await _saveJobs();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }

    return true;
  }

  /// Show status history dialog
  void _showStatusHistoryDialog(Job job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Status History - ${job.title}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: job.statusHistory.isEmpty
              ? const Center(child: Text('No status history available'))
              : ListView.builder(
                  itemCount: job.statusHistory.length,
                  itemBuilder: (context, index) {
                    final history = job.statusHistory[index];
                    return ListTile(
                      title: Text(history.status.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Date: ${history.timestamp.toString().substring(0, 16)}'),
                          if (history.reason != null)
                            Text('Reason: ${history.reason}'),
                          if (history.documentId != null)
                            Text('Document: ${history.documentId}'),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show job details dialog after customer selection
  Future<void> _showJobDetailsDialog(Customer customer) async {
    print(
        'JobsScreen: _showJobDetailsDialog called for customer ${customer.name} (${customer.email})');
    final result = await showDialog<JobDialogResult>(
      context: context,
      builder: (context) => JobDetailsDialog(
        customer: customer,
        onJobCreated: (job) async {
          await _addJob(job);
        },
      ),
    );
    print(
        'JobsScreen: _showJobDetailsDialog returned job=${result?.job.id} action=${result?.action}');
    if (result == null) return;

    var job = result.job;
    if (result.action == 'scheduleAnother') {
      // Stay on the Jobs list so the user can create/schedule another job.
      await _loadJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${job.title} scheduled. Add another job below.')),
        );
      }
      return;
    }

    if (result.action == 'reschedule') {
      // Came from the Flexible Job/Flexible Period "Confirm & Reschedule"
      // option - immediately open the scheduling calendar so the user can
      // firm up an exact date/time for this job.
      await _showScheduleCalendarForJob(job);
      final index = jobs.indexWhere((existing) => existing.id == job.id);
      if (index != -1) {
        job = jobs[index];
      }
    }

    // Default / 'continue' action: go straight to the new job's details.
    print(
        'JobsScreen: navigating to JobDetailsScreen for newly created job ${job.id}');
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailsScreen(
          job: job,
          priceBook: priceBook,
        ),
      ),
    );
    print(
        'JobsScreen: JobDetailsScreen returned deleted=$deleted for created job ${job.id}');
    if (deleted == true) {
      await _loadJobs();
    }
  }

  Future<void> _showAddJobDialog() async {
    print('JobsScreen: _showAddJobDialog called');
    await showDialog(
      context: context,
      builder: (context) => AddJobDialog(
        customers: widget.customers,
        onJobCreated: (job) async {
          print(
              'JobsScreen: AddJobDialog onJobCreated callback received job ${job.id}');
          await _addJob(job);
          await _loadJobs();
          print(
              'JobsScreen: job saved, navigating to JobDetailsScreen for ${job.id}');
          final deleted = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => JobDetailsScreen(
                job: job,
                priceBook: priceBook,
              ),
            ),
          );
          print(
              'JobsScreen: JobDetailsScreen returned deleted=$deleted for job ${job.id}');
          if (deleted == true) {
            await _loadJobs();
          }
        },
        onCustomerSelected: (customer) async {
          print(
              'JobsScreen: onCustomerSelected for ${customer.name} (${customer.email})');
          await _showJobDetailsDialog(customer);
        },
      ),
    );
    print('JobsScreen: _showAddJobDialog dialog closed');
  }
}

class AddJobDialog extends StatefulWidget {
  final List<Customer> customers;
  final void Function(Job)? onJobCreated;
  final void Function(Customer)? onCustomerSelected;

  const AddJobDialog(
      {required this.customers,
      this.onJobCreated,
      this.onCustomerSelected,
      super.key});

  @override
  State<AddJobDialog> createState() => _AddJobDialogState();
}

class _AddJobDialogState extends State<AddJobDialog> {
  String search = '';
  Customer? selectedCustomer;
  late TextEditingController searchController;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = widget.customers
        .where((c) =>
            c.name.toLowerCase().contains(search.toLowerCase()) ||
            c.address.toLowerCase().contains(search.toLowerCase()) ||
            c.email.toLowerCase().contains(search.toLowerCase()))
        .toList();

    final displayCustomers = <Customer>[];
    if (selectedCustomer != null) {
      final selectedIndex =
          filteredCustomers.indexWhere((c) => c.id == selectedCustomer!.id);
      if (selectedIndex != -1) {
        displayCustomers.add(filteredCustomers[selectedIndex]);
        displayCustomers.addAll(
            filteredCustomers.where((c) => c.id != selectedCustomer!.id));
      } else {
        displayCustomers.addAll(filteredCustomers);
      }
    } else {
      displayCustomers.addAll(filteredCustomers);
    }

    return AlertDialog(
      title: const Text('Add Job'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'Search customer',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) => setState(() => search = val),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add New Customer'),
                  onPressed: () async {
                    // Show your add customer dialog here
                    // Example:
                    final newCustomer = await showDialog<Customer>(
                      context: context,
                      builder: (context) =>
                          AddCustomerDialog(), // Dialog implemented below
                    );
                    if (newCustomer != null) {
                      setState(() {
                        widget.customers.add(newCustomer);
                        selectedCustomer = newCustomer;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_off),
                label: const Text('Create Job without Customer'),
                onPressed: () {
                  print(
                      'JobsScreen: AddJobDialog Create Job without Customer selected');
                  Navigator.pop(context);
                  if (widget.onCustomerSelected != null) {
                    widget.onCustomerSelected!(Customer(
                      id: 'no-customer-${DateTime.now().millisecondsSinceEpoch}',
                      name: '',
                      companyName: '',
                      address: '',
                      email: '',
                      phone: '',
                      paymentTerms: '7 days',
                    ));
                  }
                },
              ),
              SizedBox(
                height: 200,
                child: displayCustomers.isEmpty
                    ? const Center(child: Text('No customers found.'))
                    : ListView.builder(
                        itemCount: displayCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = displayCustomers[index];
                          final isSelected = customer == selectedCustomer;
                          return Card(
                            color: isSelected ? Colors.blue.shade50 : null,
                            child: ListTile(
                              title: Text(customer.name),
                              subtitle: Text(customer.address),
                              onTap: () {
                                print(
                                    'JobsScreen: AddJobDialog selected customer ${customer.name}');
                                setState(() => selectedCustomer =
                                    selectedCustomer?.id == customer.id
                                        ? null
                                        : customer);
                              },
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.blue)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (selectedCustomer != null)
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (widget.onCustomerSelected != null) {
                widget.onCustomerSelected!(selectedCustomer!);
              }
            },
            child: const Text('Select Customer'),
          ),
      ],
    );
  }
}

class JobDetailsEntryForm extends StatefulWidget {
  final Customer customer;
  final void Function(Job) onJobCreated;

  const JobDetailsEntryForm({
    required this.customer,
    required this.onJobCreated,
    super.key,
  });

  @override
  State<JobDetailsEntryForm> createState() => _JobDetailsEntryFormState();
}

class _JobDetailsEntryFormState extends State<JobDetailsEntryForm> {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final orderNumberController = TextEditingController();
  late TextEditingController addressController;

  /// Generate a new sequential job ID in the format J2802, J2803, ...
  Future<String> _generateShortJobId() async {
    return JobNumberService.getNextJobId();
  }

  @override
  void initState() {
    super.initState();
    addressController = TextEditingController(text: widget.customer.address);
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    orderNumberController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Job Name'),
        ),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: descriptionController,
          decoration:
              const InputDecoration(labelText: 'Job Description (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: orderNumberController,
          decoration: const InputDecoration(
            labelText: 'PO / Order Number (optional)',
            hintText: 'e.g. PO-12345',
          ),
        ),
        const SizedBox(height: 12),
        AddressSearchField(
          controller: addressController,
          labelText: 'Site Address (optional)',
          helperText: 'Optional',
          onAddressSelected: (address) {
            setState(() {
              addressController.text = address.address;
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.email, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.customer.email.isNotEmpty
                    ? widget.customer.email
                    : 'No email provided',
                style: TextStyle(
                  color: widget.customer.email.isNotEmpty
                      ? Colors.black87
                      : Colors.grey,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            // Validate required fields
            if (nameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Job name is required')),
              );
              return;
            }

            // Site address is optional now
            try {
              final newJob = Job(
                id: await _generateShortJobId(),
                title: nameController.text.trim(),
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                address: addressController.text.trim().isEmpty
                    ? null
                    : addressController.text.trim(),
                customerName: widget.customer.companyName.isNotEmpty
                    ? widget.customer.companyName
                    : widget.customer.name,
                companyName: widget.customer.companyName.isNotEmpty
                    ? widget.customer.companyName
                    : null,
                bodyCorporateNumber:
                    widget.customer.bodyCorporateNumber.isNotEmpty
                        ? widget.customer.bodyCorporateNumber
                        : null,
                customerEmail: widget.customer.email.isNotEmpty
                    ? widget.customer.email
                    : null,
                status: JobStatus.active,
                created: DateTime.now(),
                dueDate: DateTime.now().add(const Duration(days: 7)),
                jobType: 'General',
                paymentTerms: widget.customer.paymentTerms.isNotEmpty
                    ? widget.customer.paymentTerms
                    : '7 days',
                orderNumber: orderNumberController.text.trim().isEmpty
                    ? null
                    : orderNumberController.text.trim(),
              );
              widget.onJobCreated(newJob);
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to create job: $e')),
              );
              print('Error creating job: $e');
            }
          },
          child: const Text('Save Job'),
        ),
      ],
    );
  }
}

// Simple dialog for adding a new customer
class AddCustomerDialog extends StatefulWidget {
  const AddCustomerDialog({super.key});

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final nameController = TextEditingController();
  final companyNameController = TextEditingController();
  final addressController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final bodyCorporateController = TextEditingController();
  final pasteController = TextEditingController();
  final ValueNotifier<TextSelection?> selectionNotifier = ValueNotifier(null);
  TextSelection? _lastSelection;

  @override
  void initState() {
    super.initState();
    pasteController.addListener(_updateSelection);
  }

  void _updateSelection() {
    final selection = pasteController.selection;
    if (selection != _lastSelection) {
      _lastSelection = selection;
      if (selection.isValid && !selection.isCollapsed) {
        selectionNotifier.value = selection;
      } else {
        selectionNotifier.value = null;
      }
    }
  }

  Future<void> _assignSelectedText(String targetField) async {
    final selection = pasteController.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final selectedText =
        pasteController.text.substring(selection.start, selection.end).trim();
    if (selectedText.isEmpty) return;

    switch (targetField) {
      case 'company':
        companyNameController.text = selectedText;
        break;
      case 'name':
        nameController.text = selectedText;
        break;
      case 'address':
        final pickedAddress = await _pickAddressFromSelection(selectedText);
        if (pickedAddress != null && pickedAddress.isNotEmpty) {
          addressController.text = pickedAddress;
        }
        break;
      case 'email':
        emailController.text = selectedText;
        break;
      case 'phone':
        phoneController.text = selectedText;
        break;
      case 'bodyCorporate':
        bodyCorporateController.text = selectedText;
        break;
    }

    selectionNotifier.value = null;
  }

  Future<String?> _pickAddressFromSelection(String initialQuery) async {
    final addressSearchController = TextEditingController(text: initialQuery);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Address'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AddressSearchField(
                controller: addressSearchController,
                labelText: 'Address search',
                helperText:
                    'Search for the address and select it to use it here',
                isRequired: true,
                onAddressSelected: (addressResult) {
                  Navigator.of(context).pop(addressResult.address);
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context)
                      .pop(addressSearchController.text.trim());
                },
                child: const Text('Use typed text'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    companyNameController.dispose();
    addressController.dispose();
    emailController.dispose();
    phoneController.dispose();
    bodyCorporateController.dispose();
    pasteController.removeListener(_updateSelection);
    pasteController.dispose();
    selectionNotifier.dispose();
    super.dispose();
  }

  Widget _buildSelectionActions() {
    return ValueListenableBuilder<TextSelection?>(
      valueListenable: selectionNotifier,
      builder: (context, selection, _) {
        if (selection == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPasteActionButton('Company', Icons.business,
                  () => _assignSelectedText('company')),
              _buildPasteActionButton(
                  'Name', Icons.person, () => _assignSelectedText('name')),
              _buildPasteActionButton('Address', Icons.location_on,
                  () => _assignSelectedText('address')),
              _buildPasteActionButton(
                  'Email', Icons.email, () => _assignSelectedText('email')),
              _buildPasteActionButton(
                  'Phone', Icons.phone, () => _assignSelectedText('phone')),
              _buildPasteActionButton('Body Corporate', Icons.account_balance,
                  () => _assignSelectedText('bodyCorporate')),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPasteActionButton(
      String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Customer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: pasteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Paste text here',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
            _buildSelectionActions(),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: companyNameController,
              decoration: const InputDecoration(
                  labelText: 'Company Name (if applicable)'),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: bodyCorporateController,
              decoration: const InputDecoration(
                labelText: 'Body Corporate Number (optional)',
                prefixIcon: Icon(Icons.account_balance),
                border: OutlineInputBorder(),
              ),
            ),
            AddressSearchField(
              controller: addressController,
              labelText: 'Address',
              helperText: 'Start typing to search for an address',
              isRequired: true,
              onAddressSelected: (addressResult) {
                setState(() {
                  addressController.text = addressResult.address;
                });
              },
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final newCustomer = Customer(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: nameController.text,
              companyName: companyNameController.text,
              address: addressController.text,
              email: emailController.text,
              phone: phoneController.text,
              paymentTerms: '7 days',
              bodyCorporateNumber: bodyCorporateController.text.trim(),
            );
            Navigator.pop(context, newCustomer);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
