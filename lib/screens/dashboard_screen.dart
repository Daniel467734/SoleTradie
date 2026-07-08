import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/job.dart';
import '../models/customer.dart';
import '../services/storage_initializer.dart';
import '../widgets/notification_button.dart';
import 'in_progress_estimates_screen.dart';
import 'estimates_quotes_screen.dart';
import 'reports_screen.dart';
import 'jobs_screen.dart';
import 'pricebook_extensive_screen.dart';
import 'settings_screen.dart';
import 'Invoices_Screen.dart';
import 'certificates_screen.dart';
// import 'offline_data_screen.dart'; // temporarily disabled for testing
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../route_observer.dart';
import 'scheduling_screen.dart';
import 'todo_list_screen.dart';
import '../services/todo_list_service.dart';
import '../services/weather_service.dart';
import '../services/address_search_service.dart';
import '../widgets/weather_summary_tile.dart';

class DashboardScreen extends StatefulWidget {
  final List<Job> jobs;
  final List<Customer> customers;
  final List<PriceBookItem> priceBook;
  final Future<void> Function()? onRefresh;

  const DashboardScreen({
    super.key,
    required this.jobs,
    required this.customers,
    required this.priceBook,
    this.onRefresh,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  String? dailyQuote;
  String? dailyAuthor;
  bool quoteError = false;
  int toDoIncompleteCount = 0;

  // Office address weather (see WeatherService / weather_summary_tile.dart).
  List<DailyForecast> _officeForecast = [];
  bool _isLoadingWeather = false;
  bool _hasOfficeAddress = false;

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
    _refreshOnReturn();
  }

  Future<void> _refreshOnReturn() async {
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
    await fetchDailyQuote();
    await _loadToDoCount();
    await _loadOfficeWeather();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadToDoCount() async {
    final count = await ToDoListService.getIncompleteCount();
    setState(() {
      toDoIncompleteCount = count;
    });
  }

  /// Loads the 7-day forecast for the company/office address configured in
  /// Settings. If no office address is set (or it can't be geocoded), the
  /// weather card is simply hidden.
  Future<void> _loadOfficeWeather() async {
    setState(() {
      _isLoadingWeather = true;
    });

    final coords = await AddressSearchService.getCompanyCoordinates();
    if (coords == null) {
      if (mounted) {
        setState(() {
          _hasOfficeAddress = false;
          _officeForecast = [];
          _isLoadingWeather = false;
        });
      }
      return;
    }

    final forecast = await WeatherService.getSevenDayForecast(
      latitude: coords['latitude']!,
      longitude: coords['longitude']!,
    );

    if (mounted) {
      setState(() {
        _hasOfficeAddress = true;
        _officeForecast = forecast;
        _isLoadingWeather = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchDailyQuote();
    _loadToDoCount();
    _loadOfficeWeather();
    // Initialize notifications but don't show them automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.showOverdueNotifications(context, widget.jobs);
    });
  }

  Future<void> fetchDailyQuote() async {
    try {
      final response =
          await http.get(Uri.parse('https://zenquotes.io/api/today'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          dailyQuote = data[0]['q'];
          dailyAuthor = data[0]['a'];
          quoteError = false;
        });
      } else {
        setState(() {
          quoteError = true;
        });
      }
    } catch (e) {
      setState(() {
        quoteError = true;
      });
    }
  }

  void _copyCustomerFormLink(BuildContext context) {
    // Create a URL that works both locally and in production
    // For development: can use localhost or your local IP
    // For production: replace with your actual domain
    const baseUrl =
        'https://your-app-domain.com'; // Replace with your actual domain
    // Alternative for local testing: 'http://localhost:8080' or 'http://your-local-ip:8080'

    final customerFormUrl = '$baseUrl/#/customer-form';

    Clipboard.setData(ClipboardData(text: customerFormUrl));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Customer form link copied to clipboard!\nShare this link with customers to collect their details.',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = widget.jobs;
    final customers = widget.customers;
    final priceBook = widget.priceBook;

    // Sync invoice data for all jobs
    for (final job in jobs) {
      job.syncInvoices();
    }

    // Calculate outstanding amounts using the Job model's helper method
    double totalInvoiceDue =
        jobs.fold(0.0, (sum, job) => sum + job.totalOutstandingAmount);

    // --- THEME-BASED COLOUR PALETTE ---
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color primary = colorScheme.primary;
    final Color secondary = colorScheme.secondary;
    final Color pageBg = const Color(0xFFF5F6F8);
    final Color surfaceBg = Colors.white;
    final Color buttonBg = const Color(0xFFEEF0F3);
    final Color buttonText = Colors.black87;


    String formatCurrency(double value) {
      final rounded = value.toStringAsFixed(2);
      final parts = rounded.split('.');
      final integerPart = parts[0];
      final decimals = parts[1];
      final formattedInteger = integerPart.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ',',
      );
      return '\$$formattedInteger.$decimals';
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: true,
        backgroundColor: primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload app',
            onPressed: () async {
              if (widget.onRefresh != null) {
                await widget.onRefresh!();
              }
              await fetchDailyQuote();
              await _loadOfficeWeather();
              if (mounted) {
                setState(() {});
              }
            },
          ),
          NotificationButton(jobs: jobs),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Copy Customer Form Link',
            onPressed: () {
              _copyCustomerFormLink(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () async {
              // Show a loading indicator while refreshing
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    Center(child: CircularProgressIndicator()),
              );

              // Call the optional onRefresh callback if provided
              await widget.onRefresh?.call();

              // Hide the loading indicator
              Navigator.of(context).pop();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          Text(
            'Welcome back!',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Your business at a glance.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: secondary,
                ),
          ),
          const SizedBox(height: 10),
          if (_isLoadingWeather)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_hasOfficeAddress && _officeForecast.isNotEmpty) ...[
            WeatherSummaryTile(
              label: 'Weather at the office - today',
              forecast: _officeForecast.first,
            ),
            const SizedBox(height: 10),
          ],
          Card(
            color: surfaceBg,
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Invoice Amount',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Icon(Icons.trending_up, color: secondary, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatCurrency(totalInvoiceDue),
                    style: TextStyle(
                      fontSize: 24,
                      color: secondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // --- BUTTONS: three across rows ---
          Row(
            children: [
              Expanded(
                child: _DashboardButton(
                  icon: Icons.list_alt,
                  label: 'Jobs',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => JobsScreen(
                          customers: customers,
                          onAdd: (customer) {},
                          onUpdate: (customer) {},
                          onRemove: (customerId) {},
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.schedule,
                  label: 'Scheduling',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SchedulingScreen(
                          jobs: jobs,
                          customers: customers,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.receipt_long,
                  label: 'Invoices',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () async {
                    await _openInvoicesScreen(context, jobs, priceBook);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DashboardButton(
                  icon: Icons.build_circle,
                  label: 'In Progress',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InProgressEstimatesScreen(jobs: jobs),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.description,
                  label: 'Estimates/Quotes',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EstimatesQuotesScreen(
                          jobs: jobs,
                          priceBook: priceBook,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.verified,
                  label: 'Certificates',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CertificatesScreen(
                          jobs: jobs,
                          customers: customers,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DashboardButton(
                  icon: Icons.people,
                  label: 'Customers',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () async {
                    await Navigator.pushNamed(context, '/customers');
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.book,
                  label: 'Pricebook',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () async {
                    await Navigator.pushNamed(context, '/pricebook');
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.bar_chart,
                  label: 'Reports',
                  color: buttonBg,
                  textColor: buttonText,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportsScreen(jobs: jobs),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // --- To-Do List and Settings Row ---
          Row(
            children: [
              Expanded(
                child: _DashboardButton(
                  icon: Icons.checklist,
                  label: 'To-Do List',
                  color: buttonBg,
                  textColor: buttonText,
                  badgeCount: toDoIncompleteCount,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ToDoListScreen(),
                      ),
                    );
                    await _loadToDoCount();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardButton(
                  icon: Icons.settings,
                  label: 'Settings',
                  color: buttonBg,
                  textColor: buttonText,
                  showStatusDot: false,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // --- Storage Status Card ---
          StorageInitializer.buildStorageStatusCard(),

          const SizedBox(height: 12),

          // --- Daily Motivation Quote at the bottom ---
          Card(
            color: surfaceBg,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.format_quote, color: secondary, size: 24),
                      const SizedBox(width: 8),
                      Text('Daily Motivation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: primary,
                          )),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (quoteError)
                    Text('Could not load quote today.',
                        style: TextStyle(color: colorScheme.error)),
                  if (!quoteError && dailyQuote == null)
                    const Center(child: CircularProgressIndicator()),
                  if (!quoteError && dailyQuote != null)
                    Text(
                      '"$dailyQuote"',
                      style: TextStyle(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: secondary,
                      ),
                    ),
                  if (!quoteError && dailyAuthor != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('- $dailyAuthor',
                          style: TextStyle(fontSize: 13, color: secondary)),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// --- Unified, modern dashboard button ---
class _DashboardButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final bool showStatusDot;
  final int badgeCount;

  const _DashboardButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.showStatusDot = true,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.secondary;
    return Stack(
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(72),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            backgroundColor: color,
            side: BorderSide(color: color.withOpacity(0.2)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        if (showStatusDot)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        if (badgeCount > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Estimates/Quotes List Modal
Future<void> _openInvoicesScreen(BuildContext context, List<Job> allJobs,
    List<PriceBookItem> priceBook) async {
  final allInvoices = <Map<String, Object?>>[];

  for (final job in allJobs) {
    // Add invoice versions only when there is no matching Invoice object already present.
    for (final version in job.invoiceVersions) {
      final versionId = version.id ?? version.invoiceNumber;
      final hasMatchingInvoice = versionId != null &&
          job.invoices.any((invoice) {
            return invoice.id == versionId ||
                invoice.id == version.invoiceNumber;
          });
      if (!hasMatchingInvoice) {
        allInvoices.add({'job': job, 'estimateVersion': version});
      }
    }
  }

  for (final job in allJobs) {
    for (final invoice in job.invoices) {
      allInvoices.add({'job': job, 'invoice': invoice});
    }
  }

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          InvoicesScreen(invoices: allInvoices, priceBook: priceBook),
    ),
  );
}
