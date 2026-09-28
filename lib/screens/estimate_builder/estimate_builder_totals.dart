part of '../estimate_builder_screen.dart';

// Document/section total + deposit getters extracted from
// _EstimateBuilderScreenState (no behavior change, verbatim move).
// Pure computed getters - no setState calls, safe as a plain extension.
extension _EstimateBuilderTotalsExt on _EstimateBuilderScreenState {
  double get gstAmount => subTotalExGst * 0.15;
  double get totalIncGst => subTotalExGst * 1.15;
  double get totalProfit =>
      items.fold(0.0, (sum, item) {
        if (normalizeCode(item.description) == 'dis') {
          return sum - item.unitPrice * item.quantity;
        }
        final purchase = (item.purchasePrice ?? 0);
        return sum + ((item.unitPrice - purchase) * item.quantity);
      }) -
      _totalSectionExtraCosts;
  // Sum of every subsection's internal-only extra cost, deducted from
  // profit but never shown on customer-facing documents.
  double get _totalSectionExtraCosts =>
      _subsections.fold(0.0, (sum, section) => sum + section.extraCost);
  double get subTotalExGst =>
      items.fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));
  double get mainSubTotalExGst => items
      .where((item) => mainSections.any((s) => s.name == item.section))
      .fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));
  double get mainGstAmount => mainSubTotalExGst * 0.15;
  double get mainTotalIncGst => mainSubTotalExGst * 1.15;

  double get currentDepositAmount {
    if (_depositAmount != null && !_isDepositPercentage) {
      return _depositAmount!;
    } else if (_depositPercentage != null && _isDepositPercentage) {
      return mainTotalIncGst * (_depositPercentage! / 100.0);
    }
    return 0.0;
  }

  Future<bool> getShowLineItemPricesDefault() async {
    // You can customize this logic, e.g. load from SharedPreferences if needed
    return true;
  }

  List<SubsectionData> get mainSections {
    // All sections before the first "option divider"
    final dividerIndex =
        _subsections.indexWhere((s) => s.name == '---OPTIONS---');
    if (dividerIndex == -1) return _subsections;
    return _subsections.sublist(0, dividerIndex);
  }

  List<SubsectionData> get optionSections {
    // All sections after the first "option divider"
    final dividerIndex =
        _subsections.indexWhere((s) => s.name == '---OPTIONS---');
    if (dividerIndex == -1) return [];
    return _subsections.sublist(dividerIndex + 1);
  }
}
