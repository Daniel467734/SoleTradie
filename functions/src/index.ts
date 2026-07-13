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
import * as nodemailer from "nodemailer";

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
  if (!data?.refreshToken || !data?.clientId || !data?.tenantId) {
    logger.warn(`Missing Xero credentials for user ${userId}`);
    return null;
  }

  // PKCE ("Mobile or desktop app") Xero clients have no client secret -
  // the refresh_token grant only needs client_id in that case, sent as a
  // form field rather than via a Basic auth header. Confidential ("Web
  // app") clients still use Basic auth with the secret.
  const usePkce = !data.clientSecret;
  const formParams: Record<string, string> = {
    grant_type: "refresh_token",
    refresh_token: data.refreshToken,
  };
  if (usePkce) {
    formParams.client_id = data.clientId;
  }

  const response = await axios.post(
    XERO_TOKEN_URL,
    new URLSearchParams(formParams).toString(),
    {
      headers: {
        ...(usePkce
          ? {}
          : {
              Authorization: `Basic ${Buffer.from(`${data.clientId}:${data.clientSecret}`).toString("base64")}`,
            }),
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

// ============================================================================
// Customer intake form webhook.
//
// A public, unauthenticated HTML form (hosted via Firebase Hosting, see
// /public/new-customer.html) lets a tradie send a link to a prospective
// customer. The customer fills in their name, address (with live
// autocomplete), email, and phone, then submits. The form POSTs straight
// to this function (no Google Forms/Apps Script involved at all), which:
//
//   1. Validates the payload.
//   2. Writes a new Customer document to that tradie's
//      users/{uid}/customers collection (uid is passed as a query param
//      / hidden field on the link, e.g. .../new-customer.html?u=UID).
//   3. Sends a push notification to that tradie's phone via FCM, using
//      the device token(s) stored at users/{uid}/fcmTokens/{token} (see
//      NotificationService.registerFcmToken in the Flutter app), so they
//      immediately see "New customer added: {name}".
// ============================================================================

interface CustomerIntakePayload {
  uid?: string;
  firstName?: string;
  lastName?: string;
  address?: string;
  email?: string;
  phone?: string;
}

/** Very small helper: true if `email` looks roughly like an email address. */
function looksLikeEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

async function sendCustomerAddedNotification(uid: string, customerName: string): Promise<void> {
  try {
    const tokensSnapshot = await db.collection(`users/${uid}/fcmTokens`).get();
    if (tokensSnapshot.empty) {
      logger.warn(`No FCM tokens registered for user ${uid} - skipping push notification`);
      return;
    }

    const tokens = tokensSnapshot.docs.map((d) => d.id);
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "New customer added",
        body: customerName,
      },
      data: {
        type: "customer_added",
        customerName,
      },
    });

    // Clean up any tokens that are no longer valid (app uninstalled,
    // token rotated, etc.) so this collection doesn't grow unbounded.
    response.responses.forEach((r, i) => {
      if (!r.success && (r.error?.code === "messaging/registration-token-not-registered" ||
          r.error?.code === "messaging/invalid-registration-token")) {
        db.collection(`users/${uid}/fcmTokens`).doc(tokens[i]).delete().catch(() => {});
      }
    });
  } catch (e) {
    logger.error(`Failed to send customer-added notification to user ${uid}`, e);
  }
}

