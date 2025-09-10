import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
// import 'package:your_app/widgets/live_barcode_scanner.dart'; // Update the path as needed
import '../widgets/live_barcode_scanner.dart'; // Update the relative path if needed

class PriceBookItem {
  String code;
  String name;
  String unit;
  String groupCode;
  String barCode;
  double price;
  bool favourite;
  int? usageCount;

  PriceBookItem({
    required this.code,
    required this.name,
    required this.unit,
    required this.groupCode,
    required this.barCode,
    required this.price,
    this.favourite = false,
    this.usageCount,
  });
}

class PriceBookPicker extends StatefulWidget {
  final List<PriceBookItem> priceBook;
  const PriceBookPicker({super.key, required this.priceBook});

  @override
  State<PriceBookPicker> createState() => _PriceBookPickerState();
}

class _PriceBookPickerState extends State<PriceBookPicker> {
  late final TextEditingController _searchController;
  String search = '';
  bool showFavs = false;
  String _selectedSort = 'Code';
  final List<String> sortOptions = ['Code', 'Name', 'Price', 'Barcode'];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.priceBook.where((item) {
      final matchesSearch = search.isEmpty ||
          item.name.toLowerCase().contains(search.toLowerCase()) ||
          item.code.toLowerCase().contains(search.toLowerCase()) ||
          item.barCode.toLowerCase().contains(search.toLowerCase());
      final matchesFav = !showFavs || item.favourite;
      return matchesSearch && matchesFav;
    }).toList();

    filtered.sort((a, b) {
      switch (_selectedSort) {
        case 'Code':
          return a.code.compareTo(b.code);
        case 'Name':
          return a.name.compareTo(b.name);
        case 'Price':
          return a.price.compareTo(b.price);
        case 'Barcode':
          return a.barCode.compareTo(b.barCode);
        default:
          return 0;
      }
    });

    final frequentItems = widget.priceBook
        .where((item) => item.usageCount != null && item.usageCount! > 0)
        .toList()
      ..sort((a, b) => (b.usageCount ?? 0).compareTo(a.usageCount ?? 0));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) => setState(() => search = val),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan Barcode',
                  onPressed: () async {
                    final scanned = await showDialog<String>(
                      context: context,
                      builder: (context) => Dialog(
                        child: SizedBox(
                          width: 300,
                          height: 400,
                          child: SimpleBarcodeScanner(
                            onScanned: (code) => Navigator.of(context).pop(code),
                          ),
                        ),
                      ),
                    );
                    if (scanned != null && scanned.isNotEmpty) {
                      setState(() {
                        search = scanned;
                        _searchController.text = scanned;
                      });
                    }
                  },
                ),
                IconButton(
                  icon: Icon(showFavs ? Icons.star : Icons.star_border),
                  onPressed: () => setState(() => showFavs = !showFavs),
                  tooltip: 'Show Favorites',
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _selectedSort,
              items: sortOptions.map((option) {
                return DropdownMenuItem(
                  value: option,
                  child: Text('Sort by $option'),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedSort = newValue;
                  });
                }
              },
            ),
            if (frequentItems.isNotEmpty) ...[
              const Text('Frequent Items', style: TextStyle(fontWeight: FontWeight.bold)),
              ...frequentItems.take(5).map((item) => ListTile(
                leading: Icon(item.favourite ? Icons.star : Icons.star_border),
                title: Text('${item.code} - ${item.name}'),
                subtitle: Text('Unit: ${item.unit}  |  \$${item.price.toStringAsFixed(2)}'),
                onTap: () => Navigator.of(context).pop(item),
              )),
              const Divider(),
            ],
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return ListTile(
                    leading: Icon(
                      item.favourite ? Icons.star : Icons.star_border,
                      color: item.favourite ? Colors.amber : Colors.grey,
                    ),
                    title: Text('${item.code} - ${item.name}'),
                    subtitle: Text('Unit: ${item.unit}  |  \$${item.price.toStringAsFixed(2)}'),
                    onTap: () => Navigator.pop(context, item),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          final nameController = TextEditingController(text: item.name);
                          final codeController = TextEditingController(text: item.code);
                          final unitController = TextEditingController(text: item.unit);
                          final priceController = TextEditingController(text: item.price.toString());
                          await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Edit Item'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                                  TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Code')),
                                  TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Unit')),
                                  TextField(controller: priceController, decoration: const InputDecoration(labelText: 'Price'), keyboardType: TextInputType.number),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      item.name = nameController.text.trim();
                                      item.code = codeController.text.trim();
                                      item.unit = unitController.text.trim();
                                      item.price = double.tryParse(priceController.text) ?? item.price;
                                    });
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                        } else if (value == 'duplicate') {
                          setState(() {
                            widget.priceBook.add(
                              PriceBookItem(
                                code: '${item.code}_copy',
                                name: '${item.name} (Copy)',
                                unit: item.unit,
                                groupCode: item.groupCode,
                                barCode: item.barCode,
                                price: item.price,
                                favourite: item.favourite,
                                usageCount: 0,
                              ),
                            );
                          });
                        } else if (value == 'delete') {
                          setState(() {
                            widget.priceBook.remove(item);
                          });
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// When navigating to EstimateBuilderScreen:
// Example usage (place inside a function or callback):
// Navigator.push(
//   context,
//   MaterialPageRoute(
//     builder: (_) => EstimateBuilderScreen(
//       jobId: '123',
//       jobTitle: 'Test Job',
//       jobType: 'Estimate',
//       priceBook: priceBook, // <-- pass your loaded price book here
//     ),
//   ),
// );

Future<void> exportPriceBookToCsv(List<PriceBookItem> priceBook) async {
  final rows = [
    ['Code', 'Name', 'Unit', 'Price', 'Favourite', 'Barcode'],
    ...priceBook.map((item) => [
      item.code,
      item.name,
      item.unit,
      item.price,
      item.favourite ? 'Yes' : 'No',
      item.barCode, // <-- Add this line
    ]),
  ];
  final csv = const ListToCsvConverter().convert(rows);
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/pricebook_export.csv');
  await file.writeAsString(csv);
  // Optionally share or open the file
}