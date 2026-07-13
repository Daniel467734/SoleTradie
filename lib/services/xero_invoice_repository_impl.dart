// Concrete implementation of [XeroInvoiceRepository].
//
// Persistence strategy: uses SharedPreferences as a lightweight local
// cache/store, consistent with how xero_service.dart already stores
// tokens/settings in this codebase (no new DB dependency required).
// The Chart of Accounts / Tax Rates caches and the invoice sync-record
// map are all stored as JSON blobs under dedicated keys.
//
// Idempotency strategy:
//  1. Before creating a new Xero invoice, check the local sync-record
//     cache for this local invoice id - if we already have a Xero
//     InvoiceID, push as an *update* (include InvoiceID in the payload)
//     instead of a create.
//  2. If no local record exists (e.g. cache was cleared, or this is a
//     retry after a crash before the record was saved), fall back to
//     looking the invoice up in Xero by its `Reference` (our local id) -
//     Xero invoices are unique enough for this to reliably detect an
//     already-pushed invoice and avoid a duplicate.
//  3. Only if neither check finds a match do we create a brand new
//     invoice in Xero.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice.dart';
import '../models/job.dart';
import '../models/xero_models.dart';
import 'firestore_service.dart';
import 'xero_invoice_repository.dart';
import 'xero_payload_builder.dart';
import 'xero_service.dart';

class XeroInvoiceRepositoryImpl implements XeroInvoiceRepository {
  static const String _syncRecordsKey = 'xero_invoice_sync_records';
  static const String _accountsCacheKey = 'xero_accounts_cache';
  static const String _taxRatesCacheKey = 'xero_tax_rates_cache';
  static const String _accountsCacheTimestampKey =
      'xero_accounts_cache_timestamp';
  static const String _taxRatesCacheTimestampKey =
      'xero_tax_rates_cache_timestamp';

  /// How long the Chart of Accounts / Tax Rates caches are considered
  /// fresh before a background refresh is attempted again.
  static const Duration _cacheTtl = Duration(hours: 24);

  final XeroService _xeroService;

  XeroInvoiceRepositoryImpl({XeroService? xeroService})
      : _xeroService = xeroService ?? XeroService();

  Future<String?> _accessToken() async {
    final creds = await XeroService.getStoredCredentials();
    return creds['accessToken'];
  }

