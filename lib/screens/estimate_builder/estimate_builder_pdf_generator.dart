part of '../estimate_builder_screen.dart';

extension _EstimateBuilderPdfGeneratorExt on _EstimateBuilderScreenState {
  Future<void> _generateEstimatePdf(
      {required String type,
      required String layout,
      bool includeScopePage = false}) async {
    FocusScope.of(context).unfocus();
    final bool showItems = layout != 'summary';
    final bool showLineTotals = layout == 'full';
    print(
        '🧾 _generateEstimatePdf called: type=$type layout=$layout items=${items.length} showItems=$showItems showLineTotals=$showLineTotals');
    // DEBUG: inserted marker for preview route patch test
    final prefs = await SharedPreferences.getInstance();
    final logoPath = prefs.getString('company_logo_path');
    final companyName = prefs.getString('company_name') ?? 'Your Company Name';
    final gstNumber = prefs.getString('gst_number') ?? 'GST Number';
    final companyAddress =
        prefs.getString('company_address') ?? 'Company Address';
    final isGstRegistered = prefs.getBool('is_gst_registered') ?? true;
    final bankAccount = prefs.getString('bank_details') ?? '';
    final bannerColor = await getPdfBannerColor();
    final lineItemColor = await getPdfLineItemColor();
    final totalsColor = await getPdfTotalsColor();

    // Use a Unicode-friendly embedded font so Māori macron vowels render correctly.
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));

    pw.Widget? logoWidget;
    if (logoPath != null && logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        final logoBytes = await logoFile.readAsBytes();
        final logoImage = pw.MemoryImage(logoBytes);
        logoWidget = pw.Image(logoImage, height: 60);
      }
    }

    final job = widget.job;
    final customerName =
        (job.companyName != null && job.companyName!.trim().isNotEmpty)
            ? job.companyName!
            : (job.customerName ?? '');
    final customerAddress = job.address ?? '';
    final customerBodyCorporateNumber = job.bodyCorporateNumber ?? '';
    final orderNumber = _orderNumberController.text.trim();
    final today = DateTime.now();
    final estimateOrQuoteValidUntil = today.add(const Duration(days: 30));

    final List<estimate_item.EstimateItem> invoiceItems =
        List<estimate_item.EstimateItem>.from(items.map((e) => e.copyWith()));
    invoiceItems.removeWhere((item) =>
        normalizeCode(item.description) == 'deposit' ||
        normalizeCode(item.name) == 'deposit received');
    invoiceItems.removeWhere((item) => item.quantity == 0);
    print('🧾 invoiceItems count after deposit filter: ${invoiceItems.length}');
    final List<SubsectionData> invoiceSections = [
      ...mainSections,
      ...optionSections
    ];
    print('🧾 invoiceSections: ${invoiceSections.map((s) => s.name).toList()}');
    final double depositPreGst;
    final estimate_item.EstimateItem? depositLineItem;
    if (type == 'invoice' && currentDepositAmount > 0) {
      depositPreGst = currentDepositAmount / 1.15;
      depositLineItem = estimate_item.EstimateItem(
        name: 'Deposit Received',
        description: 'DEPOSIT',
        unitPrice: -depositPreGst,
        quantity: 1,
        purchasePrice: 0,
        section: 'Payments',
      );
      invoiceItems.add(depositLineItem);
      if (!invoiceSections.any((s) => s.name == 'Payments')) {
        invoiceSections.add(SubsectionData(name: 'Payments'));
      }
    } else {
      depositPreGst = 0.0;
      depositLineItem = null;
    }

    final invoiceSubTotalExGst = invoiceItems.fold<double>(
        0.0, (sum, item) => sum + item.unitPrice * item.quantity);
    final invoiceGstAmount =
        isGstRegistered ? invoiceSubTotalExGst * 0.15 : 0.0;
    final invoiceTotalIncGst =
        isGstRegistered ? invoiceSubTotalExGst * 1.15 : invoiceSubTotalExGst;

    // Move this flag outside the widget collection so it can be used in fallback invoice table
    final bool showInvoiceDiscountColumn =
        invoiceItems.any((item) => (item.discountAmount ?? 0) > 0);

    String dueDateString = '';
    DateTime? dueDate;
    if (type == 'invoice') {
      dueDate = getInvoiceDueDate(job.paymentTerms);
      dueDateString =
          '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
    } else {
      dueDate = getEstimateOrQuoteDueDate();
    }

    // Assign documentNumber and typeName before PDF build
    final docNumber = await _getNextDocumentNumber();
    String typeName;
    String documentNumber;
    switch (type) {
      case 'invoice':
        typeName = 'Invoice';
        documentNumber = docNumber;
        break;
      case 'quote':
        typeName = 'Quote';
        documentNumber = docNumber;
        break;
      default:
        typeName = 'Estimate';
        documentNumber = docNumber;
    }

    final String scopeSummaryText = _scopeSummaryController.text.trim();
    final String exclusionsText = _scopeExclusionsController.text.trim();
    print(
        '🧾 Building PDF: type=$type layout=$layout items=${invoiceItems.length} invoiceSections=${invoiceSections.map((s) => s.name).toList()} showInvoiceDiscountColumn=$showInvoiceDiscountColumn');
    try {
      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 36),
          footer: (context) => pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, thickness: 0.75),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(companyName,
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 14),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: bannerColor, width: 2.5)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoWidget != null) logoWidget,
                      pw.SizedBox(height: 8),
                      pw.Text(companyName,
                          style: pw.TextStyle(
                              fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.Text(companyAddress,
                          style: const pw.TextStyle(fontSize: 10)),
                      if (isGstRegistered)
                        pw.Text('GST: $gstNumber',
                            style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(type.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 26,
                              fontWeight: pw.FontWeight.bold,
                              color: _pdfDarkTint(bannerColor),
                              letterSpacing: 1.2)),
                      pw.SizedBox(height: 4),
                      if (type == 'invoice') ...[
                        pw.Text('Invoice #: $documentNumber',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                            'Date: ${today.day}/${today.month}/${today.year}',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Due: $dueDateString',
                            style: const pw.TextStyle(fontSize: 10)),
                      ] else ...[
                        pw.Text(
                            'Date: ${today.day}/${today.month}/${today.year}',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                            'Valid until: ${estimateOrQuoteValidUntil.day}/${estimateOrQuoteValidUntil.month}/${estimateOrQuoteValidUntil.year}',
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Customer: $customerName',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  if (customerBodyCorporateNumber.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                        'Body Corporate Number: $customerBodyCorporateNumber',
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                  pw.SizedBox(height: 2),
                  pw.Text('Address: $customerAddress',
                      style: const pw.TextStyle(fontSize: 11)),
                  if (orderNumber.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text('Order Number: $orderNumber',
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                ],
              ),
            ),
            // --- Invoice summary sections ---
            if (type == 'invoice') ...[
              if (invoiceSections.isNotEmpty)
                ...invoiceSections.expand((section) {
                  final sectionItems = invoiceItems
                      .where((i) => i.section == section.name)
                      .toList();
                  if (sectionItems.isEmpty) return <pw.Widget>[];
                  final sectionTotal = sectionItems.fold<double>(
                      0.0, (sum, item) => sum + _lineTotal(item));
                  return <pw.Widget>[
                    pw.NewPage(freeSpace: 120),
                    _pdfSectionHeader(section.name, bannerColor,
                        subtitle: section.description),
                    if (showItems) ...[
                      pw.SizedBox(height: 8),
                      _pdfStyledTable(
                        lineItemColor: lineItemColor,
                        headers: [
                          'ID',
                          'Name',
                          'Qty',
                          if (showLineTotals) 'Unit Price',
                          if (showLineTotals &&
                              sectionItems.any(
                                  (item) => (item.discountPercent ?? 0) >= 1))
                            'Discount',
                          if (showLineTotals) 'Line Total',
                        ],
                        data: sectionItems
                            .map((item) => [
                                  item.description,
                                  (item.description == 'EST' &&
                                          type == 'estimate')
                                      ? 'Estimated Labour'
                                      : item.name,
                                  formatQuantity(item.quantity),
                                  if (showLineTotals)
                                    '\$${item.unitPrice.toStringAsFixed(2)}',
                                  if (showLineTotals &&
                                      (item.discountPercent ?? 0) >= 1)
                                    '${item.discountPercent!.toStringAsFixed(1)}%',
                                  if (showLineTotals)
                                    '\$${_lineTotal(item).toStringAsFixed(2)}',
                                ])
                            .toList(),
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'Section Total: \$${sectionTotal.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.SizedBox(height: 12),
                  ];
                }),
              if (invoiceSections.isEmpty && invoiceItems.isNotEmpty) ...[
                pw.NewPage(freeSpace: 120),
                _pdfSectionHeader('Invoice Summary', bannerColor),
                if (showItems) ...[
                  pw.SizedBox(height: 8),
                  _pdfStyledTable(
                    lineItemColor: lineItemColor,
                    headers: [
                      'ID',
                      'Name',
                      'Qty',
                      if (showLineTotals) 'Unit Price',
                      if (showLineTotals &&
                          invoiceItems
                              .any((item) => (item.discountPercent ?? 0) >= 1))
                        'Discount',
                      if (showLineTotals) 'Line Total',
                    ],
                    data: invoiceItems
                        .map((item) => [
                              item.description,
                              (item.description == 'EST' && type == 'estimate')
                                  ? 'Estimated Labour'
                                  : item.name,
                              formatQuantity(item.quantity),
                              if (showLineTotals)
                                '\$${item.unitPrice.toStringAsFixed(2)}',
                              if (showLineTotals &&
                                  (item.discountPercent ?? 0) >= 1)
                                '${item.discountPercent!.toStringAsFixed(1)}%',
                              if (showLineTotals)
                                '\$${_lineTotal(item).toStringAsFixed(2)}',
                            ])
                        .toList(),
                  ),
                ],
                pw.SizedBox(height: 10),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: _pdfTotalsBox(
                    totalsColor: totalsColor,
                    lines: [
                      if (isGstRegistered)
                        pw.Text(
                            'Subtotal (ex GST): \$${invoiceSubTotalExGst.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      if (isGstRegistered)
                        pw.Text(
                            'GST (15%): \$${invoiceGstAmount.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        isGstRegistered
                            ? 'Total (inc GST): \$${invoiceTotalIncGst.toStringAsFixed(2)}'
                            : 'Total: \$${invoiceTotalIncGst.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
              ],
              if (invoiceSections.isNotEmpty && invoiceItems.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: _pdfTotalsBox(
                    totalsColor: totalsColor,
                    lines: [
                      if (isGstRegistered)
                        pw.Text(
                            'Subtotal (ex GST): \$${invoiceSubTotalExGst.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      if (isGstRegistered)
                        pw.Text(
                            'GST (15%): \$${invoiceGstAmount.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        isGstRegistered
                            ? 'Total (inc GST): \$${invoiceTotalIncGst.toStringAsFixed(2)}'
                            : 'Total: \$${invoiceTotalIncGst.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            // --- Estimate/Quote logic (main sections + options as separate) ---
            if (type != 'invoice' && mainSections.isNotEmpty)
              ...mainSections.expand((section) {
                final sectionItems =
                    items.where((i) => i.section == section.name).toList();
                if (sectionItems.isEmpty) return <pw.Widget>[];
                final sectionTotal = sectionItems.fold<double>(
                    0.0, (sum, i) => sum + _lineTotal(i));
                return <pw.Widget>[
                  pw.NewPage(freeSpace: 120),
                  _pdfSectionHeader(section.name, bannerColor,
                      subtitle: section.description),
                  if (showItems) ...[
                    pw.SizedBox(height: 8),
                    _pdfStyledTable(
                      lineItemColor: lineItemColor,
                      headers: [
                        'ID',
                        'Name',
                        'Qty',
                        if (showLineTotals) 'Unit Price',
                        if (showLineTotals &&
                            sectionItems.any(
                                (item) => (item.discountPercent ?? 0) >= 1))
                          'Discount',
                        if (showLineTotals) 'Line Total',
                      ],
                      data: sectionItems
                          .map((item) => [
                                item.description,
                                (item.description == 'EST' &&
                                        type == 'estimate')
                                    ? 'Estimated Labour'
                                    : item.name,
                                formatQuantity(item.quantity),
                                if (showLineTotals)
                                  '\$${item.unitPrice.toStringAsFixed(2)}',
                                if (showLineTotals &&
                                    (item.discountPercent ?? 0) >= 1)
                                  '${item.discountPercent!.toStringAsFixed(1)}%',
                                if (showLineTotals)
                                  '\$${_lineTotal(item).toStringAsFixed(2)}',
                              ])
                          .toList(),
                    ),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Section Total: \$${sectionTotal.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ];
              }),
            if (type != 'invoice' &&
                items.any(
                    (i) => mainSections.any((s) => s.name == i.section))) ...[
              pw.SizedBox(height: 4),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: _pdfTotalsBox(
                  totalsColor: totalsColor,
                  lines: [
                    if (isGstRegistered)
                      pw.Text(
                          'Subtotal (ex GST): \$${mainSubTotalExGst.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    if (isGstRegistered)
                      pw.Text(
                          'GST (15%): \$${mainGstAmount.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      isGstRegistered
                          ? 'Total (inc GST): \$${mainTotalIncGst.toStringAsFixed(2)}'
                          : 'Total: \$${mainSubTotalExGst.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
            if (type != 'invoice' && optionSections.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('OPTIONS',
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                        letterSpacing: 1.0)),
              ),
              pw.SizedBox(height: 8),
              ...optionSections.expand((section) {
                final sectionItems =
                    items.where((i) => i.section == section.name).toList();
                if (sectionItems.isEmpty) return <pw.Widget>[];
                final subtotal = sectionItems.fold<double>(
                    0.0, (sum, i) => sum + i.unitPrice * i.quantity);
                final total = subtotal * 1.15;
                return <pw.Widget>[
                  pw.NewPage(freeSpace: 120),
                  _pdfSectionHeader('${section.name} (Option)', bannerColor,
                      subtitle: section.description),
                  if (showItems) ...[
                    pw.SizedBox(height: 8),
                    _pdfStyledTable(
                      lineItemColor: lineItemColor,
                      headers: [
                        'ID',
                        'Name',
                        'Qty',
                        if (showLineTotals) 'Unit Price',
                        if (showLineTotals &&
                            sectionItems.any(
                                (item) => (item.discountPercent ?? 0) >= 1))
                          'Discount',
                        if (showLineTotals) 'Line Total',
                      ],
                      data: sectionItems
                          .map((item) => [
                                item.description,
                                (item.description == 'EST' &&
                                        type == 'estimate')
                                    ? 'Estimated Labour'
                                    : item.name,
                                formatQuantity(item.quantity),
                                if (showLineTotals)
                                  '\$${item.unitPrice.toStringAsFixed(2)}',
                                if (showLineTotals &&
                                    (item.discountPercent ?? 0) >= 1)
                                  '${item.discountPercent!.toStringAsFixed(1)}%',
                                if (showLineTotals)
                                  '\$${_lineTotal(item).toStringAsFixed(2)}',
                              ])
                          .toList(),
                    ),
                  ],
                  pw.SizedBox(height: 8),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (isGstRegistered)
                          pw.Text(
                              'Option Subtotal: \$${subtotal.toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 10)),
                        if (isGstRegistered)
                          pw.Text(
                              'GST: \$${(subtotal * 0.15).toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                          isGstRegistered
                              ? 'Option Total: \$${total.toStringAsFixed(2)}'
                              : 'Option Total: \$${subtotal.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ];
              }),
            ],
            if (type == 'invoice') ...[
              pw.SizedBox(height: 16),
              if (bankAccount.isNotEmpty) ...[
                pw.NewPage(freeSpace: 120),
                _pdfAccentCard(
                  bannerColor: bannerColor,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Bank Account:',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.Text(bankAccount,
                          style: const pw.TextStyle(fontSize: 12)),
                      pw.SizedBox(height: 8),
                      pw.Text('Reference: $documentNumber',
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
            if (type != 'invoice') ...[
              pw.SizedBox(),
              pw.Text('This $type is valid for 30 days from the date of issue.',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
              // Add deposit information and bank details for estimates and quotes
              if (currentDepositAmount > 0) ...[
                pw.NewPage(freeSpace: 120),
                pw.SizedBox(height: 12),
                _pdfAccentCard(
                  bannerColor: bannerColor,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Deposit Required',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _isDepositPercentage
                            ? 'A deposit of \$${currentDepositAmount.toStringAsFixed(2)} (${_depositPercentage!.toStringAsFixed(1)}% of the main total) is required.'
                            : 'A deposit of \$${currentDepositAmount.toStringAsFixed(2)} is required.',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('This amount is due before work begins.',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                      if (bankAccount.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Text('Bank Details',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text(bankAccount,
                            style: const pw.TextStyle(fontSize: 12)),
                        pw.SizedBox(height: 4),
                        pw.Text(
                            'Please use Invoice Number as reference: $documentNumber',
                            style: const pw.TextStyle(
                                fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      );
      if (includeScopePage &&
          (scopeSummaryText.isNotEmpty || exclusionsText.isNotEmpty)) {
        pdf.addPage(
          pw.MultiPage(
            margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 36),
            footer: (context) => pw.Column(
              children: [
                pw.Divider(color: PdfColors.grey300, thickness: 0.75),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(companyName,
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                    pw.Text(
                        'Page ${context.pageNumber} of ${context.pagesCount}',
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            build: (context) => [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 14),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: bannerColor, width: 2.5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(companyName,
                            style: pw.TextStyle(
                                fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        if (companyAddress.isNotEmpty)
                          pw.Text(companyAddress,
                              style: const pw.TextStyle(
                                  fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                    if (logoWidget != null)
                      pw.Container(width: 120, child: logoWidget),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Job Scope Summary',
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: _pdfDarkTint(bannerColor))),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Date: ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              if (scopeSummaryText.isNotEmpty) ...[
                _pdfSectionHeader('Scope of Work', bannerColor),
                pw.SizedBox(height: 10),
                pw.Text(scopeSummaryText,
                    style: const pw.TextStyle(fontSize: 12, height: 1.6),
                    textAlign: pw.TextAlign.justify),
              ],
              if (scopeSummaryText.isNotEmpty && exclusionsText.isNotEmpty)
                pw.SizedBox(height: 20),
              if (exclusionsText.isNotEmpty) ...[
                _pdfSectionHeader('Exclusions', bannerColor),
                pw.SizedBox(height: 10),
                pw.Text(exclusionsText,
                    style: const pw.TextStyle(fontSize: 12, height: 1.6),
                    textAlign: pw.TextAlign.justify),
              ],
              if (_selectedLiabilityRisks.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                _pdfSectionHeader(
                    'Risks, Liabilities and Notable Information', bannerColor),
                pw.SizedBox(height: 10),
                pw.Text(
                    'This section captures risks, liabilities and notable information discussed for this job. By accepting this quote you acknowledge these matters and your responsibility (if applicable).',
                    style: const pw.TextStyle(fontSize: 12, height: 1.6),
                    textAlign: pw.TextAlign.justify),
                pw.SizedBox(height: 12),
                ..._selectedLiabilityRisks.map((risk) {
                  return _pdfAccentCard(
                    bannerColor: bannerColor,
                    margin: const pw.EdgeInsets.only(bottom: 12),
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(risk['title'] ?? '',
                            style: pw.TextStyle(
                                fontSize: 13, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        pw.Text(risk['description'] ?? '',
                            style:
                                const pw.TextStyle(fontSize: 11, height: 1.5),
                            textAlign: pw.TextAlign.justify),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ],
          ),
        );
      }
    } catch (e, stack) {
      print('❌ Error building PDF page: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to build PDF page: $e')),
        );
      }
      return;
    }

    print('🧾 PDF page built, saving PDF now...');
    final fileName = generateDocumentName(
      documentType: typeName,
      job: widget.job,
      existingAttachments: widget.job.attachments,
      documentNumber: type == 'invoice' ? documentNumber : null,
    );

    File? file;
    String? cloudPdfUrl;
    try {
      final pdfBytes = await pdf.save();
      print('🧾 PDF saved successfully, byte length=${pdfBytes.length}');

      if (kIsWeb) {
        cloudPdfUrl = await DeltaSyncService.uploadGeneratedPdfBytes(
          fileName: fileName,
          jobId: widget.job.id,
          bytes: pdfBytes,
        );
        print('☁️ Browser PDF uploaded: $fileName');
      } else {
        final dir = await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        print('🧾 PDF file written to ${file.path}');
      }

      // ✅ IMPORTANT: Add the PDF to job.attachments immediately after saving
      // This ensures subsequent document generations use correct naming
      // (avoiding duplicate names for multiple PDFs)
      _attachGeneratedPdf(cloudPdfUrl ?? file?.path, fileName);
    } catch (e, stack) {
      print('❌ Error saving PDF: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save PDF: $e')),
        );
      }
      return;
    }

    // For converted estimate invoices, preserve the builder snapshot and remaining estimate build.
    String? invoiceBuilderBuildId;
    if (widget.convertToInvoice && type == 'invoice') {
      if (_currentInProgressId == null) {
        await _saveInProgressEstimate();
      }
      await _createInvoiceSnapshotBuilds(
        invoiceTotalIncGst: invoiceTotalIncGst,
        totalProfit: totalProfit,
      );
      invoiceBuilderBuildId = _currentInProgressId;
    }
    // For a normal finalize (not the estimate->invoice conversion snapshot
    // flow above), link the document to whichever in-progress build is
    // currently backing this session, so it can be preserved and shown
    // alongside the resulting document.
    final linkedBuildId = invoiceBuilderBuildId ??
        _currentInProgressId ??
        widget.inProgressBuildId;

    // Convert in-progress build to final build version
    final version = EstimateVersion(
      type: type,
      invoiceNumber: type == 'invoice' ? documentNumber : null,
      estimateNumber: type != 'invoice' ? documentNumber : null,
      timestamp: DateTime.now(),
      items: List<estimate_item.EstimateItem>.from(
          invoiceItems.map((e) => e.copyWith())),
      sections: invoiceSections
          .map((s) => s.name)
          .toList(), // Save invoice subsections, including Payments if present
      filePath: file?.path,
      cloudPdfUrl: cloudPdfUrl,
      status: 'final',
      amount: type == 'invoice' ? invoiceTotalIncGst : totalIncGst,
      dueDate: dueDate,
      documentNumber: documentNumber,
      depositAmount: _depositAmount,
      depositPercentage: _depositPercentage,
      isDepositPercentage: _isDepositPercentage,
      builderBuildId: linkedBuildId,
      expiryDate: (type == 'estimate' || type == 'quote')
          ? estimateOrQuoteValidUntil
          : null,
      profit: type == 'invoice' ? totalProfit : 0.0,
      // 🔴 CRITICAL: ALWAYS explicitly set these fields to ensure consistency
      // between newly created invoices and backup format. Previous versions
      // only relied on constructor defaults, which could cause format mismatch
      // during delta sync if any field was omitted from serialization.
      isPaid: false,
      isVoided: false,
      isArchived: false,
      isConverted: false,
      emailSent: false,
      paidVia: 'manual',
    );
    // Give the document a stable id so the originating build can be linked
    // to it via finalizedDocumentId, and so the "In Progress Builds" UI can
    // resolve which document a preserved build now belongs to.
    version.id ??=
        '${widget.job.id}_doc_${DateTime.now().millisecondsSinceEpoch}';

    _appendFinalEstimateVersion(version);

    // Preserve the in-progress build(s) that produced this document instead
    // of deleting them - mark them as finalized/linked to the resulting
    // EstimateVersion so they stay associated with it forever. If the user
    // reopens a finalized build later, a new duplicate build is created
    // instead of mutating this one (see the inProgressBuildId load logic).
    final originalBuildId = widget.inProgressBuildId;
    final currentBuildId = _currentInProgressId;
    final buildIdsToPreserve = <String>{
      if (originalBuildId != null) originalBuildId,
      if (currentBuildId != null) currentBuildId,
    };

    if (buildIdsToPreserve.isNotEmpty) {
      for (final buildId in buildIdsToPreserve) {
        try {
          print(
              '� Linking in-progress build $buildId to finalized document ${version.id} (type $type)');
          await InProgressBuildService.markFinalized(
            buildId: buildId,
            documentId: version.id!,
          );
          print('✅ In-progress build preserved and linked: $buildId');
        } catch (e) {
          print(
              '⚠️ Failed to mark in-progress build $buildId as finalized: $e');
        }
      }
    }
    // Any further edits to this build (if reopened) must go into a new
    // duplicate build, not this one.
    _currentInProgressId = null;
    _originalInProgressBuildDeleted = true;
    // No legacy cleanup here, only the build that created this document.

    // Save the job to cloud after creating final estimate/quote/invoice
    _persistJobToDisk().catchError((e) async {
      print('⚠️ Warning: failed to persist job before PDF preview: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Warning: PDF created but failed to save job: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    print('🧾 PDF ready, launching preview route.');
    final previewResult = await _showPdfPreview(pdf, file, fileName);
    if (previewResult == true) {
      if (mounted) {
        print('🧾 PDF preview route returned: $previewResult');
        Navigator.of(context).pop(true);
      }
      return;
    }

    // Call this after generating any PDF (estimate, quote, invoice)
    if (widget.onDocumentGenerated != null) {
      widget.onDocumentGenerated!(
        GeneratedDocument(
          id: UniqueKey().toString(),
          jobId: widget.job.id,
          type: type[0].toUpperCase() + type.substring(1),
          name: widget.job.customerName ?? '',
          address: widget.job.address ?? '',
          dueDate: dueDate,
          amount: totalIncGst,
          isPaid: false,
          isArchived: false,
          generatedAt: DateTime.now(),
        ),
      );
    }
  }
}
