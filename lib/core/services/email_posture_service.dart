import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/bounded_response_reader.dart';
import 'package:akshi/core/services/mta_sts_policy.dart';
import 'package:akshi/features/domains/domain/dns_snapshot.dart';
import 'package:akshi/features/domains/domain/email_posture.dart';

/// Evaluates practical email DNS and MTA-STS posture from one DNS snapshot.
///
/// This service reports facts and configuration gaps; it deliberately avoids
/// opaque third-party scores that could become stale or misleading.
class EmailPostureService {
  EmailPostureService(this._client);

  final HttpClient _client;
  final _policyReader = const MtaStsPolicyReader();

  /// Builds ordered findings for the enabled send/receive capabilities.
  ///
  /// All DNS values come from [snapshot], so the email and DNS screens describe
  /// the same observation instead of racing separate lookups. Standard owner
  /// names such as `_dmarc` are planned automatically but remain ordinary TXT
  /// RRsets; interpretation happens only here, after DNS verification.
  Future<EmailPosture> check(
    DnsSnapshot snapshot,
    String domain, {
    required bool sends,
    required bool receives,
    required List<String> dkimSelectors,
  }) async {
    appLogger.info(
      'service.email.check.started',
      data: <String, Object?>{
        'hostname': domain,
        'sends': sends,
        'receives': receives,
        'dkimSelectorCount': dkimSelectors.length,
      },
    );
    final mx = receives
        ? snapshot.records(domain, DnsRecordType.mx).toList(growable: false)
        : const <DnsRecord>[];
    final rootTxt = sends ? _txt(snapshot, domain) : const <String>[];
    final dmarc = sends ? _txt(snapshot, '_dmarc.$domain') : const <String>[];
    final mtaSts = receives
        ? _txt(snapshot, '_mta-sts.$domain')
        : const <String>[];
    final tlsRpt = receives
        ? _txt(snapshot, '_smtp._tls.$domain')
        : const <String>[];

    final findings = <MailFinding>[
      if (receives)
        _queryFinding(
          snapshot.query(domain, DnsRecordType.mx),
          id: 'mx',
          title: 'Mail exchange',
          build: () => _mxFinding(mx),
        ),
      if (sends)
        _queryFinding(
          snapshot.query(domain, DnsRecordType.txt),
          id: 'spf',
          title: 'SPF',
          build: () => _spfFinding(rootTxt),
        ),
      if (sends)
        _queryFinding(
          snapshot.query('_dmarc.$domain', DnsRecordType.txt),
          id: 'dmarc',
          title: 'DMARC',
          build: () => _dmarcFinding(dmarc),
        ),
      if (receives) await _mtaStsFromSnapshot(snapshot, domain, mtaSts, mx),
      if (receives)
        _queryFinding(
          snapshot.query('_smtp._tls.$domain', DnsRecordType.txt),
          id: 'tls-rpt',
          title: 'TLS reporting',
          build: () => _tlsRptFinding(tlsRpt),
        ),
      for (final selector in sends ? dkimSelectors : const <String>[])
        _dkimFromSnapshot(snapshot, domain, selector),
    ];
    appLogger.info(
      'service.email.check.completed',
      data: <String, Object?>{
        'hostname': domain,
        'findingCount': findings.length,
      },
    );
    return EmailPosture(checkedAt: DateTime.now(), findings: findings);
  }

  /// Handles MTA-STS DNS availability before optionally fetching its HTTPS policy.
  Future<MailFinding> _mtaStsFromSnapshot(
    DnsSnapshot snapshot,
    String domain,
    List<String> records,
    List<DnsRecord> mx,
  ) async {
    final policyRecord = snapshot.query('_mta-sts.$domain', DnsRecordType.txt);
    if (policyRecord?.state == DnsQueryState.failed) {
      return _unavailableFinding('mta-sts', 'MTA-STS', policyRecord!);
    }
    return _mtaStsFinding(
      domain,
      records,
      mx: mx,
      mailExchange: snapshot.query(domain, DnsRecordType.mx),
    );
  }

  MailFinding _dkimFromSnapshot(
    DnsSnapshot snapshot,
    String domain,
    String selector,
  ) {
    final name = '$selector._domainkey.$domain';
    return _queryFinding(
      snapshot.query(name, DnsRecordType.txt),
      id: 'dkim-$selector',
      title: 'DKIM · $selector',
      build: () => _dkimFinding(selector, _txt(snapshot, name)),
    );
  }

