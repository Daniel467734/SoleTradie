import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A single day's forecast returned by [WeatherService].
class DailyForecast {
  /// Date-only (time set to midnight, local).
  final DateTime date;
  final double tempMaxC;
  final double tempMinC;
  final int weatherCode; // WMO weather interpretation code.
  final int precipitationProbability; // 0-100, max chance for the day.

  const DailyForecast({
    required this.date,
    required this.tempMaxC,
    required this.tempMinC,
    required this.weatherCode,
    required this.precipitationProbability,
  });

  /// Short human-readable description for this WMO weather code.
  /// See: https://open-meteo.com/en/docs (WMO weather interpretation codes)
  String get description {
    switch (weatherCode) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 56:
      case 57:
        return 'Freezing drizzle';
      case 61:
        return 'Light rain';
      case 63:
        return 'Rain';
      case 65:
        return 'Heavy rain';
      case 66:
      case 67:
        return 'Freezing rain';
      case 71:
        return 'Light snow';
      case 73:
        return 'Snow';
      case 75:
        return 'Heavy snow';
      case 77:
        return 'Snow grains';
      case 80:
        return 'Light showers';
      case 81:
        return 'Showers';
      case 82:
        return 'Violent showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Unknown';
    }
  }

  /// Icon that best represents this WMO weather code.
  IconData get icon {
    switch (weatherCode) {
      case 0:
        return Icons.wb_sunny;
      case 1:
      case 2:
        return Icons.wb_twilight;
      case 3:
        return Icons.wb_cloudy;
      case 45:
      case 48:
        return Icons.foggy;
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return Icons.grain;
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return Icons.water_drop;
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return Icons.ac_unit;
      case 95:
      case 96:
      case 99:
        return Icons.thunderstorm;
      default:
        return Icons.cloud;
    }
  }

  factory DailyForecast.fromJson({
    required String isoDate,
    required double tempMax,
    required double tempMin,
    required int code,
    required int precipProbability,
  }) {
    final parsed = DateTime.parse(isoDate);
    return DailyForecast(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      tempMaxC: tempMax,
      tempMinC: tempMin,
      weatherCode: code,
      precipitationProbability: precipProbability,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'tempMaxC': tempMaxC,
        'tempMinC': tempMinC,
        'weatherCode': weatherCode,
        'precipitationProbability': precipitationProbability,
      };

  factory DailyForecast.fromCacheJson(Map<String, dynamic> json) {
    return DailyForecast(
      date: DateTime.parse(json['date'] as String),
      tempMaxC: (json['tempMaxC'] as num).toDouble(),
      tempMinC: (json['tempMinC'] as num).toDouble(),
      weatherCode: json['weatherCode'] as int,
      precipitationProbability: json['precipitationProbability'] as int,
    );
  }
}

/// Fetches free, no-API-key-required weather forecasts from Open-Meteo
/// (https://open-meteo.com) and provides simple helpers for looking up the
/// forecast for a specific day within the returned window.
class WeatherService {
  static const _cacheKeyPrefix = 'weather_cache_';

  /// Fetches a 7-day forecast for the given coordinates.
  ///
  /// Results are cached in [SharedPreferences] for a short time (per
  /// rounded lat/lon "cell" and calendar day) so rapidly re-opening a
  /// dialog, or navigating back and forth, doesn't spam the API.
  static Future<List<DailyForecast>> getSevenDayForecast({
    required double latitude,
    required double longitude,
  }) async {
    final cacheKey = _cacheKeyFor(latitude, longitude);

    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;

    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': latitude.toStringAsFixed(4),
        'longitude': longitude.toStringAsFixed(4),
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': '7',
      });

      final response = await http.get(uri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Open-Meteo API timeout'),
          );

      if (response.statusCode != 200) {
        print('⚠️ Open-Meteo API error: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>?;
      if (daily == null) return [];

      final dates = (daily['time'] as List).cast<String>();
      final maxTemps = (daily['temperature_2m_max'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final minTemps = (daily['temperature_2m_min'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final codes =
          (daily['weather_code'] as List).map((e) => (e as num).toInt()).toList();
      final precipProbabilities =
          (daily['precipitation_probability_max'] as List?)
                  ?.map((e) => (e as num?)?.toInt() ?? 0)
                  .toList() ??
              List.filled(dates.length, 0);

      final forecasts = <DailyForecast>[
        for (var i = 0; i < dates.length; i++)
          DailyForecast.fromJson(
            isoDate: dates[i],
            tempMax: maxTemps[i],
            tempMin: minTemps[i],
            code: codes[i],
            precipProbability:
                i < precipProbabilities.length ? precipProbabilities[i] : 0,
          ),
      ];

      await _writeCache(cacheKey, forecasts);
      return forecasts;
    } catch (e) {
      print('⚠️ Error fetching weather forecast: $e');
      return [];
    }
  }

  /// Returns the forecast entry matching [date] (compared by year/month/day)
  /// or null if [date] falls outside the fetched window or no forecast is
  /// available for it.
  static DailyForecast? forecastForDate(
      List<DailyForecast> forecasts, DateTime date) {
    for (final forecast in forecasts) {
      if (forecast.date.year == date.year &&
          forecast.date.month == date.month &&
          forecast.date.day == date.day) {
        return forecast;
      }
    }
    return null;
  }

  /// Whether [date] falls within today..today+6 days (the 7-day window this
  /// service fetches). Callers should only attempt to show weather for
  /// dates where this returns true.
  static bool isWithinForecastWindow(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    return diff >= 0 && diff <= 6;
  }

  static String _cacheKeyFor(double latitude, double longitude) {
    // Round to ~1.1km precision - plenty for daily forecast purposes, and
    // means tiny GPS jitter doesn't bust the cache/cause redundant fetches.
    final roundedLat = latitude.toStringAsFixed(2);
    final roundedLon = longitude.toStringAsFixed(2);
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return '$_cacheKeyPrefix${roundedLat}_${roundedLon}_$dateKey';
  }

  static Future<List<DailyForecast>?> _readCache(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(cacheKey);
      if (jsonString == null) return null;
      final list = jsonDecode(jsonString) as List;
      return list
          .map((e) => DailyForecast.fromCacheJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('⚠️ Error reading weather cache: $e');
      return null;
    }
  }

  static Future<void> _writeCache(
      String cacheKey, List<DailyForecast> forecasts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Clear out any stale cache entries from previous days so
      // SharedPreferences doesn't accumulate forever.
      final keysToRemove = prefs
          .getKeys()
          .where((key) => key.startsWith(_cacheKeyPrefix) && key != cacheKey)
          .toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
      final jsonString =
          jsonEncode(forecasts.map((f) => f.toJson()).toList());
      await prefs.setString(cacheKey, jsonString);
    } catch (e) {
      print('⚠️ Error writing weather cache: $e');
    }
  }
}
