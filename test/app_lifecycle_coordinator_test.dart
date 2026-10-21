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
        requestInitialNotificationPermission: () async {
          calls.add('permission');
        },
        reconcileReminders: () async {
          calls.add('reminders');
        },
        refreshDomains: () async {
          calls.add('domains');
        },
        reportError: (event, _, _) => errors.add(event),
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        containsAll(<String>['initialize', 'reminders', 'domains']),
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
        requestInitialNotificationPermission: () async {
          calls.add('permission');
        },
        reconcileReminders: () async {
          calls.add('reminders');
        },
        refreshDomains: () async {
          calls.add('domains');
        },
        reportError: (event, _, _) => errors.add(event),
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['initialize', 'reminders', 'domains']);

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
          'domains',
        ]),
      );

      calls.clear();
      await coordinator.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['permission', 'reminders', 'domains']);
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
      requestInitialNotificationPermission: () async {
        calls.add('permission');
        throw StateError('permission lookup failed');
      },
      reconcileReminders: () async {
        calls.add('reminders');
      },
      refreshDomains: () async {
        calls.add('domains');
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
        'domains',
      ]),
    );
    expect(errors, <String>[
      'app.foreground.notifications.initial_permission.failed',
    ]);
  });

  test(
    'foreground tasks are isolated and overlapping refreshes coalesce',
    () async {
      final reminders = Completer<void>();
      final domains = Completer<void>();
      final errors = <String>[];
      var reminderCalls = 0;
      var domainCalls = 0;
      final coordinator = AppLifecycleCoordinator(
        initializeNotifications: () async {},
        attachNotificationNavigation: () {},
        requestInitialNotificationPermission: () async {},
        reconcileReminders: () {
          reminderCalls++;
          return reminders.future;
        },
        refreshDomains: () {
          domainCalls++;
          return domains.future;
        },
        reportError: (event, _, _) => errors.add(event),
      );

      final first = coordinator.refresh();
      final joined = coordinator.refresh();
      expect(identical(first, joined), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(reminderCalls, 1);
      expect(domainCalls, 1);

      reminders.completeError(StateError('reminders failed'));
      domains.complete();
      await first;

      expect(errors, <String>['app.foreground.reminders.reconcile.failed']);
      await coordinator.refresh();
      expect(reminderCalls, 2);
      expect(domainCalls, 2);
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
        requestInitialNotificationPermission: () async {
          calls.add('permission');
        },
        reconcileReminders: () async {
          calls.add('reminders');
        },
        refreshDomains: () async {
          calls.add('domains');
        },
        reportError: (_, _, _) {},
      );

      await coordinator.start().timeout(const Duration(seconds: 2));
      expect(calls.where((call) => call == 'reminders'), hasLength(1));
      expect(calls.where((call) => call == 'domains'), hasLength(1));

      await coordinator.refresh();
      expect(calls.where((call) => call == 'reminders'), hasLength(2));
      expect(calls.where((call) => call == 'domains'), hasLength(2));
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
