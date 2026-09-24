import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// The shared visual shell for monitor data across Domain, TLS, Email, and DNS.
///
/// Defining the shape, clipping, and surface color here avoids Flutter widget
/// defaults that can render differently across Android versions and devices.
class MonitorSurface extends StatelessWidget {
  const MonitorSurface({
    required this.child,
    super.key,
    this.padding,
    this.color,
    this.border,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderSide? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// A shared icon treatment for record/finding cards.
class MonitorIconBadge extends StatelessWidget {
  const MonitorIconBadge({
    required this.icon,
    required this.color,
    super.key,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: PhosphorIcon(
      icon,
      size: size * .52,
      color: color,
    ),
  );
}
