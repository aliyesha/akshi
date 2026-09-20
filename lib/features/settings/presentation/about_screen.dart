import 'package:akshi/core/widgets/akshi_mark.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to settings',
        onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
        icon: const Icon(LucideIcons.chevron_left),
      ),
      title: const Text('About Akshi'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: <Widget>[
          const Center(child: AkshiMark(size: 76)),
          const SizedBox(height: 18),
          Text(
            'Akshi',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Watch What Matters',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 28),
          const _AboutCard(
            icon: LucideIcons.scan_search,
            title: 'An attentive eye',
            body:
                'Akshi comes from the Sanskrit akṣi (अक्षि), meaning eye. '
                'It keeps a quiet eye on domain registration, certificates, '
                'and published Email configuration, then directs attention '
                'where action is useful.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            icon: LucideIcons.smartphone,
            title: 'Local by design',
            body:
                'There is no Akshi account or central monitoring server. '
                'Checks run intentionally while the app is active, results '
                'remain on this device, and reminders are scheduled locally.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            icon: LucideIcons.code_2,
            title: 'For hands-on builders',
            body:
                'Akshi is made for indie developers, consultants, small teams, '
                'and operators who want renewal awareness without another '
                'service to deploy, secure, pay for, and maintain.',
          ),
          const SizedBox(height: 22),
          Text(
            'An aliyesha.com project',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 21, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
