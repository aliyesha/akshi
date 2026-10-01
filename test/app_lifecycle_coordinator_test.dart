import 'dart:async';

import 'package:akshi/app/app_lifecycle_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notification bootstrap failure does not suppress foreground work',
    () async {
      final calls = <String>[];
      final errors = <String>[];
      final coordinator = AppLifecycleCoordinator(
        initializeNotifications: () async {
          calls.add('initialize');
          throw StateError('notification bootstrap failed');
        },
        attachNotificationNavigation: () => calls.add('navigation'),
        configureNotificationPermission: () async {
          calls.add('permission');
        },
        reconcileReminders: () async {
          calls.add('reminders');
        },
        refreshMonitors: () async {
          calls.add('monitors');
        },
        reportError: (event, _, _) => errors.add(event),
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        containsAll(<String>['initialize', 'reminders', 'monitors']),
      );
      expect(calls, isNot(contains('navigation')));
      expect(calls, isNot(contains('permission')));
      expect(errors, <String>[
        'app.foreground.notifications.initialize.failed',
      ]);
    },
  );

  test(
    'foreground retry completes notification bootstrap after startup failure',
    () async {
      final calls = <String>[];
      final errors = <String>[];
      var initializationAttempts = 0;
      final coordinator = AppLifecycleCoordinator(
        initializeNotifications: () async {
          calls.add('initialize');
          initializationAttempts++;
          if (initializationAttempts == 1) {
            throw StateError('notification bootstrap failed');
          }
        },
        attachNotificationNavigation: () => calls.add('navigation'),
        configureNotificationPermission: () async {
          calls.add('permission');
        },
        reconcileReminders: () async {
          calls.add('reminders');
        },
        refreshMonitors: () async {
          calls.add('monitors');
        },
        reportError: (event, _, _) => errors.add(event),
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['initialize', 'reminders', 'monitors']);

      calls.clear();
      await coordinator.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(
        calls,
        containsAll(<String>[
          'initialize',
          'navigation',
          'permission',
          'reminders',
          'monitors',
        ]),
      );

      calls.clear();
      await coordinator.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['permission', 'reminders', 'monitors']);
      expect(errors, <String>[
        'app.foreground.notifications.initialize.failed',
      ]);
    },
  );
  test('permission failure does not suppress foreground work', () async {
    final calls = <String>[];
    final errors = <String>[];
    final coordinator = AppLifecycleCoordinator(
      initializeNotifications: () async {
        calls.add('initialize');
      },
      attachNotificationNavigation: () => calls.add('navigation'),
      configureNotificationPermission: () async {
        calls.add('permission');
        throw StateError('permission lookup failed');
      },
      reconcileReminders: () async {
        calls.add('reminders');
      },
      refreshMonitors: () async {
        calls.add('monitors');
      },
      reportError: (event, _, _) => errors.add(event),
    );

    await coordinator.start();
    await Future<void>.delayed(Duration.zero);

    expect(
      calls,
      containsAll(<String>[
        'initialize',
        'navigation',
        'permission',
        'reminders',
        'monitors',
      ]),
    );
    expect(errors, <String>['app.foreground.notifications.permission.failed']);
  });

  test(
    'foreground tasks are isolated and overlapping refreshes coalesce',
    () async {
      final reminders = Completer<void>();
      final monitors = Completer<void>();
      final errors = <String>[];
      var reminderCalls = 0;
      var monitorCalls = 0;
      final coordinator = AppLifecycleCoordinator(
        initializeNotifications: () async {},
        attachNotificationNavigation: () {},
        configureNotificationPermission: () async {},
        reconcileReminders: () {
          reminderCalls++;
          return reminders.future;
        },
        refreshMonitors: () {
          monitorCalls++;
          return monitors.future;
        },
        reportError: (event, _, _) => errors.add(event),
      );

      final first = coordinator.refresh();
      final joined = coordinator.refresh();
      expect(identical(first, joined), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(reminderCalls, 1);
      expect(monitorCalls, 1);

      reminders.completeError(StateError('reminders failed'));
      monitors.complete();
      await first;

      expect(errors, <String>['app.foreground.reminders.reconcile.failed']);
      await coordinator.refresh();
      expect(reminderCalls, 2);
      expect(monitorCalls, 2);
    },
  );

  test(
    'notification bootstrap cannot block current or later data maintenance',
    () async {
      final initialization = Completer<void>();
      final calls = <String>[];
      final coordinator = AppLifecycleCoordinator(
        initializeNotifications: () => initialization.future,
        attachNotificationNavigation: () => calls.add('navigation'),
        configureNotificationPermission: () async {
          calls.add('permission');
        },
        reconcileReminders: () async {
          calls.add('reminders');
        },
        refreshMonitors: () async {
          calls.add('monitors');
        },
        reportError: (_, _, _) {},
      );

      await coordinator.start().timeout(const Duration(seconds: 2));
      expect(calls.where((call) => call == 'reminders'), hasLength(1));
      expect(calls.where((call) => call == 'monitors'), hasLength(1));

      await coordinator.refresh();
      expect(calls.where((call) => call == 'reminders'), hasLength(2));
      expect(calls.where((call) => call == 'monitors'), hasLength(2));
      expect(calls, isNot(contains('navigation')));
      expect(calls, isNot(contains('permission')));

      coordinator.dispose();
      initialization.complete();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isNot(contains('navigation')));
      expect(calls, isNot(contains('permission')));
    },
  );
}
