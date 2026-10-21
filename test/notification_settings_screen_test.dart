import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _TestSettingsController extends SettingsController {
  _TestSettingsController(this.value, {this.saveResult});

  final AppSettings value;
  final ReminderHealth? saveResult;

  @override
  Future<AppSettings> build() async => value;

  @override
  Future<ReminderHealth?> saveSettings(AppSettings value) async {
    state = AsyncData(value);
    return saveResult;
  }
}

class _TestReminderController extends ReminderController {
  _TestReminderController(this.value);

  final ReminderHealth value;

  @override
  ReminderHealth build() => value;

  @override
  Future<ReminderHealth> reconcile() async => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const systemSettingsChannel = MethodChannel(
    'com.aliyesha.akshi/system_settings',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(systemSettingsChannel, null);
  });

  testWidgets('shows app switch and current OS permission separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: false)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.off,
                permission: NotificationPermissionStatus.notAllowed,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Off in Akshi'), findsOneWidget);
    expect(find.textContaining('OS permission: Not allowed'), findsOneWidget);
    expect(find.text('Enable reminders'), findsOneWidget);
  });

  testWidgets('dependent day boundaries explain why values cannot cross', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(
              AppSettings(firstWarningDays: 3, secondWarningDays: 2),
            ),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.ready,
                permission: NotificationPermissionStatus.allowed,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('day-control-First warning-decrease')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Warning order preserved'), findsOneWidget);
    expect(
      find.textContaining('earlier than the second warning'),
      findsOneWidget,
    );
    expect(find.text('3 days before expiry'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('day-control-Second warning-increase')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Warning order preserved'), findsOneWidget);
    expect(find.textContaining('later than the first warning'), findsOneWidget);
    expect(find.text('2 days before expiry'), findsOneWidget);
  });

  testWidgets('ready state offers a visible turn-off action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: true)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.ready,
                permission: NotificationPermissionStatus.allowed,
                desiredCount: 3,
                pendingCount: 3,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.textContaining('OS permission: Allowed'), findsOneWidget);
    expect(find.text('Turn off reminders'), findsOneWidget);
  });

  testWidgets('ready empty plan explains that no reminders are upcoming', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: true)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.ready,
                permission: NotificationPermissionStatus.allowed,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No upcoming expiry reminders'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('first-run permission can be allowed or turned off in Akshi', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: true)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.permissionNeeded,
                permission: NotificationPermissionStatus.notDetermined,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('Turn off Akshi reminders'), findsOneWidget);
  });

  testWidgets('failed cleanup cannot hide the enable reminders action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: false)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.needsAttention,
                permission: NotificationPermissionStatus.notAllowed,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable reminders'), findsOneWidget);
    expect(find.text('Repair reminders'), findsNothing);
  });

  testWidgets('missing OS permission takes priority over alarm repair', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: true)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.needsAttention,
                permission: NotificationPermissionStatus.notDetermined,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('Repair reminders'), findsNothing);
  });

  testWidgets('denied OS permission exposes system settings', (tester) async {
    MethodCall? settingsCall;
    messenger.setMockMethodCallHandler(systemSettingsChannel, (call) async {
      settingsCall = call;
      return true;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(remindersEnabled: true)),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.permissionNeeded,
                permission: NotificationPermissionStatus.notAllowed,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final openSettings = find.text('Open system settings');
    await tester.ensureVisible(openSettings);
    await tester.pump();
    await tester.tap(openSettings);
    await tester.pumpAndSettle();

    expect(find.text('Notification permission needed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open system settings'));
    await tester.pumpAndSettle();

    expect(settingsCall?.method, 'openNotificationSettings');
    expect(settingsCall?.arguments, isNull);
  });

  testWidgets('failed turn-off cleanup is not presented as success', (
    tester,
  ) async {
    const unhealthy = ReminderHealth(
      kind: ReminderHealthKind.needsAttention,
      permission: NotificationPermissionStatus.notAllowed,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(
              AppSettings(remindersEnabled: true),
              saveResult: unhealthy,
            ),
          ),
          reminderControllerProvider.overrideWith(
            () => _TestReminderController(
              const ReminderHealth(
                kind: ReminderHealthKind.permissionNeeded,
                permission: NotificationPermissionStatus.notAllowed,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final turnOffButton = find.text('Turn off Akshi reminders');
    await tester.ensureVisible(turnOffButton);
    await tester.pump();
    await tester.tap(turnOffButton);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Reminders are off in Akshi'), findsOneWidget);
    expect(
      find.textContaining('cleanup could not be verified'),
      findsOneWidget,
    );
    expect(find.text('Reminders are off'), findsNothing);
  });
}
