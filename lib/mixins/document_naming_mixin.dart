import '../models/job.dart';
import '../services/document_naming_service.dart';

/// Mixin to provide standardized PDF naming functionality
mixin DocumentNamingMixin {
  /// Generate a standardized filename for a PDF document
  String generateDocumentName({
    required String documentType,
    required Job job,
    List<String>? existingAttachments,
  }) {
    return DocumentNamingService.generatePdfFileName(
      documentType: documentType,
      job: job,
      existingAttachments: existingAttachments ?? job.attachments,
    );
  }

  /// Generate filename for invoice
  String generateInvoiceName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'Invoice',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Generate filename for quote
  String generateQuoteName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'Quote',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Generate filename for estimate
  String generateEstimateName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'Estimate',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Generate filename for ESC (Electrical Safety Certificate)
  String generateEscName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'ESC',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Generate filename for COC (Certificate of Compliance)
  String generateCocName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'COC',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Generate filename for Gas COC
  String generateGasCocName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'Gas COC',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Generate filename for ROI (Record of Inspection)
  String generateRoiName(Job job, {List<String>? existingAttachments}) {
    return generateDocumentName(
      documentType: 'ROI',
      job: job,
      existingAttachments: existingAttachments,
    );
  }

  /// Update job attachments with new document using standardized naming
  List<String> addDocumentToJob({
    required Job job,
    required String documentType,
    String? customFileName,
  }) {
    final currentAttachments = List<String>.from(job.attachments ?? []);
    
    final fileName = customFileName ?? generateDocumentName(
      documentType: documentType,
      job: job,
      existingAttachments: currentAttachments,
    );
    
    // The naming service already adds .pdf extension, so no need to add it again
    currentAttachments.add(fileName);
    return currentAttachments;
  }

  /// Get count of specific document type in job attachments
  int getDocumentTypeCount(Job job, String documentType) {
    final attachments = job.attachments ?? [];
    return DocumentNamingService.countExistingDocuments(documentType, attachments) - 1;
  }

  /// Rename existing attachment with standardized naming
  String renameExistingAttachment({
    required Job job,
    required String oldFileName,
    required String documentType,
  }) {
    // Generate new standardized name (already includes .pdf extension)
    return generateDocumentName(
      documentType: documentType,
      job: job,
      existingAttachments: job.attachments,
    );
  }

  /// Validate and clean filename for file system
  String validateFileName(String fileName) {
    return DocumentNamingService.validateFileName(fileName);
  }

  /// Get list of all supported document types
  List<String> getSupportedDocumentTypes() {
    return DocumentNamingService.getSupportedDocumentTypes();
  }
}
