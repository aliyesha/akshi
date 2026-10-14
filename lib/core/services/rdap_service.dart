import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/bounded_response_reader.dart';
import 'package:akshi/features/monitors/domain/check_result.dart';

/// Reads public RDAP registration data using IANA's TLD bootstrap map.
///
/// The service keeps the network dependency local to a foreground check and
/// returns null when a registry has no matching public registration record.
class RdapService {
  RdapService(this._client, {this.operationTimeout = defaultOperationTimeout}) {
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        operationTimeout,
        'operationTimeout',
        'Must be positive',
      );
    }
  }

  static const _bootstrapUri = 'https://data.iana.org/rdap/dns.json';
  static const defaultOperationTimeout = Duration(seconds: 30);
  final HttpClient _client;
  final _responseReader = const RdapResponseReader();
  final Duration operationTimeout;
  Map<String, String>? _services;
  Future<Map<String, String>>? _servicesLoading;

  /// Resolves the registrable domain and returns normalized registration facts.
  Future<DomainCheckResult?> check(String hostname) async {
    final deadline = _RdapDeadline(operationTimeout);
    appLogger.info(
      'service.rdap.check.started',
      data: <String, Object?>{'hostname': hostname},
    );
    final services = await _loadServices(deadline);
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
        deadline: deadline,
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
  ///
  /// Concurrent first checks join one in-flight download. A failed download is
  /// not cached, so a later foreground check can retry cleanly.
  Future<Map<String, String>> _loadServices(_RdapDeadline deadline) {
    final cached = _services;
    if (cached != null) {
      return Future<Map<String, String>>.value(cached);
    }

    final active = _servicesLoading;
    if (active != null) {
      // The shared download belongs to all waiting checks, so this caller may
      // stop waiting at its own deadline but must not abort work used by peers.
      return active.timeout(deadline.remaining());
    }

    late final Future<Map<String, String>> operation;
    operation = _fetchServices(deadline).whenComplete(() {
      if (identical(_servicesLoading, operation)) {
        _servicesLoading = null;
      }
    });
    _servicesLoading = operation;
    return operation;
  }

  Future<Map<String, String>> _fetchServices(_RdapDeadline deadline) async {
    final payload = await _getJson(
      Uri.parse(_bootstrapUri),
      deadline: deadline,
    );
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
    required _RdapDeadline deadline,
    bool allowNotFound = false,
  }) async {
    final request = await _openRequest(uri, deadline);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/rdap+json, application/json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'Akshi/0.1');
    final response = await _closeRequest(request, deadline);
    if (allowNotFound && response.statusCode == HttpStatus.notFound) {
      await cancelResponseBody(response);
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await cancelResponseBody(response);
      throw RdapException('Registry returned ${response.statusCode}');
    }
    late final Duration readTimeout;
    try {
      readTimeout = deadline.remaining(maximum: _responseReader.timeout);
    } on TimeoutException {
      await cancelResponseBody(response);
      rethrow;
    }
    return _responseReader.read(
      response,
      contentType: response.headers.value(HttpHeaders.contentTypeHeader),
      contentLength: expectedResponseBodyLength(response),
      readTimeout: readTimeout,
    );
  }

  Future<HttpClientRequest> _openRequest(Uri uri, _RdapDeadline deadline) =>
      openHttpGetRequest(
        _client,
        uri,
        timeout: deadline.remaining(maximum: _responseReader.timeout),
      );

  Future<HttpClientResponse> _closeRequest(
    HttpClientRequest request,
    _RdapDeadline deadline,
  ) {
    late final Duration timeout;
    try {
      timeout = deadline.remaining(maximum: _responseReader.timeout);
    } on TimeoutException catch (error, stackTrace) {
      request.abort(error, stackTrace);
      rethrow;
    }
    return sendHttpRequest(request, timeout: timeout);
  }
}

/// Monotonic time budget shared by every network stage in one RDAP check.
final class _RdapDeadline {
  _RdapDeadline(this.limit) : _elapsed = Stopwatch()..start();

  final Duration limit;
  final Stopwatch _elapsed;

  Duration remaining({Duration? maximum}) {
    final value = limit - _elapsed.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('RDAP operation timed out.', limit);
    }
    return maximum != null && maximum < value ? maximum : value;
  }
}

/// Reads one RDAP JSON object within explicit media, size, and time limits.
class RdapResponseReader {
  /// Creates a reader with explicit byte and total-duration limits.
  const RdapResponseReader({
    this.maxBytes = defaultMaxBytes,
    this.timeout = defaultTimeout,
  }) : assert(maxBytes > 0);

  /// Two MiB comfortably covers ordinary bootstrap and domain responses while
  /// keeping concurrent mobile checks within a predictable memory envelope.
  static const defaultMaxBytes = 2 * 1024 * 1024;

  /// Maximum time allowed from the first body read until completion.
  static const defaultTimeout = Duration(seconds: 12);

  /// Maximum response-body bytes buffered before JSON parsing.
  final int maxBytes;

  /// Maximum total duration allowed for reading the response body.
  final Duration timeout;

