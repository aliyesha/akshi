import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';

/// Reads public RDAP registration data using IANA's TLD bootstrap map.
///
/// The service keeps the network dependency local to a foreground check and
/// returns null when a registry has no matching public registration record.
class RdapService {
  RdapService({HttpClient? client}) : _client = client ?? HttpClient();

  static const _bootstrapUri = 'https://data.iana.org/rdap/dns.json';
  final HttpClient _client;
  Map<String, String>? _services;

  /// Resolves the registrable domain and returns normalized registration facts.
  Future<DomainCheckResult?> check(String hostname) async {
    appLogger.info(
      'service.rdap.check.started',
      data: <String, Object?>{'hostname': hostname},
    );
    final services = await _loadServices();
    final labels = hostname.split('.');
    if (labels.length < 2) {
      return null;
    }
    final base = services[labels.last];
    if (base == null) {
      return null;
    }

    for (var start = 0; start <= labels.length - 2; start++) {
      final candidate = labels.sublist(start).join('.');
      final response = await _getJson(
        Uri.parse(base).resolve('domain/${Uri.encodeComponent(candidate)}'),
        allowNotFound: true,
      );
      if (response == null) {
        continue;
      }
      appLogger.info(
        'service.rdap.check.completed',
        data: <String, Object?>{'hostname': hostname, 'found': true},
      );
      return parseRdapDomain(
        response,
        source: Uri.parse(base).host,
        registeredDomain: candidate,
      );
    }
    appLogger.info(
      'service.rdap.check.completed',
      data: <String, Object?>{'hostname': hostname, 'found': false},
    );
    return null;
  }

  /// Loads and caches the IANA TLD-to-RDAP endpoint mapping for this session.
  Future<Map<String, String>> _loadServices() async {
    final cached = _services;
    if (cached != null) {
      return cached;
    }
    final payload = await _getJson(Uri.parse(_bootstrapUri));
    if (payload == null) {
      throw const RdapException('RDAP bootstrap unavailable');
    }
    final result = <String, String>{};
    for (final service in payload['services'] as List<dynamic>? ?? const []) {
      final parts = service as List<dynamic>;
      if (parts.length < 2) {
        continue;
      }
      final urls = (parts[1] as List<dynamic>).cast<String>();
      if (urls.isEmpty) {
        continue;
      }
      final base = urls.first.endsWith('/') ? urls.first : '${urls.first}/';
      for (final tld in (parts[0] as List<dynamic>).cast<String>()) {
        result[tld.toLowerCase()] = base;
      }
    }
    return _services = result;
  }

  /// Performs one bounded RDAP JSON request and handles optional 404 responses.
  Future<Map<String, dynamic>?> _getJson(
    Uri uri, {
    bool allowNotFound = false,
  }) async {
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/rdap+json, application/json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'Akshi/0.1');
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (allowNotFound && response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw RdapException('Registry returned ${response.statusCode}');
    }
    final body = await utf8.decoder.bind(response).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

class RdapException implements Exception {
  const RdapException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Maps an RDAP payload into the app's stable domain-registration facts.
DomainCheckResult parseRdapDomain(
  Map<String, dynamic> payload, {
  required String source,
  required String registeredDomain,
}) {
  final entities = _rdapMaps(payload['entities']);
  final nameServers =
      _rdapMaps(payload['nameservers'])
          .map(
            (value) =>
                (value['unicodeName'] as String?) ??
                (value['ldhName'] as String?) ??
                '',
          )
          .map(
            (value) =>
                value.trim().replaceFirst(RegExp(r'\.$'), '').toLowerCase(),
          )
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  return DomainCheckResult(
    expiresAt: _eventDate(payload, const <String>[
      'registrar expiration',
      'expiration',
      'registry expiry',
    ]),
    registeredAt: _eventDate(payload, const <String>['registration']),
    updatedAt: _eventDate(payload, const <String>[
      'last changed',
      'last update of RDAP database',
    ]),
    source: source,
    registeredDomain: registeredDomain,
    registrar: _entityName(entities, 'registrar'),
    publicRegistrant: _entityName(entities, 'registrant'),
    nameServers: List<String>.unmodifiable(nameServers),
  );
}

DateTime? _eventDate(Map<String, dynamic> payload, List<String> priorities) {
  final events = _rdapMaps(payload['events']);
  for (final action in priorities) {
    for (final event in events) {
      if ((event['eventAction'] as String?)?.toLowerCase() != action) {
        continue;
      }
      final date = DateTime.tryParse(event['eventDate'] as String? ?? '');
      if (date != null) {
        return date.toLocal();
      }
    }
  }
  return null;
}

String? _entityName(List<Map<String, dynamic>> roots, String role) {
  for (final entity in _walkEntities(roots)) {
    final roles = (entity['roles'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .map((value) => value.toLowerCase());
    if (!roles.contains(role)) {
      continue;
    }
    final fields = _vcardFields(entity['vcardArray']);
    final candidate = role == 'registrar'
        ? fields['fn'] ?? fields['org']
        : fields['org'] ?? fields['fn'];
    final visible = _publicValue(candidate);
    if (visible != null) {
      return visible;
    }
  }
  return null;
}

Iterable<Map<String, dynamic>> _walkEntities(
  List<Map<String, dynamic>> entities,
) sync* {
  for (final entity in entities) {
    yield entity;
    yield* _walkEntities(_rdapMaps(entity['entities']));
  }
}

Map<String, String> _vcardFields(Object? raw) {
  if (raw is! List || raw.length < 2 || raw[1] is! List) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final property in raw[1] as List<dynamic>) {
    if (property is! List || property.length < 4) {
      continue;
    }
    final key = property[0];
    final value = property[3];
    if (key is! String) {
      continue;
    }
    final text = value is List
        ? value.whereType<Object>().map((part) => part.toString()).join(' ')
        : value?.toString();
    if (text != null && text.trim().isNotEmpty) {
      result.putIfAbsent(key.toLowerCase(), () => text.trim());
    }
  }
  return result;
}

String? _publicValue(String? value) {
  final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  final lower = normalized.toLowerCase();
  const hiddenMarkers = <String>[
    'redacted',
    'not disclosed',
    'not published',
    'data protected',
    'privacy protected',
    'withheld',
  ];
  if (hiddenMarkers.any(lower.contains)) {
    return null;
  }
  return normalized;
}

List<Map<String, dynamic>> _rdapMaps(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