  /// Converts a failed DNS query into an unavailable finding, otherwise builds it.
  MailFinding _queryFinding(
    DnsQueryResult? query, {
    required String id,
    required String title,
    required MailFinding Function() build,
  }) {
    if (query?.state == DnsQueryState.failed) {
      return _unavailableFinding(id, title, query!);
    }
    return build();
  }

  /// Preserves lookup failure detail without classifying it as invalid DNS data.
  MailFinding _unavailableFinding(
    String id,
    String title,
    DnsQueryResult query,
  ) => MailFinding(
    id: id,
    title: title,
    state: MailFindingState.unavailable,
    summary: query.error ?? 'This DNS lookup could not be completed.',
  );

  /// Validates MTA-STS records and, when present, the HTTPS policy document.
  ///
  /// MX coverage is checked against policy patterns. Only a covered `enforce`
  /// policy is healthy; non-enforcing modes remain informational.
  Future<MailFinding> _mtaStsFinding(
    String domain,
    List<String> records, {
    required List<DnsRecord> mx,
    required DnsQueryResult? mailExchange,
  }) async {
    final policies = records.where(_isMtaSts).toList(growable: false);
    if (policies.isEmpty) {
      return const MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.informational,
        summary: 'No MTA-STS policy is published.',
      );
    }
    if (policies.length > 1) {
      return const MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.invalid,
        summary: 'Multiple MTA-STS DNS records are published.',
      );
    }
    final id = _tagValues(policies.single)['id'];
    if (id == null || id.isEmpty) {
      return const MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.invalid,
        summary: 'The MTA-STS DNS record has no policy id.',
      );
    }
    if (mailExchange?.state == DnsQueryState.failed) {
      return _unavailableFinding('mta-sts', 'MTA-STS', mailExchange!);
    }
    try {
      final policy = await _fetchText(
        Uri.https('mta-sts.$domain', '/.well-known/mta-sts.txt'),
      );
      final parsedPolicy = MtaStsPolicy.tryParse(policy);
      if (parsedPolicy == null) {
        return const MailFinding(
          id: 'mta-sts',
          title: 'MTA-STS',
          state: MailFindingState.invalid,
          summary: 'The published HTTPS policy is incomplete or invalid.',
        );
      }
      final mode = parsedPolicy.mode;
      final maxAge = parsedPolicy.maxAgeSeconds;
      final mxPatterns = parsedPolicy.mxPatterns;
      final currentExchanges = mx
          .where((record) => record.value != '.')
          .map((record) => record.value)
          .toList(growable: false);
      final unmatched = mode == 'none'
          ? const <String>[]
          : currentExchanges
                .where(
                  (exchange) => !mxPatterns.any(
                    (pattern) => _matchesMx(exchange, pattern),
                  ),
                )
                .toList(growable: false);
      final state = switch ((mode, unmatched.isEmpty)) {
        (_, false) => MailFindingState.warning,
        ('enforce', true) => MailFindingState.healthy,
        _ => MailFindingState.informational,
      };
      final summary = unmatched.isNotEmpty
          ? 'The HTTPS policy does not cover every current MX host.'
          : switch (mode) {
              'enforce' =>
                'The enforced HTTPS policy covers the current MX hosts.',
              'testing' => 'The testing policy covers the current MX hosts but does not enforce TLS.',
              _ => 'The published policy uses mode "none" and does not enforce TLS.',
            };
      return MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: state,
        summary: summary,
        facts: <MailFact>[
          MailFact(label: 'Policy id', value: id),
          MailFact(label: 'Mode', value: mode),
          MailFact(label: 'Maximum age', value: '$maxAge seconds'),
          MailFact(label: 'MX patterns', value: mxPatterns.join(', ')),
        ],
      );
    } catch (error, stackTrace) {
      appLogger.error(
        'service.email.mta_sts_policy.failed',
        error,
        stackTrace,
        data: <String, Object?>{'hostname': domain},
      );
      return MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.unavailable,
        summary: 'The DNS record exists, but the HTTPS policy could not be verified.',
        facts: <MailFact>[MailFact(label: 'Policy id', value: id)],
      );
    }
  }

  /// Fetches a bounded text policy with one total body deadline and no redirects.
  Future<String> _fetchText(Uri uri) async {
    final request = await openHttpGetRequest(
      _client,
      uri,
      timeout: _policyReader.timeout,
    );
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'text/plain')
      ..headers.set(HttpHeaders.userAgentHeader, 'Akshi/1.0');
    final response = await sendHttpRequest(
      request,
      timeout: _policyReader.timeout,
    );
    if (response.statusCode != HttpStatus.ok) {
      await cancelResponseBody(response);
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return _policyReader.read(
      response,
      contentType: response.headers.value(HttpHeaders.contentTypeHeader),
      contentLength: expectedResponseBodyLength(response),
    );
  }
}

