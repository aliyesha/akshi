import 'package:akshi/core/services/rdap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
            'eventDate': '2026-06-12T10:30:00Z',
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
    expect(result.updatedAt?.toUtc(), DateTime.utc(2026, 6, 12, 10, 30));
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
