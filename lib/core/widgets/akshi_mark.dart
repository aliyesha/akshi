import 'package:material_ui/material_ui.dart';

/// The designer-supplied Akshi mark used consistently inside the application.
class AkshiMark extends StatelessWidget {
  const AkshiMark({super.key, this.size = 42});

  static const assetName = 'assets/branding/akshi_icon.png';

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Akshi',
    image: true,
    child: Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Image.asset(
        assetName,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}
