import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akshi/core/services/rdap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bounded RDAP response reader', () {
    const reader = RdapResponseReader(maxBytes: 64);

    test('uses a two MiB production boundary', () {
      expect(RdapResponseReader.defaultMaxBytes, 2 * 1024 * 1024);
    });

    test('accepts RDAP and generic JSON media types', () async {
      final bytes = utf8.encode('{"services": []}');
      for (final contentType in <String>[
        'application/rdap+json',
        'application/json; charset=utf-8',
      ]) {
        final result = await reader.read(
          Stream<List<int>>.value(bytes),
          contentType: contentType,
          contentLength: bytes.length,
        );

        expect(result['services'], isEmpty);
      }
    });

    test('rejects a missing or unsupported media type', () async {
      for (final contentType in <String?>[null, 'text/html']) {
        await expectLater(
          reader.read(
            Stream<List<int>>.value(utf8.encode('{}')),
            contentType: contentType,
            contentLength: 2,
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects and cancels an oversized declared body', () async {
      const smallReader = RdapResponseReader(maxBytes: 4);
      var wasCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          wasCancelled = true;
        },
      );
      addTearDown(() => unawaited(body.close()));

      await expectLater(
        smallReader.read(
          body.stream,
          contentType: 'application/json',
          contentLength: 5,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(wasCancelled, isTrue);
    });

    test(
      'rejects an oversized streamed body without a declared length',
      () async {
        const smallReader = RdapResponseReader(maxBytes: 8);

        await expectLater(
          smallReader.read(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode('{"value":'),
              utf8.encode('true}'),
            ]),
            contentType: 'application/rdap+json',
            contentLength: null,
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('rejects malformed UTF-8, malformed JSON, and JSON arrays', () async {
      final cases = <List<int>>[
        <int>[0xC3, 0x28],
        utf8.encode('{'),
        utf8.encode('[]'),
      ];
      for (final bytes in cases) {
        await expectLater(
          reader.read(
            Stream<List<int>>.value(bytes),
            contentType: 'application/json',
            contentLength: bytes.length,
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects a body shorter than its declared length', () async {
      final bytes = utf8.encode('{}');

      await expectLater(
        reader.read(
          Stream<List<int>>.value(bytes),
          contentType: 'application/json',
          contentLength: bytes.length + 1,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('applies one timeout to the complete response body', () async {
      var wasCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          wasCancelled = true;
        },
      );
      addTearDown(() => unawaited(body.close()));
      const impatientReader = RdapResponseReader(
        maxBytes: 64,
        timeout: Duration(milliseconds: 20),
      );

      await expectLater(
        impatientReader.read(
          body.stream,
          contentType: 'application/json',
          contentLength: null,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(wasCancelled, isTrue);
    });
  });

  test('one operation deadline aborts a stalled candidate lookup', () async {
    final client = _RoutingHttpClient(
      Stream<List<int>>.value(
        utf8.encode('{"services": [[ ["test"], ["https://rdap.example/"] ]]}'),
      ),
      hangDomainResponse: true,
    );
    final service = RdapService(
      client,
      operationTimeout: const Duration(milliseconds: 40),
    );

    await expectLater(
      service.check('deep.name.test'),
      throwsA(isA<TimeoutException>()),
    );

    expect(RdapService.defaultOperationTimeout, const Duration(seconds: 30));
    expect(client.domainRequests, 1);
    expect(client.lastDomainRequest?.wasAborted, isTrue);
  });

  test('concurrent checks share one IANA bootstrap download', () async {
    final bootstrapBody = StreamController<List<int>>();
    addTearDown(() {
      if (!bootstrapBody.isClosed) unawaited(bootstrapBody.close());
    });
    final client = _RoutingHttpClient(bootstrapBody.stream);
    final service = RdapService(client);

    final first = service.check('first.test');
    final second = service.check('second.test');

    expect(client.bootstrapRequests, 1);
    bootstrapBody.add(
      utf8.encode('''
        {"services": [[ ["test"], ["https://rdap.example/"] ]]}
      '''),
    );
    await bootstrapBody.close();

    expect(await Future.wait(<Future<Object?>>[first, second]), <Object?>[
      null,
      null,
    ]);
    expect(client.bootstrapRequests, 1);
    expect(client.domainRequests, 2);

    expect(await service.check('third.test'), isNull);
    expect(client.bootstrapRequests, 1);
    expect(client.domainRequests, 3);
  });

  test('parses public registration facts without inventing ownership', () {
    final result = parseRdapDomain(
      <String, dynamic>{
        'objectClassName': 'domain',
        'ldhName': 'example.com',
        'events': <Object?>[
          <String, Object?>{
            'eventAction': 'registration',
            'eventDate': '2026-02-01T09:00:00Z',
          },
          <String, Object?>{
            'eventAction': 'last changed',
            'eventDate': '2026-06-14T10:30:00Z',
          },
          <String, Object?>{
            'eventAction': 'expiration',
            'eventDate': '2026-08-31T23:59:59Z',
          },
        ],
        'entities': <Object?>[
          <String, Object?>{
            'roles': <String>['registrar'],
            'vcardArray': <Object?>[
              'vcard',
              <Object?>[
                <Object?>[
                  'fn',
                  <String, Object?>{},
                  'text',
                  'Example Registrar',
                ],
              ],
            ],
          },
          <String, Object?>{
            'roles': <String>['registrant'],
            'vcardArray': <Object?>[
              'vcard',
              <Object?>[
                <Object?>['org', <String, Object?>{}, 'text', 'Example Studio'],
              ],
            ],
          },
        ],
        'nameservers': <Object?>[
          <String, Object?>{'ldhName': 'NS2.EXAMPLE.NET.'},
          <String, Object?>{'unicodeName': 'ns1.example.net'},
          <String, Object?>{'ldhName': 'ns1.example.net'},
        ],
      },
      source: 'rdap.example',
      registeredDomain: 'example.com',
    );

    expect(result.expiresAt?.toUtc(), DateTime.utc(2026, 8, 31, 23, 59, 59));
    expect(result.registeredAt?.toUtc(), DateTime.utc(2026, 2, 1, 9));
    expect(result.updatedAt?.toUtc(), DateTime.utc(2026, 6, 14, 10, 30));
    expect(result.registrar, 'Example Registrar');
    expect(result.publicRegistrant, 'Example Studio');
    expect(result.nameServers, <String>['ns1.example.net', 'ns2.example.net']);
  });

  test('uses declared RDAP event priority instead of server order', () {
    final result = parseRdapDomain(
      <String, dynamic>{
        'objectClassName': 'domain',
        'ldhName': 'example.com',
        'events': <Object?>[
          <String, Object?>{
            'eventAction': 'expiration',
            'eventDate': '2026-08-31T23:59:59Z',
          },
          <String, Object?>{
            'eventAction': 'registrar expiration',
            'eventDate': '2026-09-15T08:30:00Z',
          },
          <String, Object?>{
            'eventAction': 'last update of RDAP database',
            'eventDate': '2026-07-20T12:00:00Z',
          },
          <String, Object?>{
            'eventAction': 'last changed',
            'eventDate': '2026-06-14T10:30:00Z',
          },
        ],
      },
      source: 'rdap.example',
      registeredDomain: 'example.com',
    );

    expect(result.expiresAt?.toUtc(), DateTime.utc(2026, 9, 15, 8, 30));
    expect(result.updatedAt?.toUtc(), DateTime.utc(2026, 6, 14, 10, 30));
  });

  test('keeps a valid RDAP result when expiry is not published', () {
    final result = parseRdapDomain(
      <String, dynamic>{
        'objectClassName': 'domain',
        'ldhName': 'example.net',
        'events': <Object?>[
          <String, Object?>{
            'eventAction': 'last changed',
            'eventDate': '2026-07-20T12:00:00Z',
          },
        ],
        'entities': <Object?>[
          <String, Object?>{
            'roles': <String>['registrant'],
            'vcardArray': <Object?>[
              'vcard',
              <Object?>[
                <Object?>[
                  'fn',
                  <String, Object?>{},
                  'text',
                  'REDACTED FOR PRIVACY',
                ],
              ],
            ],
          },
          <String, Object?>{
            'roles': <String>['technical'],
            'entities': <Object?>[
              <String, Object?>{
                'roles': <String>['registrar'],
                'vcardArray': <Object?>[
                  'vcard',
                  <Object?>[
                    <Object?>[
                      'org',
                      <String, Object?>{},
                      'text',
                      'Nested Registrar',
                    ],
                  ],
                ],
              },
            ],
          },
        ],
      },
      source: 'rdap.example',
      registeredDomain: 'example.net',
    );

    expect(result.expiresAt, isNull);
    expect(result.publicRegistrant, isNull);
    expect(result.registrar, 'Nested Registrar');
    expect(result.updatedAt?.toUtc(), DateTime.utc(2026, 7, 20, 12));
  });

  test('rejects an unidentified or mismatched RDAP domain object', () {
    for (final payload in <Map<String, dynamic>>[
      <String, dynamic>{},
      <String, dynamic>{'objectClassName': 'entity', 'ldhName': 'example.com'},
      <String, dynamic>{
        'objectClassName': 'domain',
        'ldhName': 'other.example',
      },
    ]) {
      expect(
        () => parseRdapDomain(
          payload,
          source: 'rdap.example',
          registeredDomain: 'example.com',
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });
}

final class _RoutingHttpClient implements HttpClient {
  _RoutingHttpClient(this._bootstrapBody, {this.hangDomainResponse = false});

  final Stream<List<int>> _bootstrapBody;
  final bool hangDomainResponse;
  _FakeHttpClientRequest? lastDomainRequest;
  var bootstrapRequests = 0;
  var domainRequests = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (url.host == 'data.iana.org') {
      bootstrapRequests++;
      return _FakeHttpClientRequest(
        _FakeHttpClientResponse(
          _bootstrapBody,
          statusCode: HttpStatus.ok,
          contentType: 'application/json',
        ),
      );
    }
    domainRequests++;
    final request = _FakeHttpClientRequest(
      _FakeHttpClientResponse(
        const Stream<List<int>>.empty(),
        statusCode: HttpStatus.notFound,
        contentType: 'application/rdap+json',
      ),
      waitsForResponse: hangDomainResponse,
    );
    lastDomainRequest = request;
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._response, {bool waitsForResponse = false})
    : _responseCompleter = waitsForResponse
          ? Completer<HttpClientResponse>()
          : null;

  final HttpClientResponse _response;
  final Completer<HttpClientResponse>? _responseCompleter;
  var wasAborted = false;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() =>
      _responseCompleter?.future ?? Future<HttpClientResponse>.value(_response);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    wasAborted = true;
    final completer = _responseCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(
      exception ?? const HttpException('Request aborted'),
      stackTrace ?? StackTrace.empty,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(
    this._body, {
    required this.statusCode,
    required String contentType,
  }) : headers = _FakeHttpHeaders(contentType);

  final Stream<List<int>> _body;

  @override
  final int statusCode;

  @override
  final HttpHeaders headers;

  @override
  int get contentLength => -1;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  _FakeHttpHeaders([this._contentType]);

  final String? _contentType;

  @override
  String? value(String name) =>
      name.toLowerCase() == HttpHeaders.contentTypeHeader ? _contentType : null;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
