import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:akshi/core/services/site_icon_service.dart';
import 'package:akshi/features/monitors/domain/site_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;

void main() {
  const decoder = SiteIconDecoder();
  final source = Uri.parse('https://example.com/favicon');

  test(
    'operation deadline cancels the active response before returning',
    () async {
      final responseListened = Completer<void>();
      var wasCancelled = false;
      final body = StreamController<List<int>>(
        onListen: responseListened.complete,
        onCancel: () {
          wasCancelled = true;
        },
      );
      addTearDown(() {
        if (!body.isClosed) {
          unawaited(body.close());
        }
      });
      final response = _FakeHttpClientResponse(body.stream);
      final service = SiteIconService(
        client: _FakeHttpClient(response),
        requestTimeout: const Duration(seconds: 5),
        operationTimeout: const Duration(seconds: 1),
      );

      final discovery = service.discover('example.com', 443);
      await responseListened.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError(
          'The fake response was not subscribed before the operation deadline.',
        ),
      );
      final icon = await discovery;

      expect(icon, isNull);
      expect(wasCancelled, isTrue);
      await body.close();
    },
  );

  group('SiteIconDecoder SVG', () {
    test('preserves accepted SVG bytes exactly', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="40" height="24" viewBox="0 0 40 24">
  <defs>
    <linearGradient id="paint">
      <stop offset="0" stop-color="#312e81"/>
      <stop offset="1" stop-color="#7c3aed"/>
    </linearGradient>
  </defs>
  <rect width="40" height="24" rx="3" fill="url(#paint)"/>
</svg>''';
      final bytes = Uint8List.fromList(utf8.encode(svg));

      final icon = decoder.decode(bytes, source: source);

      expect(icon, isNotNull);
      expect(icon!.format, SiteIconFormat.svg);
      expect(icon.bytes, orderedEquals(bytes));
      expect(icon.bytes.length, bytes.length);
    });

    test('rejects active or externally referenced content', () {
      final unsafeDocuments = <String>[
        _svg('<script>doSomething()</script>'),
        _svg('<style>@import url("https://example.com/icon.css");</style>'),
        _svg('<a href="https://example.com"><path d="M0 0"/></a>'),
        _svg('<image href="data:image/png;base64,AA=="/>'),
        '<!DOCTYPE svg>${_svg('<path d="M0 0"/>')}',
      ];

      for (final document in unsafeDocuments) {
        final bytes = Uint8List.fromList(utf8.encode(document));
        expect(decoder.decode(bytes, source: source), isNull, reason: document);
      }
    });

    test('rejects excessive document complexity', () {
      final nestedGroups = List<String>.filled(32, '<g>').join();
      final closingGroups = List<String>.filled(32, '</g>').join();
      final tooDeep = _svg('$nestedGroups<path d="M0 0"/>$closingGroups');
      final tooManyElements = _svg(
        List<String>.generate(512, (index) => '<path d="M$index 0"/>').join(),
      );
      final excessivePath = _svg(
        '<path d="${List<String>.filled(14000, 'M0 0 ').join()}"/>',
      );
      final excessiveBytes = _svg(
        '<!--${List<String>.filled(270 * 1024, 'x').join()}-->',
      );

      for (final document in <String>[
        tooDeep,
        tooManyElements,
        excessivePath,
        excessiveBytes,
      ]) {
        expect(
          decoder.decode(
            Uint8List.fromList(utf8.encode(document)),
            source: source,
          ),
          isNull,
        );
      }
    });

    test('rejects malformed SVG', () {
      final bytes = Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"><path>'),
      );

      expect(decoder.decode(bytes, source: source), isNull);
    });
  });

  group('SiteIconDecoder raster images', () {
    test('normalizes to PNG without changing dimensions', () {
      final original = image_codec.Image(width: 40, height: 24);
      final encoded = Uint8List.fromList(image_codec.encodePng(original));

      final icon = decoder.decode(encoded, source: source);

      expect(icon, isNotNull);
      expect(icon!.format, SiteIconFormat.png);
      final normalized = image_codec.decodeImage(icon.bytes);
      expect(normalized, isNotNull);
      expect(normalized!.width, 40);
      expect(normalized.height, 24);
    });

    test('rejects a dimension above the boundary before full decode', () {
      final oversized = image_codec.Image(width: 2049, height: 1);
      final encoded = Uint8List.fromList(image_codec.encodePng(oversized));

      expect(decoder.decode(encoded, source: source), isNull);
    });

    test('rejects an excessive decoded pixel count', () {
      final oversized = image_codec.Image(width: 1025, height: 1025);
      final encoded = Uint8List.fromList(image_codec.encodePng(oversized));

      expect(decoder.decode(encoded, source: source), isNull);
    });

    test('rejects malformed encoded data without throwing', () {
      final corrupted = Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
      ]);

      expect(decoder.decode(corrupted, source: source), isNull);
    });
  });
}

String _svg(String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg">$body</svg>';

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.response);

  final HttpClientResponse response;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(response);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.response);

  final HttpClientResponse response;

  @override
  bool followRedirects = true;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.body);

  final Stream<List<int>> body;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  bool get isRedirect => false;

  @override
  int get contentLength => -1;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
