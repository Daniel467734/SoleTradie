// ============================================================================
// DEMO MODE — fully in-memory sandbox layer.
//
// When DemoModeService.isDemoMode is true, screens/services should read and
// write through this service instead of the real repositories/Firestore/
// SharedPreferences-backed storage. Nothing in here ever touches the real
// database, disk-persisted job files, or any network/API call. All state
// lives in memory for the lifetime of the app process, EXCEPT the on/off
// flag itself and a lightweight JSON snapshot of the demo data, which are
// persisted to SharedPreferences under demo-only keys so that closing and
// reopening the app while still "in demo mode" doesn't lose the demo data
// the user built up (customers searched for, jobs created, invoices made,
// etc.) — exactly like a real backend would, just entirely sandboxed.
//
// Turning demo mode OFF (or hitting "Wipe Demo Data" in Settings) discards
// all of it and the app reverts to talking to the real repositories again.
// ============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/job.dart';
import '../models/invoice.dart';
import '../models/estimate_version.dart';
import '../models/todo_item.dart';
import '../models/estimate_item.dart' hide Job;

/// Simple in-memory pricebook line for demo mode. Deliberately not the real
/// (Isar-backed) `PriceBookItem` model, since demo items must never touch
/// the real Isar database.
class DemoPriceBookItem {
  final String id;
  final String code;
  final String name;
  final String category; // 'Main Materials' | 'Specialized Equipment'
  final double purchasePrice;
  final double salePrice;
  final String unit;
  final String? barcode;

  DemoPriceBookItem({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.purchasePrice,
    required this.salePrice,
    required this.unit,
    this.barcode,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'category': category,
        'purchasePrice': purchasePrice,
        'salePrice': salePrice,
        'unit': unit,
        'barcode': barcode,
      };

  factory DemoPriceBookItem.fromJson(Map<String, dynamic> json) =>
      DemoPriceBookItem(
        id: json['id'],
        code: json['code'],
        name: json['name'],
        category: json['category'],
        purchasePrice: (json['purchasePrice'] ?? 0).toDouble(),
        salePrice: (json['salePrice'] ?? 0).toDouble(),
        unit: json['unit'] ?? 'each',
        barcode: json['barcode'],
      );
}

/// A demo schedule entry - either a fixed appointment or a "flexible" job
/// floating in the unscheduled pipeline.
class DemoScheduleEntry {
  final String id;
  final String jobId;
  final String title;
  final DateTime? scheduledAt; // null => flexible/unscheduled
  final bool isFlexible;

  DemoScheduleEntry({
    required this.id,
    required this.jobId,
    required this.title,
    this.scheduledAt,
    required this.isFlexible,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'title': title,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'isFlexible': isFlexible,
      };

  factory DemoScheduleEntry.fromJson(Map<String, dynamic> json) =>
      DemoScheduleEntry(
        id: json['id'],
        jobId: json['jobId'],
        title: json['title'],
        scheduledAt: json['scheduledAt'] != null
            ? DateTime.tryParse(json['scheduledAt'])
            : null,
        isFlexible: json['isFlexible'] ?? false,
      );
}

/// A demo file-library template document (never a real file on disk - just
/// a named placeholder that opens a mock preview).
class DemoFileLibraryItem {
  final String id;
  final String name;
  final String category;

  DemoFileLibraryItem(
      {required this.id, required this.name, required this.category});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'category': category};

  factory DemoFileLibraryItem.fromJson(Map<String, dynamic> json) =>
      DemoFileLibraryItem(
        id: json['id'],
        name: json['name'],
        category: json['category'],
      );
}

/// Central singleton controlling Demo Mode: the on/off flag, and the entire
/// in-memory (but demo-session-persisted) sandbox data set. All screens and
/// repositories that want demo-aware behaviour should check
/// `DemoModeService.instance.isDemoMode` and, if true, read/write through
/// the methods below instead of the real services.
class DemoModeService {
  DemoModeService._internal();
  static final DemoModeService instance = DemoModeService._internal();

