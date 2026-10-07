import 'package:akshi/features/monitors/domain/monitor_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

Color monitorStatusColor(ColorScheme scheme, MonitorStatus status) {
  final warning = scheme.brightness == Brightness.dark
      ? const Color(0xFFFFC857)
      : const Color(0xFF8A5700);
  final critical = scheme.brightness == Brightness.dark
      ? const Color(0xFFFF9A76)
      : const Color(0xFFB63F1C);
  return switch (status) {
    MonitorStatus.healthy => scheme.secondary,
    MonitorStatus.warning || MonitorStatus.unavailable => warning,
    MonitorStatus.critical => critical,
    MonitorStatus.expired || MonitorStatus.failed => scheme.error,
    MonitorStatus.unknown || MonitorStatus.incomplete => scheme.outline,
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final MonitorStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = monitorStatusColor(scheme, status);
    final icon = switch (status) {
      MonitorStatus.healthy => PhosphorIconsDuotone.checkCircle,
      MonitorStatus.warning => PhosphorIconsDuotone.warning,
      MonitorStatus.critical => PhosphorIconsDuotone.warning,
      MonitorStatus.expired => PhosphorIconsDuotone.xCircle,
      MonitorStatus.failed => PhosphorIconsDuotone.warningCircle,
      MonitorStatus.unavailable => PhosphorIconsDuotone.minusCircle,
      MonitorStatus.incomplete => PhosphorIconsDuotone.info,
      MonitorStatus.unknown => PhosphorIconsDuotone.question,
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
          PhosphorIcon(icon, size: 14, color: color),
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
