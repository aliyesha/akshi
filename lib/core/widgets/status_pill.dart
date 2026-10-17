import 'package:akshi/features/domains/domain/domain_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

Color domainStatusColor(ColorScheme scheme, DomainStatus status) {
  final warning = scheme.brightness == Brightness.dark
      ? const Color(0xFFFFC857)
      : const Color(0xFF8A5700);
  final critical = scheme.brightness == Brightness.dark
      ? const Color(0xFFFF9A76)
      : const Color(0xFFB63F1C);
  return switch (status) {
    DomainStatus.healthy => scheme.secondary,
    DomainStatus.warning || DomainStatus.unavailable => warning,
    DomainStatus.critical => critical,
    DomainStatus.expired || DomainStatus.failed => scheme.error,
    DomainStatus.unknown || DomainStatus.incomplete => scheme.outline,
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final DomainStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = domainStatusColor(scheme, status);
    final icon = switch (status) {
      DomainStatus.healthy => PhosphorIconsDuotone.checkCircle,
      DomainStatus.warning => PhosphorIconsDuotone.warning,
      DomainStatus.critical => PhosphorIconsDuotone.warning,
      DomainStatus.expired => PhosphorIconsDuotone.xCircle,
      DomainStatus.failed => PhosphorIconsDuotone.warningCircle,
      DomainStatus.unavailable => PhosphorIconsDuotone.minusCircle,
      DomainStatus.incomplete => PhosphorIconsDuotone.info,
      DomainStatus.unknown => PhosphorIconsDuotone.question,
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
