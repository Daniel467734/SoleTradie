import 'package:flutter/material.dart';
import 'estimate_builder_screen.dart';

class TemplatePickerScreen extends StatelessWidget {
  final dynamic job;

  const TemplatePickerScreen({
    super.key,
    required this.job,
  });

  @override
  Widget build(BuildContext context) {
    // Sample templates - replace with your actual templates
    final templates = [
      {'name': 'Black Template', 'items': []},
    
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Template'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Choose a template to start your new build',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Icon(
                        Icons.description,
                        color: Colors.blue[700],
                      ),
                    ),
                    title: Text(
                      template['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${(template['items'] as List).length} items'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      // Navigate directly to EstimateBuilderScreen with the selected template
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EstimateBuilderScreen(
                            job: job,
                            initialItems: const [], // Use empty list for now
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // Add empty template option
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Start with empty template
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EstimateBuilderScreen(
                        job: job,
                        initialItems: const [],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Start from Scratch'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}