part of '../estimate_builder_screen.dart';

extension _EstimateBuilderSubsectionDialogsExt on _EstimateBuilderScreenState {
  void _confirmDeleteSubsection(SubsectionData section) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subsection'),
        content: Text(
          'Are you sure you want to delete the subsection "${section.name}"? '
          'All items in this section will also be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      _deleteSubsection(section);
    }
  }
}