  static const _prefsFlagKey = 'demo_mode_enabled';
  static const _prefsSnapshotKey = 'demo_mode_snapshot_v1';

  bool _isDemoMode = false;
  bool get isDemoMode => _isDemoMode;

  final Random _random = Random();

  // ---- In-memory sandbox state ----
  final List<Customer> customers = [];
  final List<Job> jobs = [];
  final List<DemoPriceBookItem> priceBook = [];
  final Map<String, DemoPriceBookItem> _barcodeCache = {}; // barcode -> item
  final List<DemoScheduleEntry> schedule = [];
  final List<ToDoItem> todos = [];
  final List<DemoFileLibraryItem> fileLibrary = [];

  /// Mock company profile shown throughout the app while in demo mode.
  Map<String, String> companyProfile = {
    'companyName': 'Mock Trades Ltd',
    'gstNumber': '123-456-789',
    'logoPath': '', // empty => UI should show a placeholder logo icon
    'email': 'hello@mocktrades.example.com',
    'phone': '021 555 0100',
    'address': '42 Demo Street, Auckland 1010',
  };

  /// Call once at app startup (after SharedPreferences is available) to
  /// restore whether demo mode was left on, and reload any previously
  /// built-up demo data so it doesn't vanish between app launches while
  /// still "in" demo mode.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isDemoMode = prefs.getBool(_prefsFlagKey) ?? false;
    if (_isDemoMode) {
      final snapshot = prefs.getString(_prefsSnapshotKey);
      if (snapshot != null) {
        _restoreSnapshot(snapshot);
      } else {
        _seedDemoData();
      }
    }
  }

  /// Turn Demo Mode on. Seeds fresh demo data if there's no existing demo
  /// session to restore.
  Future<void> enableDemoMode() async {
    _isDemoMode = true;
    if (customers.isEmpty && jobs.isEmpty) {
      _seedDemoData();
    }
    await _persistFlag();
    await _persistSnapshot();
  }

  /// Turn Demo Mode off. The in-memory sandbox data is left intact (in case
  /// the user turns it back on later this session) but the app will resume
  /// talking to the real repositories. Use [wipeDemoData] to actually clear
  /// the sandbox.
  Future<void> disableDemoMode() async {
    _isDemoMode = false;
    await _persistFlag();
  }

  /// Wipes ALL demo data (customers, jobs, pricebook items generated on the
  /// fly, schedule, to-dos, files) and reseeds a clean starter demo set.
  /// Exposed as "Wipe Demo Data" in Settings.
  Future<void> wipeDemoData() async {
    customers.clear();
    jobs.clear();
    priceBook.clear();
    _barcodeCache.clear();
    schedule.clear();
    todos.clear();
    fileLibrary.clear();
    _seedDemoData();
    await _persistSnapshot();
  }

