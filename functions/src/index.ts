/**
 * Xero webhook receiver.
 *
 * Mirrors the reconciliation logic implemented client-side in
 * lib/services/xero_webhook_parser.dart and
 * lib/services/xero_invoice_repository_impl.dart
 * (reconcileFromWebhookEvent), but running server-side so it works even
 * when the user's phone is offline/closed - this is the missing piece
 * flagged during the Xero integration work ("no webhook receiver server
 * exists").
 *
 * Flow:
 *  1. Xero POSTs { events: [...] } to this HTTPS endpoint, signed with
 *     an HMAC-SHA256 signature in the `x-xero-signature` header.
 *  2. We verify the signature using the webhook receiver key (set via
 *     `firebase functions:config:set xero.webhook_key="..."` or, for
 *     2nd-gen functions, a Secret Manager secret - see README below).
 *  3. On first delivery Xero sends an "intent to receive" validation
 *     payload with zero events - we must still respond 200 for the
 *     webhook to be considered validated, even though there's nothing
 *     to reconcile.
 *  4. For each INVOICE event, we search every user's
 *     `xeroSyncRecords/{xeroInvoiceId}` (mirrored from the app - see
 *     XeroInvoiceRepositoryImpl._saveSyncRecord) to find which
 *     user/job/invoice this Xero InvoiceID belongs to.
 *  5. We fetch that user's stored Xero refresh token from
 *     `users/{uid}/settings/xero` (mirrored via XeroService.saveTokens),
 *     exchange it for a fresh access token, and fetch the invoice's
 *     live status directly from Xero (never trust the webhook payload
 *     alone for the actual status).
 *  6. If the invoice is now PAID (or AUTHORISED with zero AmountDue), we
 *     flip the matching Invoice's `isPaid` flag on the job document in
 *     Firestore directly - exactly mirroring what the app does when the
 *     user marks it paid manually, just triggered from Xero's side.
 *
 * NOTE: Because Xero sync records are looked up by scanning a
 * collection group across all users (`xeroSyncRecords`), a Firestore
 * index is required - see firestore.indexes.json alongside this
 * function (create one if your project doesn't already define it).
 */

import * as crypto from "crypto";
import axios from "axios";
import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

admin.initializeApp();
const db = admin.firestore();

const XERO_WEBHOOK_KEY = defineSecret("XERO_WEBHOOK_KEY");

const XERO_TOKEN_URL = "https://identity.xero.com/connect/token";
const XERO_API_BASE = "https://api.xero.com/api.xro/2.0";

interface XeroWebhookEvent {
  resourceUrl: string;
  resourceId: string;
  eventDateUtc: string;
  eventType: string;
  eventCategory: string;
  tenantId: string;
  tenantType: string;
}

interface XeroWebhookPayload {
  events: XeroWebhookEvent[];
  firstEventSequence?: number;
  lastEventSequence?: number;
  entropy?: string;
}

/**
 * Verifies the `x-xero-signature` header against the raw request body,
 * matching the same computation as
 * XeroWebhookParser.verifySignature in the Flutter app.
 */
