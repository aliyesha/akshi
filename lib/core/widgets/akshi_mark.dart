import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:material_ui/material_ui.dart';

class AkshiMark extends StatelessWidget {
  const AkshiMark({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Akshi',
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(
            color: dark ? const Color(0xFF5F545A) : const Color(0xFFD8CDD2),
          ),
          borderRadius: BorderRadius.circular(size * .34),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AkshiTheme.brandRose.withValues(alpha: (55) / 255),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: <Color>[
              AkshiTheme.brandCyan,
              AkshiTheme.brandPlum,
              AkshiTheme.brandRose,
            ],
            stops: <double>[0, .48, 1],
          ).createShader(bounds),
          child: Icon(
            Icons.radar_rounded,
            color: Colors.white,
            size: size * .54,
          ),
        ),
      ),
    );
  }
}
