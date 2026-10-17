import 'dart:convert';

import 'package:akshi/core/services/notification_destination.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;

/// The only events that may produce an Akshi notification.
enum ExpiryAlarmKind {
  domainRegistration('domain', 'Domain'),
  tlsCertificate('tls', 'TLS certificate');

  const ExpiryAlarmKind(this.code, this.label);

  final String code;
  final String label;

  static ExpiryAlarmKind? fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// A local calendar date with no accidental clock or time-zone semantics.
///
/// One [AlarmDate] is one OS notification. This is the core identity rule:
/// every domain and every expiry reason landing on the same local date is
/// merged into that single notification.
class AlarmDate implements Comparable<AlarmDate> {
  const AlarmDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  factory AlarmDate.fromDateTime(DateTime value) =>
      AlarmDate(value.year, value.month, value.day);

  factory AlarmDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('Invalid alarm date');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw const FormatException('Invalid alarm date');
    }
    return AlarmDate(year, month, day);
  }

  AlarmDate subtractDays(int days) {
    final date = DateTime.utc(year, month, day - days);
    return AlarmDate(date.year, date.month, date.day);
  }

  tz.TZDateTime at(tz.Location location, int hour, int minute) =>
      tz.TZDateTime(location, year, month, day, hour, minute);

  int get epochDay =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  String toIso8601String() =>
      "${year.toString().padLeft(4, '0')}-"
      "${month.toString().padLeft(2, '0')}-"
      "${day.toString().padLeft(2, '0')}";

  @override
  int compareTo(AlarmDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is AlarmDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso8601String();
}

/// Why one domain participates in a date's notification.
class ExpiryAlarmReason {
  const ExpiryAlarmReason({
    required this.kind,
    required this.expiryDate,
    required this.warningDays,
  });

  final ExpiryAlarmKind kind;
  final AlarmDate expiryDate;
  final int warningDays;

  Map<String, Object> toJson() => <String, Object>{
    'kind': kind.code,
    'expiry': expiryDate.toIso8601String(),
    'days': warningDays,
  };

  static ExpiryAlarmReason fromJson(Map<String, dynamic> json) {
    final kind = ExpiryAlarmKind.fromCode(json['kind'] as String?);
    final expiry = json['expiry'];
    final days = json['days'];
    if (kind == null || expiry is! String || days is! int || days < 1) {
      throw const FormatException('Invalid alarm reason');
    }
    return ExpiryAlarmReason(
      kind: kind,
      expiryDate: AlarmDate.parse(expiry),
      warningDays: days,
    );
  }

  String get identity =>
      '${kind.code}:${expiryDate.toIso8601String()}:$warningDays';
}

/// One domain inside a date-based notification.
class ExpiryAlarmItem {
  const ExpiryAlarmItem({
    required this.domainId,
    required this.hostname,
    required this.reasons,
  });

  final String domainId;
  final String hostname;
  final List<ExpiryAlarmReason> reasons;

  Map<String, Object> toJson() => <String, Object>{
    'id': domainId,
    'hostname': hostname,
    'reasons': reasons.map((reason) => reason.toJson()).toList(growable: false),
  };

  static ExpiryAlarmItem fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final hostname = json['hostname'];
    final rawReasons = json['reasons'];
    if (id is! String ||
        id.isEmpty ||
        hostname is! String ||
        hostname.isEmpty ||
        rawReasons is! List<dynamic> ||
        rawReasons.isEmpty) {
      throw const FormatException('Invalid alarm item');
    }
    final reasons = rawReasons
        .map(
          (value) => ExpiryAlarmReason.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
    return ExpiryAlarmItem(domainId: id, hostname: hostname, reasons: reasons);
  }
}

/// Complete desired state for one local date.
class ExpiryAlarmSpec {
  const ExpiryAlarmSpec({
    required this.date,
    required this.scheduledAt,
    required this.timeZoneId,
    required this.items,
  });

  static const payloadVersion = 1;
  static const payloadType = 'expiry_alarm';
  static const maximumPendingAlarms = 60;
  static const _idNamespace = 100000000;
  static const _idNamespaceEnd = 200000000;

  final AlarmDate date;
  final tz.TZDateTime scheduledAt;
  final String timeZoneId;
  final List<ExpiryAlarmItem> items;

  int get notificationId => notificationIdFor(date);
  String get revision =>
      sha256.convert(utf8.encode(jsonEncode(_canonicalContent))).toString();

  List<String> get domainIds =>
      items.map((item) => item.domainId).toList(growable: false);

  String get title => items.length == 1
      ? 'Expiry reminder for ${items.single.hostname}'
      : '${items.length} expiry reminders';

  String get body {
    const visibleItems = 3;
    final shown = items.take(visibleItems).map(_formatItem).join('; ');
    final remaining = items.length - visibleItems;
    return remaining > 0 ? '$shown; and $remaining more' : shown;
  }

