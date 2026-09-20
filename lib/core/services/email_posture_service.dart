import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/services/system_dns_service.dart';
import 'package:akshi/features/monitors/domain/email_posture.dart';

class EmailPostureService {
  EmailPostureService({SystemDnsService? dns, HttpClient? client})
      : _dns = dns ?? const SystemDnsService(),
        _client = client ?? HttpClient();

  final SystemDnsService _dns;
  final HttpClient _client;

  Future<EmailPosture> check(
    String domain, {
    required bool sends,
    required bool receives,
    required List<String> dkimSelectors,
  }) async {
    final mx = receives ? await _dns.mx(domain) : const <MxRecord>[];
    final rootTxt = sends ? await _dns.txt(domain) : const <String>[];
    final dmarc = sends
        ? await _dns.txt('_dmarc.$domain')
        : const <String>[];
    final mtaSts = receives
        ? await _dns.txt('_mta-sts.$domain')
        : const <String>[];
    final tlsRpt = receives
        ? await _dns.txt('_smtp._tls.$domain')
        : const <String>[];

    final findings = <MailFinding>[
      _mxFinding(mx, receives: receives),
      _spfFinding(rootTxt, sends: sends),
      _dmarcFinding(dmarc, sends: sends),
      await _mtaStsFinding(domain, mtaSts, receives: receives, mx: mx),
      _tlsRptFinding(tlsRpt, receives: receives),
    ];
    for (final selector in dkimSelectors) {
      final values = await _dns.txt('$selector._domainkey.$domain');
      findings.add(_dkimFinding(selector, values));
    }
    return EmailPosture(checkedAt: DateTime.now(), findings: findings);
  }

  Future<MailFinding> _mtaStsFinding(
    String domain,
    List<String> records, {
    required bool receives,
    required List<MxRecord> mx,
  }) async {
    if (!receives) {
      return const MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.informational,
        summary: 'Not checked because this domain is not marked for receiving mail.',
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
      final modeValid = const <String>{'none', 'testing', 'enforce'}.contains(mode);
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
          .where((record) => record.exchange != '.')
          .map((record) => record.exchange)
          .toList(growable: false);
      final unmatched = mode == 'none'
          ? const <String>[]
          : currentExchanges
          .where((exchange) => !mxPatterns.any((pattern) => _matchesMx(exchange, pattern)))
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
    } on Object {
      return MailFinding(
        id: 'mta-sts',
        title: 'MTA-STS',
        state: MailFindingState.warning,
        summary: 'The DNS record exists, but the HTTPS policy could not be verified.',
        facts: <MailFact>[MailFact(label: 'Policy id', value: id)],
      );
    }
  }

  Future<String> _fetchText(Uri uri) async {
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
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

MailFinding _mxFinding(List<MxRecord> records, {required bool receives}) {
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
  if (records.any((record) => record.preference == 0 && record.exchange == '.')) {
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
    summary: '${records.length} receiving host${records.length == 1 ? '' : 's'} published.',
    facts: records
        .map(
          (record) => MailFact(
            label: 'Priority ${record.preference}',
            value: record.exchange,
          ),
        )
        .toList(growable: false),
  );
}

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
    state: lookupTerms > 10 ? MailFindingState.invalid : MailFindingState.healthy,
    summary: lookupTerms > 10
        ? 'The policy declares more than the 10 permitted DNS-lookup terms.'
        : 'One SPF policy is published.',
    facts: <MailFact>[
      MailFact(label: 'Policy', value: record),
      MailFact(label: 'Declared lookup terms', value: '$lookupTerms of 10'),
    ],
  );
}

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
      if (destination != null) MailFact(label: 'Reports to', value: destination),
    ],
  );
}

MailFinding _dkimFinding(String selector, List<String> values) {
  final records = values.where((value) {
    final version = _tagValues(value)['v'];
    return version == null || version.toUpperCase() == 'DKIM1';
  }).toList(growable: false);
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

bool _isSpf(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=spf1 ');
bool _isDmarc(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=dmarc1');
bool _isMtaSts(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=stsv1');
bool _isTlsRpt(String value) =>
    value.trimLeft().toLowerCase().startsWith('v=tlsrptv1');

Map<String, String> _tagValues(String record) {
  final result = <String, String>{};
  for (final part in record.split(';')) {
    final separator = part.indexOf('=');
    if (separator < 1) continue;
    result[part.substring(0, separator).trim().toLowerCase()] =
        part.substring(separator + 1).trim();
  }
  return result;
}

Map<String, String> _lineValues(String policy) {
  final result = <String, String>{};
  for (final line in policy.split(RegExp(r'\r?\n'))) {
    final separator = line.indexOf(':');
    if (separator < 1) continue;
    result[line.substring(0, separator).trim().toLowerCase()] =
        line.substring(separator + 1).trim().toLowerCase();
  }
  return result;
}

bool _matchesMx(String exchange, String pattern) {
  final normalized = pattern.toLowerCase();
  if (!normalized.startsWith('*.')) return exchange == normalized;
  final suffix = normalized.substring(1);
  return exchange.endsWith(suffix) && exchange.length > suffix.length;
}
