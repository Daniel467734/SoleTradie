part of '../estimate_builder_screen.dart';

// Pricebook search/lookup/persistence helpers extracted from
// _EstimateBuilderScreenState (no behavior change, verbatim move).
// Methods that call setState() directly (_loadPriceBookFromDisk,
// _closeSectionSearch, _handleSpecialSearchItemAdded,
// _searchExtensivePriceBookAndOfferImport) stay in the main class file -
// see estimate_builder_utils.dart's file header for why.
extension _EstimateBuilderPricebookExt on _EstimateBuilderScreenState {
  /// Ensures hardcoded labour items (CAL, EST) are always present in the estimate builder pricebook
  void _ensureHardcodedLabourItems() {
    try {
      final hardcodedItems = [
        models.PriceBookItem(
          code: 'CAL',
          name: 'Labour',
          unit: 'HR',
          category: 'LABOUR', // changed from groupCode
          salePrice: 90.0, // changed from price
          purchasePrice: 0.0,
          favorite: false,
          markupPercent: 0,
          markupOverridden: false,
          origin: 'hardcoded',
          usageCount: 0,
          percentageChanged: 0,
        ),
        models.PriceBookItem(
          code: 'EST',
          name: 'Labour',
          unit: 'HR',
          category: 'LABOUR', // changed from groupCode
          salePrice: 90.0, // changed from price
          purchasePrice: 0.0,
          favorite: false,
          markupPercent: 0,
          markupOverridden: false,
          origin: 'hardcoded',
          usageCount: 0,
          percentageChanged: 0,
        ),
      ];

      for (final hardcodedItem in hardcodedItems) {
        final existingIndex =
            priceBook.indexWhere((item) => item.code == hardcodedItem.code);
        if (existingIndex == -1) {
          // Item doesn't exist, add it
          priceBook.add(hardcodedItem);
          print('✅ Added missing labour item: ${hardcodedItem.code}');
        }
      }
    } catch (e) {
      print('❌ Error ensuring hardcoded labour items: $e');
    }
  }

  /// Refresh template line item prices AND item names using the loaded
  /// pricebook. Whenever a build template is brought in (from the Job
  /// Details "Builder" button), every matched item's buy price, sell
  /// price, and item name are pulled fresh from the current pricebook -
  /// nothing about price/name is "saved" on the template itself. Only the
  /// item's ID/code (`description`) and quantity are preserved as-is from
  /// the template.
  void _refreshTemplateItemPricesFromPriceBook() {
    if (!_didLoadTemplate || priceBook.isEmpty || items.isEmpty) return;

    for (final existingItem in List<estimate_item.EstimateItem>.from(items)) {
      final matchingPriceBookItem = _findPriceBookMatchForItem(existingItem);
      if (matchingPriceBookItem == null) continue;

      final newUnitPrice =
          _effectivePriceFromPriceBookItem(matchingPriceBookItem);
      final unitPriceToUse =
          newUnitPrice > 0 ? newUnitPrice : existingItem.unitPrice;
      final newPurchasePrice = matchingPriceBookItem.purchasePrice;
      final nameToUse = matchingPriceBookItem.name.isNotEmpty
          ? matchingPriceBookItem.name
          : existingItem.name;

      final changed = unitPriceToUse != existingItem.unitPrice ||
          newPurchasePrice != (existingItem.purchasePrice ?? 0.0) ||
          nameToUse != existingItem.name;

      if (changed) {
        final updatedItem = existingItem.copyWith(
          unitPrice: unitPriceToUse,
          purchasePrice: newPurchasePrice,
          name: nameToUse,
        );
        _updateItemFast(existingItem, updatedItem);
      }
    }
    _didLoadTemplate = false;
  }

