import 'dart:convert';
import 'dart:io';

import 'package:akshi/features/monitors/domain/check_result.dart';

class RdapService {
  RdapService({HttpClient? client}) : _client = client ?? HttpClient();

  static const _bootstrapUri = 'https://data.iana.org/rdap/dns.json';
  final HttpClient _client;
  Map<String, String>? _services;

  Future<DomainCheckResult?> check(String hostname) async {
    final services = await _loadServices();
    final labels = hostname.split('.');
    if (labels.length < 2) return null;
    final base = services[labels.last];
    if (base == null) return null;

    for (var start = 0; start <= labels.length - 2; start++) {
      final candidate = labels.sublist(start).join('.');
      final response = await _getJson(
        Uri.parse(base).resolve('domain/${Uri.encodeComponent(candidate)}'),
        allowNotFound: true,
      );
      if (response == null) continue;
      final expiry = _findExpiry(response);
      if (expiry == null) return null;
      return DomainCheckResult(
        expiresAt: expiry,
        source: Uri.parse(base).host,
        registeredDomain: candidate,
      );
    }
    return null;
  }

  Future<Map<String, String>> _loadServices() async {
    final cached = _services;
    if (cached != null) return cached;
    final payload = await _getJson(Uri.parse(_bootstrapUri));
    if (payload == null) {
      throw const RdapException('RDAP bootstrap unavailable');
    }
    final result = <String, String>{};
    for (final service in payload['services'] as List<dynamic>? ?? const []) {
      final parts = service as List<dynamic>;
      if (parts.length < 2) continue;
      final urls = (parts[1] as List<dynamic>).cast<String>();
      if (urls.isEmpty) continue;
      final base = urls.first.endsWith('/') ? urls.first : '${urls.first}/';
      for (final tld in (parts[0] as List<dynamic>).cast<String>()) {
        result[tld.toLowerCase()] = base;
      }
    }
    return _services = result;
  }

  DateTime? _findExpiry(Map<String, dynamic> payload) {
    final events = payload['events'] as List<dynamic>? ?? const [];
    const priorities = <String>[
      'registrar expiration',
      'expiration',
      'registry expiry',
    ];
    for (final action in priorities) {
      for (final raw in events) {
        final event = raw as Map<String, dynamic>;
        if ((event['eventAction'] as String?)?.toLowerCase() != action) {
          continue;
        }
        final date = DateTime.tryParse(event['eventDate'] as String? ?? '');
        if (date != null) return date.toLocal();
      }
    }
    return null;
  }

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