  Future<String?> _bankAccountCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('xero_bank_account_code');
  }

  // ---------------------------------------------------------------------
  // Sync record persistence (idempotency + payment reconciliation map)
  // ---------------------------------------------------------------------

  Future<Map<String, XeroInvoiceSyncRecord>> _loadAllSyncRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_syncRecordsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(
            key,
            XeroInvoiceSyncRecord.fromJson(value as Map<String, dynamic>),
          ));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAllSyncRecords(
      Map<String, XeroInvoiceSyncRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        jsonEncode(records.map((key, value) => MapEntry(key, value.toJson())));
    await prefs.setString(_syncRecordsKey, encoded);
  }

  Future<void> _saveSyncRecord(XeroInvoiceSyncRecord record) async {
    final all = await _loadAllSyncRecords();
    all[record.localInvoiceId] = record;
    await _saveAllSyncRecords(all);
    // Mirror to Firestore (best-effort, fire-and-forget) so a
    // server-side webhook receiver (which has no access to this
    // device's SharedPreferences) can look up which job/invoice a Xero
    // InvoiceID belongs to when Xero notifies us of a payment there
    // first. Keyed by xeroInvoiceId since that's what the webhook event
    // carries; only mirrored once we actually have one.
    if (record.xeroInvoiceId != null && FirestoreService.currentUserId != null) {
      try {
        await FirestoreService.firestore
            .collection('users/${FirestoreService.currentUserId}/xeroSyncRecords')
            .doc(record.xeroInvoiceId)
            .set({
          ...record.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Non-fatal: local idempotency/reconciliation still works from
        // the SharedPreferences copy on this device; only server-side
        // webhook reconciliation would be affected until this succeeds
        // on a future save.
      }
    }
  }

  @override
  Future<XeroInvoiceSyncRecord?> getSyncRecord(String localInvoiceId) async {
    final all = await _loadAllSyncRecords();
    return all[localInvoiceId];
  }

  /// Reverse lookup: find the sync record whose Xero InvoiceID matches,
  /// used when a webhook event arrives with only the Xero-side id.
  Future<XeroInvoiceSyncRecord?> _findByXeroInvoiceId(
      String xeroInvoiceId) async {
    final all = await _loadAllSyncRecords();
    for (final record in all.values) {
      if (record.xeroInvoiceId == xeroInvoiceId) return record;
    }
    return null;
  }

  @override
  Future<XeroInvoiceSyncRecord?> findByXeroInvoiceId(
          String xeroInvoiceId) =>
      _findByXeroInvoiceId(xeroInvoiceId);

  // ---------------------------------------------------------------------
  // Invoice push (create/update) - idempotent
  // ---------------------------------------------------------------------

  @override
  Future<XeroInvoiceSyncRecord> pushInvoice({
    required Job job,
    required Invoice invoice,
    required String localInvoiceNumber,
  }) async {
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      final failed = XeroInvoiceSyncRecord(
        localInvoiceId: invoice.id,
        status: XeroSyncStatus.failed,
        lastError: 'Not connected to Xero (missing access token).',
      );
      await _saveSyncRecord(failed);
      return failed;
    }

    // Step 1: do we already know the Xero InvoiceID for this local id?
    var existing = await getSyncRecord(invoice.id);

    // Step 2: if not, fall back to looking it up in Xero by Reference
    // (our local invoice id) before assuming this is a brand new push.
    // This protects against duplicate creation if the local cache was
    // lost after a previous successful push (e.g. app reinstall).
    if (existing?.xeroInvoiceId == null) {
      final found = await _xeroService.findInvoiceByReference(
        accessToken: token,
        reference: invoice.id,
      );
      if (found != null && found['InvoiceID'] != null) {
        existing = XeroInvoiceSyncRecord(
          localInvoiceId: invoice.id,
          jobId: job.id,
          xeroInvoiceId: found['InvoiceID'].toString(),
          status: XeroSyncStatus.synced,
          lastSyncedAt: DateTime.now(),
        );
        await _saveSyncRecord(existing);
      }
    }

    final accounts = await getAccounts();
    final salesAccountCode = accounts.isNotEmpty
        ? accounts
            .firstWhere(
              (a) => a.type == 'REVENUE',
              orElse: () => accounts.first,
            )
            .code
        : XeroPayloadBuilder.defaultSalesAccountCode;

    final payload = XeroPayloadBuilder.buildInvoicePayload(
      job: job,
      invoice: invoice,
      localInvoiceNumber: localInvoiceNumber,
      xeroInvoiceId: existing?.xeroInvoiceId,
      salesAccountCode: salesAccountCode,
    );

    final success = await _xeroService.createInvoice(
      accessToken: token,
      invoiceData: payload.toJson(),
    );

    final record = (existing ??
            XeroInvoiceSyncRecord(localInvoiceId: invoice.id))
        .copyWith(
      jobId: job.id,
      status: success ? XeroSyncStatus.synced : XeroSyncStatus.failed,
      lastSyncedAt: success ? DateTime.now() : null,
      lastError: success ? null : 'Xero createInvoice call failed.',
    );

    await _saveSyncRecord(record);
    return record;
  }

  // ---------------------------------------------------------------------
  // Payment push (invoice marked paid locally -> tell Xero)
  // ---------------------------------------------------------------------

  @override
  Future<bool> pushPayment({
    required String localInvoiceId,
    required double amountPaid,
    DateTime? paidDate,
  }) async {
    final token = await _accessToken();
    final record = await getSyncRecord(localInvoiceId);
    final bankAccountCode = await _bankAccountCode();

    if (token == null ||
        token.isEmpty ||
        record?.xeroInvoiceId == null ||
        bankAccountCode == null ||
        bankAccountCode.isEmpty) {
      // Not enough info to push yet (not synced to Xero yet, or no bank
      // account mapped in Settings). This should be queued for retry by
      // the caller's sync scheduler/outbox rather than treated as fatal.
      return false;
    }

    final payload = XeroPayloadBuilder.buildPaymentPayload(
      xeroInvoiceId: record!.xeroInvoiceId!,
      bankAccountCode: bankAccountCode,
      amountPaid: amountPaid,
      paidDate: paidDate,
    );

    final result = await _xeroService.createPayment(
      accessToken: token,
      paymentData: payload.toJson()['Payment'] as Map<String, dynamic>,
    );

    return result != null;
  }

  // ---------------------------------------------------------------------
  // Void push (invoice voided/archived/deleted locally -> tell Xero)
  // ---------------------------------------------------------------------

  @override
  Future<bool> pushVoid({required String localInvoiceId}) async {
    final token = await _accessToken();
    final record = await getSyncRecord(localInvoiceId);

    if (token == null || token.isEmpty || record?.xeroInvoiceId == null) {
      // Never synced to Xero (or not connected) - nothing to void.
      return false;
    }

    final success = await _xeroService.voidInvoice(
      accessToken: token,
      xeroInvoiceId: record!.xeroInvoiceId!,
    );

    if (success) {
      await _saveSyncRecord(record.copyWith(
        status: XeroSyncStatus.voided,
        lastSyncedAt: DateTime.now(),
      ));
    }

    return success;
  }

  // ---------------------------------------------------------------------
  // Chart of Accounts / Tax Rates caching
  // ---------------------------------------------------------------------

  bool _isCacheFresh(int? timestampMillis) {
    if (timestampMillis == null) return false;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestampMillis));
    return age < _cacheTtl;
  }

  @override
  Future<List<XeroAccount>> getAccounts({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRaw = prefs.getString(_accountsCacheKey);
    final timestamp = prefs.getInt(_accountsCacheTimestampKey);

    if (!forceRefresh && cachedRaw != null && _isCacheFresh(timestamp)) {
      try {
        final list = jsonDecode(cachedRaw) as List<dynamic>;
        return list
            .map((e) => XeroAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Fall through to refresh on parse failure.
      }
    }

    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      // No connection available; return whatever is cached (even if
      // stale) rather than an empty list, or empty if nothing cached.
      if (cachedRaw != null) {
        try {
          final list = jsonDecode(cachedRaw) as List<dynamic>;
          return list
              .map((e) => XeroAccount.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
      return [];
    }

    final raw = await _xeroService.getAllAccounts(token);
    final accounts = raw.map(XeroAccount.fromJson).toList();

    await prefs.setString(
      _accountsCacheKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    await prefs.setInt(
      _accountsCacheTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    return accounts;
  }

  @override
  Future<List<XeroTaxRate>> getTaxRates({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRaw = prefs.getString(_taxRatesCacheKey);
    final timestamp = prefs.getInt(_taxRatesCacheTimestampKey);

    if (!forceRefresh && cachedRaw != null && _isCacheFresh(timestamp)) {
      try {
        final list = jsonDecode(cachedRaw) as List<dynamic>;
        return list
            .map((e) => XeroTaxRate.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Fall through to refresh on parse failure.
      }
    }

    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      if (cachedRaw != null) {
        try {
          final list = jsonDecode(cachedRaw) as List<dynamic>;
          return list
              .map((e) => XeroTaxRate.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
      return [];
    }

    final raw = await _xeroService.getAllTaxRates(token);
    final rates = raw.map(XeroTaxRate.fromJson).toList();

    await prefs.setString(
      _taxRatesCacheKey,
      jsonEncode(rates.map((r) => r.toJson()).toList()),
    );
    await prefs.setInt(
      _taxRatesCacheTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    return rates;
  }

  // ---------------------------------------------------------------------
  // Webhook reconciliation (Xero -> local)
  // ---------------------------------------------------------------------

  @override
  Future<bool> reconcileFromWebhookEvent(
      XeroWebhookInvoiceEvent event) async {
    if (event.eventCategory != 'INVOICE') return false;

    final record = await _findByXeroInvoiceId(event.xeroInvoiceId);
    if (record == null || record.jobId == null) {
      // We don't recognise this invoice locally (may belong to a
      // different tenant/app instance), or we never recorded which job
      // owns it (older sync record from before jobId was tracked) -
      // nothing safe to reconcile automatically.
      return false;
    }

    final token = await _accessToken();
    if (token == null || token.isEmpty) return false;

    // Fetch the invoice's latest status directly from Xero rather than
    // trusting the webhook payload alone (the webhook only tells us
    // *something* changed - we still need the authoritative state).
    final xeroInvoice = await _xeroService.getInvoiceById(
      accessToken: token,
      xeroInvoiceId: event.xeroInvoiceId,
    );
    if (xeroInvoice == null) return false;

    final status = xeroInvoice['Status']?.toString().toUpperCase();
    final amountDue = (xeroInvoice['AmountDue'] ?? 0).toDouble();
    final isNowPaid = status == 'PAID' || (status == 'AUTHORISED' && amountDue <= 0);
    if (!isNowPaid) return false;

    // Load the job that owns this invoice, flip the matching Invoice's
    // isPaid flag, and save - mirroring exactly what happens when the
    // user marks it paid manually in-app, just triggered from Xero's
    // side instead. This keeps both systems reconciled without double
    // entry, per the two-way payment resolution requirement.
    try {
      final job = await FirestoreService.getJob(record.jobId!);
      if (job == null) return false;

      final invoice = job.invoices
          .where((inv) => inv.id == record.localInvoiceId)
          .cast<Invoice?>()
          .firstWhere((inv) => inv != null, orElse: () => null);
      if (invoice == null || invoice.isPaid) return false;

      invoice.isPaid = true;
      // Distinguish this from a manual "Mark as Paid" tap in-app, so the
      // UI can show "Paid (Xero)" / bank-reconciled invoices differently
      // from ones the user manually marked paid themselves.
      invoice.paidVia = 'xero';
      await FirestoreService.saveJob(job);
      return true;
    } catch (e) {
      return false;
    }
  }
}
