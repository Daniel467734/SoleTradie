// Helpers that translate our existing domain objects (Job, Invoice,
// EstimateItem) into the Xero payload models defined in xero_models.dart.
//
// Kept as pure functions (no I/O) so they're easy to unit test and reuse
// from both the background sync worker and any manual "resend to Xero"
// action in the UI.

import '../models/estimate_item.dart' show EstimateItem;
import '../models/job.dart';
import '../models/invoice.dart';
import '../models/xero_models.dart';

class XeroPayloadBuilder {
  /// Default Xero Sales account code and GST tax type, overridden by the
  /// user's mapped settings (see XeroSettings in settings_screen.dart /
  /// SharedPreferences: 'xero_sales_account_code', 'xero_tax_type').
  static const String defaultSalesAccountCode = '200';
  static const String defaultTaxType = 'OUTPUT'; // NZ/AU standard GST

  /// Builds the full invoice payload for a Job's invoice, ready to be
  /// PUT to Xero's `/Invoices` endpoint.
  ///
  /// [xeroContactId] should come from a previously-synced Contact lookup;
  /// if null, [customerName] is sent instead so Xero creates a new
  /// contact inline (Xero will still de-dupe contacts by name for us on
  /// its side, but a stored ContactID is always preferred once known).
  static XeroInvoicePayload buildInvoicePayload({
    required Job job,
    required Invoice invoice,
    required String localInvoiceNumber,
    String? xeroContactId,
    String? xeroInvoiceId,
    String salesAccountCode = defaultSalesAccountCode,
    String taxType = defaultTaxType,
    XeroLineAmountType lineAmountTypes = XeroLineAmountType.exclusive,
    List<EstimateItem>? lineItemsOverride,
  }) {
    final items = lineItemsOverride ?? job.estimateItems;

    // Group by section so the PDF's "black space" subsection splits are
    // preserved as a visual separator line in Xero (Xero has no native
    // section concept for invoice line items, so we emit a zero-amount
    // heading row per section - this keeps the layout intent intact
    // without affecting the invoice total).
    final lineItems = <XeroLineItem>[];
    String? lastSection;
    for (final item in items) {
      if (item.section.isNotEmpty && item.section != lastSection) {
        lineItems.add(XeroLineItem(
          description: '— ${item.section} —',
          quantity: 0,
          unitAmount: 0,
          accountCode: salesAccountCode,
          taxType: taxType,
        ));
        lastSection = item.section;
      }

      lineItems.add(XeroLineItem(
        description: item.description.isNotEmpty
            ? item.description
            : item.name,
        quantity: item.quantity,
        unitAmount: item.unitPrice,
        accountCode: salesAccountCode,
        taxType: taxType,
        // Preserve local item identity (name acts as our item id/code
        // since EstimateItem has no separate id field).
        itemCode: item.name,
      ));
    }

    return XeroInvoicePayload(
      xeroInvoiceId: xeroInvoiceId,
      contact: XeroContact(
        contactId: xeroContactId,
        name: job.documentCustomerName,
        emailAddress: job.customerEmail,
      ),
      invoiceNumber: localInvoiceNumber,
      // Reference carries our local invoice id so retries/duplicate
      // pushes are detectable/idempotent (see
      // XeroInvoiceRepository.pushInvoice).
      reference: invoice.id,
      date: DateTime.now(),
      dueDate: invoice.dueDate,
      lineAmountTypes: lineAmountTypes,
      lineItems: lineItems,
      status: 'AUTHORISED',
    );
  }

  /// Builds the `/Payments` payload for marking an invoice paid in Xero,
  /// used both when the user marks it paid in-app (push) and mirrored
  /// locally when a webhook tells us Xero marked it paid first.
  static XeroPaymentPayload buildPaymentPayload({
    required String xeroInvoiceId,
    required String bankAccountCode,
    required double amountPaid,
    DateTime? paidDate,
  }) {
    return XeroPaymentPayload(
      xeroInvoiceId: xeroInvoiceId,
      accountCode: bankAccountCode,
      date: paidDate ?? DateTime.now(),
      amount: amountPaid,
    );
  }
}
