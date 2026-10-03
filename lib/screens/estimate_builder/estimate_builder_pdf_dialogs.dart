part of '../estimate_builder_screen.dart';

extension _EstimateBuilderPdfDialogsExt on _EstimateBuilderScreenState {
  Future<void> _showGeneratePdfDialog() async {
    print('🧾 _showGeneratePdfDialog opened; items=${items.length}');

    final missingCustomer = widget.job.customerName == null ||
        widget.job.customerName!.trim().isEmpty;
    final missingAddress =
        widget.job.address == null || widget.job.address!.trim().isEmpty;

    if (missingCustomer || missingAddress) {
      final warningProceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Missing Job Details'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (missingCustomer)
                    const Text('This job has no customer name.'),
                  if (missingAddress)
                    const Text('This job has no site address.'),
                  const SizedBox(height: 12),
                  const Text(
                    'A PDF generated without customer or address information may be blank or incomplete.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                      'Please add these details before generating a PDF.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go Back'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue Anyway'),
                ),
              ],
            ),
          ) ??
          false;

      if (!warningProceed) return;
    }

    final zeroQtyItems = widget.convertToInvoice
        ? <estimate_item.EstimateItem>[]
        : items.where((item) => item.quantity == 0).toList();
    final zeroPriceItems = items
        .where((item) =>
            item.unitPrice == 0 && normalizeCode(item.description) != 'dis')
        .toList();

    bool proceed = true;
    if (zeroQtyItems.isNotEmpty || zeroPriceItems.isNotEmpty) {
      proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Invalid Items'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (zeroQtyItems.isNotEmpty)
                    ...zeroQtyItems.map((item) => Text(
                        'Item "${item.name}" has quantity 0',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
                  if (zeroPriceItems.isNotEmpty)
                    ...zeroPriceItems.map((item) => Text(
                        'Item "${item.name}" has \$0 amount',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 12),
                  const Text(
                      'Please fix these items before generating a PDF, or continue anyway.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go Back'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue Anyway'),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (!proceed) return;

    final method = _buildType;
    print('🧾 Generating PDF using build type: $method');

    final String scopeText = _scopeSummaryController.text.trim();
    final String exclusionsText = _scopeExclusionsController.text.trim();
    final bool scopePageAvailable = scopeText.isNotEmpty ||
        exclusionsText.isNotEmpty ||
        _selectedLiabilityRisks.isNotEmpty;
    final prefs = await SharedPreferences.getInstance();
    final bool defaultAttachScopePage =
        prefs.getBool('attach_scope_page_by_default') ?? true;

    final pdfOptions = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        String selectedLayout = 'full';
        bool includeScope = scopePageAvailable && defaultAttachScopePage;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Generate PDF'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _canChangeBuildType
                          ? () async {
                              Navigator.pop(context, null);
                              await _showChangeBuildTypeDialog();
                              await _showGeneratePdfDialog();
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8.0, horizontal: 4.0),
                        child: Row(
                          children: [
                            Icon(_buildTypeIcon(method),
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Generating: ${_buildTypeLabel(method)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (_canChangeBuildType) ...[
                              const Spacer(),
                              const Text('Change',
                                  style: TextStyle(color: Colors.blue)),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: Colors.blue),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    RadioListTile<String>(
                      value: 'full',
                      groupValue: selectedLayout,
                      title: const Text('Full line item pricing'),
                      subtitle: const Text(
                          'Full line item detail + subsection totals + description'),
                      onChanged: (value) {
                        setState(() => selectedLayout = value!);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'compact',
                      groupValue: selectedLayout,
                      title: const Text('No line item pricing'),
                      subtitle: const Text(
                          'Line items only, no line totals + subsection totals + description'),
                      onChanged: (value) {
                        setState(() => selectedLayout = value!);
                      },
                    ),
                    RadioListTile<String>(
                      value: 'summary',
                      groupValue: selectedLayout,
                      title: const Text('Descriptions only'),
                      subtitle:
                          const Text('Descriptions only + subsection totals'),
                      onChanged: (value) {
                        setState(() => selectedLayout = value!);
                      },
                    ),
                    const Divider(),
                    if (scopePageAvailable) ...[
                      CheckboxListTile(
                        value: includeScope,
                        onChanged: (value) {
                          setState(() => includeScope = value ?? false);
                        },
                        title: const Text('Attach job scope page to PDF'),
                        subtitle: const Text(
                            'Add a job scope summary page with date, company and work outline.'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'No scope or exclusions text is available to attach.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, {
                    'layout': selectedLayout,
                    'includeScopePage': includeScope,
                  }),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    if (pdfOptions == null) return;

    final layout = pdfOptions['layout'] as String;
    final includeScopePage = pdfOptions['includeScopePage'] as bool;

    print(
        '🧾 PDF generation method selected: $method layout=$layout includeScopePage=$includeScopePage');
    FocusScope.of(context).unfocus();
    await _generateEstimatePdf(
      type: method,
      layout: layout,
      includeScopePage: includeScopePage,
    );
  }
}
