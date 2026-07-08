import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CsvImportTemplate {
  final String name;
  final bool hasHeader;
  final Map<String, int> fieldIndexes;
  final DateTime createdAt;
  final DateTime updatedAt;

  CsvImportTemplate({
    required this.name,
    required this.hasHeader,
    required this.fieldIndexes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory CsvImportTemplate.fromJson(Map<String, dynamic> json) {
    return CsvImportTemplate(
      name: json['name'] as String? ?? 'Unnamed Template',
      hasHeader: json['hasHeader'] as bool? ?? true,
      fieldIndexes: Map<String, int>.from(
        (json['fieldIndexes'] as Map<String, dynamic>?) ?? {},
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'hasHeader': hasHeader,
        'fieldIndexes': fieldIndexes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class PriceBookCsvImportScreen extends StatefulWidget {
  const PriceBookCsvImportScreen({super.key});

  @override
  State<PriceBookCsvImportScreen> createState() => _PriceBookCsvImportScreenState();
}

class _PriceBookCsvImportScreenState extends State<PriceBookCsvImportScreen> {
  static const _storageFileName = 'pricebook_csv_import_templates.json';

  final Map<String, int?> _fieldIndexes = {
    'code': null,
    'name': null,
    'price': null,
    'purchasePrice': null,
    'unit': null,
    'groupCode': null,
    'barcode': null,
    'favorite': null,
  };

  final TextEditingController _templateNameController = TextEditingController();
  final List<String> _availableFields = [
    'code',
    'name',
    'price',
    'purchasePrice',
    'unit',
    'groupCode',
    'barcode',
    'favorite',
  ];

  List<CsvImportTemplate> _templates = [];
  List<String> _columnNames = [];
  List<List<dynamic>> _rows = [];
  bool _hasHeader = true;
  bool _isLoading = false;
  String? _loadedFilePath;
  String _statusMessage = 'Select a CSV file to begin mapping.';

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    super.dispose();
  }

  Future<File> _templateStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_storageFileName');
  }

  Future<void> _loadTemplates() async {
    try {
      final file = await _templateStorageFile();
      if (!await file.exists()) {
        setState(() {
          _templates = [];
        });
        return;
      }

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        setState(() {
          _templates = [];
        });
        return;
      }

      final decoded = jsonDecode(contents);
      final templateList = decoded is List<dynamic> ? decoded : [];
      setState(() {
        _templates = templateList
            .whereType<Map<String, dynamic>>()
            .map(CsvImportTemplate.fromJson)
            .toList();
      });
    } catch (e) {
      print('Failed to load CSV import templates: $e');
      setState(() {
        _templates = [];
      });
    }
  }

  Future<void> _saveTemplates() async {
    try {
      final file = await _templateStorageFile();
      final jsonList = _templates.map((template) => template.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
      if (mounted) {
        setState(() {
          _statusMessage = 'Saved ${_templates.length} template(s).';
        });
      }
    } catch (e) {
      print('Failed to save CSV import templates: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to save templates: $e';
        });
      }
    }
  }

  Future<void> _pickCsvFile() async {
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Opening CSV picker...';
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'CSV picker closed without selecting a file.';
        });
        return;
      }

      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      final rows = const CsvToListConverter(eol: '\n').convert(csvString);
      if (rows.isEmpty) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Selected CSV is empty.';
        });
        return;
      }

      _loadedFilePath = file.path;
      _hasHeader = _detectHeader(rows.first);
      _columnNames = _buildColumnLabels(rows.first, _hasHeader);
      _rows = rows;
      _templateNameController.text = '';
      _fieldIndexes.updateAll((key, value) => null);

      setState(() {
        _isLoading = false;
        _statusMessage = 'CSV loaded with ${_columnNames.length} columns. Map the fields below.';
      });
    } catch (e) {
      print('Error loading CSV file: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Unable to load CSV file: $e';
      });
    }
  }

  bool _detectHeader(List<dynamic> firstRow) {
    final headerText = firstRow.map((cell) => cell.toString().toLowerCase()).join(' ');
    return headerText.contains('code') ||
        headerText.contains('name') ||
        headerText.contains('price') ||
        headerText.contains('description');
  }

  List<String> _buildColumnLabels(List<dynamic> row, bool header) {
    if (header) {
      return row.map((cell) => cell.toString()).toList();
    }
    return List.generate(row.length, (index) => 'Column ${index + 1}');
  }

  Future<void> _saveCurrentTemplate() async {
    final name = _templateNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for this template.')),
      );
      return;
    }

    final selectedFields = Map<String, int>.fromEntries(
      _fieldIndexes.entries
          .where((entry) => entry.value != null)
          .map((entry) => MapEntry(entry.key, entry.value!)),
    );

    if (!selectedFields.containsKey('code') || !selectedFields.containsKey('name') || !selectedFields.containsKey('price')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code, Name, and Price fields are required.')),
      );
      return;
    }

    final template = CsvImportTemplate(
      name: name,
      hasHeader: _hasHeader,
      fieldIndexes: selectedFields,
    );

    final existingIndex = _templates.indexWhere((item) => item.name == name);
    if (existingIndex != -1) {
      _templates[existingIndex] = template;
    } else {
      _templates.add(template);
    }

    await _saveTemplates();
    if (mounted) {
      setState(() {
        _statusMessage = 'Template "$name" saved.';
      });
    }
  }

  Future<void> _deleteTemplate(CsvImportTemplate template) async {
    setState(() {
      _templates.removeWhere((item) => item.name == template.name);
      _statusMessage = 'Deleted template ${template.name}';
    });
    await _saveTemplates();
  }

  Future<List<Map<String, dynamic>>> _buildImportItems() async {
    if (_rows.isEmpty) return [];

    final requiredFields = ['code', 'name', 'price'];
    final missingRequired = requiredFields.where((field) => _fieldIndexes[field] == null).toList();
    if (missingRequired.isNotEmpty) {
      throw Exception('Please map the following required fields: ${missingRequired.join(', ')}');
    }

    final imported = <Map<String, dynamic>>[];
    final startIndex = _hasHeader ? 1 : 0;

    for (var rowIndex = startIndex; rowIndex < _rows.length; rowIndex++) {
      final row = _rows[rowIndex];
      if (row.isEmpty) continue;

      final codeIndex = _fieldIndexes['code'];
      final nameIndex = _fieldIndexes['name'];
      final priceIndex = _fieldIndexes['price'];
      if (codeIndex == null || nameIndex == null || priceIndex == null) continue;

      final code = codeIndex < row.length ? row[codeIndex]?.toString().trim() ?? '' : '';
      if (code.isEmpty) continue;

      final name = nameIndex < row.length ? row[nameIndex]?.toString().trim() ?? '' : '';
      if (name.isEmpty) continue;

      final price = priceIndex < row.length ? double.tryParse(row[priceIndex]?.toString() ?? '') ?? 0.0 : 0.0;
      final purchasePriceIndex = _fieldIndexes['purchasePrice'];
      final unitIndex = _fieldIndexes['unit'];
      final groupCodeIndex = _fieldIndexes['groupCode'];
      final barcodeIndex = _fieldIndexes['barcode'];
      final favoriteIndex = _fieldIndexes['favorite'];

      imported.add({
        'code': code,
        'name': name,
        'price': price,
        'purchasePrice': purchasePriceIndex != null && purchasePriceIndex < row.length
            ? double.tryParse(row[purchasePriceIndex]?.toString() ?? '') ?? 0.0
            : 0.0,
        'unit': unitIndex != null && unitIndex < row.length ? row[unitIndex]?.toString() ?? '' : '',
        'groupCode': groupCodeIndex != null && groupCodeIndex < row.length ? row[groupCodeIndex]?.toString() ?? '' : '',
        'barcode': barcodeIndex != null && barcodeIndex < row.length ? row[barcodeIndex]?.toString() ?? '' : '',
        'favorite': favoriteIndex != null && favoriteIndex < row.length
            ? row[favoriteIndex]?.toString().toLowerCase() == 'true'
            : false,
      });
    }

    return imported;
  }

  Future<void> _performImport() async {
    final templateName = _templateNameController.text.trim();
    if (templateName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a template name before importing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final importedItems = await _buildImportItems();
      if (importedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No importable rows were found using the current mapping.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final rowsWithOrigin = importedItems.map((row) {
        return {
          ...row,
          'origin': templateName,
        };
      }).toList();
      Navigator.pop(context, rowsWithOrigin);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildFieldMapper() {
    if (_rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Load a CSV file first to configure field mappings.'),
      );
    }

    final rowIndex = _hasHeader ? 1 : 0;
    final sampleRow = _rows.length > rowIndex ? _rows[rowIndex] : <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Columns detected: ${_columnNames.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Header row: ${_hasHeader ? 'Yes' : 'No'}'),
        const SizedBox(height: 12),
        ..._availableFields.map((field) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<int?>(
              decoration: InputDecoration(
                labelText: field,
                border: const OutlineInputBorder(),
              ),
              value: _fieldIndexes[field],
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Not mapped')),
                ...List.generate(_columnNames.length, (index) {
                  return DropdownMenuItem<int?>(
                    value: index,
                    child: Text('[$index] ${_columnNames[index]}'),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _fieldIndexes[field] = value;
                });
              },
            ),
          );
        }),
        const SizedBox(height: 12),
        Text('Sample row preview', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(_columnNames.length, (index) {
            final sampleValue = index < sampleRow.length ? sampleRow[index] : '';
            return Text('[$index] ${_columnNames[index]} → ${sampleValue.toString()}');
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricebook CSV Import'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Load CSV File'),
                      onPressed: _isLoading ? null : _pickCsvFile,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save Template'),
                      onPressed: _rows.isEmpty ? null : _saveCurrentTemplate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_download),
                label: const Text('Import CSV'),
                onPressed: _rows.isEmpty ? null : _performImport,
              ),
              const SizedBox(height: 12),
              Text(_statusMessage),
              const SizedBox(height: 16),
              if (_loadedFilePath != null) ...[
                Text('Loaded file:', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(_loadedFilePath!, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _templateNameController,
                decoration: const InputDecoration(
                  labelText: 'Template Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _buildFieldMapper(),
              const SizedBox(height: 24),
              const Text('Saved Templates', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_templates.isEmpty)
                const Text('No saved templates yet.')
              else
                Column(
                  children: _templates.map((template) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        title: Text(template.name),
                        subtitle: Text('Columns: ${template.fieldIndexes.length} | Header: ${template.hasHeader ? 'Yes' : 'No'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete template',
                          onPressed: () => _deleteTemplate(template),
                        ),
                        onTap: () {
                          setState(() {
                            _templateNameController.text = template.name;
                            _hasHeader = template.hasHeader;
                            _fieldIndexes.updateAll((key, value) => template.fieldIndexes[key]);
                            _statusMessage = 'Loaded template "${template.name}" for editing.';
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
