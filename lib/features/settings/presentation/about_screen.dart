import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/external_link_service.dart';
import 'package:akshi/core/widgets/akshi_mark.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to settings',
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/settings'),
        icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
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
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 28),
          const _AboutCard(
            icon: PhosphorIconsDuotone.scan,
            title: 'An attentive eye',
            body:
                'Akshi comes from the Sanskrit akṣi (अक्षि), meaning eye. '
                'It keeps a quiet eye on domain registration, certificates, '
                'and published Email configuration, then directs attention '
                'where action is useful.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            icon: PhosphorIconsDuotone.deviceMobile,
            title: 'Local by design',
            body:
                'There is no Akshi account or central monitoring server. '
                'Checks run intentionally while the app is active, results '
                'remain on this device, and reminders are scheduled locally.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            icon: PhosphorIconsDuotone.code,
            title: 'For hands-on builders',
            body:
                'Akshi is made for indie developers, consultants, small teams, '
                'and operators who want renewal awareness without another '
                'service to deploy, secure, pay for, and maintain.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            icon: PhosphorIconsDuotone.shieldCheck,
            title: 'Privacy and support',
            body:
                'Akshi does not send monitor data or diagnostics to Aliyesha. '
                'For privacy or support questions, contact '
                'ops@aliyeshamail.com.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Akshi',
              applicationLegalese:
                  'Copyright © 2026 aliyesha.com (Aliyesha)\n'
                  'Licensed under GPL-3.0-or-later',
            ),
            icon: const PhosphorIcon(PhosphorIconsRegular.scales),
            label: const Text('Open-source licenses'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 22),
          TextButton.icon(
            onPressed: () => _openAliyeshaWebsite(context),
            icon: const PhosphorIcon(PhosphorIconsRegular.globe, size: 18),
            label: const Text('An aliyesha.com project'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openAliyeshaWebsite(BuildContext context) async {
  try {
    await ExternalLinkService.openHttps(Uri.parse('https://aliyesha.com'));
  } catch (error, stackTrace) {
    appLogger.error('ui.about.external_link.failed', error, stackTrace);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open aliyesha.com on this device.'),
      ),
    );
  }
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
            child: PhosphorIcon(
              icon,
              size: 21,
              color: scheme.onPrimaryContainer,
            ),
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
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(height: 1.45, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
