import 'package:akshi/app/providers.dart';
import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/status_pill.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/domain_finding.dart';
import 'package:akshi/features/domains/domain/domain_status.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_refresh_banner.dart';
import 'package:akshi/features/domains/presentation/widgets/site_identity.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class DomainOverviewScreen extends ConsumerStatefulWidget {
  const DomainOverviewScreen({required this.domainId, super.key});

  final String domainId;

  @override
  ConsumerState<DomainOverviewScreen> createState() =>
      _DomainOverviewScreenState();
}

class _DomainOverviewScreenState extends ConsumerState<DomainOverviewScreen> {
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(domainControllerProvider);
    final refresh = ref.watch(domainRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
    final domain = _find(items.value ?? const <DomainEntry>[]);
    if (domain == null) {
      return Scaffold(
        appBar: AppBar(leading: _backButton(context)),
        body: Center(
          child: items.isLoading
              ? const CircularProgressIndicator()
              : const Text('Domain not found'),
        ),
      );
    }
    final checkProgress = ref.watch(
      domainCheckActivityProvider.select((active) => active[domain.id]),
    );
    final checking = checkProgress != null;
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings();
    final provisioning = ref.watch(domainProvisioningProvider)[domain.id];
    final findings = findingsForDomain(
      domain,
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final overall = domain.overallStatus(
      warningDays: settings.firstWarningDays,
      criticalDays: settings.secondWarningDays,
    );
    final dns = domain.dnsSnapshot;
    final recordCount =
        dns?.queries.expand((query) => query.records).length ?? 0;
    final failedQueries =
        dns?.queries.where((query) => query.hasCurrentFailure).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            onPressed:
                checking ||
                    refresh.isRunning ||
                    (provisioning?.isRunning ?? false)
                ? null
                : () {
                    if (offline) {
                      showOfflineMessage(context);
                      return;
                    }
                    context.push('/domain/${domain.id}/edit');
                  },
            icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: checking || refresh.isRunning
                ? null
                : () => _delete(domain),
            icon: const PhosphorIcon(PhosphorIconsDuotone.trash),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh.isRunning
            ? () async {
                await ref.read(domainControllerProvider.notifier).refreshAll();
              }
            : () => _refresh(domain),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
            if (refresh.shouldShowStatus) ...<Widget>[
              const DomainRefreshBanner(),
              const SizedBox(height: 14),
            ],
            if (offline) ...<Widget>[
              const OfflineNotice(),
              const SizedBox(height: 14),
            ],
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
                      const SizedBox(height: 5),
                      Text(
                        domain.hostname,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            const SizedBox(height: 18),
            if (provisioning != null) ...<Widget>[
              _DomainProgressCard(
                progress: provisioning.progress,
                failure: provisioning.failure,
                failureTitle: 'Initial check needs another try',
                description:
                    'Initial checks continue in the background and are saved '
                    'together as one consistent snapshot. They can take time '
                    'and depend on your connection and each source, so please '
                    'be patient.',
                failureDescription:
                    'The domain definition is saved safely. Use Check now to '
                    'retry the initial snapshot.',
              ),
              const SizedBox(height: 14),
            ] else if (checkProgress != null) ...<Widget>[
              _DomainProgressCard(
                progress: checkProgress,
                description:
                    'Akshi is checking the selected domain, DNS, certificate, '
                    'site identity, and email sources. New results appear '
                    'together when the complete snapshot is ready.',
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: <Widget>[
                StatusPill(status: overall),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      checking ||
                          refresh.isRunning ||
                          offline ||
                          (provisioning?.isRunning ?? false)
                      ? null
                      : () => _refresh(domain),
                  icon: checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const PhosphorIcon(
                          PhosphorIconsRegular.arrowsClockwise,
                          size: 17,
                        ),
                  label: Text(checking ? 'Checking' : 'Check now'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Overview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final finding in findings) ...<Widget>[
              _SectionCard(
                icon: _iconFor(finding.kind),
                title: finding.kind.label,
                summary: finding.summary,
                status: finding.status,
                onTap: () => context.push(
                  '/domain/${domain.id}/${_pathFor(finding.kind)}',
                ),
              ),
              const SizedBox(height: 10),
            ],
            _SectionCard(
              icon: PhosphorIconsDuotone.network,
              title: 'DNS records',
              summary: dns == null
                  ? 'No DNS snapshot yet'
                  : failedQueries > 0
                  ? '$recordCount records captured · '
                        '$failedQueries lookups could not be read'
                  : '$recordCount records captured',
              status: null,
              onTap: () => context.push('/domain/${domain.id}/dns'),
            ),
            const SizedBox(height: 18),
            Text(
              <String>[
                domain.lastAttemptedAt == null
                    ? 'No check attempted yet'
                    : 'Last attempt ${_formatDateTime(domain.lastAttemptedAt!)}',
                domain.lastVerifiedAt == null
                    ? 'Never fully verified'
                    : 'Last verified ${_formatDateTime(domain.lastVerifiedAt!)}',
              ].join('\n'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DomainEntry? _find(List<DomainEntry> items) {
    for (final item in items) {
      if (item.id == widget.domainId) return item;
    }
    return null;
  }

  Future<void> _refresh(DomainEntry domain) async {
    if (ref.read(deviceOfflineProvider).value ?? false) {
      showOfflineMessage(context);
      return;
    }
    ref.read(domainProvisioningProvider.notifier).clear(domain.id);
    try {
      await ref.read(domainControllerProvider.notifier).check(domain.id);
      if (mounted) {
        showAkshiNotice(
          context,
          title: 'Check complete',
          message: 'Latest results are saved.',
          tone: AkshiNoticeTone.success,
        );
      }
    } on DomainOfflineException {
      if (mounted) {
        showOfflineMessage(context);
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.domain_overview.check.failed',
        error,
        stackTrace,
        data: <String, Object?>{'domainId': domain.id},
      );
      if (mounted) {
        showAkshiNotice(
          context,
          title: 'Check failed',
          message: checkUserFacingError(error),
          tone: AkshiNoticeTone.error,
        );
      }
    }
  }

  Future<void> _delete(DomainEntry domain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const PhosphorIcon(PhosphorIconsDuotone.trash, size: 34),
        title: const Text('Delete this domain?'),
        content: Text(
          '${domain.displayName} and its local reminders will be removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(domainControllerProvider.notifier).delete(domain.id);
      if (mounted) context.go('/');
    } catch (error, stackTrace) {
      appLogger.error(
        'ui.domain_overview.delete.failed',
        error,
        stackTrace,
        data: <String, Object?>{'domainId': domain.id},
      );
      if (mounted) {
        showAkshiNotice(
          context,
          title: 'Could not delete domain',
          message: checkUserFacingError(error),
          tone: AkshiNoticeTone.error,
        );
      }
    }
  }
}

class _DomainProgressCard extends StatelessWidget {
  const _DomainProgressCard({
    required this.progress,
    required this.description,
    this.failure,
    this.failureTitle,
    this.failureDescription,
  }) : assert(failure == null || failureTitle != null),
       assert(failure == null || failureDescription != null);

  final DomainSaveProgress progress;
  final String description;
  final String? failure;
  final String? failureTitle;
  final String? failureDescription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = failure != null;
    final colors = AkshiTheme.progressSurface(scheme);
    final background = failed ? scheme.errorContainer : colors.background;
    final foreground = failed ? scheme.onErrorContainer : colors.foreground;
    final accent = failed ? scheme.error : colors.accent;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: failed ? scheme.error.withValues(alpha: .45) : colors.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: 20,
                  child: failed
                      ? PhosphorIcon(
                          PhosphorIconsDuotone.warningCircle,
                          color: accent,
                          size: 20,
                        )
                      : CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: accent,
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    failed ? failureTitle! : progress.message,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (!failed) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.fraction,
                color: accent,
                backgroundColor: foreground.withValues(alpha: .16),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              failed ? failureDescription! : description,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.summary,
    this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final DomainStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentStatus = status;
    final accent = currentStatus == null
        ? scheme.primary
        : domainStatusColor(scheme, currentStatus);
    final attention = switch (currentStatus) {
      DomainStatus.warning ||
      DomainStatus.critical ||
      DomainStatus.expired ||
      DomainStatus.failed ||
      DomainStatus.unavailable => true,
      DomainStatus.unknown ||
      DomainStatus.healthy ||
      DomainStatus.incomplete ||
      null => false,
    };
    return Material(
      color: attention
          ? Color.alphaBlend(
              accent.withValues(
                alpha: scheme.brightness == Brightness.dark ? .18 : .1,
              ),
              scheme.surfaceContainerLowest,
            )
          : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: attention
              ? accent.withValues(alpha: .5)
              : scheme.outlineVariant.withValues(alpha: .45),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: PhosphorIcon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (currentStatus != null) ...<Widget>[
                StatusPill(status: currentStatus),
                const SizedBox(width: 4),
              ],
              const PhosphorIcon(PhosphorIconsDuotone.caretRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(DomainCheckKind kind) => switch (kind) {
  DomainCheckKind.domainRegistration =>
    PhosphorIconsDuotone.globeHemisphereWest,
  DomainCheckKind.tlsCertificate => PhosphorIconsDuotone.certificate,
  DomainCheckKind.emailConfiguration => PhosphorIconsDuotone.envelopeSimpleOpen,
};

String _pathFor(DomainCheckKind kind) => switch (kind) {
  DomainCheckKind.domainRegistration => 'registration',
  DomainCheckKind.tlsCertificate => 'tls',
  DomainCheckKind.emailConfiguration => 'email',
};

Widget _backButton(BuildContext context) => IconButton(
  tooltip: 'Back to domains',
  onPressed: () => context.canPop() ? context.pop() : context.go('/'),
  icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
);

String _formatDateTime(DateTime value) => formatLocalDateTime(value);
