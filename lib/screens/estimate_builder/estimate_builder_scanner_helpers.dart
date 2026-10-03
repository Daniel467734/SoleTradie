part of '../estimate_builder_screen.dart';

extension _EstimateBuilderScannerHelpersExt on _EstimateBuilderScreenState {
  Future<String?> _scanBarcode() async {
    bool scanned = false;
    return await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan Barcode')),
          body: MobileScanner(
            onDetect: (capture) {
              if (scanned) return;
              final barcode = capture.barcodes.first.rawValue;
              if (barcode != null && barcode.isNotEmpty) {
                scanned = true;
                if (Navigator.of(_).canPop()) {
                  Navigator.pop(_, barcode);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showAiProgressDialog(String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the user-selected supplier receipt templates.
  Future<String?> _showSupplierTemplateSelector() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedTemplatesString =
        prefs.getString('selected_supplier_templates') ?? '';
    final selectedTemplates = selectedTemplatesString.isNotEmpty
        ? selectedTemplatesString.split(',')
        : <String>[];

    if (selectedTemplates.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Supplier Templates'),
          content: const Text(
              'No supplier templates are selected in settings. Please go to Settings > Company Settings > PDF Receipt Scanner to select your supplier templates.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Supplier Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose the supplier template for this receipt:'),
            const SizedBox(height: 16),
            ...selectedTemplates.map((template) => ListTile(
                  title: Text(template),
                  leading: const Icon(Icons.receipt_long),
                  onTap: () => Navigator.pop(context, template),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemMethodDialog(SubsectionData section) async {
    final method = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Add Item to ${section.name}'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              final source = await showDialog<ImageSource?>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('Scan Receipt'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(context, ImageSource.camera),
                      child: Row(
                        children: const [
                          Icon(Icons.camera_alt),
                          SizedBox(width: 8),
                          Text('Camera'),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(context, ImageSource.gallery),
                      child: Row(
                        children: const [
                          Icon(Icons.photo_library),
                          SizedBox(width: 8),
                          Text('Gallery'),
                        ],
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf']);
                        if (result != null &&
                            result.files.single.path != null) {
                          final file = File(result.files.single.path!);
                          final text = await extractTextFromPdf(file);
                          await _scanReceiptFromText(section.name, text);
                        }
                        Navigator.pop(context);
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.picture_as_pdf),
                          SizedBox(width: 8),
                          Text('Scan from PDF'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              Navigator.pop(context);
              if (source != null) {
                await _scanReceipt(section.name, source: source);
              }
            },
            child: Row(
              children: const [
                Icon(Icons.receipt_long),
                SizedBox(width: 8),
                Text('Scan Receipt'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: Row(
              children: const [
                Icon(Icons.edit),
                SizedBox(width: 8),
                Text('Manual Entry'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              FilePickerResult? result = await FilePicker.platform
                  .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
              if (result != null && result.files.single.path != null) {
                final file = File(result.files.single.path!);
                final text = await extractTextFromPdf(file);
                await _scanReceiptFromText(section.name, text);
              }
              Navigator.pop(context);
            },
            child: Row(
              children: const [
                Icon(Icons.picture_as_pdf),
                SizedBox(width: 8),
                Text('Scan from PDF'),
              ],
            ),
          ),
        ],
      ),
    );

    if (method == 'manual') {
      _addItemToSection(section);
    }
  }
}
