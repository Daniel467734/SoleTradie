class PriceSuggestionService {
  static const Map<String, Map<String, dynamic>> _basePrices = {
    'labour': {
      'baseRate': 85.0,
      'variations': {
        'standard': 1.0,
        'weekend': 1.5,
        'emergency': 2.0,
        'apprentice': 0.7,
      },
    },
    'callout': {
      'baseRate': 120.0,
      'variations': {
        'local': 1.0,
        'distant': 1.5,
        'emergency': 2.0,
      },
    },
  };

  /// Get suggested price based on item type and context
  static double getSuggestedPrice(String itemType, {String? context}) {
    final baseData = _basePrices[itemType.toLowerCase()];
    if (baseData == null) return 0.0;
    
    final baseRate = baseData['baseRate'] as double;
    final variations = baseData['variations'] as Map<String, dynamic>;
    
    if (context != null && variations.containsKey(context)) {
      return baseRate * (variations[context] as double);
    }
    
    return baseRate;
  }

  /// Get market rate comparison
  static Map<String, double> getMarketComparison(double currentPrice, String itemType) {
    final suggested = getSuggestedPrice(itemType);
    return {
      'current': currentPrice,
      'suggested': suggested,
      'difference': currentPrice - suggested,
      'percentage': suggested > 0 ? ((currentPrice - suggested) / suggested * 100) : 0,
    };
  }

  /// Smart markup calculator
  static double calculateOptimalMarkup(double costPrice, String category) {
    switch (category.toLowerCase()) {
      case 'materials':
        return costPrice * 1.4; // 40% markup
      case 'fixtures':
        return costPrice * 1.3; // 30% markup
      case 'consumables':
        return costPrice * 1.6; // 60% markup
      default:
        return costPrice * 1.35; // 35% markup
    }
  }
}
