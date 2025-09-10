import 'estimate_item.dart';

class EstimateTemplate {
  final String name;
  final List<EstimateItem> items;
  final List<String> subsections;

  EstimateTemplate({required this.name, required this.items, required this.subsections});

  Map<String, dynamic> toJson() => {
    'name': name,
    'items': items.map((e) => e.toJson()).toList(),
    'subsections': subsections,
  };

  factory EstimateTemplate.fromJson(Map<String, dynamic> json) => EstimateTemplate(
    name: json['name'],
    items: (json['items'] as List?)?.map((item) => EstimateItem.fromJson(item as Map<String, dynamic>)).toList() ?? [],
    subsections: List<String>.from(json['subsections'] ?? []),
  );
}