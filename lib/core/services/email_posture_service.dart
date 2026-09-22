import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/dns_snapshot.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';

/// Evaluates practical email DNS and MTA-STS posture from one DNS snapshot.
///
/// This service reports facts and configuration gaps; it deliberately avoids
/// opaque third-party scores that could become stale or misleading.
class EmailPostureService {
  EmailPostureService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Builds ordered findings for the enabled send/receive capabilities.
  ///
  /// All DNS values come from [snapshot], so the email and DNS screens describe
  /// the same observation instead of racing separate lookups.
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
      _queryFinding(
        receives ? snapshot.query(domain, DnsRecordType.mx) : null,
        id: 'mx',
        title: 'Mail exchange',
        build: () => _mxFinding(mx, receives: receives),
      ),
      _queryFinding(
        sends ? snapshot.query(domain, DnsRecordType.txt) : null,
        id: 'spf',
        title: 'SPF',
        build: () => _spfFinding(rootTxt, sends: sends),
      ),
      _queryFinding(
        sends ? snapshot.query('_dmarc.$domain', DnsRecordType.txt) : null,
        id: 'dmarc',
        title: 'DMARC',
        build: () => _dmarcFinding(dmarc, sends: sends),
      ),
      await _mtaStsFromSnapshot(snapshot, domain, mtaSts, receives, mx),
      _queryFinding(
        receives
            ? snapshot.query('_smtp._tls.$domain', DnsRecordType.txt)
            : null,
        id: 'tls-rpt',
        title: 'TLS reporting',
        build: () => _tlsRptFinding(tlsRpt, receives: receives),
      ),
    ];
    for (final selector in sends ? dkimSelectors : const <String>[]) {
      final name = '$selector._domainkey.$domain';
      final values = _txt(snapshot, name);
      findings.add(
        _queryFinding(
          snapshot.query(name, DnsRecordType.txt),
          id: 'dkim-$selector',
          title: 'DKIM · $selector',
          build: () => _dkimFinding(selector, values),
        ),
      );
    }
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
    bool receives,
    List<DnsRecord> mx,
  ) async {
    if (!receives) {
      return _mtaStsFinding(domain, records, receives: false, mx: mx);
    }
    final query = snapshot.query('_mta-sts.$domain', DnsRecordType.txt);
    if (query?.state == DnsQueryState.failed) {
      return _unavailableFinding('mta-sts', 'MTA-STS', query!);
    }
    return _mtaStsFinding(domain, records, receives: true, mx: mx);
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
  /// MX coverage is checked against policy patterns; `none` remains
  /// informational rather than an enforcement failure.
  Future<MailFinding> _mtaStsFinding(
    String domain,
    List<String> records, {
    required bool receives,
    required List<DnsRecord> mx,
  }) async {
    if (!receives) {
      return const MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.informational,
        summary:
            'Not checked because this domain is not marked for receiving mail.',
      );
    }
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
    try {
      final policy = await _fetchText(
        Uri.https('mta-sts.$domain', '/.well-known/mta-sts.txt'),
      );
      final values = _lineValues(policy);
      final mode = values['mode'];
      final maxAge = int.tryParse(values['max_age'] ?? '');
      final versionValid = values['version']?.toUpperCase() == 'STSV1';
      final modeValid = const <String>{
        'none',
        'testing',
        'enforce',
      }.contains(mode);
      final mxPatterns = policy
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trimLeft().toLowerCase().startsWith('mx:'))
          .map((line) => line.split(':').skip(1).join(':').trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (!versionValid ||
          !modeValid ||
          maxAge == null ||
          (mode != 'none' && mxPatterns.isEmpty)) {
        return const MailFinding(
          id: 'mta-sts',
          title: 'MTA-STS',
          state: MailFindingState.invalid,
          summary: 'The published HTTPS policy is incomplete or invalid.',
        );
      }
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
      return MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: unmatched.isEmpty
            ? MailFindingState.healthy
            : MailFindingState.warning,
        summary: unmatched.isEmpty
            ? 'DNS and HTTPS policy are published and cover the current MX hosts.'
            : 'The HTTPS policy does not cover every current MX host.',
        facts: <MailFact>[
          MailFact(label: 'Policy id', value: id),
          MailFact(label: 'Mode', value: mode!),
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
        state: MailFindingState.warning,
        summary: 'The DNS record exists, but the HTTPS policy could not be verified.',
        facts: <MailFact>[MailFact(label: 'Policy id', value: id)],
      );
    }
  }

  /// Fetches a bounded text policy with short timeouts and no redirects.
  ///
  /// The size limit prevents a malformed endpoint from consuming unbounded
  /// memory during a foreground check.
  Future<String> _fetchText(Uri uri) async {
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 10));
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'text/plain')
      ..headers.set(HttpHeaders.userAgentHeader, 'Akshi/1.0');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 128 * 1024) {
        throw const FormatException('MTA-STS policy is too large');
      }
    }
    return utf8.decode(bytes);
  }
}

/// Returns TXT values for an owner while preserving duplicate records.
List<String> _txt(DnsSnapshot snapshot, String name) => snapshot
    .records(name, DnsRecordType.txt)
    .map((record) => record.value)
    .toList(growable: false);

