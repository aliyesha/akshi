import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/bounded_response_reader.dart';
import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:image/image.dart' as image_codec;
import 'package:xml/xml.dart';

/// Discovers, validates, and stores a stable HTTPS site icon candidate.
///
/// HTML declarations are preferred, `/favicon.ico` is the fallback, and every
/// candidate is bounded by size, timeout, redirect, and decode checks.
class SiteIconService {
  SiteIconService({
    HttpClient? client,
    Duration requestTimeout = _defaultRequestTimeout,
    Duration operationTimeout = _defaultOperationTimeout,
  }) : _client = client ?? HttpClient(),
       _requestTimeout = requestTimeout,
       _operationTimeout = operationTimeout {
    if (requestTimeout.inMicroseconds <= 0) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive',
      );
    }
    if (operationTimeout.inMicroseconds <= 0) {
      throw ArgumentError.value(
        operationTimeout,
        'operationTimeout',
        'Must be positive',
      );
    }
  }

  static const _defaultRequestTimeout = Duration(seconds: 6);
  static const _defaultOperationTimeout = Duration(seconds: 15);
  static const _maxHtmlBytes = 512 * 1024;
  static const _maxIconBytes = 1024 * 1024;

  final HttpClient _client;
  final Duration _requestTimeout;
  final Duration _operationTimeout;
  final _iconDecoder = const SiteIconDecoder();

  /// Performs best-effort icon discovery without affecting monitor health.
  ///
  /// A null result leaves the neutral placeholder in place.
  Future<SiteIcon?> discover(String hostname, int port) async {
    appLogger.info(
      'service.site_icon.discover.started',
      data: <String, Object?>{'hostname': hostname, 'port': port},
    );
    final elapsed = Stopwatch()..start();
    try {
      return await _discover(hostname, port, elapsed);
    } finally {
      elapsed.stop();
    }
  }

  /// Tries ranked candidates and returns the first decodable image.
  Future<SiteIcon?> _discover(
    String hostname,
    int port,
    Stopwatch elapsed,
  ) async {
    final origin = Uri(
      scheme: 'https',
      host: hostname,
      port: port == 443 ? null : port,
    );
    final candidates = <_IconCandidate>[];

    try {
      final page = await _fetch(
        origin.replace(path: '/'),
        _maxHtmlBytes,
        elapsed,
      );
      final contentType = page.contentType?.mimeType.toLowerCase();
      if (contentType == null || contentType.contains('html')) {
        candidates.addAll(_discoverCandidates(page.uri, page.bytes));
      }
    } catch (error, stackTrace) {
      appLogger.error(
        'service.site_icon.page.failed',
        error,
        stackTrace,
        data: <String, Object?>{'hostname': hostname, 'port': port},
      );
      // A page is optional; the conventional icon remains a valid fallback.
    }
    if (_expired(elapsed)) return null;

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
      if (_expired(elapsed)) break;
      try {
        final response = await _fetch(candidate.uri, _maxIconBytes, elapsed);
        final icon = _decode(response.bytes, source: response.uri);
        if (icon != null) return icon;
      } catch (error, stackTrace) {
        appLogger.error(
          'service.site_icon.candidate.failed',
          error,
          stackTrace,
          data: <String, Object?>{'hostname': hostname, 'port': port},
        );
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

  /// Fetches one HTTPS resource with bounded redirects and response bytes.
  Future<_FetchedBytes> _fetch(
    Uri initial,
    int maximumBytes,
    Stopwatch elapsed,
  ) async {
    var uri = initial;
    for (var redirect = 0; redirect <= 4; redirect++) {
      if (uri.scheme != 'https') {
        throw const FormatException('Only HTTPS resources are allowed');
      }
      final request = await _client.getUrl(uri).timeout(_remaining(elapsed));
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptHeader, 'image/*,text/html;q=0.8')
        ..headers.set(HttpHeaders.userAgentHeader, 'Akshi/1.0');
      final response = await request.close().timeout(_remaining(elapsed));
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await cancelResponseBody(response);
        if (location == null || redirect == 4) {
          throw const HttpException('Invalid redirect');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await cancelResponseBody(response);
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = await readBoundedResponseBody(
        response,
        maximumBytes: maximumBytes,
        timeout: _remaining(elapsed),
        contentLength: expectedResponseBodyLength(response),
      );
      return _FetchedBytes(
        uri: uri,
        bytes: bytes,
        contentType: response.headers.contentType,
      );
    }
    throw const HttpException('Too many redirects');
  }

  bool _expired(Stopwatch elapsed) =>
      _operationTimeout.compareTo(elapsed.elapsed) <= 0;

  Duration _remaining(Stopwatch elapsed) {
    final remaining = _operationTimeout - elapsed.elapsed;
    if (remaining.inMicroseconds <= 0) {
      throw TimeoutException(
        'Site icon discovery timed out.',
        _operationTimeout,
      );
    }
    return remaining.compareTo(_requestTimeout) < 0
        ? remaining
        : _requestTimeout;
  }

  SiteIcon? _decode(Uint8List bytes, {required Uri source}) =>
      _iconDecoder.decode(bytes, source: source);
}

/// Validates and normalizes untrusted site-icon bytes before persistence.
class SiteIconDecoder {
  const SiteIconDecoder();

  static const _maxRasterEncodedBytes = 1024 * 1024;
  static const _maxRasterDimension = 2048;
  static const _maxRasterPixels = 1024 * 1024;
  static const _maxSvgBytes = 256 * 1024;
  static const _maxSvgElements = 512;
  static const _maxSvgAttributes = 2048;
  static const _maxSvgDepth = 32;
  static const _maxSvgPathDataCharacters = 64 * 1024;

  /// Returns accepted SVG bytes unchanged or a single-frame PNG.
  ///
  /// Raster normalization preserves width and height without resampling. Invalid
  /// input or any exceeded boundary returns null instead of altering the image.
  SiteIcon? decode(Uint8List bytes, {required Uri source}) {
    if (bytes.isEmpty) return null;
    final format = _detectFormat(bytes);
    if (format == null) return null;

    if (format == SiteIconFormat.svg) {
      if (!_isSafeSvg(bytes)) return null;
      return SiteIcon(
        format: SiteIconFormat.svg,
        bytes: bytes,
        sourceUrl: source.toString(),
        checkedAt: DateTime.now(),
      );
    }
    return _decodeRaster(bytes, source);
  }

  SiteIcon? _decodeRaster(Uint8List bytes, Uri source) {
    if (bytes.length > _maxRasterEncodedBytes) return null;

    try {
      // Read dimensions before allocating a full RGBA pixel buffer.
      final decoder = image_codec.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (decoder == null ||
          info == null ||
          !_withinRasterBounds(info.width, info.height)) {
        return null;
      }
      final decoded = decoder.decodeFrame(0);
      if (decoded == null ||
          decoded.width != info.width ||
          decoded.height != info.height ||
          !_withinRasterBounds(decoded.width, decoded.height)) {
        return null;
      }
      final png = Uint8List.fromList(
        image_codec.encodePng(decoded, singleFrame: true),
      );
      if (png.length > _maxRasterEncodedBytes) return null;
      return SiteIcon(
        format: SiteIconFormat.png,
        bytes: png,
        sourceUrl: source.toString(),
        checkedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  bool _withinRasterBounds(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= _maxRasterDimension &&
      height <= _maxRasterDimension &&
      width * height <= _maxRasterPixels;

  bool _isSafeSvg(Uint8List bytes) {
    if (bytes.length > _maxSvgBytes) return false;

    try {
      final source = utf8.decode(bytes);
      if (source.toLowerCase().contains('<!doctype')) return false;
      final root = XmlDocument.parse(source).rootElement;
      if (root.name.local.toLowerCase() != 'svg') return false;
      return _SvgComplexity().accepts(root);
    } catch (_) {
      return false;
    }
  }
}

class _SvgComplexity {
  static const _forbiddenElements = <String>{
    'animate',
    'animatemotion',
    'animatetransform',
    'filter',
    'foreignobject',
    'image',
    'script',
    'set',
    'style',
  };
  static final _urlReference = RegExp(
    r'url\s*\(\s*([^)]*?)\s*\)',
    caseSensitive: false,
  );

  var _elements = 0;
  var _attributes = 0;
  var _pathDataCharacters = 0;

  bool accepts(XmlElement root) => _visit(root, 1);

  bool _visit(XmlElement element, int depth) {
    if (depth > SiteIconDecoder._maxSvgDepth ||
        ++_elements > SiteIconDecoder._maxSvgElements) {
      return false;
    }
    final elementName = element.name.local.toLowerCase();
    if (_forbiddenElements.contains(elementName)) return false;

    _attributes += element.attributes.length;
    if (_attributes > SiteIconDecoder._maxSvgAttributes) return false;
    for (final attribute in element.attributes) {
      final name = attribute.name.local.toLowerCase();
      final value = attribute.value.trim();
      if (name == 'd' || name == 'points') {
        _pathDataCharacters += value.length;
        if (_pathDataCharacters > SiteIconDecoder._maxSvgPathDataCharacters) {
          return false;
        }
      }
      if (_hasUnsafeReference(name, value)) return false;
    }

    for (final child in element.childElements) {
      if (!_visit(child, depth + 1)) return false;
    }
    return true;
  }

  bool _hasUnsafeReference(String name, String value) {
    final lowerValue = value.toLowerCase();
    if (name.startsWith('on') || lowerValue.contains('@import')) return true;
    if (name == 'href' && !value.startsWith('#')) return true;

    for (final match in _urlReference.allMatches(value)) {
      var target = match.group(1)!.trim();
      if (target.length >= 2 &&
          ((target.startsWith("'") && target.endsWith("'")) ||
              (target.startsWith('"') && target.endsWith('"')))) {
        target = target.substring(1, target.length - 1).trim();
      }
      if (!target.startsWith('#')) return true;
    }
    return false;
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
