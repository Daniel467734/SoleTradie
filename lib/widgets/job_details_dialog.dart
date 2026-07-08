import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/job.dart' as job_model;
import '../services/firestore_service.dart';
import '../services/job_number_service.dart';
import '../services/weather_service.dart';
import '../services/address_search_service.dart';
import '../widgets/address_search_field.dart';
import '../widgets/multi_date_picker_dialog.dart';
import '../widgets/weather_summary_tile.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

/// Result returned by [JobDetailsDialog] when a job is created.
///
/// [action] indicates what the caller should do next:
///   - 'scheduleAnother' : creator wants to return to the Jobs list and
///                          create/schedule another job.
///   - 'continue'        : creator wants to continue straight into the
///                          newly created job's details screen.
class JobDialogResult {
  final job_model.Job job;
  final String action;

  const JobDialogResult({required this.job, required this.action});
}

/// Result returned by the "Select schedule days" confirmation dialog.
///
/// [action] is one of:
///   - 'scheduleAnother' : create the job then return to the jobs list so
///                          the user can add/schedule another job.
///   - 'continue'        : create the job then continue straight into its
///                          details screen.
class _ScheduleConfirmResult {
  final List<DateTime> dates;
  final String action;

  const _ScheduleConfirmResult({required this.dates, required this.action});
}

class JobDetailsDialog extends StatefulWidget {
  final Customer customer;
  final Future<void> Function(job_model.Job) onJobCreated;
  final List<DateTime>? initialScheduleDates;

  const JobDetailsDialog({
    super.key,
    required this.customer,
    required this.onJobCreated,
    this.initialScheduleDates,
  });

  @override
  _JobDetailsDialogState createState() => _JobDetailsDialogState();
}

