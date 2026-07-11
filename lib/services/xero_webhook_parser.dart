// Stub for handling incoming Xero webhook deliveries.
//
// Xero webhooks (https://developer.xero.com/documentation/api/accounting/webhooks)
// POST a JSON body shaped like:
// {
//   "events": [
//     {
//       "resourceUrl": "https://api.xero.com/api.xro/2.0/Invoices/...",
//       "resourceId": "<InvoiceID guid>",
//       "eventDateUtc": "2026-07-11T00:00:00.000Z",
//       "eventType": "UPDATE",
//       "eventCategory": "INVOICE",
//       "tenantId": "...",
//       "tenantType": "ORGANISATION"
//     }
//   ],
//   "firstEventSequence": 1,
//   "lastEventSequence": 1,
//   "entropy": "..."
// }
//
// This app doesn't currently run its own public server, so this class is
// a stub: it defines exactly how an inbound payload (once received by
// whatever lightweight endpoint/cloud function is stood up for this,
// e.g. a Firebase Cloud Function forwarding to this app's backend) should
// be parsed and handed off to [XeroInvoiceRepository.reconcileFromWebhookEvent].
//
// Xero also requires webhook signature validation using an HMAC-SHA256
// signature sent in the `x-xero-signature` header, computed from the raw
// request body and the webhook receiver key configured in the Xero App
// dashboard. That verification MUST happen in whatever server receives
// the webhook (verifySignature below is provided for that server-side
// code to reuse), since this Flutter app itself has no public inbound
// endpoint.

import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/xero_models.dart';
import 'xero_invoice_repository.dart';

class XeroWebhookParser {
  final XeroInvoiceRepository repository;

  XeroWebhookParser(this.repository);

  /// Verifies the `x-xero-signature` header against the raw request body
  /// using the webhook receiver key from the Xero app configuration.
  /// Must be run (server-side) before trusting any parsed event.
  static bool verifySignature({
    required String rawBody,
    required String signatureHeader,
    required String webhookKey,
  }) {
    final hmac = Hmac(sha256, utf8.encode(webhookKey));
    final digest = hmac.convert(utf8.encode(rawBody));
    final computedSignature = base64.encode(digest.bytes);
    return computedSignature == signatureHeader;
  }

  /// Parses a verified webhook body and reconciles every INVOICE event
  /// found in it against our local sync records. Returns the number of
  /// events that matched a known local invoice.
  Future<int> handleWebhookBody(String rawBody) async {
    final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
    final events = (decoded['events'] as List<dynamic>? ?? [])
        .map((e) => XeroWebhookInvoiceEvent.fromJson(e as Map<String, dynamic>))
        .where((e) => e.eventCategory == 'INVOICE')
        .toList();

    var matched = 0;
    for (final event in events) {
      final didMatch = await repository.reconcileFromWebhookEvent(event);
      if (didMatch) matched += 1;
    }
    return matched;
  }
}
