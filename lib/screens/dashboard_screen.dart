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
import 'pricebook_screen.dart';
import 'settings_screen.dart';
import 'Invoices_Screen.dart';
import 'bank_feed_screen.dart';
import 'certificates_screen.dart';
// import 'offline_data_screen.dart'; // temporarily disabled for testing
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  final List<Job> jobs;
  final List<Customer> customers;
  final List<PriceBookItem> priceBook;

  const DashboardScreen({
    super.key,
    required this.jobs,
    required this.customers,
    required this.priceBook,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? dailyQuote;
  String? dailyAuthor;
  bool quoteError = false;

  @override
  void initState() {
    super.initState();
    fetchDailyQuote();
    // Initialize notifications but don't show them automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.showOverdueNotifications(context, widget.jobs);
    });
  }

  Future<void> fetchDailyQuote() async {
    try {
      final response = await http.get(Uri.parse('https://zenquotes.io/api/today'));
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
    const baseUrl = 'https://your-app-domain.com'; // Replace with your actual domain
    // Alternative for local testing: 'http://localhost:8080' or 'http://your-local-ip:8080'
    
    final customerFormUrl = '$baseUrl/#/customer-form';
    
    Clipboard.setData(ClipboardData(text: customerFormUrl));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Customer form link copied to clipboard!\nShare this link with customers to collect their details.',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
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
    double totalInvoiceDue = jobs.fold(0.0, (sum, job) => sum + job.totalOutstandingAmount);

    // --- THEME-BASED COLOUR PALETTE ---
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color primary = colorScheme.primary;
    final Color secondary = colorScheme.secondary;
    final Color cardBg = colorScheme.surface;
    final Color buttonBg = colorScheme.primaryContainer;
    final Color buttonText = colorScheme.onPrimaryContainer;
    final Color divider = colorScheme.outline.withOpacity(0.2);

    return Scaffold(
      backgroundColor: cardBg,
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: true,
        backgroundColor: primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          NotificationButton(jobs: jobs),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Copy Customer Form Link',
            onPressed: () {
              _copyCustomerFormLink(context);
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Text(
            'Welcome back!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your business at a glance.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: secondary,
                ),
          ),
          const SizedBox(height: 24),
          Card(
            color: cardBg,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Total Invoice Amount Due',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '\$${totalInvoiceDue.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 24,
                        color: primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Divider(height: 1, thickness: 1, color: divider),
          const SizedBox(height: 18),

          // --- BUTTONS: Unified, calm, professional ---
          _DashboardButton(
            icon: Icons.list_alt,
            label: 'Jobs',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
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
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
            icon: Icons.build_circle,
            label: 'In Progress',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InProgressEstimatesScreen(jobs: jobs),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
            icon: Icons.receipt_long,
            label: 'Invoices',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              _openInvoicesScreen(context, jobs, priceBook);
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
            icon: Icons.description,
            label: 'Estimates/Quotes',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EstimatesQuotesScreen(
                    jobs: jobs,
                    priceBook: priceBook,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
            icon: Icons.people,
            label: 'Customers',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.pushNamed(context, '/customers');
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
            icon: Icons.book,
            label: 'Pricebook',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PriceBookScreen(priceBook: priceBook),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
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
          const SizedBox(height: 12),
          // Temporarily disabled offline data button for testing
          /*
          _DashboardButton(
            icon: Icons.cloud_sync,
            label: 'Offline Data',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OfflineDataScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          */
          _DashboardButton(
            icon: Icons.account_balance,
            label: 'Bank Feed Import',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BankFeedScreen(
                    jobs: jobs,
                    onTransactionsImported: (transactions) {
                      // Handle imported transactions
                      // You can store them or process them as needed
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _DashboardButton(
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
          const SizedBox(height: 12),
          // --- Add this for Settings ---
          _DashboardButton(
            icon: Icons.settings,
            label: 'Settings',
            color: buttonBg,
            textColor: buttonText,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 32),

          // --- Storage Status Card ---
          StorageInitializer.buildStorageStatusCard(),

          const SizedBox(height: 16),

          // --- Daily Motivation Quote at the bottom ---
          Card(
            color: cardBg,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  const _DashboardButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: textColor),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: color,
          side: BorderSide(color: color.withOpacity(0.2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: onTap,
      ),
    );
  }
}

// Estimates/Quotes List Modal
void _openInvoicesScreen(BuildContext context, List<Job> allJobs, List<PriceBookItem> priceBook) {
  final allInvoices = <Map<String, Object?>>[];
  
  // Add invoices from EstimateVersions
  for (final job in allJobs) {
    for (final version in job.estimateVersions) {
      if (version.type == 'invoice') {
        allInvoices.add({'job': job, 'estimateVersion': version});
      }
    }
  }
  
  // Add invoices from Invoice objects
  for (final job in allJobs) {
    for (final invoice in job.invoices) {
      allInvoices.add({'job': job, 'invoice': invoice});
    }
  }
  
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => InvoicesScreen(invoices: allInvoices, priceBook: priceBook),
    ),
  );
}