  /// Versioned, canonical evidence stored with the OS request.
  ///
  /// Android cannot enumerate AlarmManager entries with their trigger dates,
  /// so reconciliation decodes this payload from the notifications plugin's
  /// pending-request inventory. Full items are retained so equality is exact;
  /// the SHA-256 revision is an integrity check, not the source of truth.
  String get payload {
    final content = _canonicalContent;
    final value = jsonEncode(<String, Object>{
      ...content,
      'revision': revision,
    });
    if (!notificationPayloadFits(value)) {
      throw StateError(
        'Expiry notification payload exceeds $maximumNotificationPayloadBytes bytes',
      );
    }
    return value;
  }

  Map<String, Object> get _canonicalContent => <String, Object>{
    'version': payloadVersion,
    'type': payloadType,
    'date': date.toIso8601String(),
    'scheduledUtc': scheduledAt.toUtc().toIso8601String(),
    'timeZone': timeZoneId,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  static int notificationIdFor(AlarmDate date) => _idNamespace + date.epochDay;

  static bool ownsNotificationId(int id) =>
      id >= _idNamespace && id < _idNamespaceEnd;
}

/// A validated alarm decoded from one pending OS request.
class ObservedExpiryAlarm {
  const ObservedExpiryAlarm({
    required this.id,
    required this.date,
    required this.title,
    required this.body,
    required this.payload,
    required this.domainIds,
  });

  final int id;
  final AlarmDate date;
  final String? title;
  final String? body;
  final String payload;
  final List<String> domainIds;

  bool matches(ExpiryAlarmSpec desired) =>
      id == desired.notificationId &&
      title == desired.title &&
      body == desired.body &&
      payload == desired.payload;

  static ObservedExpiryAlarm? tryParse({
    required int id,
    required String? title,
    required String? body,
    required String? payload,
  }) {
    if (!ExpiryAlarmSpec.ownsNotificationId(id) ||
        payload == null ||
        !notificationPayloadFits(payload)) {
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != ExpiryAlarmSpec.payloadVersion ||
          decoded['type'] != ExpiryAlarmSpec.payloadType) {
        return null;
      }
      final dateValue = decoded['date'];
      final utcValue = decoded['scheduledUtc'];
      final timeZone = decoded['timeZone'];
      final rawItems = decoded['items'];
      final revision = decoded['revision'];
      if (dateValue is! String ||
          utcValue is! String ||
          timeZone is! String ||
          timeZone.isEmpty ||
          rawItems is! List<dynamic> ||
          rawItems.isEmpty ||
          revision is! String) {
        return null;
      }
      final date = AlarmDate.parse(dateValue);
      if (ExpiryAlarmSpec.notificationIdFor(date) != id) return null;
      final instant = DateTime.parse(utcValue);
      if (!instant.isUtc) return null;
      final items = rawItems
          .map(
            (value) => ExpiryAlarmItem.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);
      final content = <String, Object>{
        'version': ExpiryAlarmSpec.payloadVersion,
        'type': ExpiryAlarmSpec.payloadType,
        'date': date.toIso8601String(),
        'scheduledUtc': instant.toIso8601String(),
        'timeZone': timeZone,
        'items': items.map((item) => item.toJson()).toList(growable: false),
      };
      final expected = sha256
          .convert(utf8.encode(jsonEncode(content)))
          .toString();
      if (revision != expected) return null;
      return ObservedExpiryAlarm(
        id: id,
        date: date,
        title: title,
        body: body,
        payload: payload,
        domainIds: items.map((item) => item.domainId).toList(growable: false),
      );
    } on Object {
      return null;
    }
  }
}

/// Pure planner for the complete alarm schedule.
///
/// Example: if a domain's registration and TLS certificate both expire on
/// 2026-05-24 with 10-day, 5-day, and 1-day warnings, this returns only three
/// alarms: 2026-05-14, 2026-05-19, and 2026-05-23. Each alarm contains both
/// reasons; it never creates two notifications for the same date.
class ExpiryAlarmPlanner {
  const ExpiryAlarmPlanner();

