import 'package:akshi/core/services/system_settings_service.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:akshi/features/settings/presentation/settings_screen.dart';
import 'package:akshi/features/tags/application/tag_controller.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:akshi/features/tags/presentation/tags_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class _TestSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings(remindersEnabled: false);

  @override
  Future<void> saveSettings(AppSettings value) async {
    state = AsyncData(value);
  }
}

class _TestReminderController extends ReminderController {
  @override
  ReminderHealth build() => const ReminderHealth(
    kind: ReminderHealthKind.off,
    permission: NotificationPermissionStatus.notAllowed,
  );

  @override
  Future<ReminderHealth> reconcile() async => state;
}

class _TestTagController extends TagController {
  var _nextId = 0;

  @override
  Future<List<MonitorTag>> build() async => const <MonitorTag>[];

  @override
  Future<MonitorTag> create({
    required String name,
    required int colorArgb,
  }) async {
    final tag = MonitorTag(
      id: 'tag-${_nextId++}',
      name: name,
      colorArgb: colorArgb,
      createdAt: DateTime.utc(2026, 6, 14),
    );
    state = AsyncData(<MonitorTag>[...state.requireValue, tag]);
    return tag;
  }

  @override
  Future<void> updateTag(MonitorTag tag) async {
    state = AsyncData(<MonitorTag>[
      for (final current in state.requireValue)
        if (current.id == tag.id) tag else current,
    ]);
  }

  @override
  Future<void> delete(String id) async {
    state = AsyncData(
      state.requireValue.where((tag) => tag.id != id).toList(growable: false),
    );
  }
}

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'Settings keeps an exit after repeated tag routes on ${platform.name}',
      (tester) async {
        final router = GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => context.push('/settings'),
                    child: const Text('Open settings'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'tags',
                  builder: (context, state) => const TagsScreen(),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsControllerProvider.overrideWith(
                _TestSettingsController.new,
              ),
              reminderControllerProvider.overrideWith(
                _TestReminderController.new,
              ),
              tagControllerProvider.overrideWith(_TestTagController.new),
            ],
            child: MaterialApp.router(
              theme: ThemeData(platform: platform),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Tags'), 300);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tags'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Create tag'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'Production');
        await tester.tap(find.widgetWithText(FilledButton, 'Create tag'));
        await tester.pumpAndSettle();
        expect(find.text('Production'), findsOneWidget);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Production web',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save tag'));
        await tester.pumpAndSettle();
        expect(find.text('Production web'), findsOneWidget);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Production web'), findsOneWidget);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(find.text('No tags yet'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        expect(find.byTooltip('Back to monitors'), findsOneWidget);

        router.go('/');
        await tester.pumpAndSettle();
        router.go('/settings');
        await tester.pumpAndSettle();
        expect(router.canPop(), isFalse);
        expect(find.byTooltip('Back to monitors'), findsOneWidget);

        await tester.tap(find.byTooltip('Back to monitors'));
        await tester.pumpAndSettle();
        expect(find.text('Open settings'), findsOneWidget);
      },
    );
  }
}
