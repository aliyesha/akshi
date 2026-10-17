import 'package:akshi/app/providers.dart';
import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/domain_finding.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_refresh_banner.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class AttentionScreen extends ConsumerWidget {
  const AttentionScreen({
    required this.source,
    required this.domainIds,
    this.alarmDate,
    super.key,
  });

  final String source;
  final List<String> domainIds;
  final String? alarmDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domains = ref.watch(domainControllerProvider);
    final refresh = ref.watch(domainRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings();
    final title = source == 'expiry' ? 'Expiry reminder' : 'Needs attention';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: refresh.isRunning ? 'Refreshing…' : 'Refresh all',
            onPressed: refresh.isRunning || offline
                ? null
                : () => _refreshAll(context, ref, announce: true),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: refresh.isRunning
                  ? const SizedBox.square(
                      key: ValueKey<String>('refresh-progress'),
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const PhosphorIcon(
                      PhosphorIconsRegular.arrowsClockwise,
                      key: ValueKey<String>('refresh-icon'),
                    ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: domains.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          appLogger.error('ui.attention.load.failed', error, stack);
          return AsyncErrorView(
            onRetry: () => ref.invalidate(domainControllerProvider),
          );
        },
        data: (items) {
          final visible = _visible(items, settings);
          final missing = domainIds.length - visible.length;
          return RefreshIndicator(
            onRefresh: () => _refreshAll(context, ref, announce: false),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              children: <Widget>[
                if (refresh.shouldShowStatus) ...<Widget>[
                  const DomainRefreshBanner(),
                  const SizedBox(height: 14),
                ],
                if (offline) ...<Widget>[
                  const OfflineNotice(),
                  const SizedBox(height: 14),
                ],
                _AttentionHeader(
                  count: visible.length,
                  source: source,
                  alarmDate: alarmDate,
                  missing: missing > 0 ? missing : 0,
                ),
                const SizedBox(height: 16),
                if (visible.isEmpty)
                  const _ClearState()
                else
                  for (final domain in visible) ...<Widget>[
                    _AttentionCard(
                      domain: domain,
                      settings: settings,
                      showResolved: source == 'expiry' && domainIds.isNotEmpty,
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshAll(
    BuildContext context,
    WidgetRef ref, {
    required bool announce,
  }) async {
    try {
      final outcome = await ref
          .read(domainControllerProvider.notifier)
          .refreshAll();
      if (!context.mounted) return;
      if (outcome == DomainRefreshOutcome.skippedOffline) {
        showOfflineMessage(context);
        return;
      }
      if (!announce) return;
      final recentlyChecked = outcome == DomainRefreshOutcome.skippedRecent;
      showAkshiNotice(
        context,
        title: recentlyChecked ? 'Already up to date' : 'Checks complete',
        message: recentlyChecked
            ? 'The domain list was checked recently.'
            : 'Latest domain results are saved.',
        tone: recentlyChecked ? AkshiNoticeTone.info : AkshiNoticeTone.success,
      );
    } catch (error, stackTrace) {
      appLogger.error('ui.attention.refresh.failed', error, stackTrace);
      if (context.mounted) {
        showAkshiNotice(
          context,
          title: 'Refresh failed',
          message: checkUserFacingError(error),
          tone: AkshiNoticeTone.error,
        );
      }
    }
  }

  List<DomainEntry> _visible(List<DomainEntry> domains, AppSettings settings) {
    if (domainIds.isNotEmpty) {
      final byId = <String, DomainEntry>{
        for (final item in domains) item.id: item,
      };
      return domainIds.map((id) => byId[id]).whereType<DomainEntry>().toList();
    }
    return domains.where((domain) {
      final findings = findingsForDomain(
        domain,
        warningDays: settings.firstWarningDays,
        criticalDays: settings.secondWarningDays,
      );
      return findings.any((finding) => finding.needsAttention);
    }).toList();
  }
}

class _AttentionHeader extends StatelessWidget {
  const _AttentionHeader({
    required this.count,
    required this.source,
    required this.missing,
    this.alarmDate,
  });

  final int count;
  final String source;
  final int missing;
  final String? alarmDate;

  @override
  Widget build(BuildContext context) {
    final fromReminder = source == 'expiry';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          PhosphorIcon(
            fromReminder
                ? PhosphorIconsDuotone.bellRinging
                : PhosphorIconsDuotone.warningCircle,
            size: 32,
            color: scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fromReminder
                      ? '$count expiry ${count == 1 ? 'reminder' : 'reminders'}'
                      : '$count ${count == 1 ? 'domain needs' : 'domains need'} attention',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 5),
                Text(
                  fromReminder
                      ? '${alarmDate == null ? '' : 'Scheduled for $alarmDate. '}'
                            'Opened from a scheduled expiry alert. It used the '
                            'last saved expiry dates; a newer check may have '
                            'resolved it.'
                      : 'These current results need review.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    height: 1.35,
                  ),
                ),
                if (missing > 0) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    '$missing no longer ${missing == 1 ? 'exists' : 'exist'} locally.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.domain,
    required this.settings,
    required this.showResolved,
  });

  final DomainEntry domain;
  final AppSettings settings;
  final bool showResolved;

  @override
  Widget build(BuildContext context) {
    final findings = findingsForDomain(
      domain,
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final resolved = !findings.any((finding) => finding.needsAttention);
    final scheme = Theme.of(context).colorScheme;
    final status = domain.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final accent = domainStatusColor(scheme, status);
    final attentionTint = scheme.brightness == Brightness.dark ? .15 : .09;
    final cardColor = resolved
        ? scheme.surfaceContainerLowest
        : Color.alphaBlend(
            accent.withValues(alpha: attentionTint),
            scheme.surfaceContainerLowest,
          );
    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: resolved
            ? BorderSide.none
            : BorderSide(color: accent.withValues(alpha: .46), width: 1.2),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(_detailLocation(domain.id, findings)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          domain.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          domain.hostname,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const PhosphorIcon(PhosphorIconsDuotone.caretRight, size: 17),
                ],
              ),
              if (domain.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: domain.tags
                      .map((tag) => TagPill(tag: tag))
                      .toList(),
                ),
              ],
              if (showResolved && resolved) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  'Resolved since notification',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              for (final finding in findings) ...<Widget>[
                _FindingRow(finding: finding),
                if (finding != findings.last) const Divider(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final DomainFinding finding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = domainStatusColor(scheme, finding.status);
    final iconColor = finding.needsAttention ? accent : scheme.onSurfaceVariant;
    final icon = switch (finding.kind) {
      DomainCheckKind.domainRegistration =>
        PhosphorIconsDuotone.globeHemisphereWest,
      DomainCheckKind.tlsCertificate => PhosphorIconsDuotone.certificate,
      DomainCheckKind.emailConfiguration =>
        PhosphorIconsDuotone.envelopeSimpleOpen,
    };
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(
              alpha: finding.needsAttention ? .14 : .07,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: PhosphorIcon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                finding.kind.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                finding.summary,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(status: finding.status),
      ],
    );
  }
}

class _ClearState extends StatelessWidget {
  const _ClearState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
    child: Column(
      children: <Widget>[
        PhosphorIcon(
          PhosphorIconsDuotone.shieldCheck,
          size: 58,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Nothing needs attention',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        const Text(
          'The latest local results are clear.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

String _detailLocation(String domainId, List<DomainFinding> findings) {
  DomainFinding? focus;
  for (final finding in findings) {
    if (finding.needsAttention) {
      focus = finding;
      break;
    }
  }
  focus ??= findings.isEmpty ? null : findings.first;
  final path = switch (focus?.kind) {
    DomainCheckKind.domainRegistration => 'registration',
    DomainCheckKind.tlsCertificate => 'tls',
    DomainCheckKind.emailConfiguration => 'email',
    null => null,
  };
  return path == null
      ? '/domain/$domainId'
      : '/domain/$domainId/$path?attention=1';
}
