import 'dart:convert';

/// Conservative cross-platform ceiling for Akshi's local notification data.
///
/// Normal expiry payloads are only a few kilobytes. A 32 KiB boundary leaves
/// ample room while preventing accidental unbounded data from reaching either
/// native notification bridge.
const maximumNotificationPayloadBytes = 32 * 1024;

/// Whether [value] fits Akshi's UTF-8 notification payload boundary.
bool notificationPayloadFits(String value) =>
    utf8.encode(value).length <= maximumNotificationPayloadBytes;

/// Navigation-only projection of a validated expiry-alarm payload.
class NotificationDestination {
  const NotificationDestination({
    required this.monitorIds,
    required this.alarmDate,
  });

  final List<String> monitorIds;
  final String alarmDate;

  String get route => Uri(
    path: '/attention',
    queryParameters: <String, String>{
      'source': 'expiry',
      'date': alarmDate,
      if (monitorIds.isNotEmpty) 'ids': monitorIds.join(','),
    },
  ).toString();

  static NotificationDestination? fromPayload(String? payload) {
    if (payload == null ||
        payload.isEmpty ||
        !notificationPayloadFits(payload)) {
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['type'] != 'expiry_alarm') {
        return null;
      }
      final date = decoded['date'];
      final rawItems = decoded['items'];
      if (date is! String || rawItems is! List<dynamic>) return null;
      final ids = <String>{};
      for (final value in rawItems) {
        if (value is! Map) return null;
        final id = value['id'];
        if (id is! String || id.isEmpty) return null;
        ids.add(id);
      }
      return NotificationDestination(
        monitorIds: ids.toList(growable: false),
        alarmDate: date,
      );
    } on Object {
      return null;
    }
  }
}
