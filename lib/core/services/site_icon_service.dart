import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:image/image.dart' as image_codec;

class SiteIconService {
  SiteIconService({HttpClient? client}) : _client = client ?? HttpClient();

  static const _timeout = Duration(seconds: 6);
  static const _operationTimeout = Duration(seconds: 15);
  static const _maxHtmlBytes = 512 * 1024;
  static const _maxIconBytes = 1024 * 1024;

  final HttpClient _client;

  Future<SiteIcon?> discover(String hostname, int port) => _discover(
    hostname,
    port,
  ).timeout(_operationTimeout, onTimeout: () => null);

  Future<SiteIcon?> _discover(String hostname, int port) async {
    final origin = Uri(
      scheme: 'https',
      host: hostname,
      port: port == 443 ? null : port,
    );
    final candidates = <_IconCandidate>[];

    try {
      final page = await _fetch(origin.replace(path: '/'), _maxHtmlBytes);
      final contentType = page.contentType?.mimeType.toLowerCase();
      if (contentType == null || contentType.contains('html')) {
        candidates.addAll(_discoverCandidates(page.uri, page.bytes));
      }
    } on Object {
      // A page is optional; the conventional icon remains a valid fallback.
    }

    candidates.add(
      _IconCandidate(
        uri: origin.replace(path: '/favicon.ico'),
        declaredType: 'image/x-icon',
        size: 32,
        order: candidates.length,
      ),
    );
    candidates.sort(_compareCandidates);

    final attempted = <String>{};
    for (final candidate in candidates.take(6)) {
      if (!attempted.add(candidate.uri.toString())) continue;
      try {
        final response = await _fetch(candidate.uri, _maxIconBytes);
        final icon = _decode(response.bytes, source: response.uri);
        if (icon != null) return icon;
      } on Object {
        // Try the next declared icon without affecting monitor health.
      }
    }
    return null;
  }

  List<_IconCandidate> _discoverCandidates(Uri pageUri, Uint8List bytes) {
    final source = utf8.decode(bytes, allowMalformed: true);
    final document = html_parser.parse(source);
    final baseHref = document.querySelector('base[href]')?.attributes['href'];
    final baseUri = baseHref == null ? pageUri : pageUri.resolve(baseHref);
    final result = <_IconCandidate>[];
    var order = 0;
    for (final element in document.querySelectorAll('link[href]')) {
      final rel = (element.attributes['rel'] ?? '')
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (!rel.contains('icon') && !rel.contains('apple-touch-icon')) continue;
      final href = element.attributes['href'];
      if (href == null || href.trim().isEmpty) continue;
      final uri = baseUri.resolve(href.trim());
      if (uri.scheme != 'https') continue;
      result.add(
        _IconCandidate(
          uri: uri,
          declaredType: element.attributes['type'],
          size: _largestDeclaredSize(element.attributes['sizes']),
          order: order++,
        ),
      );
    }
    return result;
  }

  Future<_FetchedBytes> _fetch(Uri initial, int maximumBytes) async {
    var uri = initial;
    for (var redirect = 0; redirect <= 4; redirect++) {
      if (uri.scheme != 'https') {
        throw const FormatException('Only HTTPS resources are allowed');
      }
      final request = await _client.getUrl(uri).timeout(_timeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptHeader, 'image/*,text/html;q=0.8')
        ..headers.set(HttpHeaders.userAgentHeader, 'Akshi/1.0');
      final response = await request.close().timeout(_timeout);
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || redirect == 4) {
          throw const HttpException('Invalid redirect');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.timeout(_timeout)) {
        length += chunk.length;
        if (length > maximumBytes) {
          throw const HttpException('Resource is too large');
        }
        builder.add(chunk);
      }
      return _FetchedBytes(
        uri: uri,
        bytes: builder.takeBytes(),
        contentType: response.headers.contentType,
      );
    }
    throw const HttpException('Too many redirects');
  }

  SiteIcon? _decode(Uint8List bytes, {required Uri source}) {
    if (bytes.isEmpty) return null;
    final format = _detectFormat(bytes);
    if (format == null) return null;
    if (format == SiteIconFormat.svg) {
      return SiteIcon(
        format: format,
        bytes: bytes,
        sourceUrl: source.toString(),
        checkedAt: DateTime.now(),
      );
    }

    final decoded = image_codec.decodeImage(bytes, frame: 0);
    if (decoded == null) return null;
    return SiteIcon(
      format: SiteIconFormat.png,
      bytes: Uint8List.fromList(
        image_codec.encodePng(decoded, singleFrame: true),
      ),
      sourceUrl: source.toString(),
      checkedAt: DateTime.now(),
    );
  }
}

class _FetchedBytes {
  const _FetchedBytes({
    required this.uri,
    required this.bytes,
    required this.contentType,
  });

  final Uri uri;
  final Uint8List bytes;
  final ContentType? contentType;
}

class _IconCandidate {
  const _IconCandidate({
    required this.uri,
    required this.declaredType,
    required this.size,
    required this.order,
  });

  final Uri uri;
  final String? declaredType;
  final int? size;
  final int order;
}

int _compareCandidates(_IconCandidate left, _IconCandidate right) {
  final format = _formatPreference(right).compareTo(_formatPreference(left));
  if (format != 0) return format;
  final size = (right.size ?? 0).compareTo(left.size ?? 0);
  return size != 0 ? size : left.order.compareTo(right.order);
}

int _formatPreference(_IconCandidate candidate) {
  final hint = '${candidate.declaredType ?? ''} ${candidate.uri.path}'
      .toLowerCase();
  if (hint.contains('svg')) return 4;
  if (hint.contains('png')) return 3;
  if (hint.contains('icon') || hint.endsWith('.ico')) return 2;
  if (hint.contains('jpeg') || hint.contains('jpg')) return 1;
  return 0;
}

int? _largestDeclaredSize(String? value) {
  if (value == null || value.toLowerCase() == 'any') return null;
  var largest = 0;
  for (final token in value.split(RegExp(r'\s+'))) {
    final match = RegExp(r'^(\d+)[xX](\d+)$').firstMatch(token);
    if (match == null) continue;
    final width = int.tryParse(match.group(1)!);
    final height = int.tryParse(match.group(2)!);
    if (width != null && height != null) {
      largest = largest < width || largest < height
          ? width > height
                ? width
                : height
          : largest;
    }
  }
  return largest == 0 ? null : largest;
}

SiteIconFormat? _detectFormat(Uint8List bytes) {
  bool starts(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  if (starts(const <int>[0x89, 0x50, 0x4E, 0x47])) return SiteIconFormat.png;
  if (starts(const <int>[0xFF, 0xD8, 0xFF])) return SiteIconFormat.jpeg;
  if (starts(const <int>[0x00, 0x00, 0x01, 0x00])) return SiteIconFormat.ico;
  if (starts(const <int>[0x47, 0x49, 0x46, 0x38])) return SiteIconFormat.gif;
  if (starts(const <int>[0x42, 0x4D])) return SiteIconFormat.bmp;
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return SiteIconFormat.webp;
  }
  final prefix = utf8
      .decode(
        bytes.sublist(0, bytes.length < 512 ? bytes.length : 512),
        allowMalformed: true,
      )
      .trimLeft()
      .toLowerCase();
  if (prefix.contains('<svg')) {
    return SiteIconFormat.svg;
  }
  return null;
}
