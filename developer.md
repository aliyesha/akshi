# Akshi developer guide

This document explains how Akshi is built, how Flutter participates in the
application, where data comes from, how it is stored, and how a change travels
from a user action to the screen and local notification. It is intended for
contributors who are new to Flutter as well as engineers reviewing the code on
GitHub.

Akshi is a local-first Flutter application for iOS and Android. It monitors
domain registration, direct TLS/X.509 certificates, and selected public email
DNS configuration while the application is active. There is no Akshi server,
account system, analytics pipeline, or background network scanner.

## A short Flutter mental model

Flutter applications are Dart programs. The visible interface is a tree of
widgets. A widget is an immutable description of part of the interface; it is
not the screen's mutable state. Flutter compares widget descriptions over time
and updates the underlying element and render trees efficiently.

The important layers are:

1. **Widget tree** — immutable configuration such as `Text`, `ListView`,
   `Scaffold`, and Akshi's feature widgets.
2. **Element tree** — the mounted relationship between widgets and their
   position in the running application. Keys preserve identity when lists
   change.
3. **Render tree** — layout, painting, hit testing, and compositing.
4. **Platform channels** — typed messages between Dart and native Kotlin or
   Swift code when Flutter cannot access a platform API directly.

`build(BuildContext)` must describe the UI for the current state. It should be
fast and free of side effects. Network calls, database writes, notification
scheduling, and other work belong in controllers or services. `setState` tells
Flutter that a local stateful widget must build again; it does not persist data
and it does not replace application state management.

Flutter schedules frames. A state change marks parts of the tree dirty, Flutter
rebuilds those parts, performs layout and paint, and presents a frame. An
`async` operation can finish after a widget has been removed, so UI code checks
`mounted` before calling `setState` or using a context after an await.

## Akshi architecture

The repository is organized by responsibility:

```text
lib/
  main.dart                         process entry point
  app/
    akshi_app.dart                  theme, lifecycle, root MaterialApp
    app_router.dart                 declarative navigation
    providers.dart                  Riverpod dependency graph
  core/
    database/                       SQLite connection and schema
    formatters/                     pure certificate presentation logic
    services/                       network, native, notification, and parsing work
    theme/                          colors, typography, component defaults
    widgets/                        reusable visual components
  features/
    monitors/
      domain/                       immutable business models and rules
      data/                         SQLite repository
      application/                  Riverpod controller and check orchestration
      presentation/                 screens and monitor widgets
    settings/                       settings model, repository, controller, UI
    tags/                           tag model, repository, controller, UI
test/                               unit and widget-level tests
```

The layers have one-way responsibilities:

```text
presentation → application/controller → service/repository
       ↑                 ↓                    ↓
       └──────── Riverpod state ←────── SQLite/native/network
```

Presentation code asks for state and emits user intent. The controller
coordinates the operation. Services perform one kind of external work.
Repositories translate immutable models to and from storage. Domain objects
contain rules that can be tested without Flutter.

## Application startup and lifecycle

`lib/main.dart` calls `runApp` with `AkshiApp`. `AkshiApp` creates the Riverpod
scope, selects the light/dark theme, and owns the app lifecycle observer. On a
foreground transition it asks the monitor controller to refresh enabled
monitors and asks the notification service to reconcile the local schedule.

`appRouter` is a `GoRouter` tree. The home route lists monitors. A monitor route
opens a compact overview, with child routes for `domain`, `tls`, `email`, and
`dns`. The form and settings routes are siblings. A route is a URL-like state,
which makes notification taps and deep links deterministic and testable.

The detail flow deliberately has three levels:

```text
monitor list → monitor overview → one focused information page
```

The overview is the decision page. Focused pages keep Domain, TLS, Email, and
DNS details from becoming a single endlessly growing screen. The Attention
screen maps a finding to the corresponding child route so a notification or
attention tap lands at the exact subject.

## Riverpod and state

Akshi uses Riverpod's `Provider` and `AsyncNotifierProvider` primitives.

`Provider<T>` supplies long-lived dependencies such as `AppDatabase`, service
objects, and repositories. Providers make dependencies explicit and make
services replaceable in tests.

`monitorControllerProvider` exposes an `AsyncNotifier<List<MonitorEntry>>`.
The notifier loads the repository in `build`, performs add/edit/delete/check
commands, then assigns fresh `AsyncData` after persistence. Screens watch the
provider and render loading, error, or data states. A screen should not mutate
the database directly.

