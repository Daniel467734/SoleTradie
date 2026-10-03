part of '../estimate_builder_screen.dart';

extension _EstimateBuilderPdfHelpersExt on _EstimateBuilderScreenState {
  Future<PdfColor> getPdfBannerColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_banner_color');
    if (colorString != null &&
        colorString.startsWith('#') &&
        colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 |
          (r * 255).toInt() << 16 |
          (g * 255).toInt() << 8 |
          (b * 255).toInt());
    }
    // Default:
    return PdfColors.green400;
  }

  Future<PdfColor> getPdfLineItemColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_line_item_color');
    if (colorString != null &&
        colorString.startsWith('#') &&
        colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 |
          (r * 255).toInt() << 16 |
          (g * 255).toInt() << 8 |
          (b * 255).toInt());
    }
    // Default to banner color if not set
    return await getPdfBannerColor();
  }

  Future<PdfColor> getPdfTotalsColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorString = prefs.getString('pdf_totals_color');
    if (colorString != null &&
        colorString.startsWith('#') &&
        colorString.length == 9) {
      // Parse #AARRGGBB
      final value = int.parse(colorString.substring(1), radix: 16);
      final a = ((value >> 24) & 0xFF) / 255.0;
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return PdfColor.fromInt((a * 255).toInt() << 24 |
          (r * 255).toInt() << 16 |
          (g * 255).toInt() << 8 |
          (b * 255).toInt());
    }
    // Default to banner color if not set
    return await getPdfBannerColor();
  }

  // --- PDF styling helpers (shared look & feel for a more professional document) ---

  /// A very light tint of the accent/banner color, used for zebra-striping
  /// table rows and subtle highlight boxes without overpowering the page.
  PdfColor _pdfLightTint(PdfColor color, {double strength = 0.08}) =>
      color.shade(strength);

  /// A darker tint of the accent/banner color, used for emphasis text.
  PdfColor _pdfDarkTint(PdfColor color, {double strength = 0.75}) =>
      color.shade(strength);

  /// Clean, modern table border: no harsh full grid — just a colored rule
  /// under the header and faint hairlines between rows.
  pw.TableBorder _pdfTableBorder(PdfColor bannerColor) {
    return pw.TableBorder(
      top: pw.BorderSide(color: bannerColor, width: 1),
      bottom: pw.BorderSide(color: bannerColor, width: 1),
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    );
  }

  /// Consistently styled data table used for line items throughout the PDF:
  /// colored header band, zebra-striped rows, subtle hairline separators
  /// instead of a full grid, and tidy padding.
  pw.Widget _pdfStyledTable({
    required List<String> headers,
    required List<List<dynamic>> data,
    required PdfColor lineItemColor,
  }) {
    return pw.Table.fromTextArray(
      cellAlignment: pw.Alignment.centerLeft,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: lineItemColor),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      cellStyle: const pw.TextStyle(fontSize: 10),
      oddCellStyle: const pw.TextStyle(fontSize: 10),
      oddRowDecoration:
          pw.BoxDecoration(color: _pdfLightTint(lineItemColor, strength: 0.06)),
      border: _pdfTableBorder(lineItemColor),
      headers: headers,
      data: data,
    );
  }

  /// A section title with a colored accent bar and optional description,
  /// replacing plain bold text for a more polished, document-like hierarchy.
  pw.Widget _pdfSectionHeader(String title, PdfColor bannerColor,
      {String? subtitle}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 4,
              height: 22,
              margin: const pw.EdgeInsets.only(right: 8, top: 1),
              decoration: pw.BoxDecoration(color: bannerColor),
            ),
            pw.Expanded(
              child: pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black)),
            ),
          ],
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12),
            child: pw.Text(subtitle,
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ),
        ],
      ],
    );
  }

  /// A highlighted totals box for the grand total of a document/section,
  /// making the final figure stand out instead of blending into plain text.
  pw.Widget _pdfTotalsBox({
    required List<pw.Widget> lines,
    required PdfColor totalsColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _pdfLightTint(totalsColor, strength: 0.06),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
            color: _pdfLightTint(totalsColor, strength: 0.2), width: 0.75),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: lines,
      ),
    );
  }

  /// A rounded card with a colored accent bar on the left edge and a light grey fill.
  pw.Widget _pdfAccentCard({
    required pw.Widget child,
    required PdfColor bannerColor,
    PdfColor? fillColor,
    double accentWidth = 3,
    double radius = 6,
    pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(12),
    pw.EdgeInsetsGeometry? margin,
  }) {
    final card = pw.ClipRRect(
      horizontalRadius: radius,
      verticalRadius: radius,
      child: pw.Stack(
        children: [
          pw.Container(
            width: double.infinity,
            padding: padding.add(pw.EdgeInsets.only(left: accentWidth)),
            color: fillColor ?? PdfColors.grey100,
            child: child,
          ),
          pw.Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: pw.Container(width: accentWidth, color: bannerColor),
          ),
        ],
      ),
    );
    return margin != null ? pw.Padding(padding: margin, child: card) : card;
  }
}
