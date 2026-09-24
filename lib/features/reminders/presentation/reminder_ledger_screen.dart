import 'package:akshi/app/providers.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/reminders/domain/alarm_audit.dart';
import 'package:akshi/features/reminders/domain/expiry_alarm.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class ReminderLedgerScreen extends ConsumerWidget {
  const ReminderLedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(reminderControllerProvider);
    final settings = ref.watch(settingsControllerProvider).value;
    final days = ref.watch(alarmAuditDaysProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reminder ledger')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(alarmAuditDaysProvider);
          await ref.read(alarmAuditDaysProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
            _HealthHero(
              health: health,
              enabled: settings?.remindersEnabled == true,
            ),
            const SizedBox(height: 14),
            _ProofNotice(platform: _latestPlatform(days.value)),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Daily alarms',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (days.value?.isNotEmpty == true)
                  Text(
                    '${days.value!.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...days.when(
              loading: () => const <Widget>[
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, stackTrace) => <Widget>[
                _EmptyLedger(
                  icon: PhosphorIconsDuotone.warningCircle,
                  title: 'Ledger unavailable',
                  message: 'Akshi could not read the local proof ledger.',
                ),
              ],
              data: (values) => values.isEmpty
                  ? const <Widget>[
                      _EmptyLedger(
                        icon: PhosphorIconsDuotone.clock,
                        title: 'No alarm work yet',
                        message:
                            'When reminders are enabled and an expiry approaches, '
                            'Akshi will record each platform handoff here.',
                      ),
                    ]
                  : values
                        .map(
                          (day) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AlarmDayCard(
                              day: day,
                              onTap: () => context.push(
                                '/settings/reminder-ledger/${day.date}',
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: health.isBusy
                  ? null
                  : () async {
                      final result = await ref
                          .read(reminderControllerProvider.notifier)
                          .repair();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.kind == ReminderHealthKind.ready ||
                                    result.kind == ReminderHealthKind.off
                                ? 'Reminder verification passed.'
                                : 'Reminders still need attention.',
                          ),
                        ),
                      );
                    },
              icon: const PhosphorIcon(
                PhosphorIconsDuotone.arrowClockwise,
              ),
              label: const Text('Repair and verify reminders'),
            ),
          ],
        ),
      ),
    );
  }

  String? _latestPlatform(List<AlarmAuditDay>? days) =>
      days == null || days.isEmpty ? null : days.first.latest.platform;
}

class ReminderLedgerDetailScreen extends ConsumerWidget {
  const ReminderLedgerDetailScreen({required this.date, super.key});

