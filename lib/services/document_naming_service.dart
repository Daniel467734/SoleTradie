import '../models/job.dart';

class DocumentNamingService {
  /// Generate standardized PDF filename with automatic numbering
  /// Format: [Type] [YYMMDD][version] for estimates/quotes, or [Type] [Job Site Address] [Job Number] [(count)] for invoices
  /// Example: "Estimate 2607021" or "Quote 2607022"
  static String generatePdfFileName({
    required String documentType,
    required Job job,
    List<String>? existingAttachments,
    String? documentNumber,
  }) {
    final cleanType = _cleanDocumentType(documentType);
    final attachments = existingAttachments ?? [];

    if (cleanType == 'Estimate' || cleanType == 'Quote') {
      final datePrefix = _formatDate(DateTime.now());
      final sequence = countExistingDocumentsForDate(cleanType, attachments, datePrefix) + 1;
      final fileName = '$cleanType ${datePrefix}${sequence}';
      return _ensurePdfExtension(fileName);
    }

    // Use invoice number when provided for invoice documents
    final identifier =
        (cleanType == 'Invoice' && (documentNumber?.trim().isNotEmpty ?? false))
            ? documentNumber!.trim()
            : job.id;

    // Get job site address (cleaned)
    final address = _cleanAddress(job.address ?? 'Unknown Address');

    // Build base filename
    final baseName = '$cleanType $identifier $address';

    // Count existing documents of the same type
    final count = countExistingDocuments(cleanType, attachments);

    // Add sequence number for ESC and COC documents when there are multiples
    // First document has no label, second gets (1), third gets (2), etc.
    final fileName = (cleanType == 'ESC' || cleanType == 'COC') && count > 0
        ? '$baseName (${count})'
        : (count > 1 ? '$baseName ($count)' : baseName);

    return _ensurePdfExtension(fileName);
  }

  static String _formatDate(DateTime date) {
    final year = (date.year % 100).toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  static String _ensurePdfExtension(String fileName) {
    return fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';
  }

  /// Count existing estimate/quote documents for a specific date prefix
  static int countExistingDocumentsForDate(
      String documentType, List<String> existingAttachments, String datePrefix) {
    int count = 0;
    final typeLower = documentType.toLowerCase();
    final pattern = RegExp(r'^' + RegExp.escape(typeLower) + r'\s+' + RegExp.escape(datePrefix) + r'(\d+)');

    for (final attachment in existingAttachments) {
      final filename =
          attachment.split(RegExp(r'[\\/]+')).last.toLowerCase().trim();
      if (pattern.hasMatch(filename)) {
        count++;
      }
    }

    return count;
  }

  /// Clean and standardize document type names
  static String _cleanDocumentType(String type) {
    final lowercaseType = type.toLowerCase().trim();

    // Standardize document type names
    switch (lowercaseType) {
      case 'invoice':
        return 'Invoice';
      case 'quote':
      case 'quotation':
        return 'Quote';
      case 'estimate':
        return 'Estimate';
      case 'esc':
      case 'electrical safety certificate':
        return 'ESC';
      case 'coc':
      case 'certificate of compliance':
        return 'COC';
      case 'gas coc':
      case 'gas certificate of compliance':
        return 'Gas COC';
      case 'roi':
      case 'record of inspection':
        return 'ROI';
      default:
        // Capitalize first letter for unknown types
        return type.substring(0, 1).toUpperCase() +
            type.substring(1).toLowerCase();
    }
  }

  /// Clean and format address for filename
  static String _cleanAddress(String address) {
    // Remove invalid filename characters
    String cleaned = address
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '') // Remove invalid chars
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();

    // Limit length to prevent overly long filenames
    if (cleaned.length > 50) {
      cleaned = cleaned.substring(0, 50).trim();
      // Try to break at a word boundary
      final lastSpace = cleaned.lastIndexOf(' ');
      if (lastSpace > 30) {
        cleaned = cleaned.substring(0, lastSpace);
      }
    }

    return cleaned.isNotEmpty ? cleaned : 'Unknown Address';
  }

