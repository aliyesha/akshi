import 'dart:convert';

import 'package:akshi/core/services/notification_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expiry payload round trips into an exact attention route', () {
    const original = NotificationDestination(
      kind: NotificationDestinationKind.expiry,
      monitorIds: <String>['first-id', 'second-id'],
    );

    final restored = NotificationDestination.fromPayload(original.toPayload());

    expect(restored, isNotNull);
    expect(restored!.kind, NotificationDestinationKind.expiry);
    expect(restored.monitorIds, <String>['first-id', 'second-id']);
    final uri = Uri.parse(restored.route);
    expect(uri.path, '/attention');
    expect(uri.queryParameters['source'], 'expiry');
    expect(uri.queryParameters['ids'], 'first-id,second-id');
  });

  test('a single changed monitor routes directly to its details', () {
    const destination = NotificationDestination(
      kind: NotificationDestinationKind.changes,
      monitorIds: <String>['monitor-id'],
    );

    expect(destination.route, '/monitor/monitor-id');
  });

  test('a detail destination safely encodes its monitor id', () {
    const destination = NotificationDestination(
      kind: NotificationDestinationKind.changes,
      monitorIds: <String>['monitor id'],
    );

    expect(destination.route, '/monitor/monitor%20id');
  });

  test('a single expiry still routes to the filtered attention list', () {
    const destination = NotificationDestination(
      kind: NotificationDestinationKind.expiry,
      monitorIds: <String>['monitor-id'],
    );

    final uri = Uri.parse(destination.route);
    expect(uri.path, '/attention');
    expect(uri.queryParameters['source'], 'expiry');
    expect(uri.queryParameters['ids'], 'monitor-id');
  });

  test('multiple changed monitors route to the shared change list', () {
    const destination = NotificationDestination(
      kind: NotificationDestinationKind.changes,
      monitorIds: <String>['one', 'two'],
    );

    final uri = Uri.parse(destination.route);
    expect(uri.path, '/attention');
    expect(uri.queryParameters['source'], 'changes');
  });

  test('malformed notification payload is rejected', () {
    expect(NotificationDestination.fromPayload('not-json'), isNull);
    expect(NotificationDestination.fromPayload('{}'), isNull);
    expect(NotificationDestination.fromPayload(null), isNull);
  });

  test('empty and unsupported payload shapes are rejected', () {
    expect(NotificationDestination.fromPayload(''), isNull);
    expect(
      NotificationDestination.fromPayload(
        jsonEncode(<String, Object>{
          'type': 'unknown',
          'monitorIds': <String>['one'],
        }),
      ),
      isNull,
    );
    expect(
      NotificationDestination.fromPayload(
        jsonEncode(<String, Object>{'type': 'changes', 'monitorIds': 'one'}),
      ),
      isNull,
    );
    expect(
      NotificationDestination.fromPayload(
        jsonEncode(<String, Object>{
          'type': 1,
          'monitorIds': <String>['one'],
        }),
      ),
      isNull,
    );
  });

  test('payload restoration removes empty and duplicate monitor ids', () {
    final destination = NotificationDestination.fromPayload(
      jsonEncode(<String, Object>{
        'type': 'changes',
        'monitorIds': <Object>['one', '', 'one', 1],
      }),
    );

    expect(destination, isNotNull);
    expect(destination!.monitorIds, <String>['one']);
    expect(destination.route, '/monitor/one');
  });
}