The controller uses a single `_refreshOperation` for portfolio refreshes. This
prevents two simultaneous pull-to-refresh actions from starting overlapping
sets of checks. Individual monitor checks still update the same repository and
reload the provider after completion.

## Monitor creation and editing

The form normalizes the entered hostname using `normalizeHostname`. Domain
registration is always enabled. TLS and Email are independent optional checks;
the TLS hostname may differ from the registration hostname and Email can be
configured for sending, receiving, or both.

`MonitorController.add` creates a new immutable `MonitorEntry`, persists it in
a transaction with its tag links, requests notification permission, reloads
the list, and runs its first check. `updateMonitor` compares the check
definition with the stored entry. If the definition changed, previous result
data is intentionally cleared and the new definition is checked from a clean
state. A label/tag-only edit retains result data.

`MonitorRepository.delete` removes monitor-tag links and the monitor row in one
transaction. SQLite foreign keys are enabled as an additional cascade safety
net. The controller reloads state and rebuilds reminders after deletion, so a
deleted monitor cannot remain in an in-memory list or scheduled digest.

## One foreground check

`MonitorController._performCheck` is the central orchestration method. It runs
independent checks and records independent outcomes:

1. If enabled, `TlsCheckService` opens a direct TLS socket and parses the
   presented X.509 certificate.
2. `RdapService` discovers the authoritative RDAP endpoint from IANA's public
   bootstrap document, requests registration data, and extracts dates,
   registrar, registrant, and nameservers where available.
3. `SiteIconService` discovers and caches a declared HTTPS site icon when the
   cache is absent or stale.
4. `DnsSnapshotService` asks the device resolver for explicit record types and
   stores every query as answered, absent, or failed.
5. `EmailPostureService` analyzes the already captured DNS snapshot. It does
   not issue another DNS request. Its MTA-STS check may fetch the published
   HTTPS policy only when the corresponding DNS record exists.
6. The controller stamps `lastCheckedAt`, persists the complete immutable
   result, reloads Riverpod state, reconciles reminders, and emits one grouped
   change notification when semantic data changed.

Each external operation is isolated with `try/catch`. A failed TLS check does
not erase a successful registration result. A failed DNS query does not erase
successful MX or DMARC facts. Failure classification turns platform exceptions,
timeouts, offline conditions, and invalid responses into user-readable
`CheckFailure` values.

## DNS capture and decoding

DNS is intentionally list-based. A DNS response can contain multiple records
with the same owner and type; TXT validation and SPF-related records make this
normal. `DnsRecord` stores owner, type, TTL, value, and optional MX priority.
`DnsQueryResult` stores the requested name/type, state, records, and an error.
`DnsSnapshot` stores the timestamp and ordered query results.

Akshi asks for A, AAAA, CNAME, MX, NS, TXT, and CAA individually at the
monitored name. It adds only the role-appropriate Email names:

- `_dmarc.<domain>` and user-entered DKIM selectors when sending is enabled;
- `_mta-sts.<domain>` and `_smtp._tls.<domain>` when receiving is enabled.

The app does not use DNS `ANY`. An ANY response may be incomplete and is not a
reliable inventory. The Android bridge uses `DnsResolver.rawQuery`, parses DNS
headers, follows compressed names, and returns normalized wire data with owner,
type, and TTL. The iOS bridge uses `DNSServiceQueryRecord` and returns the same
metadata through the `com.aliyesha.akshi/dns` method channel. Dart decodes the
wire values into the shared domain model.

`EmailPostureService` consumes the snapshot by querying records in memory. It
produces concrete findings—MX, SPF, DMARC, MTA-STS, TLS-RPT, and explicit DKIM—
not a remote score. A failed query becomes an unavailable finding; an answered
query with no records becomes an absent/informational or actionable finding
according to that policy's rules.

TTL is shown as context but is excluded from semantic change detection. Answer
ordering is canonicalized. Repeated values are retained and compared as a
multiset, so adding or removing one of two same-owner TXT values is a real
change. A failed refresh is not treated as a configuration change.

## Persistence

`AppDatabase` opens the local `akshi_data.db` SQLite database with foreign keys
enabled. The `monitors` table stores the monitor definition, latest domain/TLS/
Email values, activities, cached icon, and serialized DNS snapshot. Tags use a
normalized many-to-many `monitor_tags` table.

