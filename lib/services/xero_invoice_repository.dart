// Abstract repository contract for the Xero sync engine.
//
// Implementations are responsible for:
//  - Pushing invoices to Xero (idempotently, via the local Reference id).
//  - Pushing payments to Xero when an invoice is marked paid locally.
//  - Caching the Chart of Accounts and Tax Rates to minimise API calls.
//  - Persisting the local<->Xero invoice id mapping used for idempotency
//    and two-way payment reconciliation.
//
// This lives separately from `xero_service.dart` (the raw HTTP client)
// so the repository can be unit tested against a fake/mock XeroService.

import '../models/invoice.dart';
import '../models/job.dart';
import '../models/xero_models.dart';

abstract class XeroInvoiceRepository {
  /// Pushes (creates or updates) an invoice in Xero for the given job's
  /// invoice. Must be idempotent: calling this multiple times for the
  /// same [invoice.id] must never create more than one Xero invoice.
  ///
  /// Returns the resulting [XeroInvoiceSyncRecord] (with the Xero
  /// InvoiceID populated on success, or `status: failed` with an error
  /// message on failure).
  Future<XeroInvoiceSyncRecord> pushInvoice({
    required Job job,
    required Invoice invoice,
    required String localInvoiceNumber,
  });

  /// Marks the linked Xero invoice as paid by pushing a Payment. Should
  /// be called immediately after the local DB is updated so the Xero
  /// side stays eventually-consistent without blocking the UI.
  Future<bool> pushPayment({
    required String localInvoiceId,
    required double amountPaid,
    DateTime? paidDate,
  });

  /// Voids the linked Xero invoice, mirroring a local "Void"/"Archive"
  /// or delete action. Should be called immediately after the local
  /// change so both ledgers stay reconciled. Returns false (rather than
  /// throwing) if there's no linked Xero invoice yet, if not connected,
  /// or if Xero rejects the void (e.g. a payment already exists against
  /// it) - callers should treat this as best-effort/non-fatal.
  Future<bool> pushVoid({required String localInvoiceId});

  /// Looks up the cached local<->Xero mapping for an invoice, if any.
  Future<XeroInvoiceSyncRecord?> getSyncRecord(String localInvoiceId);

  /// Returns the cached Chart of Accounts, fetching + caching from Xero
  /// only if the cache is empty or [forceRefresh] is true.
  Future<List<XeroAccount>> getAccounts({bool forceRefresh = false});

  /// Returns the cached Tax Rates, fetching + caching from Xero only if
  /// the cache is empty or [forceRefresh] is true.
  Future<List<XeroTaxRate>> getTaxRates({bool forceRefresh = false});

  /// Handles an incoming Xero webhook invoice event: if the event
  /// indicates the invoice is now paid/fully reconciled in Xero, flips
  /// the local invoice's `isPaid` status to keep both systems in sync
  /// without double data entry. Returns true if a local change was made.
  Future<bool> reconcileFromWebhookEvent(XeroWebhookInvoiceEvent event);

  /// Looks up which local job/invoice a Xero InvoiceID belongs to, if
  /// known. Used by [reconcileFromWebhookEvent] and exposed here so
  /// callers (e.g. a webhook server) can resolve the job themselves if
  /// they need to load/save it outside this repository.
  Future<XeroInvoiceSyncRecord?> findByXeroInvoiceId(String xeroInvoiceId);
}