/// Reads an MTA-STS policy within explicit size and time boundaries.
class MtaStsPolicyReader {
  /// Creates a bounded policy reader.
  const MtaStsPolicyReader({
    this.maxBytes = defaultMaxBytes,
    this.timeout = defaultTimeout,
  }) : assert(maxBytes > 0);

  /// Maximum accepted production policy size.
  static const defaultMaxBytes = 128 * 1024;

  /// Maximum production duration for reading the complete response body.
  static const defaultTimeout = Duration(seconds: 10);

  /// Maximum accepted response bytes.
  final int maxBytes;

  /// Deadline applied to the complete response-body read.
  final Duration timeout;

  /// Returns strict UTF-8 policy text or throws when a boundary is exceeded.
  Future<String> read(
    Stream<List<int>> body, {
    required String? contentType,
    required int? contentLength,
  }) async {
    if (!_isPlainText(contentType)) {
      await cancelResponseBody(body);
      throw const FormatException(
        'MTA-STS policy response must use the text/plain media type.',
      );
    }
    final bytes = await readBoundedResponseBody(
      body,
      maximumBytes: maxBytes,
      timeout: timeout,
      contentLength: contentLength,
    );
    return utf8.decode(bytes);
  }

  bool _isPlainText(String? value) {
    if (value == null) return false;
    try {
      final parsed = ContentType.parse(value);
      return parsed.primaryType.toLowerCase() == 'text' &&
          parsed.subType.toLowerCase() == 'plain';
    } on FormatException {
      return false;
    }
  }
}

/// Returns TXT values for an owner while preserving duplicate records.
List<String> _txt(DnsSnapshot snapshot, String name) => snapshot
    .records(name, DnsRecordType.txt)
    .map((record) => record.value)
    .toList(growable: false);

/// Evaluates MX presence and records published exchanges as facts.
MailFinding _mxFinding(List<DnsRecord> records) {
  if (records.isEmpty) {
    return const MailFinding(
      id: 'mx',
      title: 'Mail exchange',
      state: MailFindingState.warning,
      summary: 'No MX record is published for incoming email.',
    );
  }
  if (records.any((record) => record.preference == 0 && record.value == '.')) {
    return const MailFinding(
      id: 'mx',
      title: 'Mail exchange',
      state: MailFindingState.warning,
      summary: 'A Null MX record says this domain does not accept email.',
    );
  }
  return MailFinding(
    id: 'mx',
    title: 'Mail exchange',
    state: MailFindingState.healthy,
    summary:
        '${records.length} MX host${records.length == 1 ? ' is' : 's are'} published for incoming email.',
    facts: records
        .map(
          (record) => MailFact(
            label: 'Priority ${record.preference}',
            value: record.value,
          ),
        )
        .toList(growable: false),
  );
}

/// Reports SPF publication and only the limits visible in this record.
MailFinding _spfFinding(List<String> values) {
  final records = values.where(_isSpf).toList(growable: false);
  if (records.isEmpty) {
    return const MailFinding(
      id: 'spf',
      title: 'SPF',
      state: MailFindingState.warning,
      summary: 'No SPF record is published for this domain.',
    );
  }
  if (records.length > 1) {
    return const MailFinding(
      id: 'spf',
      title: 'SPF',
      state: MailFindingState.invalid,
      summary: 'Multiple SPF records are published. SPF permits only one record at this name.',
    );
  }
  final record = records.single;
  return MailFinding(
    id: 'spf',
    title: 'SPF',
    state: MailFindingState.informational,
    summary: 'One SPF record is published. Akshi does not test it against a sending server.',
    facts: <MailFact>[MailFact(label: 'Published policy', value: record)],
  );
}