`MonitorEntry.toMap` is the storage boundary. Dates are UTC ISO-8601 strings,
boolean values are SQLite integers, lists and rich results are JSON, and icon
bytes are a BLOB. `MonitorEntry.fromMap` performs the inverse conversion.
Repositories never expose raw SQLite rows to presentation code.

This development iteration uses a clean schema rather than a migration layer.
When the schema changes during unreleased development, clear the app's local
database by uninstalling the development app or using the platform's app-data
reset before testing. Do not add compatibility readers for an unreleased
schema.

## Change and notification behavior

The controller compares the previous and new certificate fingerprint, domain
expiry, Email finding signature, and DNS semantic values. It emits a change
event only after the new row has persisted successfully.

Expiry reminders are computed by the pure `reminder_digest.dart` domain code.
Two configurable warning offsets and a fixed one-day reminder are grouped by
local calendar date. Multiple checks for one monitor become one digest item;
multiple monitors become one daily notification. `NotificationService` owns
permission, scheduling, cancellation, and tap payloads. Tap payloads are
decoded by `notification_destination.dart` and routed through GoRouter.

The operating system controls exact delivery timing. Akshi schedules local
notifications only; it does not run a background network checker.

## UI, theme, fonts, and icons

`AkshiTheme` builds FlexColorScheme-based light and dark Material themes. Brand
colors, surface colors, radii, input decoration, dividers, typography, and
system-bar appearance are centralized there. Space Grotesk and JetBrains Mono
are bundled assets, so the app never downloads fonts at runtime. JetBrains Mono
is used for fingerprints, hostnames, DNS values, and other copyable technical
strings; slashed-zero and tabular figures improve scanning.

Phosphor Icons are packaged with the app. Duotone icons identify information
sections; regular icons are used where a quiet action glyph reads better. A
widget should use semantic labels or tooltips for icon-only actions. Avoid
inventing one-off painted logos when an existing open-source icon communicates
the intent.

Interactive cards use `Material` plus `InkWell` so backgrounds do not hide
ink splashes. Attention cards use status-aware amber/coral/error tints and a
short bell pulse. They must respect `MediaQuery.disableAnimations` and
`accessibleNavigation`.

## Testing strategy

Tests favor pure Dart/domain behavior and small platform-channel fakes. The
test suite is intentionally organized around contracts rather than widget
snapshots:

| Test file | Contract covered |
| --- | --- |
| `hostname_test.dart` | URL/hostname normalization and validation |
| `monitor_status_test.dart` | expiry boundaries and severity precedence |
| `monitor_finding_test.dart` | independent Domain/TLS/Email findings |
| `monitor_entry_test.dart` | model defaults, copy semantics, JSON/row mapping |
| `dns_snapshot_test.dart` | repeated values, JSON round-trip, TTL/order-insensitive change detection, failed refreshes |
| `system_dns_service_test.dart` | native-channel decoding for TXT and MX wire data |
| `email_posture_service_test.dart` | concrete mail facts, duplicate SPF, and per-query failure isolation |
| `rdap_service_test.dart` | bootstrap, registry parsing, missing fields, and response errors |
| `certificate_*_test.dart` | human-readable subject and algorithm formatting |
| `reminder_*_test.dart` | daily grouping, offsets, duplicate checks, and limits |
| `notification_destination_test.dart` | notification payload routing and encoding |
| `app_settings_test.dart` / `monitor_tag_test.dart` | settings and tag persistence/domain rules |

When adding a service, first test its pure parser or policy function. When a
platform channel is unavoidable, use Flutter's
`TestDefaultBinaryMessengerBinding` to provide a deterministic mock response.
Do not make unit tests depend on live DNS, RDAP, certificate endpoints, or the
current date.

Run the local quality gate from the project directory:

```sh
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

The first three commands are required before a change is considered ready.
Build commands catch native package, bundle identifier, channel, and generated
project issues that static Dart tests cannot see.

## Documentation and code-comment standard

Public classes, enums, providers, services, repository methods, and domain
methods should use Dart documentation comments (`///`). A good comment answers
why the method exists, what it owns, what it returns, and what failure or
lifecycle behavior callers must understand. Do not restate an obvious property
name.

Logic-heavy private methods should have a short block comment immediately above
the method or an inline comment at the decision boundary. In this codebase that
includes check orchestration, DNS decoding, status precedence, reminder
grouping, persistence conversion, notification reconciliation, and navigation
destination selection.

