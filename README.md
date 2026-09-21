# Akshi

Akshi is a local-first Flutter application for monitoring domain registration,
website X.509 certificates, and published email-domain configuration on iOS and
Android. It performs checks while the app is active and schedules consolidated
expiry reminders on the device.

The name comes from Sanskrit **akṣi** (अक्षि), meaning **eye**: the app keeps a
quiet eye on renewal dates and directs attention only when action is useful.

The product guide is available in [app_usage.md](app_usage.md).

## Technical principles

- No application server, account system, analytics, or advertising.
- SQLite stores monitored endpoints and their most recent check results.
- RDAP provides domain-registration expiry, registration/change dates,
  registrar, public registrant, and nameservers where the registry publishes
  them.
- Direct TLS connections provide certificate validity, trust, hostname, subject
  names, algorithms, public-key information, serial number, and fingerprint.
- The operating system DNS resolver provides MX, SPF, DMARC, MTA-STS, TLS-RPT,
  and user-selected DKIM records for Email-domain monitors.
- Website icons are discovered from declared HTML icons and /favicon.ico,
  decoded if necessary, and cached locally.
- Checks run at launch, foreground resume, manual refresh, and after endpoint
  changes. Akshi does not perform hidden background network scans.
- Local notifications are rebuilt from the latest stored results whenever a
  check or reminder setting changes.

## Design rationale

Akshi targets indie developers, consultants, small teams, and hands-on
operators whose renewal risk is real but whose portfolio does not justify a
central monitoring service. A conventional service adds hosting, authentication,
stored credentials, background workers, operational upkeep, and another system
that must remain available. Akshi deliberately avoids that footprint.

Foreground-only checking is an explicit product boundary. It improves privacy,
keeps ownership on the device, and removes server and continuous-scanning costs.
The trade-off is equally explicit: results are only as recent as the last active
check. Akshi is a focused renewal companion, not a replacement for real-time
availability monitoring or registrar safeguards on critical infrastructure.

## Toolchain

Akshi targets Flutter 3.47 or newer and Dart 3.13 or newer. The application uses
the standalone Material UI package, Riverpod, go_router, SQLite, local
notifications, and Phosphor's open-source icon set. Space Grotesk and JetBrains
Mono are bundled as local variable-font assets; the app never downloads fonts
at runtime.

The native targets support Android 10 (API 29) or newer and iOS 15 or newer.

## Getting started

```sh
flutter pub get
flutter run
```

The project contains native shells for both supported mobile platforms. Choose
the connected simulator or device through the usual Flutter tooling.

## Quality checks

Run the complete local verification set before submitting changes:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Unit tests cover hostname normalization, expiry boundaries, status precedence,
settings behavior, persistence mapping, DNS record decoding, mail-policy parsing,
and daily reminder aggregation.

## Domain assets and checks

Each normalized domain is stored once. Registration is always checked, while
TLS certificate and Email configuration checks default off and can be enabled
independently or together. The add/edit screen presents all three as consistent
service rows: a persistent service icon at the start and a Phosphor circle or
check-circle selection indicator at the end. Registration is locked on. A TLS
check may use a different hostname and port from the registered domain—for
example, `example.com` with `mail.example.com:465`.

Email checks can separately declare whether the domain sends and/or receives
mail. They report observable configuration facts and standards violations, not
a remote or potentially stale score. DKIM is checked only for selectors
explicitly entered by the user because selectors cannot be discovered reliably.
The system DNS resolver supplies the records; lookup failures remain distinct
from valid answers in which a record is absent.

Registration, TLS, and Email retain separate statuses. The asset's aggregate
status is the most urgent enabled result; the Attention screen identifies the
exact component or components that need review.

## Architecture

The code is organized by feature and responsibility:

```text
lib/
  app/                       application setup, routing, providers
  core/                      database, services, theme, shared widgets
  features/monitors/         monitoring domain, data, controller, screens
  features/settings/         reminder and appearance settings
test/                        pure domain and persistence unit tests
```

`MonitorController` coordinates foreground checks and persistence.
`MonitorEntry` stores independent registration, certificate, and Email posture findings so the UI can grow without coupling check types.
`NotificationService` owns device permission and scheduling. Reminder grouping
is implemented as pure domain logic in `reminder_digest.dart`, keeping the
notification policy deterministic and independently testable.

## Reminder policy

The user selects two early-warning offsets; a final one-day offset is always
included. Events sharing a local calendar date are combined into one scheduled
notification. A hostname appears only once even when both its domain and
certificate trigger on that date. The preview names the affected component,
such as `example.com · TLS certificate` or
`example.com · domain + TLS certificate`, and then reports any remaining count.

Changes discovered by a multi-site refresh are also emitted as one summary.
Both scheduled expiry alerts and immediate change alerts deduplicate by
hostname and use the same three-name preview policy.

Akshi schedules only the earliest 60 daily digests. This stays within practical
mobile notification limits; opening the app recalculates the schedule and rolls
the window forward.

## Network and data behavior

Akshi has no central server. It sends no monitor list, results, telemetry, or
account data to aliyesha.com or to an Akshi-operated service. Stored data remains
in the application's local SQLite database.

The app makes only these task-specific network requests while it is active:

- **https://data.iana.org/rdap/dns.json** to discover the authoritative RDAP
  base URL for each top-level domain;
- the HTTPS RDAP URL published by that IANA document, followed by
  **domain/&lt;registered-domain&gt;**, for registration data;
- a direct TLS socket to **&lt;TLS-hostname&gt;:&lt;TLS-port&gt;** when certificate
  checking is enabled;
- **https://&lt;TLS-hostname&gt;[:port]/** to read standard HTML icon
  declarations, then the declared HTTPS icon URLs and
  **https://&lt;TLS-hostname&gt;[:port]/favicon.ico** as a fallback;
- MX and TXT lookups through the device-configured system DNS resolver for
  enabled Email checks at the domain, **_dmarc.&lt;domain&gt;**,
  **_mta-sts.&lt;domain&gt;**, **_smtp._tls.&lt;domain&gt;**, and user-entered
  **&lt;selector&gt;._domainkey.&lt;domain&gt;** names;
- **https://mta-sts.&lt;domain&gt;/.well-known/mta-sts.txt** only when an MTA-STS
  DNS record is published.

Akshi does not use a public DNS-over-HTTPS provider, favicon proxy, analytics
endpoint, advertising endpoint, font CDN, or remote scoring service. HTTPS icon
redirects must remain HTTPS. Fonts and interface icons are packaged with the app.

RDAP availability and response fields vary by registry, so a registration
expiry or other field may be unavailable even when another check succeeds.
“Public registrant” is the registry-published value and may be absent, redacted,
or identify a privacy service; Akshi does not treat it as proof of legal
ownership and does not scrape legacy WHOIS data to fill gaps. A failed refresh
records whether the device is offline, a lookup timed out, DNS failed, or the
source returned unusable data. Akshi keeps the previous successful values and
labels them as saved results instead of erasing them or presenting them as fresh.