export const submitCustomerForm = onRequest(
  {
    region: "australia-southeast1",
    // NOTE: invoker is intentionally left unset (not "public") because an
    // organization policy on this project blocks granting allUsers invoker
    // access. Firebase Hosting rewrites don't need public/allUsers access -
    // `firebase deploy` automatically grants the Firebase Hosting service
    // agent invoker permission on this function, which is sufficient for
    // requests routed through the /api/submitCustomerForm rewrite.
    cors: true,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    const payload = req.body as CustomerIntakePayload;
    const uid = (payload.uid ?? "").trim();
    const firstName = (payload.firstName ?? "").trim();
    const lastName = (payload.lastName ?? "").trim();
    const address = (payload.address ?? "").trim();
    const email = (payload.email ?? "").trim();
    const phone = (payload.phone ?? "").trim();

    if (!uid) {
      res.status(400).json({ error: "Missing form link (uid) - please use the link your tradie sent you." });
      return;
    }
    if (!firstName || !lastName) {
      res.status(400).json({ error: "Please enter your first and last name." });
      return;
    }
    if (!address) {
      res.status(400).json({ error: "Please enter your address." });
      return;
    }
    if (!email || !looksLikeEmail(email)) {
      res.status(400).json({ error: "Please enter a valid email address." });
      return;
    }
    if (!phone) {
      res.status(400).json({ error: "Please enter a phone number." });
      return;
    }

    const fullName = `${firstName} ${lastName}`;

    try {
      const customerRef = db.collection(`users/${uid}/customers`).doc();
      await customerRef.set({
        id: customerRef.id,
        name: firstName,
        lastName,
        companyName: "",
        address,
        email,
        additionalEmails: [],
        phone,
        paymentTerms: "7 days",
        bodyCorporateNumber: "",
        isRemote: false,
        source: "customer_intake_form",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info(`Customer intake form: created customer ${customerRef.id} (${fullName}) for user ${uid}`);

      // Fire-and-forget the notification - don't block/fail the form
      // submission response on it.
      sendCustomerAddedNotification(uid, fullName).catch(() => {});

      res.status(200).json({ success: true });
    } catch (e) {
      logger.error(`Failed to save customer intake form submission for user ${uid}`, e);
      res.status(500).json({ error: "Something went wrong saving your details. Please try again." });
    }
  }
);

// ============================================================================
// Website contact form (multi-tenant).
//
// A public, unauthenticated form hosted at /public/contact.html?u={uid} that
// ANY user of this app can put on their own website. Which tradie's account
// it targets is determined entirely by the `u` (uid) query param on the
// link - there is nothing hardcoded here, unlike the very first version of
// this function which only worked for a single hardcoded account.
//
// Each user's own SMTP credentials (configured once in the app's Settings
// screen, see SettingsScreen._verifyAndSaveSmtpForContactForm) are mirrored
// to `users/{uid}/settings/smtp` - the exact same pattern already used for
// mirroring Xero credentials (see XeroService.saveTokens) so a server-side
// Cloud Function can act on behalf of a user's own device settings. The
// link is only shown to the user in Settings once they've successfully
// sent themselves a real test email (smtpVerified: true), so we can be
// reasonably sure the stored credentials actually work before anyone's
// customers start relying on the link.
//
// On submit it:
//   1. Saves the customer's details (name, address, email, phone) as a new
//      (or updated, matched by email) Customer document in
//      users/{uid}/customers - so they show up in the tradie's own app
//      exactly like any other customer.
//   2. Emails the tradie (at their own stored SMTP address) the full
//      submission, including the free-text message field, sent via THEIR
//      OWN SMTP credentials (so it arrives from their own business email,
//      not from a shared central inbox).
//   3. Sends a push notification to their phone via FCM, reusing the same
//      mechanism as submitCustomerForm above.
// ============================================================================

interface WebsiteContactPayload {
  uid?: string;
  firstName?: string;
  lastName?: string;
  address?: string;
  townCity?: string;
  email?: string;
  phone?: string;
  message?: string;
}

/** Shape of users/{uid}/settings/smtp, mirrored from the app's Settings screen. */
interface SmtpSettingsDoc {
  smtpEmail?: string;
  smtpPassword?: string;
  smtpServer?: string;
  smtpPort?: number;
  companyName?: string;
  verified?: boolean;
}

/**
 * Builds a nodemailer transporter for a specific user's own SMTP
 * credentials (not a shared/global inbox). Transporters are cheap enough
 * to create per-request that we don't need to cache these across users.
 */
function buildMailTransporterFor(smtp: SmtpSettingsDoc): nodemailer.Transporter {
  const port = smtp.smtpPort ?? 587;
  return nodemailer.createTransport({
    host: smtp.smtpServer,
    port,
    secure: port === 465,
    auth: {
      user: smtp.smtpEmail,
      pass: smtp.smtpPassword,
    },
  });
}

async function sendContactFormEmail(
  smtp: SmtpSettingsDoc,
  payload: { name: string; address: string; email: string; phone: string; message: string }
): Promise<void> {
  const transporter = buildMailTransporterFor(smtp);
  const escapeHtml = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const fromName = smtp.companyName || "Website Contact Form";

  await transporter.sendMail({
    from: `"${fromName}" <${smtp.smtpEmail}>`,
    to: smtp.smtpEmail,
    replyTo: payload.email,
    subject: `New website enquiry from ${payload.name}`,
    text:
      `Name: ${payload.name}\n` +
      `Address: ${payload.address}\n` +
      `Email: ${payload.email}\n` +
      `Phone: ${payload.phone}\n\n` +
      `Message:\n${payload.message}\n`,
    html:
      `<h2>New website enquiry</h2>` +
      `<p><strong>Name:</strong> ${escapeHtml(payload.name)}</p>` +
      `<p><strong>Address:</strong> ${escapeHtml(payload.address)}</p>` +
      `<p><strong>Email:</strong> ${escapeHtml(payload.email)}</p>` +
      `<p><strong>Phone:</strong> ${escapeHtml(payload.phone)}</p>` +
      `<p><strong>Message:</strong></p><p>${escapeHtml(payload.message).replace(/\n/g, "<br/>")}</p>`,
  });
}

export const submitWebsiteContactForm = onRequest(
  {
    region: "australia-southeast1",
    // NOTE: invoker intentionally left unset - see submitCustomerForm's
    // comment above for why (org policy blocks allUsers/public grants;
    // Firebase Hosting's own rewrite service agent is sufficient instead).
    cors: true,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    const payload = req.body as WebsiteContactPayload;
    const uid = (payload.uid ?? "").trim();
    const firstName = (payload.firstName ?? "").trim();
    const lastName = (payload.lastName ?? "").trim();
    const streetAddress = (payload.address ?? "").trim();
    const townCity = (payload.townCity ?? "").trim();
    const email = (payload.email ?? "").trim();
    const phone = (payload.phone ?? "").trim();
    const message = (payload.message ?? "").trim();

    // Combine street address + town/city into a single address string,
    // e.g. "22b Campbell Ave" + "Paraparaumu" -> "22b Campbell Ave Paraparaumu".
    const address = [streetAddress, townCity].filter(Boolean).join(" ");
    const name = [firstName, lastName].filter(Boolean).join(" ");

    if (!uid) {
      res.status(400).json({ error: "This form link is missing some information. Please ask for a new link." });
      return;
    }
    if (!firstName) {
      res.status(400).json({ error: "Please enter your first name." });
      return;
    }
    if (!lastName) {
      res.status(400).json({ error: "Please enter your last name." });
      return;
    }
    if (!streetAddress) {
      res.status(400).json({ error: "Please enter your address." });
      return;
    }
    if (!townCity) {
      res.status(400).json({ error: "Please enter your town/city." });
      return;
    }
    if (!email || !looksLikeEmail(email)) {
      res.status(400).json({ error: "Please enter a valid email address." });
      return;
    }
    if (!phone) {
      res.status(400).json({ error: "Please enter a phone number." });
      return;
    }

    try {
      const smtpDoc = await db.collection(`users/${uid}/settings`).doc("smtp").get();
      const smtp = smtpDoc.data() as SmtpSettingsDoc | undefined;

      if (!smtp?.verified || !smtp.smtpEmail || !smtp.smtpPassword || !smtp.smtpServer) {
        logger.warn(`Website contact form: user ${uid} has no verified SMTP settings - rejecting submission`);
        res.status(400).json({ error: "This business hasn't finished setting up their contact form yet. Please contact them directly." });
        return;
      }

      // 1. Save/upsert the customer into the app. If a customer with this
      // exact email already exists, update their details instead of
      // creating a duplicate every time the same person submits the form.
      const customersRef = db.collection(`users/${uid}/customers`);
      const existing = await customersRef.where("email", "==", email).limit(1).get();

      if (!existing.empty) {
        await existing.docs[0].ref.set(
          {
            name: firstName,
            lastName,
            address,
            phone,
            source: "website_contact_form",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        logger.info(`Website contact form: updated existing customer ${existing.docs[0].id} (${name}) for user ${uid}`);
      } else {
        const customerRef = customersRef.doc();
        await customerRef.set({
          id: customerRef.id,
          name: firstName,
          lastName,
          companyName: "",
          address,
          email,
          additionalEmails: [],
          phone,
          paymentTerms: "7 days",
          bodyCorporateNumber: "",
          isRemote: false,
          source: "website_contact_form",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logger.info(`Website contact form: created customer ${customerRef.id} (${name}) for user ${uid}`);
      }

      // 2. Email the enquiry (including the free-text message) to the
      // tradie, sent via their own SMTP credentials. This is awaited (not
      // fire-and-forget) since the email IS the primary point of this
      // form - if it fails we want the submitter to see an error rather
      // than silently losing the enquiry.
      await sendContactFormEmail(smtp, { name, address, email, phone, message });

      // 3. Best-effort push notification, reusing the same mechanism as
      // the customer intake form.
      sendCustomerAddedNotification(uid, name).catch(() => {});

      res.status(200).json({ success: true });
    } catch (e) {
      logger.error(`Failed to process website contact form submission for user ${uid}`, e);
      res.status(500).json({ error: "Something went wrong sending your message. Please try again." });
    }
  }
);

/**
 * Called by the app's Settings screen to send a real test email using the
 * SMTP credentials the user just entered, BEFORE marking them as verified
 * and revealing their website contact-form link. Requires Firebase Auth
 * (unlike the two forms above) since this is only ever called from inside
 * the app by a signed-in user, testing their OWN credentials - never
 * exposed to the public internet unauthenticated.
 *
 * On success, mirrors the credentials + verified:true to
 * users/{uid}/settings/smtp so submitWebsiteContactForm (above) can use
 * them going forward.
 */
interface SmtpTestPayload {
  smtpEmail?: string;
  smtpPassword?: string;
  smtpServer?: string;
  smtpPort?: number;
  companyName?: string;
}

export const testAndSaveSmtpSettings = onRequest(
  {
    region: "australia-southeast1",
    cors: true,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    // Verify the caller's Firebase Auth ID token (sent as a Bearer token)
    // so this can only ever be used to test/save a user's OWN SMTP
    // settings, never anyone else's.
    const authHeader = req.header("authorization") || req.header("Authorization");
    const idToken = authHeader?.startsWith("Bearer ") ? authHeader.substring(7) : undefined;
    if (!idToken) {
      res.status(401).json({ error: "Not signed in." });
      return;
    }

    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch (e) {
      logger.warn("testAndSaveSmtpSettings: invalid ID token", e);
      res.status(401).json({ error: "Your session has expired. Please sign in again." });
      return;
    }

    const payload = req.body as SmtpTestPayload;
    const smtpEmail = (payload.smtpEmail ?? "").trim();
    const smtpPassword = (payload.smtpPassword ?? "").trim();
    const smtpServer = (payload.smtpServer ?? "").trim();
    const smtpPort = payload.smtpPort ?? 587;
    const companyName = (payload.companyName ?? "").trim();

    if (!smtpEmail || !smtpPassword || !smtpServer) {
      res.status(400).json({ error: "Please fill in your SMTP email, password, and server first." });
      return;
    }

    try {
      const transporter = buildMailTransporterFor({ smtpEmail, smtpPassword, smtpServer, smtpPort, companyName });
      await transporter.sendMail({
        from: `"${companyName || smtpEmail}" <${smtpEmail}>`,
        to: smtpEmail,
        subject: "Your website contact form is ready!",
        text:
          `This is a test email confirming your SMTP settings work correctly.\n\n` +
          `Your website contact form is now ready to use - you'll find your shareable link in Settings.\n`,
        html:
          `<p>This is a test email confirming your SMTP settings work correctly.</p>` +
          `<p>Your website contact form is now ready to use - you'll find your shareable link in Settings.</p>`,
      });

      await db.collection(`users/${uid}/settings`).doc("smtp").set(
        {
          smtpEmail,
          smtpPassword,
          smtpServer,
          smtpPort,
          companyName,
          verified: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      logger.info(`SMTP settings verified and saved for user ${uid}`);
      res.status(200).json({ success: true });
    } catch (e) {
      logger.error(`SMTP test/send failed for user ${uid}`, e);
      // Also mark as not verified so a previously-working link doesn't
      // keep showing if the user changed to now-broken credentials.
      await db.collection(`users/${uid}/settings`).doc("smtp").set(
        { verified: false },
        { merge: true }
      ).catch(() => {});
      res.status(400).json({
        error: "Could not send a test email with those settings. Please double-check your SMTP email, password, server, and port.",
      });
    }
  }
);