  /// Count existing documents of the same type
  static int countExistingDocuments(
      String documentType, List<String> existingAttachments) {
    int count = 0;
    final documentTypeLower = documentType.toLowerCase();
    final datePrefixedPattern =
        RegExp(r'^\d{4}-\d{2}-\d{2}\s+' + RegExp.escape(documentTypeLower));

    for (final attachment in existingAttachments) {
      final filename =
          attachment.split(RegExp(r'[\\/]+')).last.toLowerCase().trim();
      if (filename.startsWith(documentTypeLower) ||
          datePrefixedPattern.hasMatch(filename)) {
        count++;
      }
    }

    return count;
  }

  /// Extract document type from existing filename
  static String? extractDocumentType(String filename) {
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.(pdf|PDF)$'), '');
    final parts = nameWithoutExt.split(' ');
    if (parts.isNotEmpty) {
      if (parts.length > 1 &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts.first)) {
        return _cleanDocumentType(parts[1]);
      }
      return _cleanDocumentType(parts.first);
    }
    return null;
  }

  /// Generate filename with custom parameters (for flexibility)
  static String generateCustomFileName({
    required String documentType,
    required String address,
    required String jobNumber,
    int? documentCount,
  }) {
    final cleanType = _cleanDocumentType(documentType);
    final cleanAddress = _cleanAddress(address);
    final baseName = '$cleanType $cleanAddress $jobNumber';

    final fileName = (documentCount != null && documentCount > 1)
        ? '$baseName ($documentCount)'
        : baseName;

    // Ensure .pdf extension is added
    return fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';
  }

  /// Validate filename for file system compatibility
  static String validateFileName(String filename) {
    // Ensure filename is safe for all file systems
    String safe = filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '') // Remove invalid chars
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();

    // Ensure it's not too long (most file systems support 255 chars)
    if (safe.length > 200) {
      safe = safe.substring(0, 200).trim();
    }

    // Ensure it doesn't end with a period or space
    safe = safe.replaceAll(RegExp(r'[. ]+$'), '');

    // Ensure .pdf extension
    if (!safe.toLowerCase().endsWith('.pdf')) {
      safe = '$safe.pdf';
    }

    return safe.isNotEmpty ? safe : 'Document.pdf';
  }

  /// Get all supported document types
  static List<String> getSupportedDocumentTypes() {
    return [
      'Invoice',
      'Quote',
      'Estimate',
      'ESC',
      'COC',
      'Gas COC',
      'ROI',
    ];
  }

  /// Parse existing filename to extract components
  static Map<String, String?> parseFileName(String filename) {
    // Remove extension if present
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.(pdf|PDF)$'), '');

    final parts = nameWithoutExt.split(' ');

    if (parts.isEmpty) {
      return {'type': null, 'address': null, 'jobNumber': null, 'count': null};
    }

    String? type = parts.first;
    String? count;

    // Extract count if present (e.g., "(2)")
    final countMatch = RegExp(r'\((\d+)\)$').firstMatch(nameWithoutExt);
    if (countMatch != null) {
      count = countMatch.group(1);
      // Remove count from parts for further processing
      final withoutCount =
          nameWithoutExt.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
      parts.clear();
      parts.addAll(withoutCount.split(' '));
    }

    // Try to extract job number (usually the last part that's numeric)
    String? jobNumber;
    String? address;

    if (parts.length > 1) {
      // Find the last part that looks like a job number
      for (int i = parts.length - 1; i >= 1; i--) {
        if (RegExp(r'^\d+').hasMatch(parts[i])) {
          jobNumber = parts[i];
          // Everything between type and job number is address
          if (i > 1) {
            address = parts.sublist(1, i).join(' ');
          }
          break;
        }
      }

      // If no job number found, treat everything after type as address
      if (jobNumber == null && parts.length > 1) {
        address = parts.sublist(1).join(' ');
      }
    }

    return {
      'type': type,
      'address': address,
      'jobNumber': jobNumber,
      'count': count,
    };
  }
}
