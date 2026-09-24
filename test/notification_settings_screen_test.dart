import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _TestSettingsController extends SettingsController {
  _TestSettingsController(this.value);

  final AppSettings value;

  @override
  Future<AppSettings> build() async => value;

  @override
  Future<void> saveSettings(AppSettings value) async {
    state = AsyncData(value);
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
  testWidgets('shows app switch and current OS permission separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(const AppSettings()),
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

  testWidgets('ready state offers a visible turn-off action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(
              const AppSettings(remindersEnabled: true),
            ),
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
}
