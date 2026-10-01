import 'dart:async';
import 'dart:convert';

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

  test('parses public registration facts without inventing ownership', () {
    final result = parseRdapDomain(
      <String, dynamic>{
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

  test('keeps a valid RDAP result when expiry is not published', () {
    final result = parseRdapDomain(
      <String, dynamic>{
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
}
