import '../models/estimate_item.dart';

/// Represents a version within an in-progress build
class InProgressVersion {
  final String id;
  final DateTime createdAt;
  final double totalAmount;
  final double totalProfit;
  final List<EstimateItem> items;
  final List<String> subsections;
  final Map<String, dynamic>? additionalData; // For storing other build state

  InProgressVersion({
    required this.id,
    required this.createdAt,
    required this.totalAmount,
    required this.totalProfit,
    required this.items,
    required this.subsections,
    this.additionalData,
  });

  factory InProgressVersion.fromJson(Map<String, dynamic> json) => InProgressVersion(
    id: json['id'],
    createdAt: DateTime.parse(json['createdAt']),
    totalAmount: (json['totalAmount'] ?? 0).toDouble(),
    totalProfit: (json['totalProfit'] ?? 0).toDouble(),
    items: (json['items'] as List)
        .map((item) => EstimateItem.fromJson(item as Map<String, dynamic>))
        .toList(),
    subsections: (json['subsections'] as List).cast<String>(),
    additionalData: json['additionalData'] as Map<String, dynamic>?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'totalAmount': totalAmount,
    'totalProfit': totalProfit,
    'items': items.map((item) => item.toJson()).toList(),
    'subsections': subsections,
    'additionalData': additionalData,
  };

  /// Create a copy with updated values
  InProgressVersion copyWith({
    String? id,
    DateTime? createdAt,
    double? totalAmount,
    double? totalProfit,
    List<EstimateItem>? items,
    List<String>? subsections,
    Map<String, dynamic>? additionalData,
  }) => InProgressVersion(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    totalAmount: totalAmount ?? this.totalAmount,
    totalProfit: totalProfit ?? this.totalProfit,
    items: items ?? List<EstimateItem>.from(this.items),
    subsections: subsections ?? List<String>.from(this.subsections),
    additionalData: additionalData ?? this.additionalData,
  );
}

/// Represents an in-progress build with versioning support
class InProgressBuild {
  final String id;
  final String jobId;
  final String name; // "In-Progress Build 1", "In-Progress Build 2", etc.
  final DateTime createdAt;
  final DateTime lastModified;
  final String? templateName; // Optional template that created this build
  final List<InProgressVersion> versions;
  final String currentVersionId; // ID of the current/latest version

  InProgressBuild({
    required this.id,
    required this.jobId,
    required this.name,
    required this.createdAt,
    required this.lastModified,
    this.templateName,
    required this.versions,
    required this.currentVersionId,
  });

  /// Get the current/latest version
  InProgressVersion get currentVersion => 
      versions.firstWhere((v) => v.id == currentVersionId);

  /// Get versions sorted by creation date (newest first)
  List<InProgressVersion> get sortedVersions => 
      List<InProgressVersion>.from(versions)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  factory InProgressBuild.fromJson(Map<String, dynamic> json) => InProgressBuild(
    id: json['id'],
    jobId: json['jobId'],
    name: json['name'],
    createdAt: DateTime.parse(json['createdAt']),
    lastModified: DateTime.parse(json['lastModified']),
    templateName: json['templateName'],
    versions: (json['versions'] as List)
        .map((version) => InProgressVersion.fromJson(version as Map<String, dynamic>))
        .toList(),
    currentVersionId: json['currentVersionId'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
    'templateName': templateName,
    'versions': versions.map((version) => version.toJson()).toList(),
    'currentVersionId': currentVersionId,
  };

  /// Create a copy with updated values
  InProgressBuild copyWith({
    String? id,
    String? jobId,
    String? name,
    DateTime? createdAt,
    DateTime? lastModified,
    String? templateName,
    List<InProgressVersion>? versions,
    String? currentVersionId,
  }) => InProgressBuild(
    id: id ?? this.id,
    jobId: jobId ?? this.jobId,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    lastModified: lastModified ?? this.lastModified,
    templateName: templateName ?? this.templateName,
    versions: versions ?? List<InProgressVersion>.from(this.versions),
    currentVersionId: currentVersionId ?? this.currentVersionId,
  );

  /// Add a new version and make it current
  InProgressBuild addVersion(InProgressVersion version) {
    final updatedVersions = List<InProgressVersion>.from(versions)..add(version);
    return copyWith(
      versions: updatedVersions,
      currentVersionId: version.id,
      lastModified: DateTime.now(),
    );
  }

  /// Update the current version
  InProgressBuild updateCurrentVersion(InProgressVersion updatedVersion) {
    final updatedVersions = versions.map((v) => 
        v.id == currentVersionId ? updatedVersion : v).toList();
    return copyWith(
      versions: updatedVersions,
      lastModified: DateTime.now(),
    );
  }

  /// Remove a version (returns null if this was the last version)
  InProgressBuild? removeVersion(String versionId) {
    if (versions.length <= 1) return null; // Don't remove the last version
    
    final updatedVersions = versions.where((v) => v.id != versionId).toList();
    String newCurrentId = currentVersionId;
    
    // If we're removing the current version, make the most recent remaining version current
    if (currentVersionId == versionId) {
      final remainingSorted = List<InProgressVersion>.from(updatedVersions)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      newCurrentId = remainingSorted.first.id;
    }
    
    return copyWith(
      versions: updatedVersions,
      currentVersionId: newCurrentId,
      lastModified: DateTime.now(),
    );
  }

  /// Promote a version to be the latest (gives it a new timestamp)
  InProgressBuild promoteVersionToLatest(String versionId) {
    final versionToPromote = versions.firstWhere((v) => v.id == versionId);
    final promotedVersion = versionToPromote.copyWith(
      createdAt: DateTime.now(),
    );
    
    final updatedVersions = versions.map((v) => 
        v.id == versionId ? promotedVersion : v).toList();
    
    return copyWith(
      versions: updatedVersions,
      currentVersionId: versionId,
      lastModified: DateTime.now(),
    );
  }
}
