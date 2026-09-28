import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/estimate_item.dart' as estimate_item;
import '../../models/price_book_item.dart' as models;

/// Dialog to add or edit an estimate item.
class AddEstimateItemDialog extends StatefulWidget {
  final List<models.PriceBookItem> priceBook;
  final String initialSection;
  final List<String> availableSections;
  final Future<List<estimate_item.EstimateItem>?> Function(String section,
      {ImageSource source}) onScanReceipt;
  final Future<void> Function() savePriceBook;
  final estimate_item.EstimateItem? initialItem;
  final bool showProfit;

  const AddEstimateItemDialog({
    required this.priceBook,
    required this.initialSection,
    required this.availableSections,
    required this.onScanReceipt,
    required this.savePriceBook,
    this.initialItem,
    this.showProfit = false,
    super.key,
  });

  @override
  State<AddEstimateItemDialog> createState() => _AddEstimateItemDialogState();
}

class _AddEstimateItemDialogState extends State<AddEstimateItemDialog> {
  late TextEditingController nameController;
  late TextEditingController descController;
  late TextEditingController priceController;
  late TextEditingController qtyController;
  late TextEditingController purchasePriceController;
  late TextEditingController markupController;
  late String section;
  bool saveToPriceBook = false;
  bool includesGst = false;
  // 🔴 NEW: Per-meter pricing
  bool isPerMeter = false;
  late TextEditingController meterAmountController;