  Map<AlarmDate, ExpiryAlarmSpec> build({
    required Iterable<DomainEntry> domains,
    required AppSettings settings,
    required DateTime now,
    required tz.Location location,
  }) {
    if (!settings.remindersEnabled) return const <AlarmDate, ExpiryAlarmSpec>{};
    final nowAtLocation = tz.TZDateTime.from(now, location);
    final warningDays = <int>{
      settings.firstWarningDays,
      settings.secondWarningDays,
      1,
    }.toList()..sort((left, right) => right.compareTo(left));
    final grouped = <AlarmDate, Map<String, _MutableAlarmItem>>{};

    for (final domain in domains.where((domain) => domain.remindersEnabled)) {
      final expiries = <(DateTime?, ExpiryAlarmKind)>[
        (domain.domainExpiresAt, ExpiryAlarmKind.domainRegistration),
        if (domain.checksCertificate)
          (domain.certificateExpiresAt, ExpiryAlarmKind.tlsCertificate),
      ];
      for (final (expiry, kind) in expiries) {
        if (expiry == null) continue;
        final expiryDate = AlarmDate.fromDateTime(
          tz.TZDateTime.from(expiry, location),
        );
        for (final days in warningDays) {
          final alarmDate = expiryDate.subtractDays(days);
          final scheduledAt = alarmDate.at(
            location,
            settings.notificationHour,
            settings.notificationMinute,
          );
          if (!scheduledAt.isAfter(nowAtLocation)) continue;
          final byDomain = grouped.putIfAbsent(
            alarmDate,
            () => <String, _MutableAlarmItem>{},
          );
          final item = byDomain.putIfAbsent(
            domain.id,
            () => _MutableAlarmItem(domain.id, domain.hostname),
          );
          final reason = ExpiryAlarmReason(
            kind: kind,
            expiryDate: expiryDate,
            warningDays: days,
          );
          item.reasons[reason.identity] = reason;
        }
      }
    }

    final dates = grouped.keys.toList()..sort();
    final result = <AlarmDate, ExpiryAlarmSpec>{};
    for (final date in dates.take(ExpiryAlarmSpec.maximumPendingAlarms)) {
      final items = grouped[date]!.values.map((item) => item.freeze()).toList()
        ..sort((left, right) {
          final hostname = left.hostname.toLowerCase().compareTo(
            right.hostname.toLowerCase(),
          );
          return hostname != 0
              ? hostname
              : left.domainId.compareTo(right.domainId);
        });
      result[date] = ExpiryAlarmSpec(
        date: date,
        scheduledAt: date.at(
          location,
          settings.notificationHour,
          settings.notificationMinute,
        ),
        timeZoneId: location.name,
        items: List<ExpiryAlarmItem>.unmodifiable(items),
      );
    }
    return Map<AlarmDate, ExpiryAlarmSpec>.unmodifiable(result);
  }
}

enum AlarmChange { create, replace, delete, unchanged }

class AlarmComparison {
  const AlarmComparison({
    required this.date,
    required this.current,
    required this.desired,
    required this.change,
  });

  final AlarmDate date;
  final ObservedExpiryAlarm? current;
  final ExpiryAlarmSpec? desired;
  final AlarmChange change;

  bool get isDirty => change != AlarmChange.unchanged;
}

/// Exact set comparison used by both normal reconciliation and tests.
List<AlarmComparison> compareAlarmPlans({
  required Map<AlarmDate, ObservedExpiryAlarm> current,
  required Map<AlarmDate, ExpiryAlarmSpec> desired,
}) {
  final dates = <AlarmDate>{...current.keys, ...desired.keys}.toList()..sort();
  return dates
      .map((date) {
        final existing = current[date];
        final target = desired[date];
        final change = existing == null
            ? AlarmChange.create
            : target == null
            ? AlarmChange.delete
            : existing.matches(target)
            ? AlarmChange.unchanged
            : AlarmChange.replace;
        return AlarmComparison(
          date: date,
          current: existing,
          desired: target,
          change: change,
        );
      })
      .toList(growable: false);
}

class _MutableAlarmItem {
  _MutableAlarmItem(this.domainId, this.hostname);

  final String domainId;
  final String hostname;
  final Map<String, ExpiryAlarmReason> reasons = <String, ExpiryAlarmReason>{};

  ExpiryAlarmItem freeze() {
    final sorted = reasons.values.toList()
      ..sort((left, right) {
        final kind = left.kind.index.compareTo(right.kind.index);
        if (kind != 0) return kind;
        final expiry = left.expiryDate.compareTo(right.expiryDate);
        return expiry != 0
            ? expiry
            : left.warningDays.compareTo(right.warningDays);
      });
    return ExpiryAlarmItem(
      domainId: domainId,
      hostname: hostname,
      reasons: List<ExpiryAlarmReason>.unmodifiable(sorted),
    );
  }
}

String _formatItem(ExpiryAlarmItem item) {
  final byDays = <int, List<ExpiryAlarmKind>>{};
  for (final reason in item.reasons) {
    byDays
        .putIfAbsent(reason.warningDays, () => <ExpiryAlarmKind>[])
        .add(reason.kind);
  }
  final days = byDays.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  final phrases = days.map((value) {
    final kinds = byDays[value]!
      ..sort((left, right) => left.index.compareTo(right.index));
    final labels = kinds.map((kind) => kind.label).join(' + ');
    final verb = kinds.length == 1 ? 'expires' : 'expire';
    final duration = value == 1 ? '1 day' : '$value days';
    return '$labels $verb in $duration';
  });
  return '${item.hostname} · ${phrases.join(', ')}';
}