/// Evaluates MX presence and records published exchanges as facts.
MailFinding _mxFinding(List<DnsRecord> records, {required bool receives}) {
  if (!receives) {
    return const MailFinding(
      id: 'mx',
      title: 'Mail exchange',
      state: MailFindingState.informational,
      summary: 'Receiving checks are disabled for this domain.',
    );
  }
  if (records.isEmpty) {
    return const MailFinding(
      id: 'mx',
      title: 'Mail exchange',
      state: MailFindingState.warning,
      summary: 'No MX records were found.',
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
        '${records.length} receiving host${records.length == 1 ? '' : 's'} published.',
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

/// Evaluates whether exactly one usable SPF policy is published.
MailFinding _spfFinding(List<String> values, {required bool sends}) {
  if (!sends) {
    return const MailFinding(
      id: 'spf',
      title: 'SPF',
      state: MailFindingState.informational,
      summary: 'Sending checks are disabled for this domain.',
    );
  }
  final records = values.where(_isSpf).toList(growable: false);
  if (records.isEmpty) {
    return const MailFinding(
      id: 'spf',
      title: 'SPF',
      state: MailFindingState.warning,
      summary: 'No SPF policy is published.',
    );
  }
  if (records.length > 1) {
    return const MailFinding(
      id: 'spf',
      title: 'SPF',
      state: MailFindingState.invalid,
      summary: 'Multiple SPF records are published; SPF permits only one.',
    );
  }
  final record = records.single;
  final lookupTerms = record
      .split(RegExp(r'\s+'))
      .where(
        (term) => RegExp(
          r'^[+?~-]?(include:|a(?::|$)|mx(?::|$)|ptr(?::|$)|exists:|redirect=)',
          caseSensitive: false,
        ).hasMatch(term),
      )
      .length;
  return MailFinding(
    id: 'spf',
    title: 'SPF',
    state: lookupTerms > 10
        ? MailFindingState.invalid
        : MailFindingState.healthy,
    summary: lookupTerms > 10
        ? 'The policy declares more than the 10 permitted DNS-lookup terms.'
        : 'One SPF policy is published.',
    facts: <MailFact>[
      MailFact(label: 'Policy', value: record),
      MailFact(label: 'Declared lookup terms', value: '$lookupTerms of 10'),
    ],
  );
}

/// Evaluates DMARC uniqueness and exposes policy tags as readable facts.
MailFinding _dmarcFinding(List<String> values, {required bool sends}) {
  if (!sends) {
    return const MailFinding(
      id: 'dmarc',
      title: 'DMARC',
      state: MailFindingState.informational,
      summary: 'Sending checks are disabled for this domain.',
    );
  }
  final records = values.where(_isDmarc).toList(growable: false);
  if (records.isEmpty) {
    return const MailFinding(
      id: 'dmarc',
      title: 'DMARC',
      state: MailFindingState.warning,
      summary: 'No DMARC policy is published.',
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
      summary: 'The DMARC policy is missing a valid p tag.',
    );
  }
  return MailFinding(
    id: 'dmarc',
    title: 'DMARC',
    state: MailFindingState.healthy,
    summary: 'A valid DMARC policy is published.',
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
MailFinding _tlsRptFinding(List<String> values, {required bool receives}) {
  if (!receives) {
    return const MailFinding(
      id: 'tls-rpt',
      title: 'TLS reporting',
      state: MailFindingState.informational,
      summary: 'Receiving checks are disabled for this domain.',
    );
  }
  final records = values.where(_isTlsRpt).toList(growable: false);
  if (records.isEmpty) {
    return const MailFinding(
      id: 'tls-rpt',
      title: 'TLS reporting',
      state: MailFindingState.informational,
      summary: 'No SMTP TLS reporting destination is published.',
    );
  }
  if (records.length > 1) {
    return const MailFinding(
      id: 'tls-rpt',
      title: 'TLS reporting',
      state: MailFindingState.invalid,
      summary: 'Multiple SMTP TLS reporting records are published.',
    );
  }
  final destination = _tagValues(records.single)['rua'];
  return MailFinding(
    id: 'tls-rpt',
    title: 'TLS reporting',
    state: destination == null
        ? MailFindingState.invalid
        : MailFindingState.healthy,
    summary: destination == null
        ? 'The TLS reporting record has no rua destination.'
        : 'An SMTP TLS reporting destination is published.',
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
      summary: 'No key was found for this user-supplied selector.',
    );
  }
  if (records.length > 1) {
    return MailFinding(
      id: 'dkim-$selector',
      title: 'DKIM · $selector',
      state: MailFindingState.invalid,
      summary: 'Multiple keys were returned for this selector.',
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
        : MailFindingState.healthy,
    summary: publicKey == null || publicKey.isEmpty
        ? 'The selector exists, but its key is absent or revoked.'
        : 'A public key is published for this selector.',
    facts: <MailFact>[
      MailFact(label: 'Algorithm', value: algorithm.toUpperCase()),
      MailFact(label: 'Selector', value: selector),
    ],
  );
}

/// Identifies an SPF TXT value by its version marker.
bool _isSpf(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=spf1 ');

/// Identifies a DMARC TXT value by its version marker.
bool _isDmarc(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=dmarc1');

/// Identifies an MTA-STS TXT value by its version marker.
bool _isMtaSts(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=stsv1');

/// Identifies a TLS-RPT TXT value by its version marker.
bool _isTlsRpt(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=tlsrptv1');

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

Map<String, String> _lineValues(String policy) {
  final result = <String, String>{};
  for (final line in policy.split(RegExp(r'\r?\n'))) {
    final separator = line.indexOf(':');
    if (separator < 1) continue;
    result[line.substring(0, separator).trim().toLowerCase()] = line
        .substring(separator + 1)
        .trim()
        .toLowerCase();
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
