import 'package:akshi/core/time/calendar_day.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class ExpiryMetric extends StatelessWidget {
  const ExpiryMetric({
    required this.label,
    required this.date,
    required this.icon,
    required this.accent,
    super.key,
  });

  final String label;
  final DateTime? date;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final expiry = date;
    final days = expiry == null
        ? null
        : localCalendarDayDifference(from: now, to: expiry);
    final value = expiry == null
        ? '—'
        : !expiry.isAfter(now)
        ? 'Expired'
        : switch (days!) {
            0 => 'Today',
            1 => '1 day',
            _ => '$days days',
          };
    final urgent = days != null && days <= 5;
    final identityBackground = accent.withValues(
      alpha: scheme.brightness == Brightness.dark ? .18 : .10,
    );
    final background = urgent
        ? Color.alphaBlend(
            scheme.error.withValues(
              alpha: scheme.brightness == Brightness.dark ? .12 : .07,
            ),
            identityBackground,
          )
        : identityBackground;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                PhosphorIcon(icon, size: 16, color: accent),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: urgent ? scheme.error : scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