  /// Validates response metadata, reads at most [maxBytes], and requires a JSON
  /// object. Unknown-length and chunked responses are bounded while streaming.
  Future<Map<String, dynamic>> read(
    Stream<List<int>> body, {
    required String? contentType,
    required int? contentLength,
    Duration? readTimeout,
  }) async {
    try {
      _validateContentType(contentType);
    } catch (_) {
      await cancelResponseBody(body);
      rethrow;
    }

    final bytes = await readBoundedResponseBody(
      body,
      maximumBytes: maxBytes,
      timeout: readTimeout ?? timeout,
      contentLength: contentLength,
    );
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('RDAP response is not a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void _validateContentType(String? value) {
    if (value == null) {
      throw const FormatException('RDAP response has no Content-Type.');
    }

    late final ContentType parsed;
    try {
      parsed = ContentType.parse(value);
    } on FormatException {
      throw const FormatException('RDAP response has an invalid Content-Type.');
    }
    final mimeType = parsed.mimeType.toLowerCase();
    if (mimeType != 'application/rdap+json' && mimeType != 'application/json') {
      throw FormatException(
        'RDAP response uses unsupported Content-Type $mimeType.',
      );
    }
  }
}

class RdapException implements Exception {
  const RdapException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Maps one identified RDAP domain object into an atomic registration result.
///
/// The payload must identify both the RDAP domain class and the requested name.
/// Any malformed consumed structure rejects the result so callers retain the
/// preceding complete observation instead of persisting a partial object.
DomainCheckResult parseRdapDomain(
  Map<String, dynamic> payload, {
  required String source,
  required String registeredDomain,
}) {
  _validateDomainIdentity(payload, registeredDomain);
  final entities = _rdapMaps(payload['entities'], field: 'entities');
  final nameServers =
      _rdapMaps(payload['nameservers'], field: 'nameservers')
          .map(_nameServerIdentity)
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

void _validateDomainIdentity(
  Map<String, dynamic> payload,
  String registeredDomain,
) {
  if (payload['objectClassName'] != 'domain') {
    throw const FormatException('RDAP response is not a domain object.');
  }
  final identities = <String>[];
  for (final key in const <String>['ldhName', 'unicodeName']) {
    final value = payload[key];
    if (value == null) continue;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('RDAP $key is invalid.');
    }
    identities.add(_normalizeDomainIdentity(value));
  }
  if (!identities.contains(_normalizeDomainIdentity(registeredDomain))) {
    throw const FormatException(
      'RDAP response does not identify the requested domain.',
    );
  }
}

String _nameServerIdentity(Map<String, dynamic> value) {
  final unicodeName = value['unicodeName'];
  final ldhName = value['ldhName'];
  if ((unicodeName != null && unicodeName is! String) ||
      (ldhName != null && ldhName is! String)) {
    throw const FormatException('RDAP nameserver identity is invalid.');
  }
  final identity = (unicodeName as String?) ?? (ldhName as String?);
  if (identity == null || identity.trim().isEmpty) {
    throw const FormatException('RDAP nameserver has no identity.');
  }
  return identity;
}

DateTime? _eventDate(Map<String, dynamic> payload, List<String> priorities) {
  final events = _rdapMaps(payload['events'], field: 'events');
  for (final event in events) {
    final action = event['eventAction'];
    final rawDate = event['eventDate'];
    if (action is! String || rawDate is! String) {
      throw const FormatException('RDAP event is invalid.');
    }
    final date = DateTime.tryParse(rawDate);
    if (date == null) {
      throw const FormatException('RDAP event date is invalid.');
    }
    if (priorities.contains(action.toLowerCase())) return date.toLocal();
  }
  return null;
}

String? _entityName(List<Map<String, dynamic>> roots, String role) {
  for (final entity in _walkEntities(roots)) {
    final rawRoles = entity['roles'];
    if (rawRoles != null &&
        (rawRoles is! List || rawRoles.any((value) => value is! String))) {
      throw const FormatException('RDAP entity roles are invalid.');
    }
    final roles = (rawRoles as List<dynamic>? ?? const <dynamic>[])
        .cast<String>()
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
    yield* _walkEntities(
      _rdapMaps(entity['entities'], field: 'nested entities'),
    );
  }
}

Map<String, String> _vcardFields(Object? raw) {
  if (raw == null) return const <String, String>{};
  if (raw is! List || raw.length < 2 || raw[1] is! List) {
    throw const FormatException('RDAP vCard is invalid.');
  }
  final result = <String, String>{};
  for (final property in raw[1] as List<dynamic>) {
    if (property is! List || property.length < 4 || property[0] is! String) {
      throw const FormatException('RDAP vCard property is invalid.');
    }
    final key = property[0] as String;
    final value = property[3];
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

List<Map<String, dynamic>> _rdapMaps(Object? value, {required String field}) {
  if (value == null) return const <Map<String, dynamic>>[];
  if (value is! List || value.any((item) => item is! Map)) {
    throw FormatException('RDAP $field is invalid.');
  }
  return value
      .cast<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

String _normalizeDomainIdentity(String value) =>
    value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
