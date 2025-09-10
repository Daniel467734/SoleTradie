import '../models/job.dart';

/// Utility class for automatic job status updates based on system events
class JobStatusAutomation {
  
  /// Update job status when a PDF is created
  static void onPdfCreated(Job job, String documentType, String documentId) {
    if (documentType.toLowerCase().contains('estimate') || 
        documentType.toLowerCase().contains('quote')) {
      job.onEstimateCreated(documentId);
    } else if (documentType.toLowerCase().contains('invoice')) {
      job.onInvoiceCreated(documentId);
    }
  }

  /// Update job status when an email is sent with attachments
  static void onEmailSent(Job job, List<String> attachmentTypes, String documentId) {
    bool hasEstimate = attachmentTypes.any((type) => 
      type.toLowerCase().contains('estimate') || 
      type.toLowerCase().contains('quote'));
    bool hasInvoice = attachmentTypes.any((type) => 
      type.toLowerCase().contains('invoice'));

    if (hasEstimate && hasInvoice) {
      // Both estimate and invoice sent - prioritize estimate
      job.onEstimateAndInvoiceSent(documentId, documentId);
    } else if (hasEstimate) {
      job.onEstimateSent(documentId);
    } else if (hasInvoice) {
      job.onInvoiceSent(documentId);
    }
  }

  /// Update job status when an invoice is marked as paid
  static void onInvoicePaymentReceived(Job job, String invoiceId) {
    job.onInvoicePaid(invoiceId);
    
    // After invoice is paid, ask if job is complete
    _promptForJobCompletion(job);
  }

  /// Private method to prompt for job completion (would show dialog in real app)
  static void _promptForJobCompletion(Job job) {
    // In a real app, this would show a dialog asking:
    // "Invoice has been paid. Is this job now complete?"
    // For now, we'll just add it to the job's notes
    job.notes = [...(job.notes ?? []), 
      'Invoice paid - consider marking job as complete'];
  }

  /// Demo function to show how statuses auto-update
  static void demonstrateStatusFlow(Job job) {
    print('=== Job Status Flow Demo ===');
    print('Initial status: ${job.statusDisplayName}');
    
    // Simulate creating an estimate PDF
    onPdfCreated(job, 'estimate', 'EST-001');
    print('After estimate created: ${job.statusDisplayName}');
    
    // Simulate sending estimate via email
    onEmailSent(job, ['estimate'], 'EST-001');
    print('After estimate sent: ${job.statusDisplayName}');
    
    // Simulate creating an invoice PDF
    onPdfCreated(job, 'invoice', 'INV-001');
    print('After invoice created: ${job.statusDisplayName}');
    
    // Simulate sending invoice via email
    onEmailSent(job, ['invoice'], 'INV-001');
    print('After invoice sent: ${job.statusDisplayName}');
    
    // Simulate invoice payment
    onInvoicePaymentReceived(job, 'INV-001');
    print('After invoice paid: ${job.statusDisplayName}');
    
    // Manually mark as complete
    job.onJobComplete();
    print('After job completed: ${job.statusDisplayName}');
    
    print('\n=== Status History ===');
    for (int i = 0; i < job.statusHistory.length; i++) {
      final history = job.statusHistory[i];
      print('${i + 1}. ${history.status.displayName} - ${history.reason}');
    }
  }

  /// Simulate the special case where both estimate and invoice are sent together
  static void demonstrateEstimateInvoiceTogether(Job job) {
    print('\n=== Estimate + Invoice Together Demo ===');
    print('Initial status: ${job.statusDisplayName}');
    
    // Send both estimate and invoice in same email
    onEmailSent(job, ['estimate', 'invoice'], 'COMBINED-001');
    print('After sending both together: ${job.statusDisplayName}');
    print('Note: Estimate status takes priority when both are sent together');
  }
}
