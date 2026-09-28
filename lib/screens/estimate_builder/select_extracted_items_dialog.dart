import 'package:flutter/material.dart';

/// Dialog that lets the user pick which AI-extracted items to import,
/// optionally editing quantities before adding them.
class SelectExtractedItemsDialogMulti extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final bool showQuantity;
  const SelectExtractedItemsDialogMulti({
    super.key,
    required this.items,
    this.showQuantity = false,
  });

  @override
  State<SelectExtractedItemsDialogMulti> createState() =>
      _SelectExtractedItemsDialogMultiState();
}

class _SelectExtractedItemsDialogMultiState
    extends State<SelectExtractedItemsDialogMulti> {
  late List<bool> _selected;
  late List<TextEditingController> _qtyControllers;

  @override
  void initState() {
    super.initState();
    _selected = List<bool>.filled(widget.items.length, true);
    _qtyControllers = widget.items
        .map((item) =>
            TextEditingController(text: (item['quantity'] ?? 1).toString()))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Items'),
      content: SizedBox(
        width: 350,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final item = widget.items[i];
            return CheckboxListTile(
              value: _selected[i],
              onChanged: (val) => setState(() => _selected[i] = val ?? false),
              title: Text(item['item_name'] ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${item['id_number'] ?? ''}'),
                  if (widget.showQuantity)
                    Row(
                      children: [
                        const Text('Qty: '),
                        SizedBox(
                          width: 50,
                          child: TextField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: _qtyControllers[i],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 4),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              setState(() {
                                if (parsed != null && parsed > 0) {
                                  _qtyControllers[i].text = parsed.toString();
                                } else {
                                  _qtyControllers[i].text = '1';
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final selectedItems = <Map<String, dynamic>>[];
            for (int i = 0; i < widget.items.length; i++) {
              if (_selected[i]) {
                final item = widget.items[i];
                final qty = int.tryParse(_qtyControllers[i].text) ?? 1;
                selectedItems.add({
                  'id_number': item['id_number'],
                  'item_name': item['item_name'],
                  'quantity': qty,
                });
              }
            }
            Navigator.pop(context, selectedItems);
          },
          child: const Text('Add Selected'),
        ),
      ],
    );
  }
}
