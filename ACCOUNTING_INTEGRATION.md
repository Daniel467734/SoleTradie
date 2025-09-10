# Accounting Software Integration Setup Guide

This guide covers setting up MYOB AccountRight and Xero integrations for automated bank feed synchronization and invoice management.

## Features

### MYOB AccountRight Integration
- ✅ Connection testing with API credentials
- ✅ Automatic invoice creation from job data
- ✅ Bank account management
- ✅ Transaction synchronization
- ✅ Customer contact creation

### Xero Accounting Integration
- ✅ OAuth 2.0 authentication
- ✅ Bank feed synchronization
- ✅ Automatic invoice creation
- ✅ Contact management
- ✅ Transaction matching
- ✅ Auto-sync scheduling

### Bank Feed Features
- ✅ Transaction matching to jobs/invoices
- ✅ Automated payment reconciliation
- ✅ Confidence scoring for matches
- ✅ Manual review and approval
- ✅ Scheduled synchronization

## Setup Instructions

### MYOB AccountRight Setup

1. **Enable API Access**
   - Open MYOB AccountRight
   - Go to Setup > User Access
   - Enable "Allow API access" for your user
   - Note down your username and password

2. **Get API Key**
   - Visit [MYOB Developer Portal](https://developer.myob.com/)
   - Create a developer account
   - Register a new application
   - Copy your API key

3. **Find Company File GUID**
   - In MYOB, go to Help > About
   - Click "Open Log Folder"
   - Look for the Company File GUID in the log files
   - Or use the API endpoint to list company files

4. **Configure in App**
   - Open Settings > Company Settings
   - Scroll to "Accounting Software Integration"
   - Toggle MYOB AccountRight ON
   - Enter your API key, Company File GUID, username, and password
   - Click "Test MYOB Connection"

### Xero Setup

1. **Create Xero App**
   - Visit [Xero Developer Portal](https://developer.xero.com/)
   - Click "My Apps" > "New App"
   - Choose "Web App" type
   - Set redirect URI to: `https://localhost:8080/callback`

2. **Configure Scopes**
   Required scopes:
   - `accounting.transactions` - Read/write bank transactions
   - `accounting.contacts` - Read/write customer contacts
   - `accounting.settings` - Read organization settings
   - `offline_access` - Refresh tokens

3. **Get Client Credentials**
   - Copy your Client ID and Client Secret
   - Keep these secure and don't share them

4. **Configure in App**
   - Open Settings > Company Settings
   - Scroll to "Accounting Software Integration"
   - Toggle Xero Accounting ON
   - Enter your Client ID and Client Secret
   - Click "Connect to Xero"
   - Complete OAuth authorization in browser

## Bank Feed Synchronization

### How It Works

1. **Transaction Download**: Automatically downloads new bank transactions from connected accounts
2. **Smart Matching**: Uses AI-powered matching to link transactions to jobs and invoices
3. **Confidence Scoring**: Each match gets a confidence score based on:
   - Amount exactness (50 points)
   - Description keywords (30 points)
   - Invoice number presence (20 points)
4. **Auto-approval**: High-confidence matches (>80 points) can be auto-approved
5. **Manual Review**: Lower confidence matches require manual review

### Matching Algorithm

The system matches bank transactions to jobs/invoices using:

- **Amount Matching**: Exact or near-exact amounts (±$5 tolerance for fees)
- **Description Keywords**: Job titles, customer names, invoice numbers
- **Date Proximity**: Transactions near invoice due dates get higher scores
- **Pattern Recognition**: Learns from manual approvals to improve future matching

### Auto-sync Settings

Configure automatic synchronization:
- **Daily Sync**: Enable daily bank feed downloads
- **Sync Time**: Set preferred time (default 6:00 AM)
- **Auto-approval**: Set confidence threshold for automatic approvals
- **Notifications**: Get alerts for sync results and manual reviews needed

## Usage Examples

### Creating Invoice from Job

```dart
// Automatic sync when job invoice is marked as paid
final job = Job(id: 'job-001', title: 'Kitchen Electrical Work');
final customer = Customer(name: 'John Smith', email: 'john@example.com');

await BankFeedIntegrationService.syncJobInvoiceToAccounting(
  job: job,
  customer: customer,
);
```

### Manual Bank Feed Sync

```dart
// Trigger manual sync
final xeroService = XeroService();
final transactions = await xeroService.syncBankFeeds(
  accessToken: accessToken,
  accountIds: ['bank-account-1', 'bank-account-2'],
);
```

### Transaction Matching

```dart
// Match bank transactions to jobs
final matches = await BankFeedIntegrationService.matchBankTransactionsToJobs(
  transactions,
  jobs,
);

// Review high-confidence matches
for (final match in matches.where((m) => m['confidence'] > 80)) {
  print('Auto-approving: ${match['transaction']['Description']}');
}
```

## Troubleshooting

### MYOB Connection Issues

1. **Authentication Failed**
   - Verify username/password are correct
   - Ensure user has API access enabled
   - Check if MYOB file is open elsewhere

2. **Company File Not Found**
   - Verify Company File GUID is correct
   - Ensure file is accessible via API
   - Check MYOB version compatibility

3. **API Key Invalid**
   - Verify API key from developer portal
   - Check app registration status
   - Ensure subscription is active

### Xero Connection Issues

1. **OAuth Failed**
   - Check Client ID and Secret
   - Verify redirect URI matches exactly
   - Ensure app has required scopes

2. **Token Expired**
   - Tokens expire after 30 minutes
   - App automatically refreshes using refresh token
   - Re-authenticate if refresh fails

3. **Permission Denied**
   - Verify user has admin access to Xero organization
   - Check if organization is active
   - Ensure required scopes are granted

### Bank Feed Issues

1. **No Transactions Found**
   - Check bank account connections
   - Verify date range settings
   - Ensure accounts have recent activity

2. **Poor Matching Results**
   - Review job titles and customer names for typos
   - Ensure invoice numbers are included in descriptions
   - Train system by manually approving correct matches

3. **Sync Failures**
   - Check internet connection
   - Verify API credentials are valid
   - Review error logs for specific issues

## Security Considerations

### Data Protection
- All API credentials are encrypted at rest
- OAuth tokens use secure refresh mechanisms
- Bank data is processed locally, not stored permanently

### Access Control
- Only users with admin access can configure integrations
- API keys and secrets are masked in UI
- Connection testing doesn't store sensitive data

### Compliance
- Follows bank-grade security standards
- Compatible with PCI DSS requirements
- Supports audit logging for compliance

## API Rate Limits

### MYOB AccountRight
- 1000 requests per hour per API key
- Burst limit: 10 requests per second
- Auto-retry with exponential backoff

### Xero
- 10,000 requests per day per app
- 60 requests per minute per organization
- Separate limits for different endpoints

## Support

For technical support with accounting integrations:

1. Check error messages in app logs
2. Verify API credentials and permissions
3. Test connections using built-in tools
4. Contact support with specific error codes

## Changelog

### Version 1.0
- Initial MYOB AccountRight integration
- Basic Xero OAuth setup
- Bank feed synchronization
- Transaction matching algorithm

### Future Enhancements
- QuickBooks Online integration
- Advanced matching rules
- Multi-currency support
- Real-time notifications
- Bulk transaction processing
