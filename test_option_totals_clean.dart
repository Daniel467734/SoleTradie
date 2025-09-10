import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lib/screens/estimate_builder_screen.dart';
import 'lib/models/job.dart' as job_model;
import 'lib/models/estimate_item.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clean Option Totals Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Set up company information
    await prefs.setString('company_name', 'Clean Totals Demo Ltd');
    await prefs.setString('company_address', '123 Demo Street, Demo City');
    await prefs.setString('gst_number', '123-456-789');
    await prefs.setBool('is_gst_registered', true);
    
    print('Settings initialized for clean option totals demo');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Clean Option Totals Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Demo: Clean Option Section Totals',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 20),
            Text(
              'This demo shows option section totals without yellow boxes',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _openEstimateBuilder(),
              child: Text('Open Estimate Builder'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _toggleGstRegistration(),
              child: Text('Toggle GST Registration'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEstimateBuilder() async {
    // Create a demo job
    final job = job_model.Job(
      id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      title: 'Clean Totals Demo Job',
      customerName: 'Clean Totals Customer',
      address: '789 Option Street, Clean City',
      description: 'Demo job for clean option totals',
      status: job_model.JobStatus.active,
      created: DateTime.now(),
    );

    // Create demo items for main and option sections
    final demoItems = [
      // Main section items
      EstimateItem(
        name: 'Standard Cable',
        description: '1001',
        unitPrice: 150.0,
        quantity: 3,
        purchasePrice: 100.0,
        section: 'Main Work',
      ),
      EstimateItem(
        name: 'Installation Labour',
        description: 'LAB1',
        unitPrice: 80.0,
        quantity: 4,
        purchasePrice: 0.0,
        section: 'Main Work',
      ),
      
      // Option section items
      EstimateItem(
        name: 'Premium Cable Upgrade',
        description: '2001',
        unitPrice: 250.0,
        quantity: 2,
        purchasePrice: 180.0,
        section: 'Upgrade Options',
      ),
      EstimateItem(
        name: 'Smart Switch Installation',
        description: '3001',
        unitPrice: 120.0,
        quantity: 5,
        purchasePrice: 75.0,
        section: 'Upgrade Options',
      ),
      EstimateItem(
        name: 'Additional Outlet',
        description: '4001',
        unitPrice: 90.0,
        quantity: 3,
        purchasePrice: 50.0,
        section: 'Extra Features',
      ),
    ];

    final demoSubsections = [
      'Main Work',
      '---OPTIONS---',
      'Upgrade Options',
      'Extra Features',
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EstimateBuilderScreen(
          job: job,
          initialItems: demoItems,
          initialSubsections: demoSubsections,
        ),
      ),
    );
  }

  Future<void> _toggleGstRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    final isGstRegistered = prefs.getBool('is_gst_registered') ?? true;
    await prefs.setBool('is_gst_registered', !isGstRegistered);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isGstRegistered 
            ? 'GST Registration: DISABLED (totals will show without GST)' 
            : 'GST Registration: ENABLED (totals will show with GST)'
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
