# Xero Webhook Receiver (Cloud Function)

This function closes the last remaining gap in the Xero integration:
a **public inbound HTTPS endpoint** that Xero can call when an invoice's
status changes on their side (e.g. someone pays it via a bank
reconciliation in Xero directly, rather than through this app).

Without this, only one direction of the two-way sync worked:
`app marks paid -> pushes Payment to Xero`. This function completes
the other direction: `Xero marks paid -> app's local invoice flips to paid`.

## How it works

1. Xero POSTs webhook events to this function's URL whenever a
   subscribed resource (Invoices) changes.
2. The function verifies the `x-xero-signature` header (HMAC-SHA256)
   using your Xero app's **webhook receiver key**.
3. For each `INVOICE` event, it looks up which user/job/invoice owns
   that Xero InvoiceID by querying the `xeroSyncRecords` collection
   group (mirrored automatically from the Flutter app - see
   `XeroInvoiceRepositoryImpl._saveSyncRecord` in
   `lib/services/xero_invoice_repository_impl.dart`).
4. It exchanges that user's stored refresh token (mirrored via
   `XeroService.saveTokens` in `lib/services/xero_service.dart`) for a
   fresh access token, and fetches the invoice's **live** status
   directly from Xero (never trusts the webhook payload's contents
   alone).
5. If the invoice is now `PAID` (or `AUTHORISED` with `AmountDue <= 0`),
   it flips the matching invoice's `isPaid` flag directly in Firestore
   on the job document - mirroring exactly what happens when the user
   taps "Mark as Paid" in the app.

## One-time setup

### 1. Install the Firebase CLI (if not already installed)

```zsh
npm install -g firebase-tools
firebase login
```

### 2. Set your Firebase project

```zsh
firebase use --add
# Select your existing Firebase project used by this app (the same one
# google-services.json / GoogleService-Info.plist point to)
```

This creates/updates `.firebaserc` at the repo root.

### 3. Install function dependencies

```zsh
cd functions
npm install
cd ..
```

### 4. Create a webhook receiver key in the Xero Developer Portal

1. Go to https://developer.xero.com/app/manage → your app → **Webhooks**.
2. Enable webhooks for **Invoices**.
3. Copy the **webhook receiver key** shown there (you'll paste it below).
4. Leave the "Delivery URL" field for now - you'll fill it in after
   deploying, in step 6.

### 5. Store the webhook key as a Cloud Functions secret

```zsh
firebase functions:secrets:set XERO_WEBHOOK_KEY
# Paste the webhook receiver key from step 4 when prompted
```

### 6. Deploy

```zsh
firebase deploy --only functions,firestore:indexes
```

After deploying, the CLI prints the function's HTTPS URL, e.g.:

```
https://us-central1-<your-project-id>.cloudfunctions.net/xeroWebhook
```

Copy that URL back into the Xero Developer Portal's **Delivery URL**
field (from step 4), then click **Send Intent to Receive** in the
portal to validate it - this function already handles that empty-events
validation ping and will respond `200 OK`.

## Notes / limitations

- This function relies on the Flutter app having mirrored the user's
  Xero refresh token + tenant id to
  `users/{uid}/settings/xero` (done automatically in
  `XeroService.saveTokens`) and each invoice's sync record to
  `users/{uid}/xeroSyncRecords/{xeroInvoiceId}` (done automatically in
  `XeroInvoiceRepositoryImpl._saveSyncRecord`). If a user connected
  Xero **before** these mirrors were added, they'll need to push at
  least one invoice (or reconnect) for the mirrors to be populated.
- Xero requires a `200` response within 5 seconds or it will retry the
  whole delivery, and will disable the webhook after repeated failures
  - keep this function's logic fast; it already avoids failing the
    whole request if a single event's reconciliation throws.
- Firestore security rules in `firestore.rules` are a placeholder if
  your project doesn't already define equivalent `users/{uid}/**`
  scoping - merge with your existing rules rather than blindly
  deploying this file if you already have one, to avoid overwriting
  unrelated rules.