class _JobDetailsDialogState extends State<JobDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _jobNameController = TextEditingController();
  final TextEditingController _jobDescriptionController =
      TextEditingController();
  final TextEditingController _siteAddressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _orderNumberController = TextEditingController();

  bool _isCreating = false;
  final List<DateTime> _scheduleDates = [];

  // Weather for the job site address (see WeatherService). Populated once
  // an address is selected via AddressSearchField's autocomplete, so the
  // "Select schedule days" calendar can show the forecast for each picked
  // day (only days within the next 7 days have data - see
  // WeatherService.isWithinForecastWindow).
  List<DailyForecast> _siteWeatherForecast = [];
  bool _isLoadingSiteWeather = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with customer information
    _siteAddressController.text = widget.customer.address;
    _emailController.text = widget.customer.email;
    if (widget.initialScheduleDates != null) {
      _scheduleDates.addAll(widget.initialScheduleDates!);
      _scheduleDates.sort((a, b) => a.compareTo(b));
    }
    // If a customer address was pre-filled, try to fetch weather for it too.
    if (_siteAddressController.text.trim().isNotEmpty) {
      _fetchWeatherForAddress(_siteAddressController.text.trim());
    }
  }

  @override
  void dispose() {
    _jobNameController.dispose();
    _jobDescriptionController.dispose();
    _siteAddressController.dispose();
    _emailController.dispose();
    _orderNumberController.dispose();
    super.dispose();
  }

  /// Geocodes [address] and fetches its 7-day forecast, storing the result
  /// in [_siteWeatherForecast]. Silently does nothing if the address can't
  /// be geocoded (no coordinates found) - the calendar/schedule dialog
  /// simply won't show weather in that case.
  Future<void> _fetchWeatherForAddress(String address) async {
    if (address.trim().isEmpty) {
      setState(() {
        _siteWeatherForecast = [];
      });
      return;
    }

    setState(() {
      _isLoadingSiteWeather = true;
    });

    try {
      final geocoded = await AddressSearchService.geocodeAddress(address);
      if (geocoded?.latitude == null || geocoded?.longitude == null) {
        if (mounted) {
          setState(() {
            _siteWeatherForecast = [];
            _isLoadingSiteWeather = false;
          });
        }
        return;
      }

      final forecast = await WeatherService.getSevenDayForecast(
        latitude: geocoded!.latitude!,
        longitude: geocoded.longitude!,
      );

      if (mounted) {
        setState(() {
          _siteWeatherForecast = forecast;
          _isLoadingSiteWeather = false;
        });
      }
    } catch (e) {
      print('⚠️ JobDetailsDialog: failed to fetch site weather: $e');
      if (mounted) {
        setState(() {
          _siteWeatherForecast = [];
          _isLoadingSiteWeather = false;
        });
      }
    }
  }

  Future<void> _createJob({String? action, bool flexibleNoDate = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
    });

    try {
      print(
          'JobDetailsDialog: creating job for customer ${widget.customer.name} (${widget.customer.email})');
      final now = DateTime.now();
      final selectedDueDate = _scheduleDates.isNotEmpty
          ? _scheduleDates.first
          : flexibleNoDate
              // Midnight (no time-of-day) on today is how this app marks a
              // job as "flexible" for today (see scheduling_screen.dart's
              // _isFlexibleForDay), with no specific time attached.
              ? DateTime(now.year, now.month, now.day)
              : now.add(const Duration(days: 7));

      final newJob = job_model.Job(
        id: await JobNumberService.getNextJobId(),
        title: _jobNameController.text.trim(),
        description: _jobDescriptionController.text.trim(),
        customerName: widget.customer.name,
        address: _siteAddressController.text.trim().isEmpty
            ? null
            : _siteAddressController.text.trim(),
        orderNumber: _orderNumberController.text.trim().isNotEmpty
            ? _orderNumberController.text.trim()
            : null,
        customerEmail: _emailController.text.trim(),
        status: job_model.JobStatus.active,
        created: now,
        dueDate: selectedDueDate,
        scheduleDates: _scheduleDates.isNotEmpty ? _scheduleDates : null,
        jobType: 'Estimate',
      );
      print(
          'JobDetailsDialog: created job object ${newJob.id} title="${newJob.title}"');

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
      print(
          'JobDetailsDialog: saving ${jobs.length} jobs to local file ${jobsFile.path}');
      await jobsFile.writeAsString(jsonEncode(jsonList));
      print('JobDetailsDialog: local save complete');

      // Save to cloud in the background so the dialog does not wait on remote persistence.
      print(
          'JobDetailsDialog: starting background cloud save for ${newJob.id}');
      FirestoreService.saveJob(newJob).then((_) {
        print('✅ JobDetailsDialog: job synced to cloud');
      }).catchError((e) {
        print('❌ JobDetailsDialog: error syncing job to cloud: $e');
      });

      print('JobDetailsDialog: calling widget.onJobCreated for ${newJob.id}');
      await widget.onJobCreated(newJob);
      print('JobDetailsDialog: widget.onJobCreated completed for ${newJob.id}');
      if (mounted) {
        print(
            'JobDetailsDialog: popping dialog with job ${newJob.id} using rootNavigator (action=$action)');
        Navigator.of(context, rootNavigator: true).pop(
          JobDialogResult(job: newJob, action: action ?? 'continue'),
        );
      }
    } catch (e) {
      print('JobDetailsDialog: failed to create job with error: $e');
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

  /// Shows the "Select schedule days" confirmation dialog listing each
  /// previously-picked date on its own row, e.g.:
  ///   Tues 7/7/26   [Add time]
  ///   Wed  8/7/26   [9:30 AM]   <- once a time is set, the button itself
  ///                                shows the time and stays clickable to edit.
  /// Returns a [_ScheduleConfirmResult] (dates + chosen action) or null if
  /// the user cancels.
  Future<_ScheduleConfirmResult?> _showScheduleDaysWithTimesDialog(
      List<DateTime> initialDates) async {
    final selectedDates = [...initialDates];
    selectedDates.sort((a, b) => a.compareTo(b));

    const dayAbbrev = [
      'Mon',
      'Tues',
      'Wed',
      'Thurs',
      'Fri',
      'Sat',
      'Sun',
    ];

    return showDialog<_ScheduleConfirmResult>(
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
                          // Only show weather for days within the next 7
                          // days AND when we have a site address forecast.
                          final dayForecast =
                              WeatherService.isWithinForecastWindow(date)
                                  ? WeatherService.forecastForDate(
                                      _siteWeatherForecast, date)
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
                                    // Tapping this button opens the time
                                    // picker. Once a time is set, the button
                                    // itself shows the chosen time (still
                                    // clickable to edit).
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
                                // Weather for this day, only shown when the
                                // date is within the next 7 days AND a site
                                // address forecast is available.
                                if (_isLoadingSiteWeather)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 6),
                                    child: SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                else if (dayForecast != null)
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
                              // Preserve times for dates that remain selected,
                              // add new dates fresh, drop de-selected ones.
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
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: selectedDates.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _ScheduleConfirmResult(
                            dates: selectedDates,
                            action: 'scheduleAnother',
                          )),
                  child: const Text('Confirm & Schedule Another'),
                ),
                ElevatedButton(
                  onPressed: selectedDates.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _ScheduleConfirmResult(
                            dates: selectedDates,
                            action: 'continue',
                          )),
                  child: const Text('Confirm & Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Reduced confirmation dialog used by the "Flexible Job" and "Flexible
  /// Period" flows. Unlike [_showScheduleDaysWithTimesDialog] there is NO
  /// per-day time editing here - just Cancel / Confirm & Reschedule /
  /// Confirm & Continue.
  ///
  /// Returns the chosen action string ('reschedule' | 'continue') or null
  /// if the user cancels.
  Future<String?> _showFlexibleConfirmDialog({required String message}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Flexible Scheduling'),
          content: Text(message),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'reschedule'),
              child: const Text('Confirm & Reschedule'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'continue'),
              child: const Text('Confirm & Continue'),
            ),
          ],
        );
      },
    );
  }

  /// "Flexible Job" - no calendar at all. The job is created with no fixed
  /// time (marked flexible for today, see [_createJob]'s `flexibleNoDate`)
  /// so it shows up in the Scheduling screen's "Flexible" list. There is no
  /// time-editing step - just a simple confirm.
  Future<void> _handleFlexibleJob() async {
    if (!_formKey.currentState!.validate()) return;

    final action = await _showFlexibleConfirmDialog(
      message: 'This job will be added to the flexible list in Scheduling '
          '(no fixed date or time). You can set an exact date/time for it '
          'anytime from the Jobs list.',
    );
    if (action == null) return;
    if (!mounted) return;

    setState(() {
      _scheduleDates.clear();
    });
    await _createJob(action: action, flexibleNoDate: true);
  }

  /// "Flexible Period" - opens the calendar so the user can pick one or more
  /// candidate/tentative dates (e.g. 3rd, 7th and 27th) to indicate the job
  /// might happen on those days. No per-day time editing - just a simple
  /// confirm afterwards.
  Future<void> _handleFlexiblePeriod() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final picked = await showMultiDatePickerDialog(
      context: context,
      initialSelectedDates: _scheduleDates,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return; // Cancelled - stay on the form.
    if (!mounted) return;

    final action = await _showFlexibleConfirmDialog(
      message: picked.isEmpty
          ? 'This job will be added to the flexible list in Scheduling '
              '(no fixed date or time).'
          : 'This job will be marked flexible on ${picked.length} candidate '
              'date${picked.length == 1 ? '' : 's'}. You can firm up an '
              'exact time anytime from the Jobs list.',
    );
    if (action == null) return;
    if (!mounted) return;

    setState(() {
      _scheduleDates
        ..clear()
        ..addAll(picked);
      _scheduleDates.sort((a, b) => a.compareTo(b));
    });
    await _createJob(action: action, flexibleNoDate: picked.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer.name.isNotEmpty
          ? 'Create Job for ${widget.customer.name}'
          : 'Create Job'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  textCapitalization: TextCapitalization.sentences,
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
                  textCapitalization: TextCapitalization.sentences,
                  controller: _jobDescriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Job Description',
                    hintText: 'Describe the work to be done',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _orderNumberController,
                  decoration: const InputDecoration(
                    labelText: 'PO / Order Number (optional)',
                    hintText: 'e.g. PO-12345',
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final orderNumberRegex = RegExp(r'^[a-zA-Z0-9/-]+$');
                      if (!orderNumberRegex.hasMatch(value)) {
                        return 'Please enter a valid PO or order number';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AddressSearchField(
                  controller: _siteAddressController,
                  labelText: 'Site Address (optional)',
                  helperText: 'Start typing to search for addresses',
                  onAddressSelected: (addressResult) {
                    // Address selected from search results
                    print(
                        'Selected job site address: ${addressResult.address}');
                    print(
                        'Coordinates: ${addressResult.latitude}, ${addressResult.longitude}');
                    // Kick off the 7-day forecast fetch for this address so
                    // the scheduling calendar can show weather per day.
                    if (addressResult.latitude != null &&
                        addressResult.longitude != null) {
                      setState(() {
                        _isLoadingSiteWeather = true;
                      });
                      WeatherService.getSevenDayForecast(
                        latitude: addressResult.latitude!,
                        longitude: addressResult.longitude!,
                      ).then((forecast) {
                        if (mounted) {
                          setState(() {
                            _siteWeatherForecast = forecast;
                            _isLoadingSiteWeather = false;
                          });
                        }
                      });
                    } else {
                      setState(() {
                        _siteWeatherForecast = [];
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter customer email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final emailRegex =
                          RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value)) {
                        return 'Please enter a valid email address';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'You can schedule this job after entering details using Create & Schedule.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                // "Above the calendar" flexible-scheduling shortcuts:
                //  - Flexible Job: no date/time at all, just added to the
                //    flexible list in Scheduling.
                //  - Flexible Period: pick one or more tentative/candidate
                //    dates (e.g. 3rd, 7th, 27th) without committing to times.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isCreating ? null : _handleFlexibleJob,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text('Flexible Job'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isCreating ? null : _handleFlexiblePeriod,
                        icon: const Icon(Icons.event_repeat, size: 18),
                        label: const Text('Flexible Period'),
                      ),
                    ),
                  ],
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
        OutlinedButton(
          onPressed: _isCreating ? null : _createJob,
          child: const Text('Create'),
        ),
        ElevatedButton(
          onPressed: _isCreating
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;

                  // Step 1: Go STRAIGHT to the calendar to pick days.
                  // (No intermediate "Select schedule days" dialog first.)
                  final now = DateTime.now();
                  final pickedDates = await showMultiDatePickerDialog(
                    context: context,
                    initialSelectedDates: _scheduleDates,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (pickedDates == null || pickedDates.isEmpty) {
                    // User cancelled the calendar - stay on the form.
                    return;
                  }
                  if (!mounted) return;

                  // Step 2: NOW show "Select schedule days" listing the
                  // picked dates, each with a clickable time button, plus
                  // the "Cancel / Schedule Another / Continue" choices.
                  final confirmResult =
                      await _showScheduleDaysWithTimesDialog(pickedDates);
                  if (confirmResult == null || confirmResult.dates.isEmpty) {
                    // User cancelled the confirmation dialog - stay on the form.
                    return;
                  }

                  setState(() {
                    _scheduleDates
                      ..clear()
                      ..addAll(confirmResult.dates);
                    _scheduleDates.sort((a, b) => a.compareTo(b));
                  });
                  await _createJob(action: confirmResult.action);
                },
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create & Schedule'),
        ),
      ],
    );
  }
}