  final AlarmDate date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisions = ref.watch(alarmAuditDateProvider(date));
    return Scaffold(
      appBar: AppBar(title: Text(date.toString())),
      body: revisions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(
          child: Text('This ledger entry could not be read.'),
        ),
        data: (values) {
          if (values.isEmpty) {
            return const Center(child: Text('This ledger entry is unavailable.'));
          }
          final latest = values.first;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: <Widget>[
              _DetailHero(entry: latest),
              const SizedBox(height: 20),
              Text(
                'Proof of setup',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              _ProofTimeline(entry: latest),
              const SizedBox(height: 24),
              Text(
                'Alarm snapshot',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              _SnapshotGrid(entry: latest),
              const SizedBox(height: 24),
              Text(
                'Included monitors',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              ...latest.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MonitorSnapshot(item: item),
                ),
              ),
              if (values.length > 1) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Revision history',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                _RevisionHistory(revisions: values),
              ],
              const SizedBox(height: 20),
              _DeliveryBoundary(platform: latest.platform),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _copyReceipt(context, latest),
                icon: const PhosphorIcon(PhosphorIconsDuotone.copy),
                label: const Text('Copy proof receipt'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyReceipt(
    BuildContext context,
    AlarmAuditEntry entry,
  ) async {
    final receipt = <String>[
      'Akshi reminder proof',
      'Alarm date: ${entry.date}',
      'Requested time: ${entry.requestedTime} (${entry.timeZoneId})',
      'Scheduled UTC: ${entry.scheduledUtc.toIso8601String()}',
      'Notification ID: ${entry.notificationId}',
      'Revision: ${entry.revision}',
      'Computed: ${entry.computedAt.toUtc().toIso8601String()}',
      'Platform accepted: ${_timestamp(entry.submittedAt)}',
      'Pending verified: ${_timestamp(entry.verifiedAt)}',
      'State: ${_stageLabel(entry.stage)}',
      'Platform: ${entry.platform}',
      'OS version: ${entry.osVersion}',
      'Monitors: ${entry.monitorCount}',
      'Reasons: ${entry.reasonCount}',
      'Delivery is controlled by the operating system after handoff.',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: receipt));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Proof receipt copied.')),
    );
  }
}

class _HealthHero extends StatelessWidget {
  const _HealthHero({required this.health, required this.enabled});

  final ReminderHealth health;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _healthVisual(health);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.lerp(scheme.surfaceContainerLowest, visual.color(scheme), .08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: visual.color(scheme).withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _IconTile(icon: visual.icon, color: visual.color(scheme)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(visual.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text(
                  visual.message,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (enabled && health.nextAlarmDate != null) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(
                    'Next daily alarm · ${health.nextAlarmDate}',
                    style: Theme.of(context).textTheme.labelLarge,
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

class _ProofNotice extends StatelessWidget {
  const _ProofNotice({this.platform});

  final String? platform;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final android = platform == 'android';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.shieldCheck,
            color: scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              android
                  ? 'Verified means the Android scheduling call returned and '
                      'the notification plugin’s private pending inventory '
                      'matched Akshi’s plan.'
                  : 'Verified means the platform scheduling call returned and '
                      'the pending notification inventory matched Akshi’s plan.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmDayCard extends StatelessWidget {
  const _AlarmDayCard({required this.day, required this.onTap});

  final AlarmAuditDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = day.latest;
    final scheme = Theme.of(context).colorScheme;
    final visual = _stageVisual(entry.stage);
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _IconTile(icon: visual.icon, color: visual.color(scheme)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.date.toString(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        _StatusPill(
                          label: visual.label,
                          color: visual.color(scheme),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Around ${entry.requestedTime} · '
                      '${entry.monitorCount} ${entry.monitorCount == 1 ? 'monitor' : 'monitors'} · '
                      '${entry.reasonCount} ${entry.reasonCount == 1 ? 'reason' : 'reasons'}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        if (entry.domainReasonCount > 0)
                          _ReasonBadge(
                            icon: PhosphorIconsDuotone.globeHemisphereWest,
                            label: 'Domain ${entry.domainReasonCount}',
                          ),
                        if (entry.domainReasonCount > 0 &&
                            entry.tlsReasonCount > 0)
                          const SizedBox(width: 8),
                        if (entry.tlsReasonCount > 0)
                          _ReasonBadge(
                            icon: PhosphorIconsDuotone.certificate,
                            label: 'TLS ${entry.tlsReasonCount}',
                          ),
                        const Spacer(),
                        if (day.revisions.length > 1)
                          Text(
                            '${day.revisions.length} revisions',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        const SizedBox(width: 5),
                        const PhosphorIcon(
                          PhosphorIconsDuotone.caretRight,
                          size: 17,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.entry});

  final AlarmAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _stageVisual(entry.stage);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.lerp(scheme.surfaceContainerLowest, visual.color(scheme), .08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: visual.color(scheme).withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconTile(icon: visual.icon, color: visual.color(scheme)),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  visual.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _stageDescription(entry.stage),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProofTimeline extends StatelessWidget {
  const _ProofTimeline({required this.entry});

  final AlarmAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _TimelineStep(
            icon: PhosphorIconsDuotone.clock,
            title: 'Computed',
            value: formatLocalDateTime(entry.computedAt),
            complete: true,
          ),
          const Divider(),
          _TimelineStep(
            icon: PhosphorIconsDuotone.deviceMobile,
            title: 'Platform accepted',
            value: entry.submittedAt == null
                ? 'Not recorded'
                : formatLocalDateTime(entry.submittedAt!),
            complete: entry.submittedAt != null,
          ),
          const Divider(),
          _TimelineStep(
            icon: PhosphorIconsDuotone.shieldCheck,
            title: 'Pending verified',
            value: entry.verifiedAt == null
                ? 'Not verified'
                : formatLocalDateTime(entry.verifiedAt!),
            complete: entry.verifiedAt != null,
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.value,
    required this.complete,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: PhosphorIcon(
        icon,
        color: complete ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(value),
      trailing: Text(
        complete ? 'Done' : 'Waiting',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: complete ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SnapshotGrid extends StatelessWidget {
  const _SnapshotGrid({required this.entry});

  final AlarmAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final values = <(IconData, String, String)>[
      (
        PhosphorIconsDuotone.clock,
        'Requested',
        '${entry.date} · ${entry.requestedTime}',
      ),
      (
        PhosphorIconsDuotone.globeHemisphereWest,
        'Time zone',
        entry.timeZoneId,
      ),
      (
        PhosphorIconsDuotone.deviceMobile,
        'Platform',
        entry.platform,
      ),
      (
        PhosphorIconsDuotone.deviceMobile,
        'OS version',
        entry.osVersion,
      ),
      (
        PhosphorIconsDuotone.listBullets,
        'Notification ID',
        '${entry.notificationId}',
      ),
      (
        PhosphorIconsDuotone.fingerprint,
        'Revision',
        entry.shortRevision,
      ),
      (
        PhosphorIconsDuotone.clock,
        'Scheduled UTC',
        entry.scheduledUtc.toUtc().toIso8601String(),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 560
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: values
              .map(
                (value) => SizedBox(
                  width: width,
                  child: _SnapshotValue(
                    icon: value.$1,
                    label: value.$2,
                    value: value.$3,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          PhosphorIcon(icon, color: scheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorSnapshot extends StatelessWidget {
  const _MonitorSnapshot({required this.item});

  final ExpiryAlarmItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(item.hostname, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...item.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    PhosphorIcon(
                      reason.kind == ExpiryAlarmKind.domainRegistration
                          ? PhosphorIconsDuotone.globeHemisphereWest
                          : PhosphorIconsDuotone.certificate,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${reason.kind.label} expires ${reason.expiryDate} · '
                        '${reason.warningDays}-day warning',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevisionHistory extends StatelessWidget {
  const _RevisionHistory({required this.revisions});

  final List<AlarmAuditEntry> revisions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < revisions.length; index++) ...<Widget>[
            ListTile(
              leading: PhosphorIcon(_stageVisual(revisions[index].stage).icon),
              title: Text(
                index == 0
                    ? 'Current · ${revisions[index].shortRevision}'
                    : 'Replaced · ${revisions[index].shortRevision}',
              ),
              subtitle: Text(formatLocalDateTime(revisions[index].computedAt)),
              trailing: Text(_stageLabel(revisions[index].stage)),
            ),
            if (index != revisions.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _DeliveryBoundary extends StatelessWidget {
  const _DeliveryBoundary({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.deviceMobile,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Akshi verified the request was pending. Delivery after this '
              'point is controlled by ${platform == 'ios' ? 'iOS' : platform == 'android' ? 'Android' : 'the operating system'}, '
              'including battery, focus, and notification settings.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: <Widget>[
          PhosphorIcon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withAlpha(28),
      borderRadius: BorderRadius.circular(14),
    ),
    alignment: Alignment.center,
    child: PhosphorIcon(icon, color: color),
  );
}

class _ReasonBadge extends StatelessWidget {
  const _ReasonBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PhosphorIcon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}

typedef _ColorResolver = Color Function(ColorScheme scheme);

class _Visual {
  const _Visual({
    required this.icon,
    required this.label,
    required this.color,
    this.title = '',
    this.message = '',
  });

  final IconData icon;
  final String label;
  final _ColorResolver color;
  final String title;
  final String message;
}

_Visual _stageVisual(AlarmAuditStage stage) => switch (stage) {
  AlarmAuditStage.computed => _Visual(
    icon: PhosphorIconsDuotone.clock,
    label: 'Computed',
    color: (scheme) => scheme.tertiary,
  ),
  AlarmAuditStage.submitted => _Visual(
    icon: PhosphorIconsDuotone.deviceMobile,
    label: 'Accepted',
    color: (scheme) => scheme.primary,
  ),
  AlarmAuditStage.verified => _Visual(
    icon: PhosphorIconsDuotone.shieldCheck,
    label: 'Verified',
    color: (scheme) => scheme.primary,
  ),
  AlarmAuditStage.cancelled => _Visual(
    icon: PhosphorIconsDuotone.bellSlash,
    label: 'Replaced',
    color: (scheme) => scheme.onSurfaceVariant,
  ),
  AlarmAuditStage.failed => _Visual(
    icon: PhosphorIconsDuotone.warningCircle,
    label: 'Needs attention',
    color: (scheme) => scheme.error,
  ),
};

_Visual _healthVisual(ReminderHealth health) => switch (health.kind) {
  ReminderHealthKind.checking => _Visual(
    icon: PhosphorIconsDuotone.clock,
    label: 'Checking',
    title: 'Checking reminders',
    message: 'Comparing the desired plan with pending alarms.',
    color: (scheme) => scheme.primary,
  ),
  ReminderHealthKind.off => _Visual(
    icon: PhosphorIconsDuotone.bellSlash,
    label: 'Off',
    title: 'Reminders are off',
    message: 'No expiry alarms should be pending.',
    color: (scheme) => scheme.onSurfaceVariant,
  ),
  ReminderHealthKind.permissionNeeded => _Visual(
    icon: PhosphorIconsDuotone.warningCircle,
    label: 'Permission needed',
    title: 'Notification permission needed',
    message: 'Akshi cannot hand reminders to the operating system.',
    color: (scheme) => scheme.error,
  ),
  ReminderHealthKind.ready => _Visual(
    icon: PhosphorIconsDuotone.shieldCheck,
    label: 'Ready',
    title: 'Reminder plan verified',
    message: '${health.pendingCount} daily alarms match the current expiry plan.',
    color: (scheme) => scheme.primary,
  ),
  ReminderHealthKind.needsAttention => _Visual(
    icon: PhosphorIconsDuotone.warningCircle,
    label: 'Needs attention',
    title: 'Reminder plan needs attention',
    message: 'Akshi could not prove that pending alarms match the plan.',
    color: (scheme) => scheme.error,
  ),
};

String _stageLabel(AlarmAuditStage stage) => _stageVisual(stage).label;

String _stageDescription(AlarmAuditStage stage) => switch (stage) {
  AlarmAuditStage.computed =>
    'Akshi computed this alarm but has not recorded a platform handoff.',
  AlarmAuditStage.submitted =>
    'The platform scheduling call returned; pending verification is incomplete.',
  AlarmAuditStage.verified =>
    'The platform accepted this alarm and its pending inventory matched.',
  AlarmAuditStage.cancelled =>
    'This revision was cancelled or replaced by a newer alarm plan.',
  AlarmAuditStage.failed =>
    'The handoff or verification failed and needs another reconciliation.',
};

String _timestamp(DateTime? value) =>
    value?.toUtc().toIso8601String() ?? 'Not recorded';
