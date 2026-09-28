part of '../estimate_builder_screen.dart';

// Small, self-contained helper methods extracted from
// _EstimateBuilderScreenState (no behavior change, verbatim move).
// Kept as an `extension` (not a mixin) so no field declarations need to
// move and there's no mixin `on`-clause ordering to get right - these
// still call `this.<field>` implicitly exactly as before.
extension EstimateBuilderUtilsExt on _EstimateBuilderScreenState {
  String _itemKey(estimate_item.EstimateItem item) {
    return '${item.name.trim().toLowerCase()}|${item.description.trim().toLowerCase()}|${item.section.trim().toLowerCase()}|${item.unitPrice.toStringAsFixed(2)}';
  }

  double _calculateAlreadyInvoicedQuantity(estimate_item.EstimateItem item) {
    final itemKey = _itemKey(item);
    return widget.job.estimateVersions
        .where((version) => version.type == 'invoice')
        .fold<double>(0.0, (sum, version) {
      return sum +
          version.items.where((invoicedItem) {
            return _itemKey(invoicedItem) == itemKey;
          }).fold<double>(0.0, (innerSum, invoicedItem) {
            return innerSum + invoicedItem.quantity;
          });
    });
  }

  String _lineItemControllerKey(estimate_item.EstimateItem item) {
    return '${item.section}||${item.description}||${item.name}||${identityHashCode(item)}';
  }

  double _effectivePriceFromPriceBookItem(models.PriceBookItem item) {
    // 🔴 NEW: Handle per-meter pricing
    double baseSalePrice = item.price;

    if (item.isPerMeter && item.meterAmount > 0) {
      // For per-meter items, calculate per-meter sale price
      baseSalePrice = item.salePrice / item.meterAmount;
    }

    if (item.purchasePrice > 0 && item.percentageChanged != 0) {
      return double.parse(
        (item.purchasePrice * (1 + item.percentageChanged / 100))
            .toStringAsFixed(2),
      );
    }
    return baseSalePrice;
  }

  /// 🔴 NEW: Get effective purchase price for a line item, handling per-meter pricing
  double _getEffectivePurchasePrice(estimate_item.EstimateItem item) {
    if (item.purchasePrice == null || item.purchasePrice! <= 0) {
      return 0;
    }

    if (item.isPerMeter && item.meterAmount > 0) {
      // Per-meter item: purchase price is for total meters, divide by meter amount
      return item.purchasePrice! / item.meterAmount;
    }

    return item.purchasePrice!;
  }

  TextEditingController _getSalePriceController(
      estimate_item.EstimateItem item) {
    final key = _lineItemControllerKey(item);
    return _itemSalePriceControllers.putIfAbsent(
      key,
      () => TextEditingController(text: item.unitPrice.toStringAsFixed(2)),
    );
  }

  TextEditingController _getQuantityController(
      estimate_item.EstimateItem item) {
    final key = _lineItemControllerKey(item);
    return _itemQuantityControllers.putIfAbsent(
      key,
      () => TextEditingController(
        text: item.quantity.truncateToDouble() == item.quantity
            ? item.quantity.toStringAsFixed(0)
            : item.quantity.toStringAsFixed(2),
      ),
    );
  }

  FocusNode _getSalePriceFocusNode(estimate_item.EstimateItem item) {
    final key = _lineItemControllerKey(item);
    return _itemSalePriceFocusNodes.putIfAbsent(key, () => FocusNode());
  }

  FocusNode _getQuantityFocusNode(estimate_item.EstimateItem item) {
    final key = _lineItemControllerKey(item);
    return _itemQuantityFocusNodes.putIfAbsent(key, () => FocusNode());
  }

  void _commitSalePriceEdit(estimate_item.EstimateItem item,
      {bool save = true}) {
    final ctrl = _getSalePriceController(item);
    final parsed = double.tryParse(ctrl.text.trim());
    final price = parsed != null ? parsed : item.unitPrice;
    ctrl.text = price.toStringAsFixed(2);
    if (price != item.unitPrice) {
      // The user has hand-typed a sell price here, distinct from the
      // pricebook-derived price. Flag it so a later estimate->invoice
      // conversion's "Purchase Prices Have Changed" dialog leaves this
      // item's sell price alone (informational only if its buy price also
      // changed) instead of offering to overwrite it.
      final newItem =
          item.copyWith(unitPrice: price, sellPriceManuallyEdited: true);
      _updateItemFast(item, newItem);
    }
    if (save) {
      _debouncedSave();
    }
  }

