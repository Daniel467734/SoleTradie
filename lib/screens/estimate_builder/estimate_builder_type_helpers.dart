part of '../estimate_builder_screen.dart';

extension _EstimateBuilderTypeHelpersExt on _EstimateBuilderScreenState {
  String _buildTypeLabel(String? type) {
    switch (type) {
      case 'invoice':
        return 'Invoice';
      case 'quote':
        return 'Quote';
      case 'estimate':
      default:
        return 'Estimate';
    }
  }

  IconData _buildTypeIcon(String? type) {
    switch (type) {
      case 'invoice':
        return Icons.receipt_long;
      case 'quote':
        return Icons.request_quote;
      case 'estimate':
      default:
        return Icons.description;
    }
  }

  Widget _buildTypeOption(String value, IconData icon, String label) {
    final bool isSelected = value == _buildType;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          if (isSelected) const Icon(Icons.check, color: Colors.green),
        ],
      ),
    );
  }
}
