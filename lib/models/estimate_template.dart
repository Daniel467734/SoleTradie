import 'estimate_item.dart';

class EstimateTemplate {
  final String name;
  final List<EstimateItem> items;
  final List<String> subsections;
  final String type; // 'build' or 'section'
  final String scopeSummary;
  final String scopeExclusions;
  final String builderNote;
  final List<Map<String, String>> liabilityRisks;

  EstimateTemplate({
    required this.name,
    required this.items,
    required this.subsections,
    this.type = 'build',
    this.scopeSummary = '',
    this.scopeExclusions = '',
    this.builderNote = '',
    this.liabilityRisks = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'items': items.map((e) => e.toJson()).toList(),
        'subsections': subsections,
        'type': type,
        'scopeSummary': scopeSummary,
        'scopeExclusions': scopeExclusions,
        'builderNote': builderNote,
        'liabilityRisks': liabilityRisks,
      };

  factory EstimateTemplate.fromJson(Map<String, dynamic> json) => EstimateTemplate(
        name: json['name'],
        items: (json['items'] as List?)
                ?.map((item) => EstimateItem.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        subsections: List<String>.from(json['subsections'] ?? []),
        type: json['type'] as String? ??
            ((json['subsections'] is List && (json['subsections'] as List).length == 1)
                ? 'section'
                : 'build'),
        scopeSummary: json['scopeSummary'] as String? ?? '',
        scopeExclusions: json['scopeExclusions'] as String? ?? '',
        builderNote: json['builderNote'] as String? ?? '',
        liabilityRisks: (json['liabilityRisks'] as List?)
                ?.map((risk) => Map<String, String>.from(risk as Map))
                .toList() ??
            [],
      );
}