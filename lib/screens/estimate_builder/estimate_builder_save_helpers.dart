part of '../estimate_builder_screen.dart';

extension _EstimateBuilderSaveHelpersExt on _EstimateBuilderScreenState {
  void _saveEstimate() async {
    try {
      widget.job.estimateItems
        ..clear()
        ..addAll(items.map((e) => estimate_item.EstimateItem(
              name: e.name,
              description: e.description,
              unitPrice: e.unitPrice,
              quantity: e.quantity,
              purchasePrice: e.purchasePrice,
              section: e.section,
            )));

      final saved = await _saveInProgressEstimate();
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Build saved successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to save build. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save build: $e')),
      );
    }
  }
}
