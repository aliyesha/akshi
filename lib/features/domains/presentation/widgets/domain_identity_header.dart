import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/presentation/widgets/site_identity.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:material_ui/material_ui.dart';

class DomainIdentityHeader extends StatelessWidget {
  const DomainIdentityHeader({required this.domain, super.key});

  final DomainEntry domain;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SiteIdentity(domain: domain, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  domain.displayName,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  domain.hostname,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: AkshiTheme.monoFontFamily,
                    fontFeatures: const <FontFeature>[
                      FontFeature.slashedZero(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (domain.tags.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: domain.tags.map((tag) => TagPill(tag: tag)).toList(),
        ),
      ],
    ],
  );
}
