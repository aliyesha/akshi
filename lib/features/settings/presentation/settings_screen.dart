import 'package:akshi/app/providers.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsValue = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: <Widget>[
            Text(
              'Reminders',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose two early warnings. A final one-day reminder is always included.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _SettingsCard(
              children: <Widget>[
                _DayControl(
                  title: 'First warning',
                  value: settings.firstWarningDays,
                  minimum: settings.secondWarningDays + 1,
                  maximum: 90,
                  onChanged: (value) =>
                      _save(ref, settings.copyWith(firstWarningDays: value)),
                ),
                const Divider(),
                _DayControl(
                  title: 'Second warning',
                  value: settings.secondWarningDays,
                  minimum: 2,
                  maximum: settings.firstWarningDays - 1,
                  onChanged: (value) =>
                      _save(ref, settings.copyWith(secondWarningDays: value)),
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
                    TimeOfDay(
                      hour: settings.notificationHour,
                      minute: settings.notificationMinute,
                    ).format(context),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => _pickTime(context, ref, settings),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _requestPermission(context, ref),
              icon: const PhosphorIcon(PhosphorIconsDuotone.bellRinging),
              label: const Text('Enable notifications'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
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
                    'Create reusable colored labels for your monitors',
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
              onSelectionChanged: (selection) => _save(
                ref,
                settings.copyWith(themeMode: selection.single),
                reschedule: false,
              ),
            ),
            const SizedBox(height: 30),
            Text('Privacy', style: Theme.of(context).textTheme.headlineMedium),
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
                    'Saved data stays here; checks go directly to registries and configured sources.',
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
                    'Akshi connects only when opened, resumed, edited, or refreshed.',
                  ),
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
                  trailing: const PhosphorIcon(PhosphorIconsDuotone.caretRight),
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
        ),
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.notificationHour,
        minute: settings.notificationMinute,
      ),
    );
    if (selected == null) return;
    await _save(
      ref,
      settings.copyWith(
        notificationHour: selected.hour,
        notificationMinute: selected.minute,
      ),
    );
  }

  Future<void> _save(
    WidgetRef ref,
    AppSettings settings, {
    bool reschedule = true,
  }) async {
    await ref.read(settingsControllerProvider.notifier).saveSettings(settings);
    if (!reschedule) return;
    final monitors = ref.read(monitorControllerProvider).value ?? const [];
    await ref
        .read(notificationServiceProvider)
        .reconcileAll(monitors, settings);
  }

  Future<void> _requestPermission(BuildContext context, WidgetRef ref) async {
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted ? 'Notifications are enabled.' : 'Notifications remain disabled. You can enable them in system settings.',
        ),
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
  });
  final String title;
  final int value;
  final int minimum;
  final int maximum;
  final ValueChanged<int> onChanged;

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
          onPressed: value > minimum ? () => onChanged(value - 1) : null,
          icon: const PhosphorIcon(PhosphorIconsRegular.minus, size: 17),
        ),
        const SizedBox(width: 7),
        IconButton.filledTonal(
          onPressed: value < maximum ? () => onChanged(value + 1) : null,
          icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 17),
        ),
      ],
    ),
  );
}
