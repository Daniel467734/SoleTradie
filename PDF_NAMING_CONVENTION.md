# PDF Document Naming Convention

## Overview
This document describes the standardized PDF naming convention implemented across all document types in the app.

## Naming Format
```
[Document Type] [Job Site Address] [Job Number] [(count)].pdf
```

For estimates and quotes, the attachment naming now uses a date-based format:
```
[YYYY-MM-DD] [Estimate|Quote] [sequence].pdf
```

### Components:
1. **Document Type**: Standardized type name (Invoice, Estimate, Quote, ESC, COC, Gas COC, ROI)
2. **Job Site Address**: Cleaned job site address (invalid characters removed, length limited)
3. **Job Number**: Job ID from the system
4. **Count**: Added only when multiple documents of the same type exist (2, 3, 4, etc.)
5. **Extension**: Always ends with `.pdf` to indicate file type

## Examples

### Single Documents
- `Invoice 22B Campbell Ave 3664566345.pdf`
- `2026-07-01 Estimate 1.pdf`
- `2026-07-01 Quote 1.pdf`
- `ESC 15 High Street 98765432.pdf`
- `COC 10 Main Road 11111111.pdf`
- `Gas COC 5 Queen Street 12345678.pdf`
- `ROI 8 Park Avenue 99887766.pdf`

### Multiple Documents (with count)
- `Invoice 22B Campbell Ave 3664566345 (2).pdf` ← Second invoice for this job
- `2026-07-01 Estimate 2.pdf` ← Second estimate for this job or date
- `2026-07-01 Quote 2.pdf` ← Second quote for this job or date
- `ESC 15 High Street 98765432 (2).pdf` ← Second ESC for this job

## Supported Document Types

| Type | Full Name | Example |
|------|-----------|---------|
| **Invoice** | Invoice | `Invoice 22B Campbell Ave 3664566345.pdf` |
| **Estimate** | Estimate | `Estimate 19A Mamaku Street 44555343.pdf` |
| **Quote** | Quote/Quotation | `Quote 15 High Street 98765432.pdf` |
| **ESC** | Electrical Safety Certificate | `ESC 10 Main Road 11111111.pdf` |
| **COC** | Certificate of Compliance | `COC 5 Queen Street 12345678.pdf` |
| **Gas COC** | Gas Certificate of Compliance | `Gas COC 8 Park Avenue 99887766.pdf` |
| **ROI** | Record of Inspection | `ROI 12 River Road 55443322.pdf` |

## Implementation

### 1. Core Service
The `DocumentNamingService` class provides the core functionality:

```dart
import '../services/document_naming_service.dart';

// Generate filename
final fileName = DocumentNamingService.generatePdfFileName(
  documentType: 'Invoice',
  job: job,
  existingAttachments: job.attachments,
);
```

### 2. Mixin for Easy Integration
The `DocumentNamingMixin` provides convenient methods:

```dart
import '../mixins/document_naming_mixin.dart';

class MyFormScreen extends StatefulWidget with DocumentNamingMixin {
  // Generate specific document types
  final invoiceName = generateInvoiceName(job);
  final estimateName = generateEstimateName(job);
  final escName = generateEscName(job);
  final cocName = generateCocName(job);
  final gasCocName = generateGasCocName(job);
  final roiName = generateRoiName(job);
}
```

### 3. Updated Screens
The following screens have been updated to use the new naming convention:

- **COC Form Screen** (`coc_form_screen.dart`) - Generates COC documents
- **ESC Form Screen** (`esc_form_screen.dart`) - Generates ESC documents  
- **ROI Form Screen** (`roi_form_screen.dart`) - Generates ROI documents
- **Gas COC Form Screen** (`gas_coc_form_screen.dart`) - Generates Gas COC documents
- **Estimate Builder Screen** (`estimate_builder_screen.dart`) - Generates estimates, quotes, and invoices

## Address Cleaning

The system automatically cleans addresses for filename compatibility:

### Cleaning Rules:
1. **Invalid Characters Removed**: `< > : " / \ | ? *`
2. **Whitespace Normalized**: Multiple spaces become single spaces
3. **Length Limited**: Maximum 50 characters (breaks at word boundaries when possible)
4. **Fallback**: Uses "Unknown Address" if address is empty

### Examples:
- `22B Campbell Ave, Auckland` → `22B Campbell Ave, Auckland`
- `19A Mamaku Street/Unit 2` → `19A Mamaku Street Unit 2`
- `Very Long Address Name That Exceeds Fifty Characters...` → `Very Long Address Name That Exceeds Fifty`

## Count Logic

The automatic numbering system:

1. **Scans existing attachments** for documents of the same type
2. **Counts matches** by checking if filename starts with document type
3. **Increments count** for the new document
4. **Omits count** if it's the first document of that type

### Example Progression:
1. First invoice: `Invoice 22B Campbell Ave 3664566345.pdf`
2. Second invoice: `Invoice 22B Campbell Ave 3664566345 (2).pdf`
3. Third invoice: `Invoice 22B Campbell Ave 3664566345 (3).pdf`

## File System Compatibility

The generated names are compatible with all major file systems:

- **Windows**: No reserved characters or names
- **macOS**: HFS+ and APFS compatible
- **Linux**: ext4 and other filesystems
- **Length**: Under 255 character limit
- **Unicode**: Basic ASCII characters only

## Benefits

### 1. **Consistency**
- All PDFs follow the same naming pattern
- Easy to identify document type and job at a glance
- Professional appearance

### 2. **Organization**
- Documents sort naturally by type and address
- No more timestamp-based random names
- Clear relationship between documents and jobs

### 3. **User-Friendly**
- Meaningful names instead of random strings
- Easy to find specific documents
- Professional when sharing with customers

### 4. **Automatic**
- No manual naming required
- Handles duplicates automatically
- Maintains uniqueness

## Migration Notes

### Existing Files
- Old naming convention files remain unchanged
- New documents use the new convention
- No breaking changes to existing functionality

### CSV Customer Import
- CSV customer books won't use address search (as requested)
- Standard naming convention still applies to generated documents
- Address data comes from imported CSV rather than API search

## Testing

A demo app (`test_document_naming.dart`) is provided to demonstrate:
- Various naming scenarios
- Multiple document types
- Count increment behavior
- Address cleaning examples

Run with: `flutter run test_document_naming.dart`

## Support

For questions or issues with the naming convention:
1. Check existing job attachments for conflicts
2. Verify job has valid address and ID
3. Test with the demo app for expected behavior
4. Review cleaning rules for address formatting issues
