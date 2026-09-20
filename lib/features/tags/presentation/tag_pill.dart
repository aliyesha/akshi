import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:material_ui/material_ui.dart';

class TagPill extends StatelessWidget {
  const TagPill({
    required this.tag,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final MonitorTag tag;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final source = Color(tag.colorArgb);
    final background = Color.alphaBlend(
      source.withValues(
        alpha: (selected ? (dark ? 92 : 60) : (dark ? 58 : 30)) / 255,
      ),
      scheme.surfaceContainerLowest,
    );
    final foreground = _foregroundFor(source, background, dark: dark);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: source, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            tag.name,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Material(
      color: background,
      shape: StadiumBorder(
        side: BorderSide(
          color: source.withValues(alpha: (selected ? 190 : 80) / 255),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

Color _foregroundFor(Color source, Color background, {required bool dark}) {
  final hsl = HSLColor.fromColor(source);
  var candidate = hsl.withLightness(dark ? .82 : .27).toColor();
  if (_contrast(candidate, background) >= 4.5) return candidate;
  final black = const Color(0xFF101418);
  final white = const Color(0xFFF8FAFC);
  candidate = _contrast(black, background) >= _contrast(white, background)
      ? black
      : white;
  return candidate;
}

double _contrast(Color left, Color right) {
  final lighter = left.computeLuminance() > right.computeLuminance()
      ? left.computeLuminance()
      : right.computeLuminance();
  final darker = left.computeLuminance() > right.computeLuminance()
      ? right.computeLuminance()
      : left.computeLuminance();
  return (lighter + .05) / (darker + .05);
}