  /// Finds the pricebook entry (if any) matching an estimate/invoice line
  /// item by code/name, the same matching rules used elsewhere (template
  /// refresh, template apply, etc.) so behaviour stays consistent across
  /// the app.
  models.PriceBookItem? _findPriceBookMatchForItem(
      estimate_item.EstimateItem item) {
    final normalizedDescription = normalizeCode(item.description);
    final normalizedName = normalizeCode(item.name);
    // 🔴 EXACT MATCH: Try exact match on code first (case-insensitive)
    var match = priceBook.firstWhereOrNull((pbItem) {
      return pbItem.code.trim().toLowerCase() ==
          item.description.trim().toLowerCase();
    });
    if (match != null) return match;

    // Fallback to fuzzy matching with normalization for name
    return priceBook.firstWhereOrNull((pbItem) {
      final normalizedCodeValue = normalizeCode(pbItem.code);
      final normalizedNameValue = normalizeCode(pbItem.name);
      return normalizedCodeValue == normalizedDescription ||
          normalizedNameValue == normalizedDescription ||
          normalizedCodeValue == normalizedName ||
          normalizedNameValue == normalizedName;
    });
  }

  Future<List<models.PriceBookItem>> _loadExtensivePriceBookFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book_extensive.json');
      print('🔍 [ExtensiveLoad] looking for file at: ${file.path}');
      final exists = await file.exists();
      print('🔍 [ExtensiveLoad] file exists: $exists');
      if (!exists) {
        return [];
      }
      final jsonString = await file.readAsString();
      print('🔍 [ExtensiveLoad] file size: ${jsonString.length} chars');
      if (jsonString.trim().isEmpty) {
        print('🔍 [ExtensiveLoad] file is empty');
        return [];
      }

      final decoded = jsonDecode(jsonString);
      print('🔍 [ExtensiveLoad] decoded JSON type: ${decoded.runtimeType}');
      if (decoded is Map<String, dynamic>) {
        print('🔍 [ExtensiveLoad] decoded JSON keys: ${decoded.keys.toList()}');
      }

      List<Map<String, dynamic>> jsonList = [];

      List<Map<String, dynamic>> extractJsonList(dynamic source) {
        if (source is List) {
          print('🔍 [ExtensiveLoad] found list with length ${source.length}');
          return source.whereType<Map<String, dynamic>>().toList();
        }
        if (source is Map<String, dynamic>) {
          final child = source['items'] ?? source['data'];
          print(
              '🔍 [ExtensiveLoad] found map child keys: ${source.keys.toList()}');
          if (child is List) {
            print(
                '🔍 [ExtensiveLoad] extracted child list with length ${child.length}');
            return child.whereType<Map<String, dynamic>>().toList();
          }
          if (child is Map<String, dynamic>) {
            print('🔍 [ExtensiveLoad] descending into nested map');
            return extractJsonList(child);
          }
        }
        return [];
      }

      jsonList = extractJsonList(decoded);
      print('🔍 [ExtensiveLoad] extracted item count: ${jsonList.length}');

      if (jsonList.isEmpty) {
        print('🔍 [ExtensiveLoad] no items found after extraction');
        return [];
      }

