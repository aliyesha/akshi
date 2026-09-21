import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class ExpiryMetric extends StatelessWidget {
  const ExpiryMetric({
    required this.label,
    required this.date,
    required this.icon,
    super.key,
  });

  final String label;
  final DateTime? date;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = date?.difference(DateTime.now()).inDays;
    final value = switch (days) {
      null => '—',
      < 0 => 'Expired',
      0 => 'Today',
      1 => '1 day',
      _ => '$days days',
    };
    final urgent = days != null && days <= 5;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: urgent
              ? scheme.errorContainer.withValues(alpha: (90) / 255)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                PhosphorIcon(icon, size: 16, color: scheme.onSurfaceVariant),
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
