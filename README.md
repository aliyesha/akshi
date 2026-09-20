# Akshi

Akshi is a local-first Flutter application for monitoring domain-registration
and TLS-certificate expiry on iOS and Android. It performs checks while the app
is active and schedules consolidated reminders on the device.

The name comes from Sanskrit **akṣi** (अक्षि), meaning **eye**: the app keeps a
quiet eye on renewal dates and directs attention only when action is useful.

The product guide is available in [app_usage.md](app_usage.md).

## Technical principles

- No application server, account system, analytics, or advertising.
- SQLite stores monitored endpoints and their most recent check results.
- RDAP provides domain-registration expiry data where the registry publishes it.
- Direct TLS connections provide certificate validity and trust information.
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
notifications, and Lucide's open-source icon set. Space Grotesk and JetBrains
Mono are bundled as local variable-font assets; the app never downloads fonts
at runtime.

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
settings behavior, persistence mapping, and daily reminder aggregation.

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
`MonitorEntry` exposes independent domain and certificate findings so the UI can grow with additional check types without changing the monitoring flow.
`NotificationService` owns device permission and scheduling. Reminder grouping
is implemented as pure domain logic in `reminder_digest.dart`, keeping the
notification policy deterministic and independently testable.

## Reminder policy

The user selects two early-warning offsets; a final one-day offset is always
included. Events sharing a local calendar date are combined into one scheduled
notification. A hostname appears only once even when both its domain and
certificate trigger on that date. The preview shows up to three names followed
by the remaining count.

Changes discovered by a multi-site refresh are also emitted as one summary.
Both scheduled expiry alerts and immediate change alerts deduplicate by
hostname and use the same three-name preview policy.

Akshi schedules only the earliest 60 daily digests. This stays within practical
mobile notification limits; opening the app recalculates the schedule and rolls
the window forward.

## Network and data behavior

RDAP availability and response fields vary by registry, so a domain expiry may
occasionally be unavailable even when its TLS certificate can be checked.
Certificate checks connect to the configured hostname and port. Dashboard
favicons are requested directly from the configured website at `/favicon.ico`;
Akshi does not use a third-party favicon proxy. Stored data remains in the local
application database, while normal RDAP, TLS, and favicon requests go directly
to the relevant public services.
