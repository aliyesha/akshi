import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _TestSettingsController extends SettingsController {
  _TestSettingsController([AppSettings? initial])
    : initial = initial ?? AppSettings();

  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;

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
    'day changes restart the visible three-second confirmation countdown',
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

      final decrease = find.byKey(
        const ValueKey<String>('day-control-First warning-decrease'),
      );
      expect(find.text('10 days before expiry'), findsOneWidget);

      await tester.tap(decrease);
      await tester.pump();

      expect(find.text('9 days before expiry'), findsOneWidget);
      final pending = find.byKey(
        const ValueKey<String>('reminder-change-pending'),
      );
      expect(pending, findsOneWidget);
      expect(
        find.text(
          'Confirmation opens automatically. Continue adjusting if needed.',
        ),
        findsOneWidget,
      );
      final countdown = find.byKey(
        const ValueKey<String>('reminder-change-countdown'),
      );
      expect(
        find.descendant(of: countdown, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pending, matching: find.byType(TextButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: pending, matching: find.byType(OutlinedButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: pending, matching: find.byType(FilledButton)),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(of: countdown, matching: find.text('2')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(of: countdown, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(decrease);
      await tester.pump();
      expect(find.text('8 days before expiry'), findsOneWidget);
      expect(
        find.descendant(of: countdown, matching: find.text('3')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(
        find.descendant(of: countdown, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 999));
      expect(pending, findsOneWidget);
      expect(find.text('Update expiry reminders?'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      expect(pending, findsNothing);
      expect(find.text('Update expiry reminders?'), findsNothing);
      await tester.pump();
      expect(find.text('Update expiry reminders?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('10 days before expiry'), findsOneWidget);
    },
  );

  testWidgets('holding increase stops at 90 with an inline maximum', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(firstWarningDays: 89)),
          ),
          reminderControllerProvider.overrideWith(_OffReminderController.new),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    final increase = find.byKey(
      const ValueKey<String>('day-control-First warning-increase'),
    );
    final gesture = await tester.startGesture(tester.getCenter(increase));

    await tester.pump(
      kLongPressTimeout + kPressTimeout + const Duration(milliseconds: 1),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(find.text('90 days before expiry'), findsOneWidget);
    expect(find.text('Maximum reached'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('day-control-First warning-boundary')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reminder-change-pending')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    final countdown = find.byKey(
      const ValueKey<String>('reminder-change-countdown'),
    );
    expect(
      find.descendant(of: countdown, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey<String>('reminder-change-pending')),
      findsNothing,
    );
    expect(find.text('Update expiry reminders?'), findsNothing);
    await tester.pump();
    expect(find.text('Update expiry reminders?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('89 days before expiry'), findsOneWidget);
    expect(find.text('Maximum reached'), findsNothing);
  });

  testWidgets('pressing increase at 90 does not stage a change', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _TestSettingsController(AppSettings(firstWarningDays: 90)),
          ),
          reminderControllerProvider.overrideWith(_OffReminderController.new),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Maximum reached'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('day-control-First warning-increase')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('reminder-change-pending')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Update expiry reminders?'), findsNothing);
    expect(find.text('Maximum reached'), findsOneWidget);
  });
}