  Future<void> _persistFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsFlagKey, _isDemoMode);
  }

  /// Call after any mutation (new job, new invoice, magic customer, etc.)
  /// that should survive an app restart while still in demo mode.
  /// Public wrapper so screens (e.g. JobDetailsScreen's `_saveJob`) can
  /// persist the current in-memory demo sandbox state after mutating a
  /// demo `Job`/`Invoice`/`EstimateVersion` object in place, without
  /// needing access to the private snapshot internals.
  Future<void> persistCurrentSnapshot() => _persistSnapshot();

  Future<void> _persistSnapshot() async {
    final snapshot = jsonEncode({
      'customers': customers
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'companyName': c.companyName,
                'address': c.address,
                'email': c.email,
                'phone': c.phone,
              })
          .toList(),
      'jobs': jobs.map((j) => j.toJson()).toList(),
      'priceBook': priceBook.map((p) => p.toJson()).toList(),
      'barcodeCache':
          _barcodeCache.map((k, v) => MapEntry(k, v.toJson())),
      'schedule': schedule.map((s) => s.toJson()).toList(),
      'todos': todos.map((t) => t.toJson()).toList(),
      'fileLibrary': fileLibrary.map((f) => f.toJson()).toList(),
      'companyProfile': companyProfile,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSnapshotKey, snapshot);
  }

  void _restoreSnapshot(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      customers
        ..clear()
        ..addAll((data['customers'] as List? ?? []).map((c) => Customer(
              id: c['id'],
              name: c['name'],
              companyName: c['companyName'] ?? '',
              address: c['address'] ?? '',
              email: c['email'] ?? '',
              phone: c['phone'] ?? '',
            )));

      jobs
        ..clear()
        ..addAll((data['jobs'] as List? ?? [])
            .map((j) => Job.fromJson(j as Map<String, dynamic>)));

      priceBook
        ..clear()
        ..addAll((data['priceBook'] as List? ?? [])
            .map((p) => DemoPriceBookItem.fromJson(p)));

      _barcodeCache.clear();
      (data['barcodeCache'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        _barcodeCache[k] = DemoPriceBookItem.fromJson(v);
      });

      schedule
        ..clear()
        ..addAll((data['schedule'] as List? ?? [])
            .map((s) => DemoScheduleEntry.fromJson(s)));

      todos
        ..clear()
        ..addAll((data['todos'] as List? ?? [])
            .map((t) => ToDoItem.fromJson(t as Map<String, dynamic>)));

      fileLibrary
        ..clear()
        ..addAll((data['fileLibrary'] as List? ?? [])
            .map((f) => DemoFileLibraryItem.fromJson(f)));

      if (data['companyProfile'] != null) {
        companyProfile = Map<String, String>.from(data['companyProfile']);
      }
    } catch (e) {
      // If the snapshot is somehow corrupt, fall back to a fresh seed
      // rather than crashing the app.
      _seedDemoData();
    }
  }

  // ==========================================================================
  // 1. THE "MAGIC" DYNAMIC CUSTOMER BOOK
  // ==========================================================================

  static const List<String> _seedFirstNames = [
    'Olivia', 'Liam', 'Emma', 'Noah', 'Ava', 'Mason', 'Isla', 'Lucas',
    'Sophie', 'James', 'Chloe', 'Ethan', 'Grace', 'Jack', 'Ella', 'Oliver',
    'Mia', 'William', 'Charlotte', 'Henry',
  ];
  static const List<String> _seedLastNames = [
    'Smith', 'Wilson', 'Brown', 'Taylor', 'Anderson', 'Thomas', 'Jones',
    'White', 'Clarke', 'Robinson', 'Walker', 'Hall', 'King', 'Wright',
    'Green', 'Baker', 'Mitchell', 'Campbell', 'Roberts', 'Stewart',
  ];
  static const List<String> _seedStreets = [
    'Queen Street', 'Ponsonby Road', 'Dominion Road', 'Great South Road',
    'Karangahape Road', 'Remuera Road', 'Manukau Road', 'Tamaki Drive',
    'Great North Road', 'Sandringham Road',
  ];
  static const List<String> _seedSuburbs = [
    'Auckland CBD', 'Ponsonby', 'Mount Eden', 'Remuera', 'Newmarket',
    'Grey Lynn', 'Parnell', 'Ellerslie', 'Epsom', 'Kingsland',
  ];

  void _seedCustomers() {
    for (var i = 0; i < 20; i++) {
      final first = _seedFirstNames[i % _seedFirstNames.length];
      final last = _seedLastNames[(i * 3) % _seedLastNames.length];
      customers.add(_buildCustomer('$first $last', index: i));
    }
  }

  Customer _buildCustomer(String name, {int? index}) {
    final seed = index ?? _random.nextInt(999999);
    final streetNum = 10 + (seed * 7) % 190;
    final street = _seedStreets[seed % _seedStreets.length];
    final suburb = _seedSuburbs[seed % _seedSuburbs.length];
    final phoneBlock = (200 + seed % 799).toString().padLeft(3, '0');
    final phoneEnd = (1000 + seed % 8999).toString().padLeft(4, '0');
    final emailName = name.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), '').trim().replaceAll(RegExp(r'\s+'), '.');

    return Customer(
      id: 'demo_customer_${DateTime.now().microsecondsSinceEpoch}_$seed',
      name: name,
      companyName: '',
      address: '$streetNum $street, $suburb, Auckland',
      email: '$emailName@example.com',
      phone: '02$phoneBlock $phoneEnd',
    );
  }

  /// "Magic" customer search: returns existing matches by name, and — if
  /// nothing matches a full name that looks legit (2+ words) — dynamically
  /// fabricates a brand-new customer with that name so it "just appears" in
  /// results, exactly like a real CRM autofilling a new contact. The
  /// generated customer is added to the in-memory book so subsequent
  /// searches/job creation see it consistently.
  List<Customer> searchCustomers(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return List.unmodifiable(customers);

    final lower = trimmed.toLowerCase();
    final matches = customers
        .where((c) =>
            c.name.toLowerCase().contains(lower) ||
            c.address.toLowerCase().contains(lower) ||
            c.email.toLowerCase().contains(lower))
        .toList();

    if (matches.isNotEmpty) return matches;

    // Only auto-generate for something that looks like a real full name
    // (at least a first and last name), to avoid magic-generating garbage
    // for single-letter/partial searches.
    final looksLikeFullName = RegExp(r'^[A-Za-z]+(\s+[A-Za-z]+)+$').hasMatch(trimmed);
    if (!looksLikeFullName) return [];

    final magicCustomer = _buildCustomer(trimmed);
    customers.add(magicCustomer);
    unawaited(_persistSnapshot());
    return [magicCustomer];
  }

  // ==========================================================================
  // 2. PRICEBOOK & BARCODE SCANNER FALLBACK
  // ==========================================================================

  static const List<Map<String, dynamic>> _mainMaterials = [
    {'name': '20mm PVC Conduit', 'unit': 'per m', 'buy': 2.10, 'sell': 3.60},
    {'name': '25mm PVC Conduit', 'unit': 'per m', 'buy': 2.80, 'sell': 4.60},
    {'name': '2.5mm² TPS Cable (Twin & Earth)', 'unit': 'per m', 'buy': 1.90, 'sell': 3.20},
    {'name': '1.5mm² TPS Cable (Twin & Earth)', 'unit': 'per m', 'buy': 1.30, 'sell': 2.40},
    {'name': 'Flush Mount Junction Box', 'unit': 'each', 'buy': 3.50, 'sell': 6.90},
    {'name': 'Standard Flush Box (1 Gang)', 'unit': 'each', 'buy': 2.20, 'sell': 4.50},
    {'name': '12-Way Switchboard', 'unit': 'each', 'buy': 145.00, 'sell': 249.00},
    {'name': '20-Way Switchboard', 'unit': 'each', 'buy': 210.00, 'sell': 349.00},
    {'name': '10A Single Light Switch', 'unit': 'each', 'buy': 3.00, 'sell': 6.50},
    {'name': 'Double Power Point (10A)', 'unit': 'each', 'buy': 8.50, 'sell': 16.90},
  ];

  static const List<Map<String, dynamic>> _specializedEquipment = [
    {'name': 'RCD/RCBO Circuit Breaker 20A', 'unit': 'each', 'buy': 42.00, 'sell': 78.00},
    {'name': '3-Phase Isolator Switch 32A', 'unit': 'each', 'buy': 95.00, 'sell': 165.00},
    {'name': 'Smart Home Hub Controller', 'unit': 'each', 'buy': 210.00, 'sell': 399.00},
    {'name': 'EV Charger (7kW Wall Mount)', 'unit': 'each', 'buy': 650.00, 'sell': 1099.00},
    {'name': 'Solar Inverter (5kW)', 'unit': 'each', 'buy': 1200.00, 'sell': 1899.00},
  ];

  static const List<String> _magicItemAdjectives = [
    'Premium', 'Heavy Duty', 'Commercial Grade', 'Industrial', 'Deluxe',
  ];
  static const List<String> _magicItemNames = [
    'Copper Cable', 'Aluminium Conduit', 'Circuit Breaker', 'Power Supply Unit',
    'Junction Box', 'Cable Tray', 'Distribution Board', 'Surge Protector',
  ];

  void _seedPriceBook() {
    var codeCounter = 1000;
    for (final item in _mainMaterials) {
      priceBook.add(DemoPriceBookItem(
        id: 'demo_pb_${codeCounter}',
        code: 'MM-$codeCounter',
        name: item['name'],
        category: 'Main Materials',
        purchasePrice: item['buy'],
        salePrice: item['sell'],
        unit: item['unit'],
      ));
      codeCounter++;
    }
    for (final item in _specializedEquipment) {
      priceBook.add(DemoPriceBookItem(
        id: 'demo_pb_${codeCounter}',
        code: 'SE-$codeCounter',
        name: item['name'],
        category: 'Specialized Equipment',
        purchasePrice: item['buy'],
        salePrice: item['sell'],
        unit: item['unit'],
      ));
      codeCounter++;
    }
  }

  /// Scans [barcode] against the mock pricebook. If it's a barcode we've
  /// never seen, a brand-new randomly-generated trade item is minted and
  /// cached against that exact barcode, so re-scanning the same real-world
  /// barcode later always returns the identical item (consistent "magic").
  DemoPriceBookItem scanBarcode(String barcode) {
    final existing = priceBook.where((p) => p.barcode == barcode);
    if (existing.isNotEmpty) return existing.first;

    if (_barcodeCache.containsKey(barcode)) return _barcodeCache[barcode]!;

    final seed = barcode.hashCode.abs();
    final adjective = _magicItemAdjectives[seed % _magicItemAdjectives.length];
    final itemName = _magicItemNames[(seed ~/ 7) % _magicItemNames.length];
    final buy = 5.0 + (seed % 500) / 10.0;
    final sell = buy * (1.4 + (seed % 30) / 100.0);

    final generated = DemoPriceBookItem(
      id: 'demo_pb_scanned_$barcode',
      code: 'SCN-${(seed % 90000 + 10000)}',
      name: '$adjective $itemName',
      category: 'Specialized Equipment',
      purchasePrice: double.parse(buy.toStringAsFixed(2)),
      salePrice: double.parse(sell.toStringAsFixed(2)),
      unit: 'each',
      barcode: barcode,
    );

    _barcodeCache[barcode] = generated;
    priceBook.add(generated);
    unawaited(_persistSnapshot());
    return generated;
  }

  // ==========================================================================
  // 3. JOBS, INVOICES, ESTIMATES
  // ==========================================================================

  void _seedJobs() {
    final now = DateTime.now();

    // Two clean-slate active jobs.
    jobs.add(Job(
      id: 'demo_job_active_1',
      title: 'Rewire Kitchen Circuit',
      customerName: 'Olivia Smith',
      address: '12 Queen Street, Auckland CBD, Auckland',
      created: now.subtract(const Duration(days: 2)),
      status: JobStatus.active,
    ));
    jobs.add(Job(
      id: 'demo_job_active_2',
      title: 'Install Outdoor Lighting',
      customerName: 'Liam Wilson',
      address: '58 Ponsonby Road, Ponsonby, Auckland',
      created: now.subtract(const Duration(days: 1)),
      status: JobStatus.active,
    ));

    // A completed job, pre-loaded with a mock invoice + estimate + file.
    final completedJob = Job(
      id: 'demo_job_completed_1',
      title: 'Switchboard Upgrade',
      customerName: 'Emma Brown',
      address: '77 Dominion Road, Mount Eden, Auckland',
      created: now.subtract(const Duration(days: 30)),
      status: JobStatus.invoicePaid,
      attachments: ['Demo Site Photo.jpg'],
    );
    completedJob.estimateVersions.add(EstimateVersion(
      type: 'estimate',
      timestamp: now.subtract(const Duration(days: 29)),
      items: <EstimateItem>[],
      status: 'final',
      amount: 1450.00,
      documentNumber: 'EST-DEMO-001',
    ));
    completedJob.invoices.add(Invoice(
      id: 'demo_invoice_1',
      total: 1450.00,
      customerId: 'demo_customer_seed',
      customerName: 'Emma Brown',
      isPaid: true,
      status: 'paid',
    ));
    jobs.add(completedJob);
  }

  /// Returns all demo jobs (used instead of the real job repository/disk
  /// storage while in demo mode).
  List<Job> getJobs() => List.unmodifiable(jobs);

  Job? getJobById(String id) {
    try {
      return jobs.firstWhere((j) => j.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Adds a brand new demo job (e.g. from the "New Job" screen while in
  /// demo mode) so it appears in the jobs list immediately and persists for
  /// the rest of the demo session.
  Future<Job> createJob(Job job) async {
    jobs.add(job);
    await _persistSnapshot();
    return job;
  }

  /// Persist an invoice/estimate/quote created against a demo job so it's
  /// visible next time the user opens that job's details screen. Call this
  /// from the estimate builder's finalize step when `isDemoMode` is true,
  /// in place of the real Firestore/local-disk save.
  Future<void> addDocumentToJob(String jobId, EstimateVersion version) async {
    final job = getJobById(jobId);
    if (job == null) return;
    job.estimateVersions.add(version);
    await _persistSnapshot();
  }

  Future<void> addInvoiceToJob(String jobId, Invoice invoice) async {
    final job = getJobById(jobId);
    if (job == null) return;
    job.invoices.add(invoice);
    await _persistSnapshot();
  }

  /// Fake "Mark as Paid" - instantly flips local demo state, no real
  /// accounting sync.
  Future<void> markInvoicePaid(String jobId, String invoiceId) async {
    final job = getJobById(jobId);
    if (job == null) return;
    for (final inv in job.invoices) {
      if (inv.id == invoiceId) {
        inv.isPaid = true;
      }
    }
    await _persistSnapshot();
  }

  // ==========================================================================
  // 4. SCHEDULING & TO-DO
  // ==========================================================================

  void _seedSchedule() {
    final now = DateTime.now();
    schedule.addAll([
      DemoScheduleEntry(
        id: 'demo_sched_1',
        jobId: 'demo_job_active_1',
        title: 'Rewire Kitchen Circuit - Site Visit',
        scheduledAt: DateTime(now.year, now.month, now.day, 9, 0)
            .add(const Duration(days: 1)),
        isFlexible: false,
      ),
      DemoScheduleEntry(
        id: 'demo_sched_2',
        jobId: 'demo_job_active_2',
        title: 'Install Outdoor Lighting - Install Day',
        scheduledAt: DateTime(now.year, now.month, now.day, 13, 30)
            .add(const Duration(days: 3)),
        isFlexible: false,
      ),
      DemoScheduleEntry(
        id: 'demo_sched_3',
        jobId: 'demo_job_completed_1',
        title: 'Switchboard Upgrade - Follow-up Check',
        isFlexible: true,
      ),
    ]);
  }

  void _seedTodos() {
    todos.addAll([
      ToDoItem(
          id: 'demo_todo_1',
          title: 'Sign off safety cert for Job #102',
          createdDate: DateTime.now()),
      ToDoItem(
          id: 'demo_todo_2',
          title: 'Order 20mm conduit',
          createdDate: DateTime.now()),
      ToDoItem(
          id: 'demo_todo_3',
          title: 'Call Emma Brown re: switchboard invoice',
          createdDate: DateTime.now()),
      ToDoItem(
          id: 'demo_todo_4',
          title: 'Restock double power points',
          createdDate: DateTime.now()),
    ]);
  }

  Future<void> toggleTodo(String id) async {
    for (final t in todos) {
      if (t.id == id) t.isCompleted = !t.isCompleted;
    }
    await _persistSnapshot();
  }

  Future<void> addTodo(String title) async {
    todos.add(ToDoItem(
      id: 'demo_todo_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      createdDate: DateTime.now(),
    ));
    await _persistSnapshot();
  }

  // ==========================================================================
  // 5. FILES / ATTACHMENTS / CERTIFICATES
  // ==========================================================================

  void _seedFileLibrary() {
    fileLibrary.addAll([
      DemoFileLibraryItem(id: 'demo_file_1', name: 'Site Safe Checklist.pdf', category: 'Safety'),
      DemoFileLibraryItem(id: 'demo_file_2', name: 'Standard Terms of Trade.pdf', category: 'Legal'),
      DemoFileLibraryItem(id: 'demo_file_3', name: 'Electrical Safety Certificate Template.pdf', category: 'Compliance'),
      DemoFileLibraryItem(id: 'demo_file_4', name: 'Job Sheet Template.docx', category: 'Templates'),
      DemoFileLibraryItem(id: 'demo_file_5', name: 'Customer Feedback Form.pdf', category: 'Templates'),
    ]);
  }

  List<DemoFileLibraryItem> searchFileLibrary(String query) {
    if (query.trim().isEmpty) return List.unmodifiable(fileLibrary);
    final lower = query.toLowerCase();
    return fileLibrary
        .where((f) => f.name.toLowerCase().contains(lower))
        .toList();
  }

  /// Simulates attaching a photo/file to a job without touching real
  /// storage/camera/file-picker APIs - just adds a placeholder name to the
  /// job's demo attachments list.
  Future<void> addFakeAttachment(String jobId, String fileName) async {
    final job = getJobById(jobId);
    if (job == null) return;
    job.attachments ??= [];
    job.attachments!.add(fileName);
    await _persistSnapshot();
  }

  /// Builds the data for a mock compliance-certificate preview, pulling
  /// straight from the given job's in-memory demo state instead of
  /// generating a real PDF.
  Map<String, dynamic> generateCertificatePreview(String jobId) {
    final job = getJobById(jobId);
    return {
      'jobTitle': job?.title ?? 'Demo Job',
      'customerName': job?.customerName ?? 'Demo Customer',
      'address': job?.address ?? '',
      'companyName': companyProfile['companyName'],
      'gstNumber': companyProfile['gstNumber'],
      'issuedDate': DateTime.now().toIso8601String(),
      'certificateNumber':
          'DEMO-CERT-${DateTime.now().millisecondsSinceEpoch % 100000}',
    };
  }

  // ==========================================================================
  // 6. FAKE COMMUNICATIONS
  // ==========================================================================

  /// Simulates sending an email: no mailer/SMTP call, no PDF compilation.
  /// Returns a friendly toast message the caller should display via
  /// ScaffoldMessenger, e.g.:
  ///   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  ///     content: Text(DemoModeService.instance.fakeSendEmail(...))));
  String fakeSendEmail({
    required String documentType, // 'Invoice' | 'Estimate' | 'Quote' | 'Certificate'
    required String recipientEmail,
  }) {
    return '[Demo] $documentType successfully sent to $recipientEmail!';
  }

  // ==========================================================================
  // Seeding orchestration
  // ==========================================================================

  void _seedDemoData() {
    _seedCustomers();
    _seedPriceBook();
    _seedJobs();
    _seedSchedule();
    _seedTodos();
    _seedFileLibrary();
  }
}

/// Small helper so we can call `unawaited(...)` without pulling in
/// `package:pedantic`/`dart:async`'s Future extension in older SDKs.
void unawaited(Future<void> future) {}
