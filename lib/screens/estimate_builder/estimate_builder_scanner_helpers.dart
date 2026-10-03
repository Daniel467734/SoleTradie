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
}
