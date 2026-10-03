part of '../estimate_builder_screen.dart';

extension _EstimateBuilderSaveHelpersExt on _EstimateBuilderScreenState {
  Future<String?> _createInvoiceSnapshotBuilds({
    required double invoiceTotalIncGst,
    required double totalProfit,
  }) async {
    try {
      final List<String> subsections = _subsections.map((s) => s.name).toList();
      final Map<String, dynamic> additionalData = {
        'depositAmount': _depositAmount,
        'depositPercentage': _depositPercentage,
        'isDepositPercentage': _isDepositPercentage,
        'buildType': _buildType,
        'sectionDescriptions': {
          for (final section in _subsections) section.name: section.description,
        },
        'sectionExtraCosts': {
          for (final section in _subsections) section.name: section.extraCost,
        },
        'builderNote': _jobNotesController.text.trim(),
        'scopeSummaryNotes': _scopeSummaryController.text.trim(),
        'scopeExclusionsNotes': _scopeExclusionsController.text.trim(),
        'liabilityRisks': _selectedLiabilityRisks,
      };

      final invoiceSnapshotBuild = await InProgressBuildService.createNewBuild(
        jobId: widget.job.id,
        items: items.map((item) => item.copyWith()).toList(),
        subsections: subsections,
        buildName: 'Invoice Snapshot Build',
        buildType: 'invoice',
        totalAmount: invoiceTotalIncGst,
        totalProfit: totalProfit,
        additionalData: additionalData,
      );

      final remainingItems =
          items.map((item) => item.copyWith(quantity: 0)).toList();
      await InProgressBuildService.createNewBuild(
        jobId: widget.job.id,
        items: remainingItems,
        subsections: subsections,
        buildName: 'Remaining Invoice Build',
        buildType: _buildType,
        totalAmount: 0.0,
        totalProfit: 0.0,
        additionalData: additionalData,
      );

      return invoiceSnapshotBuild.id;
    } catch (e) {
      print('⚠️ Failed to create invoice snapshot builds: $e');
      return null;
    }
  }

  void _saveEstimate() async {
    try {
      widget.job.estimateItems
        ..clear()
        ..addAll(items.map((e) => estimate_item.EstimateItem(
              name: e.name,
              description: e.description,
              unitPrice: e.unitPrice,
              quantity: e.quantity,
              purchasePrice: e.purchasePrice,
              section: e.section,
            )));

      final saved = await _saveInProgressEstimate();
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Build saved successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to save build. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save build: $e')),
      );
    }
  }
}
