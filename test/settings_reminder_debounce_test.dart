import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _TestSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings();

  @override
  Future<void> saveSettings(AppSettings value) async {
    state = AsyncData(value);
  }
}

class _OffReminderController extends ReminderController {
  @override
  ReminderHealth build() => const ReminderHealth(
    kind: ReminderHealthKind.off,
    permission: NotificationPermissionStatus.notDetermined,
  );

  @override
  Future<ReminderHealth> reconcile() async => state;
}

void main() {
  testWidgets(
    'day changes restart the three-second reminder confirmation timer',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsControllerProvider.overrideWith(
              _TestSettingsController.new,
            ),
            reminderControllerProvider.overrideWith(_OffReminderController.new),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('10 days before expiry'), findsOneWidget);
      await tester.tap(find.byType(IconButton).first);
      await tester.pump();

      expect(find.text('9 days before expiry'), findsOneWidget);
      expect(
        find.textContaining('confirmation opens in 3 seconds'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Update expiry reminders?'), findsNothing);

      await tester.tap(find.byType(IconButton).first);
      await tester.pump();
      expect(find.text('8 days before expiry'), findsOneWidget);
      expect(
        find.textContaining('confirmation opens in 3 seconds'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Update expiry reminders?'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Update expiry reminders?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('10 days before expiry'), findsOneWidget);
    },
  );
}
