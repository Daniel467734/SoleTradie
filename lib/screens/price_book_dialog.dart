import 'package:flutter/material.dart';

class PriceBookItem {
  final String name;
  final String code;
  final double price;
  final double? purchasePrice;
  final String? barcode;

  PriceBookItem({
    required this.name,
    required this.code,
    required this.price,
    this.purchasePrice,
    this.barcode,
  });
}

class PriceBookDialog extends StatefulWidget {
  final List<PriceBookItem> items;
  final void Function(PriceBookItem selected) onItemSelected;

  const PriceBookDialog({
    super.key,
    required this.items,
    required this.onItemSelected,
  });

  @override
  State<PriceBookDialog> createState() => _PriceBookDialogState();
}

class _PriceBookDialogState extends State<PriceBookDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((item) =>
            item.name.toLowerCase().contains(query.toLowerCase()))
        .toList();

    return AlertDialog(
      title: const Text('Select Item from Price Book'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(textCapitalization: TextCapitalization.sentences, 
            decoration: const InputDecoration(hintText: 'Search...'),
            onChanged: (val) => setState(() => query = val),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                return ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                      '${item.code} - \$${item.price.toStringAsFixed(2)}'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onItemSelected(item);
                  },
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}