Comments must describe current behavior, not an abandoned implementation or a
future promise. If a rule is user-visible—such as one daily digest, no DNS
`ANY`, or preserving repeated TXT values—document it in both the relevant code
and the public guide.

## Contributor workflow

Work on `dev` while the feature is under development. Keep changes coherent
and leave them uncommitted until `dart format`, `flutter analyze`, `flutter
test`, and the relevant platform builds pass in the Flutter environment. Use
small commits only after verification, with a subject describing the behavior
and a multiline body explaining the design decision and test coverage.

Before opening a pull request, check:

- no generated build output or local database is tracked;
- no old application identifier remains after a bundle-id change;
- no deprecated Flutter/Dart API is introduced;
- offline, timeout, absent-record, and partial-success states are visible;
- notification taps reach the exact intended route;
- documentation and tests describe every new user-visible rule.

## Useful source-reading order

For a first contribution, read these files in order:

1. `lib/main.dart`, `lib/app/akshi_app.dart`, and `lib/app/app_router.dart`;
2. `lib/app/providers.dart` and `monitor_controller.dart`;
3. `monitor_entry.dart`, `dns_snapshot.dart`, and `email_posture.dart`;
4. `monitor_repository.dart` and `app_database.dart`;
5. `system_dns_service.dart`, `email_posture_service.dart`, `rdap_service.dart`,
   and `tls_check_service.dart`;
6. the monitor presentation screens;
7. the matching tests before changing behavior.

This order follows the direction of data through the application and keeps UI
decisions grounded in the domain contracts.
## Save ordering and failure boundaries

Adding or editing a monitor follows a deliberate two-phase flow:

1. Form values are normalized and validated.
2. Foreground RDAP, TLS, favicon, DNS, and Email work runs against an immutable in-memory draft.
3. Every expected network failure is converted into a typed, human-readable check failure while previous successful values remain intact.
4. The completed aggregate and tag links are inserted or updated in one SQLite transaction.
5. Riverpod state reloads only after the transaction succeeds. Notification permission and scheduling are post-save side effects and cannot report a committed monitor as unsaved.

The form receives a `MonitorSaveProgress` callback for the same ordering, so the user sees each active stage and a coarse progress indicator instead of a generic spinner. This ordering prevents the duplicate-domain symptom where a row was committed before a later platform or network exception reached the form. Repository failures remain save failures; network failures are saved as explicit unavailable observations.

## Local crash diagnostics

Top-level Flutter and platform error hooks write a bounded newest-first JSON array to the app-private `akshi_crash_logs.json` file. The file is independent of SQLite so a database failure does not remove the diagnostics path. Writes use a temporary sibling file and rename, and retention is capped at 50 entries. The store catches its own errors so diagnostics never create a second failure.

Crash capture records the exception type, message, stack trace, context, timestamp, and platform version. The platform handler returns `false`, preserving normal unhandled-error behavior; logging is observational, not a crash-recovery mechanism. Users can inspect, copy, or delete individual reports from Settings. No report is uploaded automatically.

Tests must cover malformed JSON, retention trimming, deletion, storage failure boundaries, and the distinction between a saved monitor with unavailable checks and a failed database transaction.


## Runtime logging

Akshi uses the official Dart `logging` package (`logging: ^1.3.0`) with one
process-wide console handler configured in `main.dart`. INFO records describe
workflow starts, service stages, persistence boundaries, lifecycle refreshes,
and notification scheduling. SEVERE records describe caught failures and carry
the Dart stack trace so a failure can be located without reproducing it.

Every monitor add, edit, refresh, check, and delete workflow receives a short
flow ID. Service records use stable event names such as
`service.tls.check.started` and `service.dns.query.failed`; this makes one
operation searchable in device logs. The logger is observational only: it does
not upload, persist, or display logs in the app.

Logging is privacy-safe by contract. Allowed fields are operation names,
normalized public hostnames, ports, check flags, aggregate counts, and error
types. Responses, DNS/TLS contents, certificate fingerprints, labels, DKIM
selectors, arbitrary textbox text, URLs with query data, and raw exception
messages are never passed to the logger. Caught errors are emitted with a
sanitized error type plus stack trace; the user-facing classifier remains the
source of messages shown in the UI. Dart permits any non-null object to be
thrown, so operational boundaries use plain `catch (error, stackTrace)` rather
than `on Object` or `on Exception`: this catches both ordinary exceptions and
runtime `Error` values without pretending they share a Java-style hierarchy.
