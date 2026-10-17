import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  AppSettings? _reminderDraft;
  Timer? _reminderDebounce;
  var _secondsUntilReminderPrompt = 0;
  var _reminderDialogOpen = false;
  var _committingReminder = false;
  var _notificationRequestOpen = false;

  static const _reminderConfirmationDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(reminderControllerProvider.notifier).reconcile());
  }

  @override
  void dispose() {
    _reminderDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(reminderControllerProvider.notifier).reconcile());
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminderHealth = ref.watch(reminderControllerProvider);
    final settingsValue = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to domains',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
        ),
        title: const Text('Settings'),
      ),
      body: settingsValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          appLogger.error('ui.settings.load.failed', error, stack);
          return AsyncErrorView(
            onRetry: () => ref.invalidate(settingsControllerProvider),
          );
        },
        data: (settings) {
          final reminder =
              _reminderDraft?.copyWith(themeMode: settings.themeMode) ??
              settings;
          final reminderChanged = !settings.hasSameReminderSchedule(reminder);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: <Widget>[
              Text(
                'Reminders',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose two different early warnings, each at least two days '
                'before expiry. A final one-day reminder is always included.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _SettingsCard(
                children: <Widget>[
                  _DayControl(
                    title: 'First warning',
                    value: reminder.firstWarningDays,
                    minimum: reminder.secondWarningDays + 1,
                    maximum: AppSettings.maximumWarningDays,
                    onChanged: (value) => _stageReminderChange(
                      reminder.copyWith(firstWarningDays: value),
                    ),
                    onMinimumReached: () => showAkshiNotice(
                      context,
                      title: 'Warning order preserved',
                      message:
                          'The first warning must stay at least one day '
                          'earlier than the second warning.',
                      tone: AkshiNoticeTone.warning,
                    ),
                    onMaximumReached: () => showAkshiNotice(
                      context,
                      title: 'Maximum warning reached',
                      message:
                          'The earliest reminder is 90 days before expiry.',
                      tone: AkshiNoticeTone.warning,
                    ),
                  ),
                  const Divider(),
                  _DayControl(
                    title: 'Second warning',
                    value: reminder.secondWarningDays,
                    minimum: AppSettings.minimumWarningDays,
                    maximum: reminder.firstWarningDays - 1,
                    onChanged: (value) => _stageReminderChange(
                      reminder.copyWith(secondWarningDays: value),
                    ),
                    onMinimumReached: () => showAkshiNotice(
                      context,
                      title: 'Minimum warning reached',
                      message:
                          'The final configurable warning must stay at least '
                          'two days before expiry.',
                      tone: AkshiNoticeTone.warning,
                    ),
                    onMaximumReached: () => showAkshiNotice(
                      context,
                      title: 'Warning order preserved',
                      message:
                          'The second warning must stay at least one day '
                          'later than the first warning.',
                      tone: AkshiNoticeTone.warning,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: const PhosphorIcon(PhosphorIconsDuotone.clock),
                    title: const Text('Reminder time'),
                    subtitle: const Text(
                      'Approximate delivery in your local time',
                    ),
                    trailing: Text(
                      format24HourTime(
                        hour: reminder.notificationHour,
                        minute: reminder.notificationMinute,
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    onTap: () => _pickTime(context, reminder),
                  ),
                ],
              ),
              if (reminderChanged &&
                  _secondsUntilReminderPrompt > 0) ...<Widget>[
                const SizedBox(height: 12),
                _ReminderDraftActions(
                  secondsUntilPrompt: _secondsUntilReminderPrompt,
                  onUndo: _discardReminderDraft,
                  onReviewNow: _promptReminderChange,
                ),
              ],
              const SizedBox(height: 14),
              _NotificationAccessCard(
                health: reminderHealth,
                remindersEnabled: settings.remindersEnabled,
                onPressed: () =>
                    _handleReminderAction(context, settings, reminderHealth),
                onTurnOff: () => _turnOffReminders(context, settings),
              ),
              const SizedBox(height: 30),
              Text(
                'Organization',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                children: <Widget>[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: const PhosphorIcon(PhosphorIconsDuotone.tag),
                    title: const Text('Tags'),
                    subtitle: const Text(
                      'Create reusable colored labels for your domains',
                    ),
                    trailing: const PhosphorIcon(
                      PhosphorIconsDuotone.caretRight,
                      size: 17,
                    ),
                    onTap: () => context.push('/settings/tags'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                'Diagnostics',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                children: <Widget>[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: const PhosphorIcon(PhosphorIconsDuotone.bell),
                    title: const Text('Reminder ledger'),
                    subtitle: const Text(
                      'Review verified alarm handoffs and repair reminders',
                    ),
                    trailing: const PhosphorIcon(
                      PhosphorIconsDuotone.caretRight,
                      size: 17,
                    ),
                    onTap: () => context.push('/settings/reminder-ledger'),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: const PhosphorIcon(PhosphorIconsDuotone.bug),
                    title: const Text('Crash reports'),
                    subtitle: const Text('Review and copy local diagnostics'),
                    trailing: const PhosphorIcon(
                      PhosphorIconsDuotone.caretRight,
                      size: 17,
                    ),
                    onTap: () => context.push('/settings/crash-logs'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),
              SegmentedButton<AkshiThemeMode>(
                segments: const <ButtonSegment<AkshiThemeMode>>[
                  ButtonSegment(
                    value: AkshiThemeMode.system,
                    icon: PhosphorIcon(PhosphorIconsDuotone.deviceMobile),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: AkshiThemeMode.light,
                    icon: PhosphorIcon(PhosphorIconsDuotone.sun),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: AkshiThemeMode.dark,
                    icon: PhosphorIcon(PhosphorIconsDuotone.moonStars),
                    label: Text('Dark'),
                  ),
                ],
                selected: <AkshiThemeMode>{settings.themeMode},
                onSelectionChanged: (selection) =>
                    _save(settings.copyWith(themeMode: selection.single)),
              ),
              const SizedBox(height: 30),
              Text(
                'Privacy',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                children: <Widget>[
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: PhosphorIcon(PhosphorIconsDuotone.hardDrives),
                    title: Text('No Akshi server'),
                    subtitle: Text(
                      'Saved data stays here; checks go directly to '
                      'registries and configured sources.',
                    ),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: PhosphorIcon(PhosphorIconsDuotone.wifiHigh),
                    title: Text('Checks happen while active'),
                    subtitle: Text(
                      'Akshi connects when opened, resumed, manually refreshed, or when check settings change.',
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: const PhosphorIcon(PhosphorIconsDuotone.network),
                    title: const Text('Network destinations'),
                    subtitle: const Text(
                      'Review every service and endpoint Akshi can contact',
                    ),
                    trailing: const PhosphorIcon(
                      PhosphorIconsDuotone.caretRight,
                    ),
                    onTap: () => context.push('/settings/network-destinations'),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: const PhosphorIcon(PhosphorIconsDuotone.info),
                    title: const Text('About Akshi'),
                    subtitle: const Text(
                      'Name, philosophy, and intended audience',
                    ),
                    trailing: const PhosphorIcon(
                      PhosphorIconsDuotone.caretRight,
                    ),
                    onTap: () => context.push('/settings/about'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  'Akshi · Watch What Matters',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickTime(BuildContext context, AppSettings reminder) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: reminder.notificationHour,
        minute: reminder.notificationMinute,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    _stageReminderChange(
      reminder.copyWith(
        notificationHour: selected.hour,
        notificationMinute: selected.minute,
      ),
    );
  }

  Future<void> _save(AppSettings settings) =>
      ref.read(settingsControllerProvider.notifier).saveSettings(settings);

  /// Stages reminder settings locally and restarts the three-second quiet
  /// period. Platform alarms are untouched until the user confirms.
  void _stageReminderChange(AppSettings candidate) {
    if (_committingReminder) return;
    _reminderDebounce?.cancel();
    setState(() {
      _reminderDraft = candidate;
      _secondsUntilReminderPrompt = _reminderConfirmationDelay.inSeconds;
    });
    _reminderDebounce = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsUntilReminderPrompt > 1) {
        setState(() => _secondsUntilReminderPrompt--);
        return;
      }
      timer.cancel();
      _reminderDebounce = null;
      setState(() => _secondsUntilReminderPrompt = 0);
      unawaited(_promptReminderChange());
    });
  }

  void _discardReminderDraft() {
    _reminderDebounce?.cancel();
    _reminderDebounce = null;
    if (!mounted) return;
    setState(() {
      _reminderDraft = null;
      _secondsUntilReminderPrompt = 0;
    });
  }

  Future<void> _promptReminderChange() async {
    if (_reminderDialogOpen || _committingReminder) return;
    final previous = ref.read(settingsControllerProvider).value;
    final draft = _reminderDraft;
    if (previous == null || draft == null) return;

    final candidate = draft.copyWith(themeMode: previous.themeMode);
    final reminderTime = format24HourTime(
      hour: candidate.notificationHour,
      minute: candidate.notificationMinute,
    );
    if (previous.hasSameReminderSchedule(candidate)) {
      _discardReminderDraft();
      return;
    }

    _reminderDebounce?.cancel();
    _reminderDebounce = null;
    setState(() {
      _secondsUntilReminderPrompt = 0;
      _reminderDialogOpen = true;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const PhosphorIcon(PhosphorIconsDuotone.bellRinging, size: 34),
          title: const Text('Update expiry reminders?'),
          content: Text(
            'Akshi will schedule reminders ${candidate.firstWarningDays} '
            'days, ${candidate.secondWarningDays} days, and 1 day before '
            'each saved expiry, around $reminderTime.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update reminders'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        _discardReminderDraft();
        return;
      }

      setState(() => _committingReminder = true);
      try {
        await _withBlockingProgress<void>(
          title: 'Updating expiry reminders',
          message: 'Saving your settings and verifying local alarms…',
          operation: () => _save(candidate),
        );
        if (!mounted) return;
        setState(() {
          _reminderDraft = null;
          _secondsUntilReminderPrompt = 0;
        });
        showAkshiNotice(
          context,
          title: 'Reminders updated',
          message: 'Your new expiry warning schedule is active.',
          tone: AkshiNoticeTone.success,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _reminderDraft = null;
          _secondsUntilReminderPrompt = 0;
        });
        showAkshiNotice(
          context,
          title: 'Could not update reminders',
          message: 'Your previous warning schedule is unchanged.',
          tone: AkshiNoticeTone.error,
        );
      } finally {
        if (mounted) setState(() => _committingReminder = false);
      }
    } finally {
      _reminderDialogOpen = false;
    }
  }

  /// Presents the same explicit progress treatment for platform operations.
  /// The modal barrier prevents overlapping requests without changing the
  /// visual treatment of the underlying settings controls.
  Future<T> _withBlockingProgress<T>({
    required String title,
    required String message,
    required Future<T> Function() operation,
  }) async {
    final dialogReady = Completer<BuildContext>();
    final dialogClosed = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!dialogReady.isCompleted) dialogReady.complete(dialogContext);
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: Row(
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(width: 18),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
      },
    );
    final dialogContext = await dialogReady.future;
    try {
      return await operation();
    } finally {
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      await dialogClosed;
    }
  }

  Future<void> _handleReminderAction(
    BuildContext context,
    AppSettings settings,
    ReminderHealth health,
  ) async {
    if (_notificationRequestOpen) return;
    _notificationRequestOpen = true;
    try {
      if (!settings.remindersEnabled) {
        await _withBlockingProgress<void>(
          title: 'Enabling reminders',
          message: 'Saving your choice and checking notification access…',
          operation: () => _save(settings.copyWith(remindersEnabled: true)),
        );
        if (!context.mounted) return;
        final permission =
            await SystemSettingsService.notificationPermissionStatus();
        if (!context.mounted) return;
        await _resolveNotificationPermission(context, permission);
        return;
      }

      if (health.permission != NotificationPermissionStatus.allowed) {
        await _resolveNotificationPermission(context, health.permission);
        return;
      }

      if (health.kind == ReminderHealthKind.needsAttention) {
        final repaired = await _withBlockingProgress<ReminderHealth>(
          title: 'Repairing reminders',
          message: 'Rebuilding owned expiry alarms and verifying the result…',
          operation: () =>
              ref.read(reminderControllerProvider.notifier).repair(),
        );
        if (!context.mounted) return;
        final ready = repaired.kind == ReminderHealthKind.ready;
        _showReminderResult(
          context,
          title: ready ? 'Reminders ready' : 'Reminders need attention',
          message: ready
              ? 'Expiry reminders are ready.'
              : 'See the Reminder Ledger for details.',
          tone: ready ? AkshiNoticeTone.success : AkshiNoticeTone.warning,
        );
        return;
      }

      await _turnOffReminders(context, settings);
    } catch (error, stackTrace) {
      appLogger.error('ui.settings.reminders.action.failed', error, stackTrace);
      if (!context.mounted) return;
      _showReminderResult(
        context,
        title: 'Reminder action failed',
        message: 'The reminder action could not finish.',
        tone: AkshiNoticeTone.error,
      );
    } finally {
      _notificationRequestOpen = false;
    }
  }

  Future<void> _resolveNotificationPermission(
    BuildContext context,
    NotificationPermissionStatus permission,
  ) async {
    if (permission == NotificationPermissionStatus.allowed) {
      final health = ref.read(reminderControllerProvider);
      final ready = health.kind == ReminderHealthKind.ready;
      _showReminderResult(
        context,
        title: ready ? 'Reminders enabled' : 'Reminders need attention',
        message: ready
            ? 'Expiry reminders are enabled.'
            : 'Reminders are enabled, but verification needs attention.',
        tone: ready ? AkshiNoticeTone.success : AkshiNoticeTone.warning,
      );
      return;
    }

    if (permission == NotificationPermissionStatus.notDetermined) {
      final granted = await ref
          .read(notificationServiceProvider)
          .requestPermission();
      if (!context.mounted) return;
      final result = await _withBlockingProgress<ReminderHealth>(
        title: 'Verifying reminders',
        message: 'Checking notification access and scheduled alarms…',
        operation: () =>
            ref.read(reminderControllerProvider.notifier).reconcile(),
      );
      if (!context.mounted) return;
      if (granted && result.kind == ReminderHealthKind.ready) {
        _showReminderResult(
          context,
          title: 'Reminders ready',
          message: 'Expiry reminders are ready.',
          tone: AkshiNoticeTone.success,
        );
        return;
      }
      if (granted) {
        _showReminderResult(
          context,
          title: 'Reminders need attention',
          message:
              'Notification access is allowed, but verification is incomplete.',
          tone: AkshiNoticeTone.warning,
        );
        return;
      }
    }

    if (context.mounted) await _offerNotificationSettings(context);
  }

  Future<void> _offerNotificationSettings(BuildContext context) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const PhosphorIcon(PhosphorIconsDuotone.bellSlash),
        title: const Text('Notification permission needed'),
        content: const Text(
          'Akshi reminders remain enabled, but this device is not allowing '
          'notifications. Open system settings and allow notifications '
          'for Akshi.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open system settings'),
          ),
        ],
      ),
    );
    if (openSettings == true && context.mounted) {
      await _openNotificationSettings(context);
    }
  }

  void _showReminderResult(
    BuildContext context, {
    required String title,
    required String message,
    required AkshiNoticeTone tone,
  }) {
    showAkshiNotice(context, title: title, message: message, tone: tone);
  }

  Future<void> _turnOffReminders(
    BuildContext context,
    AppSettings settings,
  ) async {
    await _withBlockingProgress<void>(
      title: 'Turning off reminders',
      message: 'Removing Akshi expiry alarms and verifying they are gone…',
      operation: () => _save(settings.copyWith(remindersEnabled: false)),
    );
    if (!context.mounted) return;
    showAkshiNotice(
      context,
      title: 'Reminders are off',
      message: 'Akshi removed its scheduled expiry alerts.',
      tone: AkshiNoticeTone.success,
    );
  }

  Future<void> _openNotificationSettings(BuildContext context) async {
    final opened = await SystemSettingsService.openNotificationSettings();
    if (!opened && context.mounted) {
      showAkshiNotice(
        context,
        title: 'Could not open settings',
        message: 'Open notification settings manually from your device.',
        tone: AkshiNoticeTone.error,
      );
    }
  }
}

class _NotificationAccessCard extends StatelessWidget {
  const _NotificationAccessCard({
    required this.health,
    required this.remindersEnabled,
    required this.onPressed,
    required this.onTurnOff,
  });

  final ReminderHealth health;
  final bool remindersEnabled;
  final VoidCallback onPressed;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = health.kind == ReminderHealthKind.ready;
    final needsAttention = health.kind == ReminderHealthKind.needsAttention;
    final label = switch (health.kind) {
      ReminderHealthKind.checking => 'Checking…',
      ReminderHealthKind.off => 'Off in Akshi',
      ReminderHealthKind.permissionNeeded => 'Permission needed',
      ReminderHealthKind.ready => 'Ready',
      ReminderHealthKind.needsAttention => 'Needs attention',
    };
    final action = health.isBusy
        ? 'Checking reminders…'
        : !remindersEnabled
        ? 'Enable reminders'
        : health.permission == NotificationPermissionStatus.notDetermined
        ? 'Allow notifications'
        : health.permission != NotificationPermissionStatus.allowed
        ? 'Open system settings'
        : health.kind == ReminderHealthKind.needsAttention
        ? 'Repair reminders'
        : 'Turn off reminders';
    return _SettingsCard(
      children: <Widget>[
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          leading: PhosphorIcon(
            ready
                ? PhosphorIconsDuotone.bellRinging
                : needsAttention
                ? PhosphorIconsDuotone.warningCircle
                : PhosphorIconsDuotone.bellSlash,
          ),
          title: const Text('Expiry reminders'),
          subtitle: Text(
            'Only domain and TLS certificate expiries. '
            'OS permission: ${health.permission.label}.',
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ready
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: ready
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: health.isBusy ? null : onPressed,
                icon: PhosphorIcon(
                  ready
                      ? PhosphorIconsDuotone.bellSlash
                      : PhosphorIconsDuotone.bellRinging,
                ),
                label: Text(action),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              if (remindersEnabled &&
                  (health.kind == ReminderHealthKind.permissionNeeded ||
                      needsAttention))
                TextButton(
                  onPressed: health.isBusy ? null : onTurnOff,
                  child: const Text('Turn off Akshi reminders'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReminderDraftActions extends StatelessWidget {
  const _ReminderDraftActions({
    required this.secondsUntilPrompt,
    required this.onUndo,
    required this.onReviewNow,
  });

  final int secondsUntilPrompt;
  final VoidCallback onUndo;
  final VoidCallback onReviewNow;

  @override
  Widget build(BuildContext context) {
    final countdown = secondsUntilPrompt.clamp(1, 3);
    final colors = AkshiTheme.progressSurface(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Reminder changes ready',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Review or undo before the confirmation opens in $countdown '
            '${countdown == 1 ? 'second' : 'seconds'}.',
            style: TextStyle(color: colors.foreground),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              OutlinedButton(
                onPressed: onUndo,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.foreground,
                  side: BorderSide(color: colors.accent),
                ),
                child: const Text('Undo'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onReviewNow,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.background,
                ),
                child: const Text('Review now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _DayControl extends StatelessWidget {
  const _DayControl({
    required this.title,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
    required this.onMinimumReached,
    required this.onMaximumReached,
  });
  final String title;
  final int value;
  final int minimum;
  final int maximum;
  final ValueChanged<int> onChanged;
  final VoidCallback onMinimumReached;
  final VoidCallback onMaximumReached;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text('$value days before expiry'),
            ],
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey<String>('day-control-$title-decrease'),
          tooltip: value > minimum
              ? 'Move one day later'
              : 'Why this cannot go later',
          onPressed: () =>
              value > minimum ? onChanged(value - 1) : onMinimumReached(),
          icon: const PhosphorIcon(PhosphorIconsRegular.minus, size: 17),
        ),
        const SizedBox(width: 7),
        IconButton.filledTonal(
          key: ValueKey<String>('day-control-$title-increase'),
          tooltip: value < maximum
              ? 'Move one day earlier'
              : 'Why this cannot go earlier',
          onPressed: () =>
              value < maximum ? onChanged(value + 1) : onMaximumReached(),
          icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 17),
        ),
      ],
    ),
  );
}
