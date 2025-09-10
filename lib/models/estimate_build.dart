import '../models/estimate_item.dart'; // or wherever your main EstimateItem is

class EstimateBuild {
  final String id;
  final String jobId;
  final String name;
  final DateTime savedAt;
  final List<EstimateItem>? items;

  EstimateBuild({
    required this.id,
    required this.jobId,
    required this.name,
    required this.savedAt,
    this.items,
  });

  factory EstimateBuild.fromJson(Map<String, dynamic> json) => EstimateBuild(
        id: json['id'],
        jobId: json['jobId'],
        name: json['name'],
        savedAt: DateTime.parse(json['savedAt']),
        items: json['items'] != null
            ? (json['items'] as List)
                .map((item) => EstimateItem.fromJson(item as Map<String, dynamic>))
                .toList()
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'items': items?.map((item) => item.toJson()).toList(),
      };
}