/// Reports DMARC uniqueness and recognized policy tags as published facts.
MailFinding _dmarcFinding(List<String> values) {
  final records = values.where(_isDmarc).toList(growable: false);
  if (records.isEmpty) {
    return const MailFinding(
      id: 'dmarc',
      title: 'DMARC',
      state: MailFindingState.warning,
      summary: 'No DMARC record is published for this domain.',
    );
  }
  if (records.length > 1) {
    return const MailFinding(
      id: 'dmarc',
      title: 'DMARC',
      state: MailFindingState.invalid,
      summary: 'Multiple DMARC records are published.',
    );
  }
  final tags = _tagValues(records.single);
  final policy = tags['p']?.toLowerCase();
  if (!const <String>{'none', 'quarantine', 'reject'}.contains(policy)) {
    return const MailFinding(
      id: 'dmarc',
      title: 'DMARC',
      state: MailFindingState.invalid,
      summary: 'The DMARC record does not contain a recognized p policy.',
    );
  }
  return MailFinding(
    id: 'dmarc',
    title: 'DMARC',
    state: MailFindingState.informational,
    summary: 'A DMARC record publishes the "$policy" policy.',
    facts: <MailFact>[
      MailFact(label: 'Policy', value: policy!),
      if (tags['sp'] case final subdomainPolicy?)
        MailFact(label: 'Subdomain policy', value: subdomainPolicy),
      if (tags['rua'] case final reports?)
        MailFact(label: 'Aggregate reports', value: reports),
    ],
  );
}

/// Evaluates TLS-RPT publication without assigning a vendor score.
MailFinding _tlsRptFinding(List<String> values) {
  final records = values.where(_isTlsRpt).toList(growable: false);
  if (records.isEmpty) {
    return const MailFinding(
      id: 'tls-rpt',
      title: 'TLS reporting',
      state: MailFindingState.informational,
      summary: 'No TLS reporting record is published for this domain.',
    );
  }
  if (records.length > 1) {
    return const MailFinding(
      id: 'tls-rpt',
      title: 'TLS reporting',
      state: MailFindingState.invalid,
      summary: 'Multiple TLS reporting records are published. Only one is permitted.',
    );
  }
  final destination = _tagValues(records.single)['rua'];
  return MailFinding(
    id: 'tls-rpt',
    title: 'TLS reporting',
    state: destination == null
        ? MailFindingState.invalid
        : MailFindingState.informational,
    summary: destination == null
        ? 'The TLS reporting record has no rua report destination.'
        : 'A TLS reporting destination value is published.',
    facts: <MailFact>[
      if (destination != null)
        MailFact(label: 'Reports to', value: destination),
    ],
  );
}

/// Evaluates a configured DKIM selector and reports its published key record.
MailFinding _dkimFinding(String selector, List<String> values) {
  final records = values
      .where((value) {
        final version = _tagValues(value)['v'];
        return version == null || version.toUpperCase() == 'DKIM1';
      })
      .toList(growable: false);
  if (records.isEmpty) {
    return MailFinding(
      id: 'dkim-$selector',
      title: 'DKIM · $selector',
      state: MailFindingState.warning,
      summary: 'No DKIM record was found for this selector.',
    );
  }
  if (records.length > 1) {
    return MailFinding(
      id: 'dkim-$selector',
      title: 'DKIM · $selector',
      state: MailFindingState.invalid,
      summary: 'Multiple DKIM records were returned for this selector.',
    );
  }
  final tags = _tagValues(records.single);
  final publicKey = tags['p'];
  final algorithm = tags['k'] ?? 'rsa';
  return MailFinding(
    id: 'dkim-$selector',
    title: 'DKIM · $selector',
    state: publicKey == null || publicKey.isEmpty
        ? MailFindingState.warning
        : MailFindingState.informational,
    summary: publicKey == null || publicKey.isEmpty
        ? 'The selector exists, but its key is absent or revoked.'
        : 'A DKIM public-key value is published for this selector.',
    facts: <MailFact>[
      MailFact(label: 'Algorithm', value: algorithm.toUpperCase()),
      MailFact(label: 'Selector', value: selector),
    ],
  );
}

/// Identifies an SPF TXT value by its version marker.
bool _isSpf(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'v=spf1' || normalized.startsWith('v=spf1 ');
}

/// Identifies a DMARC TXT value by its exact version marker.
bool _isDmarc(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=dmarc1;');

/// Identifies an MTA-STS TXT value by its exact version marker.
bool _isMtaSts(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=stsv1;');

/// Identifies a TLS-RPT TXT value by its exact version marker.
bool _isTlsRpt(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=tlsrptv1;');

Map<String, String> _tagValues(String record) {
  final result = <String, String>{};
  for (final part in record.split(';')) {
    final separator = part.indexOf('=');
    if (separator < 1) continue;
    result[part.substring(0, separator).trim().toLowerCase()] = part
        .substring(separator + 1)
        .trim();
  }
  return result;
}

/// Matches an MX hostname against an MTA-STS wildcard pattern.
bool _matchesMx(String exchange, String pattern) {
  final normalized = pattern.toLowerCase();
  if (!normalized.startsWith('*.')) return exchange == normalized;
  final suffix = normalized.substring(1);
  return exchange.endsWith(suffix) && exchange.length > suffix.length;
}