function verifySignature(rawBody: Buffer, signatureHeader: string | undefined, webhookKey: string): boolean {
  if (!signatureHeader) return false;
  const computed = crypto.createHmac("sha256", webhookKey).update(rawBody).digest("base64");
  // Constant-time comparison to avoid timing attacks.
  const a = Buffer.from(computed);
  const b = Buffer.from(signatureHeader);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/** Sync record shape mirrored from XeroInvoiceSyncRecord.toJson(). */
interface XeroSyncRecordDoc {
  localInvoiceId: string;
  jobId?: string | null;
  xeroInvoiceId?: string | null;
  status?: string;
}

/**
 * Finds which user owns a given Xero InvoiceID by querying the
 * collection-group of `xeroSyncRecords` mirrored from every user's
 * device. Returns the owning user id and the sync record, or null if
 * unknown (e.g. belongs to a different app install/tenant we don't
 * recognise).
 */
async function findSyncRecordOwner(
  xeroInvoiceId: string
): Promise<{ userId: string; record: XeroSyncRecordDoc } | null> {
  const snapshot = await db
    .collectionGroup("xeroSyncRecords")
    .where("xeroInvoiceId", "==", xeroInvoiceId)
    .limit(1)
    .get();

  if (snapshot.empty) return null;

  const doc = snapshot.docs[0];
  // Path is users/{uid}/xeroSyncRecords/{xeroInvoiceId}
  const userId = doc.ref.parent.parent?.id;
  if (!userId) return null;

  return { userId, record: doc.data() as XeroSyncRecordDoc };
}

/** Exchanges a stored refresh token for a fresh Xero access token. */
async function getAccessTokenForUser(userId: string): Promise<{ accessToken: string; tenantId: string } | null> {
  const settingsDoc = await db.collection(`users/${userId}/settings`).doc("xero").get();
  const data = settingsDoc.data();
  if (!data?.refreshToken || !data?.clientId || !data?.clientSecret || !data?.tenantId) {
    logger.warn(`Missing Xero credentials for user ${userId}`);
    return null;
  }

  const basicAuth = Buffer.from(`${data.clientId}:${data.clientSecret}`).toString("base64");

  const response = await axios.post(
    XERO_TOKEN_URL,
    new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: data.refreshToken,
    }).toString(),
    {
      headers: {
        Authorization: `Basic ${basicAuth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
    }
  );

  if (response.status !== 200) {
    logger.error(`Xero token refresh failed for user ${userId}: ${response.status}`);
    return null;
  }

  // Xero rotates refresh tokens on every use - persist the new one so
  // the next webhook (or the app itself) doesn't fail with a stale
  // token.
  await settingsDoc.ref.set(
    {
      refreshToken: response.data.refresh_token ?? data.refreshToken,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { accessToken: response.data.access_token, tenantId: data.tenantId };
}

/** Fetches a single invoice's live status directly from Xero. */
async function fetchXeroInvoice(
  accessToken: string,
  tenantId: string,
  xeroInvoiceId: string
): Promise<Record<string, unknown> | null> {
  const response = await axios.get(`${XERO_API_BASE}/Invoices/${xeroInvoiceId}`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Xero-tenant-id": tenantId,
      Accept: "application/json",
    },
    validateStatus: () => true,
  });

  if (response.status !== 200) {
    logger.error(`Failed to fetch Xero invoice ${xeroInvoiceId}: ${response.status}`);
    return null;
  }

  const invoices = response.data?.Invoices as Record<string, unknown>[] | undefined;
  return invoices && invoices.length > 0 ? invoices[0] : null;
}

/**
 * Flips the matching invoice's isPaid flag on the job document,
 * mirroring exactly what happens when the user marks it paid manually
 * in-app - see job_details_screen.dart's 'paid' case and
 * XeroInvoiceRepositoryImpl.reconcileFromWebhookEvent.
 */
async function markLocalInvoicePaid(userId: string, jobId: string, localInvoiceId: string): Promise<boolean> {
  const jobRef = db.collection(`users/${userId}/jobs`).doc(jobId);
  const jobSnapshot = await jobRef.get();
  if (!jobSnapshot.exists) {
    logger.warn(`Job ${jobId} not found for user ${userId}`);
    return false;
  }

  const jobData = jobSnapshot.data();
  const invoices = (jobData?.invoices as Record<string, unknown>[] | undefined) ?? [];

  let changed = false;
  const updatedInvoices = invoices.map((inv) => {
    if (inv.id === localInvoiceId && inv.isPaid !== true) {
      changed = true;
      return { ...inv, isPaid: true };
    }
    return inv;
  });

  if (!changed) return false;

  await jobRef.set(
    {
      invoices: updatedInvoices,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return true;
}

/** Reconciles a single INVOICE webhook event end-to-end. */
async function reconcileInvoiceEvent(event: XeroWebhookEvent): Promise<boolean> {
  const owner = await findSyncRecordOwner(event.resourceId);
  if (!owner || !owner.record.jobId) {
    logger.info(`No known local invoice for Xero InvoiceID ${event.resourceId}`);
    return false;
  }

  const tokens = await getAccessTokenForUser(owner.userId);
  if (!tokens) return false;

  const xeroInvoice = await fetchXeroInvoice(tokens.accessToken, tokens.tenantId, event.resourceId);
  if (!xeroInvoice) return false;

  const status = String(xeroInvoice.Status ?? "").toUpperCase();
  const amountDue = Number(xeroInvoice.AmountDue ?? 0);
  const isNowPaid = status === "PAID" || (status === "AUTHORISED" && amountDue <= 0);
  if (!isNowPaid) return false;

  return markLocalInvoicePaid(owner.userId, owner.record.jobId, owner.record.localInvoiceId);
}

/**
 * HTTPS endpoint for Xero to POST webhook events to. Register this
 * function's deployed URL in the Xero App dashboard's Webhooks tab, and
 * set the "webhook receiver key" shown there as the XERO_WEBHOOK_KEY
 * secret (see README.md in this folder for the exact commands).
 */
export const xeroWebhook = onRequest(
  {
    secrets: [XERO_WEBHOOK_KEY],
    region: "australia-southeast1",
    // Xero's servers call this endpoint directly with no Google auth
    // credentials, so it must allow unauthenticated invocations (the
    // HMAC signature check below is what actually secures it).
    invoker: "public",
  },
  async (req, res) => {
    const rawBody: Buffer = (req as unknown as { rawBody: Buffer }).rawBody;
    const signature = req.header("x-xero-signature");
    const webhookKey = XERO_WEBHOOK_KEY.value();

    if (!verifySignature(rawBody, signature, webhookKey)) {
      logger.warn("Xero webhook signature verification failed");
      // Xero requires a 401 for invalid signatures so it can flag the
      // webhook as misconfigured in the dashboard.
      res.status(401).send("Invalid signature");
      return;
    }

    let payload: XeroWebhookPayload;
    try {
      payload = JSON.parse(rawBody.toString("utf8"));
    } catch (e) {
      logger.error("Failed to parse Xero webhook payload", e);
      res.status(400).send("Invalid payload");
      return;
    }

    // Xero's "intent to receive" validation ping has an empty events
    // array - a 200 with an empty body is all that's required to pass
    // validation in the dashboard.
    if (!payload.events || payload.events.length === 0) {
      res.status(200).send();
      return;
    }

    const invoiceEvents = payload.events.filter((e) => e.eventCategory === "INVOICE");

    let reconciledCount = 0;
    for (const event of invoiceEvents) {
      try {
        const didReconcile = await reconcileInvoiceEvent(event);
        if (didReconcile) reconciledCount += 1;
      } catch (e) {
        logger.error(`Failed to reconcile event for InvoiceID ${event.resourceId}`, e);
        // Continue processing remaining events rather than failing the
        // whole delivery - Xero will retry the whole payload on
        // non-200, which we want to avoid for events we've already
        // successfully processed.
      }
    }

    logger.info(`Xero webhook processed: ${reconciledCount}/${invoiceEvents.length} invoice events reconciled`);
    // Must respond within 5 seconds with a 200 or Xero will retry (and
    // eventually disable the webhook after repeated failures).
    res.status(200).send();
  }
);
