import 'package:flutter/material.dart';

// --- EditableHeader widget ---
class EditableHeader extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController orderNumberController;
  const EditableHeader({
    required this.nameController,
    required this.addressController,
    required this.orderNumberController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Customer Name'),
        ),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: addressController,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: orderNumberController,
          decoration: const InputDecoration(
            labelText: 'Order Number',
            hintText: 'e.g., ORD-2024-001',
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
