import 'dart:async';
import 'dart:io';

import 'package:akshi/core/services/async_concurrency_gate.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:flutter/services.dart';

/// Reads DNS records through the platform resolver exposed by native code.
///
/// The native bridge returns wire-format record bytes. This service decodes
/// only explicit record types so duplicate records and missing records remain
/// distinguishable to the rest of the app.
class SystemDnsService {
  const SystemDnsService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.aliyesha.akshi/dns');

  final MethodChannel _channel;

  /// Queries one owner/type pair and maps the native response into domain data.
  ///
  /// A successful empty response becomes [DnsQueryState.absent]; transport,
  /// timeout, and malformed responses are surfaced to [DnsSnapshotService].
  Future<DnsQueryResult> query(String name, DnsRecordType type) async {
    final normalizedName = _normalizeName(name);
    appLogger.info(
      'service.dns.query.started',
      data: <String, Object?>{'name': normalizedName, 'type': type.name},
    );
    final response = await _channel
        .invokeMapMethod<String, Object?>('query', <String, Object?>{
          'name': normalizedName,
          'type': type.code,
        })
        .timeout(const Duration(seconds: 10));
    if (response == null) throw const FormatException('Empty DNS response');
    final values = response['records'];
    if (values is! List) throw const FormatException('Invalid DNS response');

    final records = <DnsRecord>[];
    for (final value in values.whereType<Map>()) {
      final map = Map<String, Object?>.from(value);
      final recordType = DnsRecordType.fromCode(map['type']! as int);
      final bytes = _bytes(map['data']);
      if (recordType == null || bytes == null) continue;
      final decoded = _decode(recordType, bytes);
      if (decoded == null) continue;
      records.add(
        DnsRecord(
          owner: _normalizeName(map['owner']! as String),
          type: recordType,
          ttlSeconds: map['ttl']! as int,
          value: decoded.value,
          preference: decoded.preference,
        ),
      );
    }
    records.sort((left, right) {
      final owner = left.owner.compareTo(right.owner);
      if (owner != 0) return owner;
      final priority = (left.preference ?? -1).compareTo(
        right.preference ?? -1,
      );
      return priority != 0 ? priority : left.value.compareTo(right.value);
    });
    appLogger.info(
      'service.dns.query.completed',
      data: <String, Object?>{
        'name': normalizedName,
        'type': type.name,
        'recordCount': records.length,
      },
    );
    return DnsQueryResult(
      name: normalizedName,
      type: type,
      state: records.isEmpty ? DnsQueryState.absent : DnsQueryState.answered,
      records: records,
    );
  }
}

/// Collects one consistent DNS snapshot for domain and email checks.
///
/// Every requested query is isolated behind its own failure boundary, so one
/// unavailable record does not erase useful results from the other queries.
class DnsSnapshotService {
  DnsSnapshotService({SystemDnsService? dns, AsyncConcurrencyGate? gate})
    : _dns = dns ?? const SystemDnsService(),
      _gate = gate ?? AsyncConcurrencyGate(maximum: 10);

  final SystemDnsService _dns;
  final AsyncConcurrencyGate _gate;

  /// Runs the explicit root and role-specific queries for a monitor.
  ///
  /// Email names are requested only when the corresponding send/receive role
  /// is enabled. The returned snapshot is shared by email posture evaluation
  /// and the DNS details screen, preventing duplicate lookups.
  Future<DnsSnapshot> check(
    String domain, {
    required bool checkEmailSending,
    required bool checkEmailReceiving,
    required List<String> dkimSelectors,
  }) async {
    final normalizedDomain = _normalizeName(domain);
    appLogger.info(
      'service.dns.snapshot.started',
      data: <String, Object?>{
        'domain': normalizedDomain,
        'checkEmailSending': checkEmailSending,
        'checkEmailReceiving': checkEmailReceiving,
        'dkimSelectorCount': dkimSelectors.length,
      },
    );
    final requests = <({String name, DnsRecordType type})>[
      for (final type in DnsRecordType.values)
        (name: normalizedDomain, type: type),
      if (checkEmailSending) ...<({String name, DnsRecordType type})>[
        (name: '_dmarc.$normalizedDomain', type: DnsRecordType.txt),
        for (final selector in dkimSelectors)
          (
            name: '$selector._domainkey.$normalizedDomain',
            type: DnsRecordType.txt,
          ),
      ],
      if (checkEmailReceiving) ...<({String name, DnsRecordType type})>[
        (name: '_mta-sts.$normalizedDomain', type: DnsRecordType.txt),
        (name: '_smtp._tls.$normalizedDomain', type: DnsRecordType.txt),
      ],
    ];
    late final List<DnsQueryResult> queries;
    try {
      queries = await Future.wait(
        requests.map((request) async {
          try {
            return await _gate.run(
              () => _dns.query(request.name, request.type),
            );
          } catch (error, stackTrace) {
            appLogger.error(
              'service.dns.query.failed',
              error,
              stackTrace,
              data: <String, Object?>{
                'name': request.name,
                'type': request.type.name,
              },
            );
            return DnsQueryResult(
              name: request.name,
              type: request.type,
              state: DnsQueryState.failed,
              error: _errorMessage(error),
            );
          }
        }),
      );
    } catch (error, stackTrace) {
      appLogger.error(
        'service.dns.snapshot.failed',
        error,
        stackTrace,
        data: <String, Object?>{'domain': normalizedDomain},
      );
      final message = _errorMessage(error);
      queries = requests
          .map(
            (request) => DnsQueryResult(
              name: request.name,
              type: request.type,
              state: DnsQueryState.failed,
              error: message,
            ),
          )
          .toList(growable: false);
    }
    final snapshot = DnsSnapshot(checkedAt: DateTime.now(), queries: queries);
    appLogger.info(
      'service.dns.snapshot.completed',
      data: <String, Object?>{
        'domain': normalizedDomain,
        'queryCount': queries.length,
        'failedCount': queries
            .where((query) => query.state == DnsQueryState.failed)
            .length,
      },
    );
    return snapshot;
  }
}

