import 'package:flutter/material.dart';
import 'estimate_version.dart';

class Certificate {
  final String id;
  final String jobId;
  final String certificateType; // 'COC', 'ESC', 'ROI', 'Gas COC', etc.
  final String certificateNumber;
  final String jobTitle;
  final String customerName;
  final String customerAddress;
  final DateTime dateCreated;
  final DateTime? dateIssued;
  final String? filePath;
  final String status; // 'draft', 'issued', 'completed'
  final String? notes;
  final Map<String, dynamic>? certificateData; // Specific data for each certificate type
  
  Certificate({
    required this.id,
    required this.jobId,
    required this.certificateType,
    required this.certificateNumber,
    required this.jobTitle,
    required this.customerName,
    required this.customerAddress,
    required this.dateCreated,
    this.dateIssued,
    this.filePath,
    required this.status,
    this.notes,
    this.certificateData,
  });

  factory Certificate.fromEstimateVersion({
    required String jobId,
    required String jobTitle,
    required String customerName,
    required String customerAddress,
    required EstimateVersion estimateVersion,
  }) {
    // Extract certificate type from invoice number (e.g., "COC-001" -> "COC")
    final certType = estimateVersion.invoiceNumber?.split('-').first ?? 'Unknown';
    
    return Certificate(
      id: estimateVersion.id ?? '',
      jobId: jobId,
      certificateType: certType,
      certificateNumber: estimateVersion.invoiceNumber ?? '',
      jobTitle: jobTitle,
      customerName: customerName,
      customerAddress: customerAddress,
      dateCreated: estimateVersion.timestamp ?? DateTime.now(),
      dateIssued: estimateVersion.status == 'final' ? estimateVersion.timestamp : null,
      filePath: estimateVersion.filePath,
      status: _mapEstimateStatusToCertificateStatus(estimateVersion.status),
      notes: estimateVersion.items.isNotEmpty ? estimateVersion.items.first.description : null,
      certificateData: null, // Could be extended with more specific data
    );
  }

  static String _mapEstimateStatusToCertificateStatus(String? estimateStatus) {
    switch (estimateStatus) {
      case 'final':
        return 'issued';
      case 'in_progress':
        return 'draft';
      default:
        return 'draft';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'certificateType': certificateType,
        'certificateNumber': certificateNumber,
        'jobTitle': jobTitle,
        'customerName': customerName,
        'customerAddress': customerAddress,
        'dateCreated': dateCreated.toIso8601String(),
        'dateIssued': dateIssued?.toIso8601String(),
        'filePath': filePath,
        'status': status,
        'notes': notes,
        'certificateData': certificateData,
      };

  factory Certificate.fromJson(Map<String, dynamic> json) => Certificate(
        id: json['id'],
        jobId: json['jobId'],
        certificateType: json['certificateType'],
        certificateNumber: json['certificateNumber'],
        jobTitle: json['jobTitle'],
        customerName: json['customerName'],
        customerAddress: json['customerAddress'],
        dateCreated: DateTime.parse(json['dateCreated']),
        dateIssued: json['dateIssued'] != null ? DateTime.parse(json['dateIssued']) : null,
        filePath: json['filePath'],
        status: json['status'],
        notes: json['notes'],
        certificateData: json['certificateData'],
      );

  Certificate copyWith({
    String? id,
    String? jobId,
    String? certificateType,
    String? certificateNumber,
    String? jobTitle,
    String? customerName,
    String? customerAddress,
    DateTime? dateCreated,
    DateTime? dateIssued,
    String? filePath,
    String? status,
    String? notes,
    Map<String, dynamic>? certificateData,
  }) {
    return Certificate(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      certificateType: certificateType ?? this.certificateType,
      certificateNumber: certificateNumber ?? this.certificateNumber,
      jobTitle: jobTitle ?? this.jobTitle,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      dateCreated: dateCreated ?? this.dateCreated,
      dateIssued: dateIssued ?? this.dateIssued,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      certificateData: certificateData ?? this.certificateData,
    );
  }

  // Helper getters
  String get statusDisplayName {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'issued':
        return 'Issued';
      case 'completed':
        return 'Completed';
      default:
        return status.toUpperCase();
    }
  }

  Color get statusColor {
    switch (status) {
      case 'draft':
        return Colors.orange;
      case 'issued':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  bool get isIssued => status == 'issued' || status == 'completed';
  bool get hasPdf => filePath != null && filePath!.isNotEmpty;
}
