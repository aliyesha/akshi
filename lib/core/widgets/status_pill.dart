import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

Color monitorStatusColor(ColorScheme scheme, MonitorStatus status) =>
    switch (status) {
      MonitorStatus.healthy => scheme.secondary,
      MonitorStatus.warning => const Color(0xFFA66B00),
      MonitorStatus.critical => const Color(0xFFD25932),
      MonitorStatus.expired || MonitorStatus.failed => scheme.error,
      MonitorStatus.unavailable || MonitorStatus.unknown => scheme.outline,
    };

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final MonitorStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = monitorStatusColor(scheme, status);
    final icon = switch (status) {
      MonitorStatus.healthy => LucideIcons.circle_check,
      MonitorStatus.warning => LucideIcons.timer,
      MonitorStatus.critical => LucideIcons.triangle_alert,
      MonitorStatus.expired => LucideIcons.circle_x,
      MonitorStatus.failed => LucideIcons.circle_alert,
      MonitorStatus.unavailable => LucideIcons.circle_minus,
      MonitorStatus.unknown => LucideIcons.circle_question_mark,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: (24) / 255),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
