import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/site_icon.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class SiteIdentity extends StatelessWidget {
  const SiteIdentity({required this.domain, this.size = 44, super.key});

  final DomainEntry domain;
  final double size;

  @override
  Widget build(BuildContext context) {
    final siteIcon = domain.checksCertificate ? domain.siteIcon : null;
    final contentSize = size * .64;
    final Widget child;
    if (siteIcon != null) {
      child = siteIcon.format == SiteIconFormat.svg
          ? SvgPicture.memory(
              siteIcon.bytes,
              width: contentSize,
              height: contentSize,
              fit: BoxFit.contain,
            )
          : Image.memory(
              siteIcon.bytes,
              width: contentSize,
              height: contentSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            );
    } else {
      final color = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFD1D5DB)
          : const Color(0xFF59616B);
      final fallback = domain.checksEmail && !domain.checksCertificate
          ? PhosphorIconsDuotone.envelopeSimple
          : PhosphorIconsRegular.globeHemisphereWest;
      child = PhosphorIcon(fallback, size: size * .52, color: color);
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .18),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? Colors.black : Colors.white,
        border: Border.all(
          color: dark ? const Color(0xFF656B73) : const Color(0xFFD6DAE0),
        ),
        borderRadius: BorderRadius.circular(size * .34),
      ),
      child: child,
    );
  }
}
