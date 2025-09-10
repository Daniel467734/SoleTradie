import 'package:flutter/material.dart';

class QuickAddWidget extends StatelessWidget {
  final Function(String type) onQuickAdd;
  
  const QuickAddWidget({super.key, required this.onQuickAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Add',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _QuickAddChip(
                  label: 'Labour',
                  icon: Icons.person,
                  onTap: () => onQuickAdd('labour'),
                ),
                _QuickAddChip(
                  label: 'Materials',
                  icon: Icons.build,
                  onTap: () => onQuickAdd('materials'),
                ),
                _QuickAddChip(
                  label: 'Call Out',
                  icon: Icons.directions_car,
                  onTap: () => onQuickAdd('callout'),
                ),
                _QuickAddChip(
                  label: 'Discount',
                  icon: Icons.percent,
                  onTap: () => onQuickAdd('discount'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAddChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
