import 'package:flutter/material.dart';
import '../models/template_preference.dart';
import '../templates/pdf_receipt_templates.dart';

class EnhancedTemplatePickerDialog extends StatefulWidget {
  final List<PdfReceiptTemplate> templates;
  final List<PdfReceiptTemplate> topTemplates;
  final Map<String, TemplatePreference> templatePrefs;
  final Function(String templateName, int rating) onPreferenceChanged;

  const EnhancedTemplatePickerDialog({
    super.key,
    required this.templates,
    required this.topTemplates,
    required this.templatePrefs,
    required this.onPreferenceChanged,
  });

  @override
  State<EnhancedTemplatePickerDialog> createState() => _EnhancedTemplatePickerDialogState();
}

class _EnhancedTemplatePickerDialogState extends State<EnhancedTemplatePickerDialog> {
  String searchQuery = '';
  bool showAll = false;

  @override
  Widget build(BuildContext context) {
    final displayTemplates = showAll 
        ? widget.templates.where((t) => 
            t.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
            t.description.toLowerCase().contains(searchQuery.toLowerCase())
          ).toList()
        : widget.topTemplates;

    return AlertDialog(
      title: const Text('Select PDF Receipt Template'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            if (showAll) ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search templates',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => searchQuery = value),
              ),
              const SizedBox(height: 8),
            ],
            
            // Top 5 or Search Results
            if (!showAll) ...[
              const Text(
                'Top 5 Templates',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
            ],
            
            Expanded(
              child: ListView.builder(
                itemCount: displayTemplates.length,
                itemBuilder: (context, index) {
                  final template = displayTemplates[index];
                  final pref = widget.templatePrefs[template.name];
                  final starRating = pref?.starRating ?? 0;
                  final usageCount = pref?.usageCount ?? 0;
                  
                  return Card(
                    child: ListTile(
                      title: Text(template.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(template.description),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Star rating display and setter
                              ...List.generate(5, (starIndex) {
                                return GestureDetector(
                                  onTap: () {
                                    final newRating = starIndex + 1;
                                    widget.onPreferenceChanged(template.name, newRating);
                                    setState(() {});
                                  },
                                  child: Icon(
                                    starIndex < starRating ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                );
                              }),
                              const SizedBox(width: 8),
                              if (usageCount > 0)
                                Text(
                                  'Used $usageCount time${usageCount != 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () {
                        // Update usage and last used
                        final existingPref = widget.templatePrefs[template.name];
                        final updatedPref = TemplatePreference(
                          templateName: template.name,
                          starRating: existingPref?.starRating ?? 0,
                          lastUsed: DateTime.now(),
                          usageCount: (existingPref?.usageCount ?? 0) + 1,
                        );
                        widget.templatePrefs[template.name] = updatedPref;
                        
                        Navigator.pop(context, template);
                      },
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 8),
            if (!showAll && widget.templates.length > 5)
              ElevatedButton(
                onPressed: () => setState(() => showAll = true),
                child: Text('Show All ${widget.templates.length} Templates'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
