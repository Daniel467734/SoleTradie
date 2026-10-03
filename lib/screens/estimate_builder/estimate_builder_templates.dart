part of '../estimate_builder_screen.dart';

extension _EstimateBuilderTemplatesExt on _EstimateBuilderScreenState {
  Future<void> _showTemplateSelector() async {
    final buildTemplates = _templates.where((t) => t.type == 'build').toList();
    if (buildTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No build templates available.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Template'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: buildTemplates.length,
              itemBuilder: (context, index) {
                final template = buildTemplates[index];
                return ListTile(
                  title: Text(template.name),
                  subtitle: Text('${template.subsections.length} subsections'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _applyTemplate(template);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Applied template: ${template.name}')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _templates.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('estimate_templates', jsonList);
  }
}
