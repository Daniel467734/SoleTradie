part of '../estimate_builder_screen.dart';

// Profit / totals calculation helpers extracted from
// _EstimateBuilderScreenState (no behavior change, verbatim move).
// Note: _applyProjectManagerMarkup and _toggleProfitView stay in the main
// class file (not here) since they call setState() directly - Dart's
// analyzer flags State.setState as @protected and disallows calling it
// from extension methods (invalid_use_of_protected_member), even though
// it works fine at runtime. Keeping them in the class avoids that warning.
extension _EstimateBuilderProfitExt on _EstimateBuilderScreenState {
  // Helper method to calculate the line total for an item, including discount
  double _lineTotal(estimate_item.EstimateItem item) {
    final discount = item.discountAmount ?? 0;
    return (item.unitPrice * item.quantity) - discount;
  }

  double _lineProfit(estimate_item.EstimateItem item) {
    final discount = item.discountAmount ?? 0;
    return ((item.unitPrice * item.quantity - discount) -
        ((item.purchasePrice ?? 0) * item.quantity));
  }

  /// Calculates the QUOTED subsection total (what was estimated/quoted originally).
  /// 🔴 FIXED: Now returns the stored original quoted amount for this subsection (from the estimate/quote),
  /// NOT calculated from line items. This amount is INDEPENDENT and doesn't change as items are added/removed.
  /// If no quoted amount was stored (new build, not a conversion), returns 0.
  double _quotedSubsectionTotal(List<estimate_item.EstimateItem> items) {
    if (items.isEmpty) return 0.0;

    // Get the section name from the first item
    final sectionName = items.first.section;

    // Return the stored quoted amount for this section, or 0 if not set
    return _quotedSubsectionAmounts[sectionName] ?? 0.0;
  }

  /// Calculates the ACTUAL subsection total (what's currently on the invoice).
  /// This represents the real cost of the subsection with all items currently included.
  double _actualSubsectionTotal(List<estimate_item.EstimateItem> items) {
    return items.fold<double>(0, (sum, item) => sum + _lineTotal(item));
  }

  /// Calculates subsection difference: current total - quoted total.
  /// Positive = over quote (items added or quantities increased)
  /// Negative = under quote (items removed or quantities decreased)
  /// Accounts for items that weren't estimated but are used, AND items that were estimated but aren't used.
  double _subsectionQuotedDifference(List<estimate_item.EstimateItem> items) {
    final actual = _actualSubsectionTotal(items);
    final quoted = _quotedSubsectionTotal(items);
    return quoted - actual;
  }

  /// 🔴 NEW: Loads the original quoted amounts from the source estimate/quote.
  /// Called when converting an estimate/quote to an invoice to capture the fixed budget amounts.
  /// Groups items by section and stores the totals in [_quotedSubsectionAmounts] and [_quotedDocumentTotal].
  void _loadQuotedAmountsFromSourceEstimate() {
    if (widget.initialItems == null || widget.initialItems!.isEmpty) {
      return;
    }

    // Clear previous values
    _quotedSubsectionAmounts.clear();

    // Group items by section and calculate totals
    final Map<String, double> sectionTotals = {};
    for (final item in widget.initialItems!) {
      final sectionName = item.section;
      final itemTotal = _lineTotal(item);
      sectionTotals[sectionName] =
          (sectionTotals[sectionName] ?? 0) + itemTotal;
    }

    // Store subsection totals
    sectionTotals.forEach((section, total) {
      _quotedSubsectionAmounts[section] = total;
    });

    // Calculate and store document total
    _quotedDocumentTotal =
        sectionTotals.values.fold<double>(0, (sum, total) => sum + total);

    print('📋 Loaded quoted amounts from source estimate: '
        'subsections=$_quotedSubsectionAmounts, documentTotal=$_quotedDocumentTotal');
  }
}