  String normalizeCode(String? s) => (s ?? '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '')
      .replaceAll('\u200B', '')
      .replaceAll('\uFFFD', '')
      .trim()
      .toLowerCase();

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    nameController = TextEditingController(text: item?.name ?? '');
    descController = TextEditingController(text: item?.description ?? '');
    priceController =
        TextEditingController(text: item?.unitPrice.toString() ?? '');
    qtyController =
        TextEditingController(text: item?.quantity.toString() ?? '1');
    purchasePriceController =
        TextEditingController(text: item?.purchasePrice?.toString() ?? '');
    double markup = 0;
    if (item != null && item.purchasePrice != null && item.purchasePrice! > 0) {
      markup =
          ((item.unitPrice - item.purchasePrice!) / item.purchasePrice! * 100);
    }
    markupController = TextEditingController(text: markup.toStringAsFixed(1));
    section = widget.initialSection;
    // 🔴 NEW: Initialize per-meter fields from existing item
    isPerMeter = item?.isPerMeter ?? false;
    meterAmountController = TextEditingController(
      text: (item?.meterAmount ?? 1.0).toString(),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    descController.dispose();
    priceController.dispose();
    qtyController.dispose();
    purchasePriceController.dispose();
    markupController.dispose();
    meterAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void updateSellPrice() {
      final buy = double.tryParse(purchasePriceController.text) ?? 0;
      final percent = double.tryParse(markupController.text) ?? 0;
      if (buy > 0) {
        priceController.text = (buy * (1 + percent / 100)).toStringAsFixed(2);
      }
    }

    void updateMarkupFromSell() {
      final buy = double.tryParse(purchasePriceController.text) ?? 0;
      final sell = double.tryParse(priceController.text) ?? 0;
      if (buy > 0) {
        final percent = ((sell - buy) / buy * 100);
        markupController.text = percent.toStringAsFixed(1);
      }
    }

    return AlertDialog(
      title: Text(widget.initialItem == null ? 'Add Item' : 'Edit Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: section,
              items: widget.availableSections.map((sec) {
                return DropdownMenuItem<String>(
                  value: sec,
                  child: Text(sec),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    section = val;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Section'),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: descController,
              decoration: const InputDecoration(labelText: 'ID Code'),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: purchasePriceController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Buy Price'),
              onChanged: (val) => updateSellPrice(),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: markupController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Profit %'),
              onChanged: (val) => updateSellPrice(),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Sell Price'),
              onChanged: (val) => updateMarkupFromSell(),
            ),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              controller: qtyController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            // 🔴 NEW: Per-meter pricing
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Charge Per Meter'),
              subtitle:
                  const Text('Price above is for total meters, not per meter'),
              value: isPerMeter,
              onChanged: (val) => setState(() => isPerMeter = val ?? false),
            ),
            if (isPerMeter)
              Padding(
                padding:
                    const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                child: Column(
                  children: [
                    TextField(
                      controller: meterAmountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Total Meters',
                        hintText: 'e.g., 20',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final buyPrice =
                            double.tryParse(purchasePriceController.text) ?? 0;
                        final meters =
                            double.tryParse(meterAmountController.text) ?? 1;
                        final perMeter =
                            meters > 0 ? buyPrice / meters : buyPrice;
                        return Text(
                          'Effective purchase price: \$${perMeter.toStringAsFixed(2)}/meter',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        );
                      },
                    ),
                  ],
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Includes GST'),
              subtitle: const Text(
                  'Entered price includes GST, store the line as ex-GST.'),
              value: includesGst,
              onChanged: (val) => setState(() => includesGst = val ?? false),
            ),
            if (includesGst)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final enteredPrice =
                            double.tryParse(priceController.text.trim()) ?? 0;
                        final enteredPurchase = double.tryParse(
                                purchasePriceController.text.trim()) ??
                            0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (enteredPrice > 0)
                              Text(
                                  'Sell price ex GST: \$${(enteredPrice / 1.15).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                            if (enteredPurchase > 0)
                              Text(
                                  'Buy price ex GST: \$${(enteredPurchase / 1.15).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save manual entry to pricebook'),
              value: saveToPriceBook,
              onChanged: (val) =>
                  setState(() => saveToPriceBook = val ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = nameController.text.trim();
            final desc = descController.text.trim();
            final price = double.tryParse(priceController.text.trim()) ?? 0;
            final qty = double.tryParse(qtyController.text.trim()) ?? 1;
            final purchase =
                double.tryParse(purchasePriceController.text.trim()) ?? 0;

            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Item name is required')),
              );
              return;
            }

            if (saveToPriceBook && desc.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('ID code is required to save to pricebook')),
              );
              return;
            }

            final exGstPrice = includesGst ? price / 1.15 : price;
            final exGstPurchase = includesGst ? purchase / 1.15 : purchase;

            if (saveToPriceBook && desc.isNotEmpty) {
              final existingIndex = widget.priceBook.indexWhere(
                  (pb) => normalizeCode(pb.code) == normalizeCode(desc));
              if (existingIndex != -1) {
                final existing = widget.priceBook[existingIndex];
                final priceActuallyChanged =
                    (exGstPrice - existing.salePrice).abs() >= 0.005 ||
                        (exGstPurchase - existing.purchasePrice).abs() >= 0.005;
                existing.name = name;
                existing.salePrice = exGstPrice;
                existing.purchasePrice = exGstPurchase;
                existing.description = name;
                existing.isEdited = true;
                existing.needsSync = true;
                // 🔴 NEW: Update per-meter settings
                existing.isPerMeter = isPerMeter;
                existing.meterAmount =
                    double.tryParse(meterAmountController.text) ?? 1.0;
                if (priceActuallyChanged) {
                  existing.markPriceChanged();
                }
              } else {
                widget.priceBook.add(models.PriceBookItem(
                  code: desc,
                  name: name,
                  salePrice: exGstPrice,
                  purchasePrice: exGstPurchase,
                  unit: null,
                  description: name,
                  origin: 'manual',
                  favorite: false,
                  usageCount: 0,
                  percentageChanged: 0,
                  isEdited: true,
                  needsSync: true,
                  isUsed: false,
                  priceLastChangedAt: DateTime.now(),
                  isPerMeter: isPerMeter,
                  meterAmount:
                      double.tryParse(meterAmountController.text) ?? 1.0,
                ));
              }
              try {
                await widget.savePriceBook();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save pricebook: $e')),
                  );
                }
              }
            }

            final item = estimate_item.EstimateItem(
              name: name,
              description: desc,
              unitPrice: exGstPrice,
              quantity: qty,
              purchasePrice: exGstPurchase != 0
                  ? exGstPurchase
                  : null, // Allow negative prices
              section: section,
              isPerMeter: isPerMeter,
              meterAmount: double.tryParse(meterAmountController.text) ?? 1.0,
            );
            Navigator.pop(context, item);
          },
          child: Text(widget.initialItem == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