/// Decodes one DNS wire-format payload into a display value and MX priority.
({String value, int? preference})? _decode(
  DnsRecordType type,
  Uint8List bytes,
) => switch (type) {
  DnsRecordType.a when bytes.length == 4 => (
    value: bytes.join('.'),
    preference: null,
  ),
  DnsRecordType.aaaa when bytes.length == 16 => (
    value: InternetAddress.fromRawAddress(bytes).address,
    preference: null,
  ),
  DnsRecordType.ns || DnsRecordType.cname => switch (_decodeName(bytes, 0)) {
    final String value => (value: value, preference: null),
    null => null,
  },
  DnsRecordType.mx when bytes.length >= 3 => switch (_decodeName(bytes, 2)) {
    final String value => (
      value: value,
      preference: (bytes[0] << 8) | bytes[1],
    ),
    null => null,
  },
  DnsRecordType.txt => switch (_decodeTxt(bytes)) {
    final String value => (value: value, preference: null),
    null => null,
  },
  DnsRecordType.caa when bytes.length >= 2 => switch (_decodeCaa(bytes)) {
    final String value => (value: value, preference: null),
    null => null,
  },
  _ => null,
};

/// Joins all length-prefixed TXT character strings in one DNS record.
String? _decodeTxt(Uint8List data) {
  final buffer = StringBuffer();
  var offset = 0;
  while (offset < data.length) {
    final length = data[offset++];
    if (offset + length > data.length) return null;
    buffer.write(String.fromCharCodes(data.sublist(offset, offset + length)));
    offset += length;
  }
  return buffer.toString();
}

/// Decodes an uncompressed DNS name from the supplied record payload.
String? _decodeName(Uint8List data, int start) {
  final labels = <String>[];
  var offset = start;
  while (offset < data.length) {
    final length = data[offset++];
    if (length == 0) {
      return labels.isEmpty ? '.' : labels.join('.').toLowerCase();
    }
    if ((length & 0xc0) != 0 || offset + length > data.length) return null;
    labels.add(String.fromCharCodes(data.sublist(offset, offset + length)));
    offset += length;
  }
  return null;
}

/// Formats CAA flags, tag, and value into a readable single record value.
String? _decodeCaa(Uint8List data) {
  final tagLength = data[1];
  if (2 + tagLength > data.length) return null;
  final flags = data[0];
  final tag = String.fromCharCodes(data.sublist(2, 2 + tagLength));
  final value = String.fromCharCodes(data.sublist(2 + tagLength));
  return '$flags $tag $value';
}

/// Converts platform byte containers into one predictable [Uint8List].
Uint8List? _bytes(Object? value) => switch (value) {
  final Uint8List bytes => bytes,
  final List<int> bytes => Uint8List.fromList(bytes),
  _ => null,
};

/// Canonicalizes DNS names for query keys and semantic comparisons.
String _normalizeName(String name) =>
    name.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');

/// Converts platform exceptions into user-facing, non-stack-trace text.
String _errorMessage(Object error) => switch (error) {
  PlatformException(code: 'dns_error') =>
    'The system DNS resolver could not complete this lookup.',
  PlatformException() =>
    'The system DNS resolver returned an invalid response.',
  TimeoutException() => 'The DNS lookup timed out.',
  SocketException() => 'The device could not reach its DNS resolver.',
  _ => 'This DNS lookup could not be completed.',
};