      return jsonList.map(models.PriceBookItem.fromJson).toList();
    } catch (e, st) {
      print('❌ Error loading extensive pricebook: $e');
      print(st);
      return [];
    }
  }

  List<models.PriceBookItem> searchPriceBook(
      List<models.PriceBookItem> priceBook, String query,
      {int maxResults = 10}) {
    if (query.trim().isEmpty) return [];

    final q = query.trim().toLowerCase();
    final queryWords =
        q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final multiWord = queryWords.length > 1;

    bool matchesAllWords(String text) {
      final lower = text.toLowerCase();
      return queryWords.every((word) => lower.contains(word));
    }

    // 🔴 PERFORMANCE FIX: The previous implementation did 6 separate full
    // O(n) passes over the pricebook (exact/mostUsed/starred/partial/anyOrder/
    // fuzzy), and each pass used `.contains(item)` on the previous result
    // lists to de-duplicate - an O(n) list scan done for every single item,
    // making the whole function effectively O(n^2)+. It also always ran a
    // Levenshtein distance calculation against all 52,000+ items even when
    // exact/partial matches already existed. Since this runs on every
    // keystroke while searching the pricebook (and even on every widget
    // rebuild for the subsection search box), this was a major cause of the
    // "selecting from pricebook is slow" / scrolling-lag / GC-churn symptoms.
    //
    // Fix: classify each item in ONE pass into the first matching bucket
    // (exact > mostUsed > starred > partial > anyOrder), tracking already-seen
    // codes with a Set (O(1) lookup) instead of List.contains (O(n)). Fuzzy
    // (Levenshtein) matching only runs if we still need more results after
    // the cheap passes, and stops early once maxResults is reached.
    final exact = <models.PriceBookItem>[];
    final codeExact = <models.PriceBookItem>[];
    final mostUsed = <models.PriceBookItem>[];
    final starred = <models.PriceBookItem>[];
    final partial = <models.PriceBookItem>[];
    final anyOrder = <models.PriceBookItem>[];
    final seenCodes = <String>{};

    for (final item in priceBook) {
      if (seenCodes.contains(item.code)) continue;
      final codeLower = item.code.toLowerCase();
      final nameLower = item.name.toLowerCase();
      final barcodeLower = (item.barcode ?? '').toLowerCase();
      final containsQuery = codeLower.contains(q) ||
          nameLower.contains(q) ||
          barcodeLower.contains(q);

      // 🔴 NEW: Searching by exact stock/ID code should show ONLY that exact
      // item, not every partial match that happens to contain the code.
      if (codeLower == q) {
        codeExact.add(item);
        seenCodes.add(item.code);
      } else if (nameLower == q || barcodeLower == q) {
        exact.add(item);
        seenCodes.add(item.code);
      } else if (item.usageCount > 0 && containsQuery) {
        mostUsed.add(item);
        seenCodes.add(item.code);
      } else if (item.favorite == true && containsQuery) {
        starred.add(item);
        seenCodes.add(item.code);
      } else if (containsQuery) {
        partial.add(item);
        seenCodes.add(item.code);
      } else if (multiWord && matchesAllWords(item.name)) {
        anyOrder.add(item);
        seenCodes.add(item.code);
      }
    }
    mostUsed.sort((a, b) => b.usageCount.compareTo(a.usageCount));

    // An exact stock/ID code match means the user typed a specific code -
    // return only that, ignoring name/partial matches entirely.
    if (codeExact.isNotEmpty) {
      return codeExact.take(maxResults).toList();
    }

    final combined = [
      ...exact,
      ...mostUsed,
      ...starred,
      ...partial,
      ...anyOrder
    ];

    // Fuzzy match (Levenshtein distance <= 2) - only run if we still need
    // more results, and stop scanning as soon as we have enough.
    if (combined.length < maxResults && q.length >= 3) {
      for (final item in priceBook) {
        if (seenCodes.contains(item.code)) continue;
        final code = item.code.toLowerCase();
        final name = item.name.toLowerCase();
        if ((code.length - q.length).abs() > 2 &&
            (name.length - q.length).abs() > 2) {
          continue;
        }
        final codeDist = _boundedLevenshtein(code, q, 2);
        final nameDist =
            codeDist <= 2 ? codeDist : _boundedLevenshtein(name, q, 2);
        if (codeDist <= 2 || nameDist <= 2) {
          combined.add(item);
          seenCodes.add(item.code);
          if (combined.length >= maxResults) break;
        }
      }
    }

    final unique = combined.take(maxResults).toList();
    // Sort so that used items appear first, then by usage count and favorite status,
    // but exact name/barcode matches always stay pinned at the very top.
    final exactCodes = exact.map((e) => e.code).toSet();
    unique.sort((a, b) {
      final aExact = exactCodes.contains(a.code);
      final bExact = exactCodes.contains(b.code);
      if (aExact != bExact) return aExact ? -1 : 1;
      final aScore =
          (a.isUsed ? 10000 : 0) + (a.favorite ? 5000 : 0) + a.usageCount;
      final bScore =
          (b.isUsed ? 10000 : 0) + (b.favorite ? 5000 : 0) + b.usageCount;
      if (aScore != bScore) return bScore.compareTo(aScore);
      return 0;
    });
    return unique;
  }

  /// Adds a pricebook search result to the subsection, or (if it was already
  /// added earlier in this same search session) bumps its quantity instead of
  /// inserting a duplicate line. Must be called inside setState.
  /// Returns the resulting/updated estimate item so callers can run CAL/DIS
  /// follow-up handling.
  estimate_item.EstimateItem _addOrBumpPriceBookSearchResult(
      SubsectionData section, models.PriceBookItem item,
      {required bool closeSearchAfter}) {
    final addedMap =
        _sectionSearchAddedItems.putIfAbsent(section.name, () => {});
    final countMap =
        _sectionSearchAddCounts.putIfAbsent(section.name, () => {});
    final existing = addedMap[item.code];

    estimate_item.EstimateItem result;
    if (existing != null && items.contains(existing)) {
      final idx = items.indexOf(existing);
      result = existing.copyWith(quantity: existing.quantity + 1);
      items[idx] = result;
    } else {
      item.usageCount = item.usageCount + 1;
      final insertIdx = items.indexWhere((i) => i.section == section.name);
      result = estimate_item.EstimateItem(
        name: item.name,
        description: item.code,
        unitPrice: item.price,
        quantity: 1,
        purchasePrice: item.purchasePrice,
        section: section.name,
        isPerMeter: item.isPerMeter,
        meterAmount: item.meterAmount,
      );
      if (insertIdx == -1) {
        items.insert(0, result);
      } else {
        items.insert(insertIdx, result);
      }
    }
    addedMap[item.code] = result;
    countMap[item.code] = (countMap[item.code] ?? 0) + 1;
    _moveVehicleItemsToBottomInSection(section.name);
    _hasUnsavedChanges = true;

    if (closeSearchAfter) {
      _sectionSearchQueries[section.name] = '';
      _sectionSearchControllers[section.name]?.clear();
      addedMap.clear();
      countMap.clear();
      _sectionSearchShowMore[section.name] = false;
    }
    return result;
  }

  /// Adds an extensive-pricebook search result to the subsection (importing it
  /// into the local pricebook cache first), or bumps `existing`'s quantity if
  /// it was already added earlier in this same dialog session. Must be called
  /// inside setState.
  estimate_item.EstimateItem _addOrBumpExtensivePriceBookItem(
      SubsectionData section, models.PriceBookItem selectedItem,
      {estimate_item.EstimateItem? existing}) {
    final selectedCodeNormalized = normalizeCode(selectedItem.code);
    final existingIndex = priceBook.indexWhere((item) {
      return normalizeCode(item.code) == selectedCodeNormalized ||
          normalizeCode(item.name) == normalizeCode(selectedItem.name);
    });

    models.PriceBookItem importedItem;
    if (existingIndex == -1) {
      importedItem = models.PriceBookItem(
        code: selectedItem.code,
        name: selectedItem.name,
        category: selectedItem.category,
        purchasePrice: selectedItem.purchasePrice,
        salePrice: selectedItem.salePrice,
        unit: selectedItem.unit,
        description: selectedItem.description ?? selectedItem.name,
        barcode: selectedItem.barcode,
        favorite: false,
        origin: 'extensive_import',
        usageCount: 1,
        percentageChanged: 0,
        isEdited: true,
        needsSync: true,
        isUsed: true,
        priceLastChangedAt: DateTime.now(),
      );
      priceBook.add(importedItem);
    } else {
      importedItem = priceBook[existingIndex];
      final oldPurchasePrice = importedItem.purchasePrice;
      final oldSalePrice = importedItem.salePrice;
      if (selectedItem.purchasePrice > 0) {
        importedItem.purchasePrice = selectedItem.purchasePrice;
      }

      if (importedItem.percentageChanged != 0) {
        if (importedItem.purchasePrice > 0) {
          importedItem.salePrice = double.parse(
            (importedItem.purchasePrice *
                    (1 + importedItem.percentageChanged / 100))
                .toStringAsFixed(2),
          );
        }
      } else {
        if (selectedItem.salePrice > 0) {
          importedItem.salePrice = selectedItem.salePrice;
        }
        if (selectedItem.percentageChanged != 0) {
          importedItem.percentageChanged = selectedItem.percentageChanged;
          importedItem.markupPercent = selectedItem.percentageChanged;
          importedItem.markupOverridden = true;
          if (importedItem.purchasePrice > 0) {
            importedItem.salePrice = double.parse(
              (importedItem.purchasePrice *
                      (1 + importedItem.percentageChanged / 100))
                  .toStringAsFixed(2),
            );
          }
        }
      }

      importedItem.usageCount += 1;
      importedItem.isUsed = true;

      final priceActuallyChanged =
          (importedItem.purchasePrice - oldPurchasePrice).abs() >= 0.005 ||
              (importedItem.salePrice - oldSalePrice).abs() >= 0.005;
      if (priceActuallyChanged) {
        importedItem.markPriceChanged();
      }
    }

    estimate_item.EstimateItem result;
    if (existing != null && items.contains(existing)) {
      final idx = items.indexOf(existing);
      result = existing.copyWith(quantity: existing.quantity + 1);
      items[idx] = result;
    } else {
      result = estimate_item.EstimateItem(
        name: importedItem.name,
        description: importedItem.code,
        unitPrice: _effectivePriceFromPriceBookItem(importedItem),
        quantity: 1,
        purchasePrice: importedItem.purchasePrice,
        section: section.name,
        isPerMeter: importedItem.isPerMeter,
        meterAmount: importedItem.meterAmount,
      );
      final insertIdx = items.indexWhere((i) => i.section == section.name);
      if (insertIdx == -1) {
        items.insert(0, result);
      } else {
        items.insert(insertIdx, result);
      }
    }
    _moveVehicleItemsToBottomInSection(section.name);
    _hasUnsavedChanges = true;
    return result;
  }

  Future<void> _saveSubsectionItemProfitPercentToPriceBook(
      SubsectionData section) async {
    final sectionItems =
        items.where((item) => item.section == section.name).toList();
    if (sectionItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in this subsection to save.')),
      );
      return;
    }

    int savedCount = 0;
    for (final item in sectionItems) {
      if (item.purchasePrice == null || item.purchasePrice! <= 0) {
        continue;
      }
      final pbItem = priceBook.firstWhereOrNull((pb) {
        final codeMatch =
            normalizeCode(pb.code) == normalizeCode(item.description);
        final nameMatch =
            normalizeCode(pb.name) == normalizeCode(item.description);
        final nameMatchAlt = normalizeCode(pb.name) == normalizeCode(item.name);
        return codeMatch || nameMatch || nameMatchAlt;
      });
      if (pbItem == null) {
        continue;
      }
      final percent =
          ((item.unitPrice - item.purchasePrice!) / item.purchasePrice!) * 100;
      final priceActuallyChanged =
          (item.purchasePrice! - pbItem.purchasePrice).abs() >= 0.005 ||
              (item.unitPrice - pbItem.price).abs() >= 0.005;
      pbItem.percentageChanged = percent;
      pbItem.markupPercent = percent;
      pbItem.markupOverridden = true;
      pbItem.purchasePrice = item.purchasePrice!;
      pbItem.price = item.unitPrice;
      if (priceActuallyChanged) {
        pbItem.markPriceChanged();
      }
      savedCount++;
    }

    if (savedCount > 0) {
      _savePriceBookToDisk();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedCount > 0
              ? 'Saved profit % for $savedCount item${savedCount == 1 ? '' : 's'}.'
              : 'No matching pricebook items were updated.',
        ),
      ),
    );
  }

  void _savePriceBookToDisk() {
    _priceBookSaveDebounce?.cancel();
    _priceBookSaveDebounce = Timer(const Duration(milliseconds: 800), () {
      _runPriceBookSave();
    });
  }

  Future<void> _runPriceBookSave() async {
    // 🔍 MEMORY DEBUG: Price book save entry
    print(
        '🔍 [PRICEBOOK SAVE ENTRY] Starting _runPriceBookSave(), items=${priceBook.length}');

    if (_priceBookSaveInFlight) {
      // A save is already running - remember that we need another one once it's done.
      _priceBookSavePending = true;
      print('🔍 [PRICEBOOK SAVE] Skipping - already in flight, marked pending');
      return;
    }
    _priceBookSaveInFlight = true;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/price_book.json');

      // 🔍 MEMORY DEBUG: Before JSON encoding
      print(
          '🔍 [PRICEBOOK ENCODE] Converting ${priceBook.length} items to JSON...');
      final encodeStopwatch = Stopwatch()..start();

      final jsonList = priceBook.map((e) => e.toJson()).toList();
      final data = {
        'items': jsonList,
        'lastSaved': DateTime.now().toIso8601String(),
        'version': 1,
        'totalItems': jsonList.length,
      };

      // Encode off the UI thread - this is the expensive part for 50k+ items.
      final encoded = await compute(_encodePriceBookJson, data);
      print(
          '🔍 [PRICEBOOK ENCODE] Encoding took ${encodeStopwatch.elapsedMilliseconds}ms, encoded size ~${(encoded.length / 1024 / 1024).toStringAsFixed(1)}MB');

      // 🔍 MEMORY DEBUG: Before file write
      final writeStopwatch = Stopwatch()..start();
      await file.writeAsString(encoded);
      print(
          '🔍 [PRICEBOOK WRITE] File write took ${writeStopwatch.elapsedMilliseconds}ms');

      // 🎯 PERFORMANCE FIX: DO NOT sync to cloud on every save
      // The pricebook is already synced periodically (every 5 minutes via _cloudSyncTimer)
      // and on app exit (dispose). Syncing on every single item add/edit was causing
      // severe lag (blocking I/O to Firebase, network delays). Local pricebook is the
      // source of truth; cloud is just a backup/mirror. Cloud sync only needs to happen:
      // - Periodically (handled by timer)
      // - On app exit (handled in dispose)
      // - After PDF generation (handled separately)
      // NOT on every keystroke/item add/edit.

      // To restore cloud sync if needed, uncomment the code below:
      /*
      try {
        if (FirestoreService.isAuthenticated) {
          final firestoreItems = priceBook
              .map((item) => models.PriceBookItem(
                    code: item.code,
                    name: item.name,
                    category: item.groupCode,
                    purchasePrice: item.purchasePrice,
                    salePrice: item.price,
                    unit: item.unit,
                    description: '',
                    favorite: item.favorite,
                    usageCount: item.usageCount,
                  ))
              .toList();
          await FirestoreService.batchSavePriceBookItems(firestoreItems);
          print('✅ Pricebook synced to cloud (${firestoreItems.length} items)');
        }
      } catch (e) {
        print('Cloud sync failed, but local save succeeded: $e');
      }
      */
    } catch (e) {
      print('❌ Failed to save pricebook: $e');
    } finally {
      // 🔍 MEMORY DEBUG: Price book save exit
      print('🔍 [PRICEBOOK SAVE EXIT] _runPriceBookSave() completed');

      _priceBookSaveInFlight = false;
      if (_priceBookSavePending) {
        _priceBookSavePending = false;
        // Another save was requested while this one was running - run it now.
        unawaited(_runPriceBookSave());
      }
    }
  }
}
