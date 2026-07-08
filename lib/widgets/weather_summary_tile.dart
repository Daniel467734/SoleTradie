import 'package:flutter/material.dart';
import '../services/weather_service.dart';

/// Compact weather summary widget - shows a single day's forecast (icon,
/// description, high/low temps, and precipitation chance).
///
/// Used both on the Dashboard (office address weather) and in the job
/// scheduling flow (weather for a selected schedule day).
class WeatherSummaryTile extends StatelessWidget {
  final DailyForecast forecast;
  final String? label;
  final bool dense;

  const WeatherSummaryTile({
    super.key,
    required this.forecast,
    this.label,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final high = forecast.tempMaxC.round();
    final low = forecast.tempMinC.round();

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 10 : 14, vertical: dense ? 8 : 12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(forecast.icon, color: colorScheme.primary, size: dense ? 24 : 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                Text(
                  forecast.description,
                  style: (dense
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.titleSmall)
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (forecast.precipitationProbability > 0)
                  Text(
                    '${forecast.precipitationProbability}% chance of rain',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$high°',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '$low°',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