  void _commitQuantityEdit(estimate_item.EstimateItem item,
      {bool save = true}) {
    final ctrl = _getQuantityController(item);
    final parsed = double.tryParse(ctrl.text.trim());
    final qty = (parsed != null && parsed >= 0) ? parsed : item.quantity;
    ctrl.text = qty.truncateToDouble() == qty
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(2);
    if (qty != item.quantity) {
      final newItem = item.copyWith(quantity: qty);
      _updateItemFast(item, newItem);
    }
    if (save) {
      _debouncedSave();
    }
  }

  // Helper for month abbreviation
  String _monthAbbr(int month) {
    const abbr = [
      '', // 0 index unused
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month < 1 || month > 12) return '';
    return abbr[month];
  }

  int _boundedLevenshtein(String source, String target, int maxDistance) {
    if (source == target) return 0;
    if ((source.length - target.length).abs() > maxDistance) {
      return maxDistance + 1;
    }
    if (source.isEmpty) return target.length;
    if (target.isEmpty) return source.length;

    if (target.length > source.length) {
      final shorter = source;
      source = target;
      target = shorter;
    }

    var previous = List<int>.generate(target.length + 1, (index) => index);
    for (var sourceIndex = 1; sourceIndex <= source.length; sourceIndex++) {
      final current = List<int>.filled(target.length + 1, maxDistance + 1);
      current[0] = sourceIndex;
      var rowMinimum = current[0];

      for (var targetIndex = 1; targetIndex <= target.length; targetIndex++) {
        final substitutionCost = source.codeUnitAt(sourceIndex - 1) ==
                target.codeUnitAt(targetIndex - 1)
            ? 0
            : 1;
        final distance = [
          previous[targetIndex] + 1,
          current[targetIndex - 1] + 1,
          previous[targetIndex - 1] + substitutionCost,
        ].reduce((left, right) => left < right ? left : right);
        current[targetIndex] = distance;
        if (distance < rowMinimum) rowMinimum = distance;
      }

      if (rowMinimum > maxDistance) return maxDistance + 1;
      previous = current;
    }

    return previous[target.length] <= maxDistance
        ? previous[target.length]
        : maxDistance + 1;
  }

  /// Check if changes have been made to items or subsections compared to original state
  bool _hasChangesFromOriginal() {
    if (!_isEditingFinalBuild)
      return true; // Always save for new builds/templates

    print(
        '🔍 Checking changes: ${items.length} vs ${_originalItems.length} items');

    // Check if item count changed
    if (items.length != _originalItems.length) {
      print(
          '🔍 Item count changed: ${_originalItems.length} → ${items.length}');
      return true;
    }

    // Check if subsection count changed
    final currentSections = _subsections
        .where((s) => s.name != '---OPTIONS---')
        .map((s) => s.name)
        .toList();
    final originalSections =
        _originalSubsections.where((s) => s != '---OPTIONS---').toList();
    if (currentSections.length != originalSections.length) {
      print(
          '🔍 Subsection count changed: ${originalSections.length} → ${currentSections.length}');
      return true;
    }

    // Check if any items changed (more thorough comparison)
    for (int i = 0; i < items.length; i++) {
      if (i >= _originalItems.length) {
        print('🔍 Item added at index $i');
        return true;
      }

      final current = items[i];
      final original = _originalItems[i];

      if (current.name != original.name ||
          current.description != original.description ||
          current.unitPrice != original.unitPrice ||
          current.quantity != original.quantity ||
          current.section != original.section ||
          current.purchasePrice != original.purchasePrice) {
        print(
            '🔍 Item changed at index $i: ${original.description} → ${current.description}');
        return true;
      }
    }

    // Check if any subsections changed
    for (int i = 0; i < currentSections.length; i++) {
      if (i >= originalSections.length ||
          currentSections[i] != originalSections[i]) {
        print('🔍 Subsection changed at index $i');
        return true;
      }
    }

    print('🔍 No changes detected');
    return false;
  }

  /// Simple method to trigger save only when items actually change
  void _triggerAutoSaveIfNeeded() {
    // Only save if there are actual items and we're not already saving
    if (items.isNotEmpty && !_isSaving) {
      _debouncedAutoSave();
    }
  }
}
