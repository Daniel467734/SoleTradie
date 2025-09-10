import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class SimpleBarcodeScanner extends StatefulWidget {
  final void Function(String code) onScanned;
  const SimpleBarcodeScanner({required this.onScanned, super.key});

  @override
  State<SimpleBarcodeScanner> createState() => _SimpleBarcodeScannerState();
}

class _SimpleBarcodeScannerState extends State<SimpleBarcodeScanner> {
  bool _scanned = false;
  MobileScannerController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String normalize(String? code) =>
      code?.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'^0+'), '') ?? '';

  @override
  Widget build(BuildContext context) {
    // fixed
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_scanned) return;
            final barcode = capture.barcodes.first;
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              _scanned = true;
              widget.onScanned(value);
              Navigator.of(context).pop();
            }
          },
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        // Optional: Add a border overlay for better UX
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}