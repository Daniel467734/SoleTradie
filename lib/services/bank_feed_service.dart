import 'dart:io';
import 'package:csv/csv.dart';
import '../models/bank_transaction.dart';
import '../models/invoice.dart';
import '../models/job.dart';

enum BankFileFormat {
  csv,
  ofx,
  qif,
  txt,
  unknown
}

class BankFeedService {
  /// Detect file format based on content and extension
  static BankFileFormat detectFileFormat(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'csv':
        return BankFileFormat.csv;
      case 'ofx':
      case 'qfx':
        return BankFileFormat.ofx;
      case 'qif':
        return BankFileFormat.qif;
      case 'txt':
        return BankFileFormat.txt;
      default:
        return BankFileFormat.unknown;
    }
  }

  /// Parse bank file and extract transactions
  static Future<List<BankTransaction>> parseFile(File file) async {
    final format = detectFileFormat(file);
    
    switch (format) {
      case BankFileFormat.csv:
        return _parseCSV(file);
      case BankFileFormat.ofx:
        return _parseOFX(file);
      case BankFileFormat.qif:
        return _parseQIF(file);
      case BankFileFormat.txt:
        return _parseCSV(file); // Try CSV parsing for TXT files
      default:
        throw Exception('Unsupported file format: ${file.path.split('.').last}');
    }
  }

  /// Parse CSV files (most common format)
  static Future<List<BankTransaction>> _parseCSV(File file) async {
    try {
      final content = await file.readAsString();
      final lines = const CsvToListConverter().convert(content);
      
      if (lines.isEmpty) return [];
      
      // Try to detect column structure
      final headers = lines.first.map((e) => e.toString().toLowerCase()).toList();
      final dateColumn = _findColumn(headers, ['date', 'transaction date', 'posted date', 'value date']);
      final descriptionColumn = _findColumn(headers, ['description', 'narrative', 'details', 'memo', 'reference']);
      final amountColumn = _findColumn(headers, ['amount', 'value', 'transaction amount', 'debit amount', 'credit amount']);
      final creditColumn = _findColumn(headers, ['credit', 'credit amount', 'deposits']);
      final debitColumn = _findColumn(headers, ['debit', 'debit amount', 'withdrawals']);
      
      final transactions = <BankTransaction>[];
      
      // Skip header row
      for (int i = 1; i < lines.length; i++) {
        final row = lines[i];
        if (row.length < headers.length) continue;
        
        try {
          final dateStr = _safeGetCell(row, dateColumn);
          final description = _safeGetCell(row, descriptionColumn);
          
          // Handle amount - could be single column or credit/debit columns
          double amount = 0.0;
          if (amountColumn != -1) {
            amount = _parseAmount(_safeGetCell(row, amountColumn));
          } else if (creditColumn != -1 && debitColumn != -1) {
            final credit = _parseAmount(_safeGetCell(row, creditColumn));
            final debit = _parseAmount(_safeGetCell(row, debitColumn));
            amount = credit - debit; // Positive for credits, negative for debits
          }
          
          final date = _parseDate(dateStr);
          
          if (date != null && description.isNotEmpty && amount != 0) {
            transactions.add(BankTransaction(
              id: 'import_${DateTime.now().millisecondsSinceEpoch}_$i',
              date: date,
              description: description,
              amount: amount,
              balance: null, // Will be calculated if needed
              reference: _safeGetCell(row, _findColumn(headers, ['reference', 'ref', 'transaction id'])),
              category: null,
              isReconciled: false,
              matchedInvoiceId: null,
            ));
          }
        } catch (e) {
          // Skip invalid rows
          continue;
        }
      }
      
      return transactions;
    } catch (e) {
      throw Exception('Failed to parse CSV file: $e');
    }
  }

  /// Parse OFX files (Open Financial Exchange)
  static Future<List<BankTransaction>> _parseOFX(File file) async {
    try {
      final content = await file.readAsString();
      final transactions = <BankTransaction>[];
      
      // Simple OFX parsing - look for STMTTRN blocks
      final transactionBlocks = content.split('<STMTTRN>');
      
      for (int i = 1; i < transactionBlocks.length; i++) {
        final block = transactionBlocks[i];
        final endIndex = block.indexOf('</STMTTRN>');
        if (endIndex == -1) continue;
        
        final transactionData = block.substring(0, endIndex);
        
        try {
          final id = _extractOFXValue(transactionData, 'FITID');
          final dateStr = _extractOFXValue(transactionData, 'DTPOSTED');
          final amount = _parseAmount(_extractOFXValue(transactionData, 'TRNAMT'));
          final name = _extractOFXValue(transactionData, 'NAME');
          final memo = _extractOFXValue(transactionData, 'MEMO');
          
          final description = memo.isNotEmpty ? '$name - $memo' : name;
          final date = _parseOFXDate(dateStr);
          
          if (date != null && description.isNotEmpty) {
            transactions.add(BankTransaction(
              id: id.isNotEmpty ? id : 'ofx_${DateTime.now().millisecondsSinceEpoch}_$i',
              date: date,
              description: description,
              amount: amount,
              balance: null,
              reference: id,
              category: null,
              isReconciled: false,
              matchedInvoiceId: null,
            ));
          }
        } catch (e) {
          continue;
        }
      }
      
      return transactions;
    } catch (e) {
      throw Exception('Failed to parse OFX file: $e');
    }
  }

  /// Parse QIF files (Quicken Interchange Format)
  static Future<List<BankTransaction>> _parseQIF(File file) async {
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');
      final transactions = <BankTransaction>[];
      
      Map<String, String> currentTransaction = {};
      
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        
        if (trimmed == '^') {
          // End of transaction
          if (currentTransaction.isNotEmpty) {
            try {
              final date = _parseDate(currentTransaction['D'] ?? '');
              final amount = _parseAmount(currentTransaction['T'] ?? '0');
              final description = currentTransaction['P'] ?? currentTransaction['M'] ?? '';
              
              if (date != null && description.isNotEmpty) {
                transactions.add(BankTransaction(
                  id: 'qif_${DateTime.now().millisecondsSinceEpoch}_${transactions.length}',
                  date: date,
                  description: description,
                  amount: amount,
                  balance: null,
                  reference: currentTransaction['N'] ?? '',
                  category: currentTransaction['L'],
                  isReconciled: false,
                  matchedInvoiceId: null,
                ));
              }
            } catch (e) {
              // Skip invalid transaction
            }
            currentTransaction.clear();
          }
        } else if (trimmed.length > 1) {
          final field = trimmed.substring(0, 1);
          final value = trimmed.substring(1);
          currentTransaction[field] = value;
        }
      }
      
      return transactions;
    } catch (e) {
      throw Exception('Failed to parse QIF file: $e');
    }
  }

  /// Auto-match transactions to invoices
  static Future<List<TransactionMatch>> matchTransactionsToInvoices(
    List<BankTransaction> transactions,
    List<Job> jobs,
  ) async {
    final matches = <TransactionMatch>[];
    final allInvoices = <InvoiceForMatching>[];
    
    // Collect all invoices from jobs
    for (final job in jobs) {
      // Add Invoice objects
      for (final invoice in job.invoices) {
        allInvoices.add(InvoiceForMatching(
          id: invoice.id,
          total: invoice.total,
          isPaid: invoice.isPaid,
          dueDate: invoice.dueDate,
          customerName: job.customerName ?? 'Unknown Customer',
        ));
      }
      
      // Add EstimateVersion invoices
      for (final version in job.estimateVersions) {
        if (version.type == 'invoice') {
          allInvoices.add(InvoiceForMatching(
            id: version.id ?? 'est_${version.hashCode}',
            total: version.amount,
            isPaid: version.isPaid,
            dueDate: version.dueDate,
            customerName: job.customerName ?? 'Unknown Customer',
          ));
        }
      }
    }
    
    for (final transaction in transactions) {
      // Skip negative amounts (outgoing payments)
      if (transaction.amount <= 0) continue;
      
      for (final invoice in allInvoices) {
        if (invoice.isPaid) continue; // Skip already paid invoices
        
        final confidence = _calculateMatchConfidence(transaction, invoice);
        
        if (confidence > 0.7) { // High confidence threshold
          matches.add(TransactionMatch(
            transaction: transaction,
            invoice: invoice,
            confidence: confidence,
            matchType: confidence > 0.9 ? MatchType.automatic : MatchType.suggested,
          ));
          break; // One transaction per invoice
        }
      }
    }
    
    return matches;
  }

  /// Calculate match confidence between transaction and invoice
  static double _calculateMatchConfidence(BankTransaction transaction, InvoiceForMatching invoice) {
    double confidence = 0.0;
    
    // Amount matching (most important)
    final amountDiff = (transaction.amount - invoice.total).abs();
    final amountTolerance = invoice.total * 0.02; // 2% tolerance
    
    if (amountDiff == 0) {
      confidence += 0.6; // Perfect amount match
    } else if (amountDiff <= amountTolerance) {
      confidence += 0.4; // Close amount match
    } else if (amountDiff <= invoice.total * 0.1) {
      confidence += 0.2; // Reasonable amount match
    }
    
    // Customer name matching
    final customerName = invoice.customerName.toLowerCase();
    final description = transaction.description.toLowerCase();
    
    if (description.contains(customerName) || customerName.split(' ').any((word) => description.contains(word))) {
      confidence += 0.3;
    }
    
    // Invoice number matching
    if (description.contains(invoice.id.toLowerCase())) {
      confidence += 0.2;
    }
    
    // Date proximity (within 30 days of due date)
    if (invoice.dueDate != null) {
      final daysDiff = transaction.date.difference(invoice.dueDate!).inDays.abs();
      if (daysDiff <= 7) {
        confidence += 0.1;
      } else if (daysDiff <= 30) {
        confidence += 0.05;
      }
    }
    
    return confidence.clamp(0.0, 1.0);
  }

  /// Apply matches to invoices
  static Future<void> applyMatches(List<TransactionMatch> matches, List<Job> jobs) async {
    for (final match in matches) {
      if (match.matchType == MatchType.automatic || match.isApproved) {
        // Mark transaction as reconciled
        match.transaction.isReconciled = true;
        match.transaction.matchedInvoiceId = match.invoice.id;
        
        // Find and update the actual invoice in the jobs
        for (final job in jobs) {
          // Check Invoice objects
          for (int i = 0; i < job.invoices.length; i++) {
            if (job.invoices[i].id == match.invoice.id) {
              job.invoices[i] = job.invoices[i].copyWith(isPaid: true);
              break;
            }
          }
          
          // Check EstimateVersion invoices
          for (final version in job.estimateVersions) {
            if ((version.id ?? 'est_${version.hashCode}') == match.invoice.id) {
              version.isPaid = true;
              break;
            }
          }
        }
      }
    }
  }

  // Helper methods
  static int _findColumn(List<String> headers, List<String> searchTerms) {
    for (int i = 0; i < headers.length; i++) {
      for (final term in searchTerms) {
        if (headers[i].contains(term)) {
          return i;
        }
      }
    }
    return -1;
  }

  static String _safeGetCell(List<dynamic> row, int index) {
    if (index == -1 || index >= row.length) return '';
    return row[index]?.toString() ?? '';
  }

  static double _parseAmount(String amountStr) {
    if (amountStr.isEmpty) return 0.0;
    
    // Remove currency symbols and spaces
    final cleaned = amountStr
        .replaceAll(RegExp(r'[^\d.-]'), '')
        .replaceAll(',', '');
    
    return double.tryParse(cleaned) ?? 0.0;
  }

  static DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    
    // Try common date formats
    final formats = [
      RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})'), // MM/DD/YYYY or DD/MM/YYYY
      RegExp(r'(\d{4})-(\d{2})-(\d{2})'), // YYYY-MM-DD
      RegExp(r'(\d{2})-(\d{2})-(\d{4})'), // DD-MM-YYYY
    ];
    
    for (final format in formats) {
      final match = format.firstMatch(dateStr);
      if (match != null) {
        try {
          final groups = match.groups([1, 2, 3]);
          if (groups.every((g) => g != null)) {
            // Try different interpretations
            final parts = groups.map((g) => int.parse(g!)).toList();
            
            // If first part is 4 digits, it's year first
            if (parts[0] > 31) {
              return DateTime(parts[0], parts[1], parts[2]);
            } else if (parts[2] > 31) {
              // Year is last
              return DateTime(parts[2], parts[0], parts[1]); // MM/DD/YYYY
            }
          }
        } catch (e) {
          continue;
        }
      }
    }
    
    // Fallback to DateTime.tryParse
    return DateTime.tryParse(dateStr);
  }

  static DateTime? _parseOFXDate(String dateStr) {
    if (dateStr.length >= 8) {
      try {
        final year = int.parse(dateStr.substring(0, 4));
        final month = int.parse(dateStr.substring(4, 6));
        final day = int.parse(dateStr.substring(6, 8));
        return DateTime(year, month, day);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  static String _extractOFXValue(String data, String tag) {
    final startTag = '<$tag>';
    final endTag = '</$tag>';
    
    final startIndex = data.indexOf(startTag);
    if (startIndex == -1) return '';
    
    final valueStart = startIndex + startTag.length;
    final endIndex = data.indexOf(endTag, valueStart);
    
    if (endIndex == -1) {
      // Try without end tag (some OFX files don't use closing tags)
      final nextTagIndex = data.indexOf('<', valueStart);
      if (nextTagIndex == -1) {
        return data.substring(valueStart).trim();
      } else {
        return data.substring(valueStart, nextTagIndex).trim();
      }
    }
    
    return data.substring(valueStart, endIndex).trim();
  }
}
