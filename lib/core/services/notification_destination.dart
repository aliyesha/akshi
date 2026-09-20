import 'dart:convert';

enum NotificationDestinationKind { expiry, changes }

class NotificationDestination {
  const NotificationDestination({required this.kind, required this.monitorIds});

  final NotificationDestinationKind kind;
  final List<String> monitorIds;

  String toPayload() =>
      jsonEncode(<String, Object>{'type': kind.name, 'monitorIds': monitorIds});

  String get route {
    if (kind == NotificationDestinationKind.changes && monitorIds.length == 1) {
      return Uri(pathSegments: <String>['', 'monitor', monitorIds.single])
          .toString();
    }
    return Uri(
      path: '/attention',
      queryParameters: <String, String>{
        'source': kind.name,
        if (monitorIds.isNotEmpty) 'ids': monitorIds.join(','),
      },
    ).toString();
  }

  static NotificationDestination? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['type'];
      final rawIds = decoded['monitorIds'];
      if (type is! String || rawIds is! List<dynamic>) return null;
      NotificationDestinationKind? kind;
      for (final candidate in NotificationDestinationKind.values) {
        if (candidate.name == type) {
          kind = candidate;
          break;
        }
      }
      if (kind == null) return null;
      final ids = rawIds
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      return NotificationDestination(kind: kind, monitorIds: ids.toList());
    } on FormatException {
      return null;
    }
  }
}
