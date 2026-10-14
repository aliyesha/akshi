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
    reminders/                      alarm planning, reconciliation, proof ledger
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
monitors and asks the reminder controller to reconcile the local schedule.

`AppLifecycleCoordinator` owns every future launched by the post-frame startup
callback and lifecycle observer. Reminder reconciliation and monitor refresh
share one coalesced foreground data session and run behind independent error
boundaries. Notification maintenance starts alongside that session but owns a
separate coalesced operation.

Notification maintenance initializes the plugin, attaches navigation once, and
checks whether the first-run permission prompt is needed. A failed initialization
remains retryable after its operation settles. A slow or never-completing plugin
cannot keep the data operation active, so later foreground transitions can still
refresh monitors and reminders.

Disposal prevents a later phase from beginning; an already running platform call
is allowed to settle and its result is contained.
`NotificationService` joins concurrent initialization calls, clears a failed
attempt for retry, rejects use after disposal, and closes its owned navigation
stream when the Riverpod provider is disposed. Startup failures do not replace
saved monitor state with an error screen: monitor state remains readable,
reminder health reports its own degraded state, and sanitized details stay in
local logs.

`appRouter` is a `GoRouter` tree. The home route lists monitors. A monitor route
opens a compact overview, with child routes for `domain`, `tls`, `email`, and
`dns`. Settings owns child routes for tags, crash reports, the Reminder Ledger,
dated ledger detail, and About. A route is URL-like state, which makes
notification taps and internal destinations deterministic and testable.

The detail flow deliberately has three levels:

```text
monitor list → monitor overview → one focused information page
```

The overview is the decision page. Focused pages keep Domain, TLS, Email, and
DNS details from becoming a single endlessly growing screen. The Attention
screen maps a finding to the corresponding child route so a notification or
attention tap lands at the exact subject.

## Navigation design

Navigation describes visible location and history; it does not own monitor,
settings, tag, or reminder state. Route builders receive stable identity such
as a monitor ID or ledger date, then watch repository-backed providers for
current data. Passing a complete mutable model through route arguments would
make long-lived pages vulnerable to stale data.

The current route hierarchy is:

```text
/                                  monitor portfolio
├── attention                       current findings
├── monitor/new                     create form
├── monitor/:id                     monitor overview
│   ├── domain
│   ├── tls
│   ├── email
│   ├── dns
│   └── edit
└── settings
    ├── tags
    ├── crash-logs
    ├── reminder-ledger
    │   └── :date
    ├── network-destinations
    └── about
```

Choose the router operation from user intent:

| Intent | Operation | History contract |
| --- | --- | --- |
| Drill from the current page into Settings, Tags, a monitor, or a focused detail | `push` | Back returns to the exact caller |
| Close a page, dialog, or bottom sheet whose parent already exists | `pop` | Reveal the existing parent without rebuilding history |
| Open a validated notification or direct internal destination | `go` | Reconstruct the canonical matched page stack |
| Finish creation or leave a deleted entity | `go` | Remove a transient or invalid location from usable history |

Nested routes encode the information hierarchy. Opening
`/settings/reminder-ledger/2026-06-14` from a cold start constructs Settings,
the ledger, and dated detail as matched page levels. An ordinary child action
that means “return to Settings” pops; it does not call `go('/settings')`, because
`go` is a location replacement and may intentionally make Settings the root.

Settings has an explicit **Back to monitors** action. It pops when a caller is
present and otherwise goes to `/`. The fallback is part of the route contract:
Settings may legitimately be opened without prior history by a validated
notification or explicit internal location change. The page must never rely on
an automatically inferred leading button as its only exit.

The portfolio remains mounted beneath ordinary pushed routes. Back therefore
restores its existing scroll position, search query, and tag filter; returning
from a detail page must not force a jump to the top. Canonical `go` navigation
is reserved for flows such as leaving a deleted entity whose route is no longer
valid.

Dialogs and modal bottom sheets are overlay routes. Their controls pop the
overlay's builder context, not an arbitrary page context. Code awaiting an
overlay or controller command checks `context.mounted` before showing feedback
or navigating because the owning page may have been removed while the Future
was incomplete.

Android system Back, iOS edge-swipe, and visible leading actions all resolve
through the same Flutter navigation policy. Platform animation differences do
not justify different route semantics. Tests therefore assert destinations and
stack behavior under both Android and iOS target-platform themes.

Notification navigation is deliberately separate:

1. The notification service emits a bounded versioned payload.
2. The destination parser validates JSON shape, route, identifiers, dates, and
   integrity revision.
3. The lifecycle coordinator attaches one navigation listener.
4. The router goes to the validated canonical destination.
5. Missing monitors or ledger entries render a designed unavailable state.

Navigation never starts a network check merely because a route built. User
commands and lifecycle coordination own external work; shared Riverpod state
keeps progress coherent while the user moves between pages.

## Riverpod and state

Akshi uses Riverpod's `Provider` and `AsyncNotifierProvider` primitives.

`Provider<T>` supplies long-lived dependencies such as `AppDatabase`, service
objects, and repositories. Providers make dependencies explicit and make
services replaceable in tests.

## Database lifecycle

`databaseProvider` owns one `AppDatabase` for the lifetime of its Riverpod
scope and registers its synchronous `dispose` callback with `ref.onDispose`.
Repositories borrow that database; they never open or close independent
connections.

The lazy `instance` getter caches both the in-flight open and the resulting
SQLite connection. Concurrent repository calls therefore join one future
instead of racing separate opens. An opening failure clears the attempt and may
be retried while the owner remains alive. `close()` is terminal, idempotent,
and awaitable: it rejects later access and, if opening is still in flight, waits
for the raw connection and closes it before completing. The synchronous
provider disposer owns and logs close failures; explicit lifecycle tests or
other callers that require completion await `close()` directly.

`monitorControllerProvider` exposes an `AsyncNotifier<List<MonitorEntry>>`.
The notifier loads the repository in `build`, performs add/edit/delete/check
commands, then assigns fresh `AsyncData` after persistence. Screens watch the
provider and render loading, error, or data states. A screen should not mutate
the database directly.

The controller uses a single `_refreshOperation` for portfolio refreshes.
`monitorRefreshProvider` is the canonical cross-screen refresh session: it
records the start time, total and completed monitor counts, the latest successful
completion, and an unresolved failed attempt. Screens must use that state
instead of maintaining private portfolio-refresh flags.

A manual check is also one complete coalesced operation per monitor: source I/O,
observation persistence, list reload, and reminder reconciliation all share one
future. `monitorCheckActivityProvider` publishes the active monitor IDs so every
screen renders the same busy state across navigation.

A shared FIFO `AsyncConcurrencyGate` admits only submitted leaf I/O and caps
active external operations at ten. It is a small semaphore built only from the
standard `dart:collection` `Queue` and `dart:async` `Completer` APIs. RDAP
requests, TLS handshakes, icon fetches, MTA-STS fetches, and individual DNS
queries acquire that gate. Never acquire the same gate around a whole monitor
check: the monitor would then wait for child work that cannot acquire a slot,
which can deadlock when all ten parent slots are occupied. The gate is a
resource ceiling, not a batch size.

## Refresh consistency contract

Akshi treats a portfolio refresh as one foreground snapshot transaction. It is
asynchronous, but it is not background monitoring and it does not pretend that
partly refreshed data is a new coherent state.

Before a remote operation starts, the controller performs one conservative OS
transport check. If every reported transport is `none`, it returns
`MonitorRefreshOutcome.skippedOffline` for a portfolio refresh. A manual check
throws the typed `MonitorOfflineException`. Creating a monitor and saving any
monitor edit are also rejected while the device is known offline. These
decisions happen before persistence, refresh activity, FIFO admission,
external requests, attempt timestamps, or observation writes. A positive
transport result is only permission to try; it does not assert that the
internet or any individual source is reachable.

1. The controller freezes enabled monitor definitions from SQLite at the start
   of the session. Checks only read those immutable values.
2. Each monitor is prepared in memory. Independent sources run concurrently;
   the shared cap-ten gate limits only external leaf I/O.
3. Progress is published through `monitorRefreshProvider`. It distinguishes
   source preparation, per-monitor progress, and final database publication.
   Existing screens remain readable and navigable, with an explicit "showing
   saved results" notice, while the list itself remains the last committed
   snapshot. A failed session keeps its sanitized failure notice visible until a
   later successful refresh; it never presents the failed attempt as current
   data.
4. Add, edit, delete, tag-mutation, and manual-check commands fail fast
   with the typed
   `MonitorRefreshInProgressException` while a portfolio refresh is active.
   Disabled UI controls are a convenience; the controller check is the command
   boundary.
5. After all checks finish, the repository writes observation columns for all
   still-present rows in one short SQLite transaction. Refresh never writes
   definition columns (`hostname`, TLS endpoint, enabled checks, mail mode,
   selectors, label, tags, creation time, or definition update time). Each row
   also matches the frozen definition's `updated_at` revision; a stale result
   rolls back instead of attaching old observations to a new definition.
6. Riverpod publishes the committed list once, and reminders reconcile once.
   No intermediate monitor result is exposed to readers.
7. Startup and resume refreshes may use a freshness window to avoid repeating
   a just-completed session. An explicit user refresh always runs.

The observation-only database boundary is required even though mutation
controls are disabled. Lifecycle callbacks and already-running form saves can
overlap by a few instructions; a refresh that cannot write definitions remains
safe under those races. Initial provisioning and a one-monitor manual check use
the same observation-only write shape but are not portfolio transactions. While
a manual check is active, its shared activity state disables repeat checks and
definition mutations for that monitor in overview and detail UI. Calls that do
repeat still join the original complete command at the controller boundary.

## Monitor creation and editing

The form normalizes the entered hostname using `normalizeHostname`. Domain
registration is always enabled. TLS and Email are independent optional checks;
the TLS hostname may differ from the registration hostname. Sending
automatically selects published SPF and DMARC checks. Receiving automatically
selects MX, MTA-STS, and TLS-RPT checks. DKIM is the only optional custom input
because its selector cannot be enumerated reliably from the domain; the form
shows how to copy the selector prefix from a name such as
`selector1._domainkey.example.com`. These checks report published
configuration facts. They do not test mail delivery, reputation, or live mail
flow.

Create and edit are explicit form modes. Edit waits for monitor state to load.
A missing id renders a not-found state, and an edit save can call only
`updateMonitor`; it never falls through to `add`.
Both form modes show the shared offline notice and disable their save action
while the device is known offline. The controller repeats that guard before
persistence so a direct call or a connectivity change during interaction
cannot bypass it.

`MonitorController.add` commits the immutable monitor definition and tag links
in one SQLite transaction, reloads Riverpod, and returns immediately. The form
navigates to the summary without waiting for the network.
`monitorProvisioningProvider` carries the live initial-check stage across that
navigation. The summary explains that source and connection speed determine
the duration and remains usable while checks run.

The initial observation is a second atomic boundary. Domain, DNS, TLS, and site
identity start concurrently when selected; Email starts after the exact DNS
snapshot it analyzes is available. Results join in memory and replace the
monitor row once, so readers see either the saved definition with no snapshot
or one internally consistent domain/TLS/Email snapshot—never a partially
updated mixture. Expected source failures are stored as typed unavailable
observations; an orchestration failure leaves the definition intact and exposes
a retry message on the summary.

`updateMonitor` uses the same preparation-before-persistence boundary. A changed
check definition clears obsolete results before preparing fresh observations;
a label, tag, or enabled-state-only edit skips external checks and retains
existing result data, but an edit is still saved only while a transport is
available. This keeps the form's save contract uniform.

`MonitorRepository.delete` removes monitor-tag links and the monitor row in one
transaction. SQLite foreign keys are enabled as an additional cascade safety
net. The controller reloads state and rebuilds reminders after deletion, so a
deleted monitor cannot remain in an in-memory list or scheduled digest.

## One foreground check

`MonitorController._prepareCheck` is a pure orchestration boundary: it starts
independent selected work concurrently through the shared dynamic I/O gate and
returns one immutable result without writing SQLite. Its callers select the
persistence boundary: an initial or manual check writes one observation set;
portfolio refresh collects every result before one batch transaction.

1. If enabled, `TlsCheckService` opens one direct TLS socket to the exact
   hostname and port. It retains the presented leaf certificate long enough to
   report platform trust failure and parses validity, subject, issuer, SANs,
   hostname match, serial number, signature algorithm, public-key information,
   and SHA-256 fingerprint. Trust or hostname mismatch is critical independently
   of expiry. The service does not infer a protocol from the port or substitute
   a web API's certificate view.
2. `RdapService` discovers the authoritative RDAP endpoint from IANA's public
   bootstrap document, requests registration data, and extracts dates,
   registrar, registrant, and nameservers where available. Every successful
   bootstrap or registry response passes through `RdapResponseReader`, which
   accepts only `application/rdap+json` or `application/json`, rejects a declared
   or streamed body above 2 MiB, requires valid UTF-8 and JSON, and requires a
   top-level JSON object. A monotonic 30-second deadline belongs to the complete
   check: bootstrap discovery, every registrable-domain candidate, connection,
   response headers, and body. Each individual request/body phase may use at
   most 12 seconds and always receives the smaller of that phase cap and the
   operation time remaining. No later candidate starts after the total budget
   expires. Non-success response bodies are cancelled without being read. The
   shared bounded-body reader owns one stream subscription and completes only
   after that subscription has been cancelled on timeout, overflow, error, or
   completion.

   The process-lifetime service caches the completed IANA bootstrap map. While
   the first bootstrap download is still active, concurrent monitor checks join
   its single in-flight `Future` instead of issuing duplicate requests. The
   temporary reference is cleared after success or failure: a successful map
   remains cached, while a failed load can be retried by a later check. A caller
   that joins shared bootstrap work retains its own operation deadline; it may
   stop waiting without aborting the shared download that another caller owns.
3. `SiteIconService` discovers and caches a declared HTTPS site icon when the
   cache is absent or stale. Page responses are limited to 512 KiB and icon
   responses to 1 MiB by both declared and streamed length. Each request has a
   six-second limit, and one 15-second operation deadline is shared by the page
   and all candidate icons. Redirect, unsuccessful, oversized, and timed-out
   response bodies are cancelled rather than buffered. Discovery does not
   return while an active response body remains subscribed, and it starts no
   further candidate after the operation deadline.

   Raster input is rejected before full pixel decoding when either dimension
   exceeds 2048 pixels or the image exceeds 1,048,576 total pixels. Its encoded
   input and normalized PNG output must each fit within 1 MiB. Normalization
   decodes only the first frame, keeps the original width and height, and never
   resamples the image.

   SVG input is limited to 256 KiB, strict UTF-8 and XML, 512 elements, 2,048
   attributes, 32 levels of nesting, and 64 KiB of cumulative path and point
   data. DTDs, scripts, animation, filters, embedded images or foreign content,
   style blocks, event handlers, imports, and external references are rejected.
   An accepted SVG is stored byte-for-byte unchanged: it is never rewritten,
   simplified, cropped, or resized. A rejected candidate is skipped in favor of
   the next candidate or the neutral placeholder.
4. `DnsSnapshotService` asks the device resolver for explicit record types and
   stores every query as answered, absent, or failed. Each native query, rather
   than the outer snapshot, acquires one shared I/O slot.
5. `EmailPostureService` analyzes the already captured DNS snapshot. It does
   not issue another DNS request. Its MTA-STS check fetches the published HTTPS
   policy only when the corresponding DNS record exists. The response is
   limited to 128 KiB by declared and streamed length, uses one ten-second
   deadline for the complete body, requires strict UTF-8, and cancels
   non-successful, oversized, or timed-out bodies. `MtaStsPolicy` then validates
   the RFC 8461 field grammar: exact `STSv1`; mode `enforce`, `testing`, or
   `none`; `max_age` as 1–10 unsigned decimal digits no greater than 31,557,600;
   and valid MX domain patterns, with at least one MX except in `none` mode.
   Every `mx` line is retained. Unknown extension fields are accepted, and the
   first occurrence of any other repeated field wins, as RFC 8461 requires.
   The current MX RRset is compared with the validated patterns only after all
   those transport and syntax checks pass.
6. After every admitted run finishes, the controller advances `lastAttemptedAt`.
   It advances `lastVerifiedAt` only when Domain and every enabled TLS or Email
   activity completed in that same run, every requested DNS query was answered
   or confirmed absent, and no Email finding is unavailable. A successfully
   observed unhealthy result—such as an expired certificate or invalid mail
   policy—is verified evidence and therefore advances both timestamps. A source,
   resolver, or MTA-STS policy-fetch failure advances only the attempt and keeps
   the previous verification time. Site-icon discovery is presentation metadata
   and never blocks verification.
7. The caller persists observation fields only, reloads Riverpod state at its
   transaction boundary, and rebuilds scheduled expiry reminders once.

### HTTP response ownership and early cancellation

`dart:io` represents `HttpClientResponse` as a single-subscription
`Stream<List<int>>`. Obtaining status and headers does not consume that stream.
Every response therefore has exactly one explicit body policy: bounded read,
small bounded diagnostic read, or immediate cancellation. Leaving it unread can
retain transport resources; draining it can download an arbitrary error page.
Akshi cancels bodies whose status or media type makes their content irrelevant,
and awaits `StreamSubscription.cancel()` so cleanup completes before the method
returns.

The shared bounded reader uses a `Timer`, a `Completer`, and one subscription.
Stream completion, stream error, overflow, and the timer race to settle the
single completer. Its `finally` block cancels both timer and subscription on
every exit path. This is deliberate source ownership, not a replacement for
Dart's asynchronous APIs.

`Future.timeout` limits how long its caller waits; it does not cancel the source
future. Akshi therefore routes RDAP, site-icon, and MTA-STS requests through the
same request lifecycle helpers. If `getUrl()` produces a request only after the
timeout, its late completion handler aborts that request immediately. If
response headers miss their deadline, the helper aborts the active request. The
bounded reader separately cancels the response-body subscription.

One app-scoped `HttpClient` supplies pooled HTTPS connections to all three
services. Riverpod owns that client and force-closes it when the provider
container is disposed. A waiter on shared RDAP bootstrap work is the exception:
it times out its own wait without cancelling work still used by peers.

These are current, supported Dart APIs. `HttpClient`, `HttpClientResponse`,
`StreamSubscription.cancel()`, `HttpClientRequest.abort()`, and `Timer` are not
deprecated. Dart generally recommends a higher-level HTTP package for ordinary
requests, but Akshi intentionally uses `dart:io` at this narrow boundary because
it needs direct streamed-byte limits, header-first decisions, and explicit
request/body cancellation. A higher-level client would not remove those
resource-ownership requirements.

Each external operation is isolated with `try/catch`. TLS ports are validated
only as the protocol-neutral range 1 through 65535. The TLS service performs one
direct handshake on the exact endpoint; it records certificate trust failures
without reconnecting and classifies DNS, closed-port, and wrong-protocol errors
separately. A failed TLS check does not erase a successful registration result.
Failure classification turns platform exceptions, timeouts, connectivity lost
after admission, and invalid responses into user-readable `CheckFailure` values.

Expected external failures are data, not orchestration exceptions. They are
contained per source and per monitor, so another host can still prepare its
result. An unexpected programming or invariant error remains exceptional and
aborts the portfolio transaction; readers continue seeing the preceding
committed portfolio instead of an unexplained partial internal result.

## DNS capture and decoding

DNS is intentionally RRset-based. One DNS query asks one question identified by
owner name, record type, and the Internet (`IN`) class. The response can contain
several resource records for that single question—for example, three MX routes
or several TXT values. Together those records are one RRset and therefore one
atomic observation. A DNS message can also contain CNAME, authority, or
additional-section data; the native bridge extracts only the requested `IN`
RRset for Dart. `DnsRecord` stores one member's owner, type, TTL, value, and
optional MX priority. `DnsQueryResult` stores the whole requested RRset, its
outcome, latest attempt, latest conclusive verification, and latest error.
`DnsSnapshot` contains the independently observed RRsets for one monitor run.

Akshi asks for A, AAAA, CNAME, MX, NS, TXT, and CAA individually at the
monitored name. A/AAAA carry IP addresses, CNAME carries an alias, MX carries
mail routing, NS carries authoritative nameservers, TXT carries opaque text,
and CAA carries certificate-authority authorization. Decoding preserves the
record owner, type, TTL, value, and MX priority where present. No TXT value,
including ACME or Let’s Encrypt validation data, receives provider-specific
querying, decoding, persistence, health, or alert handling. A presentation layer
may attach a recognizable, explanatory provider label only after the generic
record has been verified; such decoration is never evidence and cannot affect
state or timestamps.

Persistence reconciles each DNS RRset independently. A complete answer or a
conclusive negative answer (NXDOMAIN or NOERROR/NODATA) replaces the previous
observation. An unchanged complete answer still advances that RRset's
verification time. Timeout, connectivity loss after admission, SERVFAIL,
cancellation, malformed metadata, or one undecodable member makes the whole
RRset unavailable: its
attempt time advances, while its previous conclusive state, complete record
list, and verification time remain intact. A response containing three valid
members and one malformed member is never saved as a three-member partial
RRset. When no prior observation exists, the RRset remains failed.

The planned questions are known before the run; Akshi does not need and cannot
reliably enumerate an entire public zone. If a plan has eight questions and
five complete while three fail, the five conclusive RRsets advance and the
three failed RRsets retain their saved observations. The monitor run is marked
partial and its monitor-wide verification time does not advance.
`DnsSnapshot.hasFailures` detects both unresolved failures and latest-attempt
errors retained beside saved evidence.

Email analysis receives the raw attempt snapshot, not the reconciled saved
snapshot, so stale DNS evidence cannot be mistaken for a current answer.
`EmailPosture.reconcileWith` updates conclusive findings and retains only
findings whose latest dependencies were unavailable. MTA-STS depends on both
its TXT marker and the current MX query; either DNS failure makes that finding
unavailable before any HTTPS-policy conclusion. Per-finding `observedAt` and
`latestError` keep saved evidence and current availability explicit.
The check plan derives standardized Email owner names automatically:

- `_dmarc.<domain>` and user-entered DKIM selectors when sending is enabled;
- `_mta-sts.<domain>` and `_smtp._tls.<domain>` when receiving is enabled.

These are ordinary TXT questions to the DNS engine. The Email layer—not the
resolver—interprets their standards-defined meaning. Each finding advances only
when every RRset or HTTPS policy on which that finding depends is conclusive.

The app does not use DNS `ANY`. An ANY response may be incomplete and is not a
reliable inventory. The Android bridge uses `DnsResolver.rawQuery`, parses DNS
headers, follows compressed names, and returns normalized wire data with owner,
type, and TTL. The iOS bridge uses `DNSServiceQueryRecord` and returns the same
metadata through the `com.aliyesha.akshi/dns` method channel. Dart decodes the
wire values into the shared domain model.

On iOS, `kDNSServiceFlagsReturnIntermediates` makes conclusive negative answers
available promptly, but it can also deliver a CNAME before the requested RRset.
For a TXT question, that CNAME is resolution progress rather than the TXT
answer. The native query therefore stays active, discards only that intermediate
callback, and publishes the later requested `IN` record type. A direct CNAME
question still records its CNAME normally. A wrong DNS class or an unrelated
record type remains a contract error. This matches Android's one-question,
one-type result.

`EmailPostureService` consumes the snapshot by querying records in memory. It
produces only findings selected by the configured mail roles: MX, SPF, DMARC,
MTA-STS, TLS-RPT, and explicit DKIM selectors. It does not produce a remote
score. A failed query becomes an unavailable finding; an answered query with no
records becomes an absent/informational or actionable finding according to that
policy's rules. Presence of one syntactically recognizable SPF, DMARC, TLS-RPT,
or DKIM record is reported as published information rather than proof that the
policy is operationally correct. MTA-STS is the exception because Akshi also
fetches the advertised HTTPS policy and compares its MX patterns. MX presence
is healthy as an observed routing fact. A covered MTA-STS `enforce` policy is
healthy; covered `testing` and `none` policies are informational. Uncovered
`testing` or `enforce` policies are warnings. Duplicate, malformed, or
explicitly requested but absent configuration remains actionable.

MTA-STS has two deliberately separate protocol layers. The ordinary TXT RRset
at `_mta-sts.<domain>` advertises `v=STSv1` and a policy `id`; it is observed and
reconciled like every other TXT RRset. A valid marker permits an HTTPS GET of
`https://mta-sts.<domain>/.well-known/mta-sts.txt` with redirects disabled,
normal platform certificate validation, and a required `text/plain` response
media type. The line-oriented policy parser keeps
repeated `mx` fields but uses the first value of non-repeatable fields, ignores
valid unknown extensions, and rejects malformed required fields. `max_age` is
metadata published for sending MTA caches; Akshi reports it but does not pretend
to be a mail sender or cache delivery policy. Finally, the Email layer compares
the domain's current MX hosts with exact or `*.` policy patterns. A DNS failure,
HTTPS failure, malformed policy, and uncovered MX are different evidence and
remain different finding states.

TTL is shown as context but is excluded from semantic change detection. Answer
ordering is canonicalized. Repeated values are retained and compared as a
multiset, so adding or removing one of two same-owner TXT values is a real
change. A failed refresh is not treated as a configuration change or
notification event.

Settings → Network destinations is a presentation-only disclosure derived from
monitor definitions and saved source URLs. It lists the IANA bootstrap, dynamic
registry source, system DNS names, direct TLS endpoint, website/icon sources,
conditional MTA-STS URL, and the manually opened project link. It contains no
editable network override and does not initiate a connection.

The portfolio's global offline notice is live device state, not persisted
monitor evidence. `deviceOfflineProvider` performs an initial platform query,
then listens for transport changes; application resume invalidates it so a
transition missed while suspended is queried again. A reconnect only removes
the transient notice. It neither mutates saved `CheckActivity` failures nor
starts an extra refresh. This keeps connectivity presentation responsive while
preserving the distinction between "a transport exists" and "this source was
successfully verified".

The controller reads the same platform source once at each remote-operation
boundary. A known-offline result skips the whole operation and leaves every
saved state and timestamp untouched. If connectivity disappears after that
admission, each source and DNS RRset follows its normal independent failure and
reconciliation boundary.

## Persistence

`AppDatabase` opens the local `akshi.db` SQLite database with foreign keys
enabled. The `monitors` table stores the monitor definition, latest domain/TLS/
Email values, activities, cached icon, and serialized DNS snapshot. Tags use a
normalized many-to-many `monitor_tags` table. `TagPolicy` caps reusable tags
at ten; `TagRepository.create` enforces that limit inside the insert
transaction so rapid create intents cannot bypass the UI count.

`MonitorEntry.toMap` is the storage boundary. Dates are UTC ISO-8601 strings,
boolean values are SQLite integers, lists and rich results are JSON, and icon
bytes are a BLOB. `MonitorEntry.fromMap` performs the inverse conversion.
Repositories never expose raw SQLite rows to presentation code.

Schema version 1 is the current pre-release schema. Incompatible development
changes update that schema and its models directly; test installations clear
their application data before running against the new shape.

## Expiry notification behavior

`ExpiryAlarmPlanner` is pure domain code. For each enabled Domain/TLS expiry,
it subtracts the two configurable calendar-day offsets and fixed one-day
offset, resolves the configured local time in the explicit device time zone,
drops non-future instants, and groups all collisions into one alarm per local
date. DNS, Email, connectivity, and ordinary state changes never notify.

`ReminderController` serializes every request from startup, resume, monitor
CRUD/refresh, settings changes, and manual repair. Each run reads fresh
repositories. `AlarmReconciler` compares the pure desired map with decoded
pending requests and incrementally creates, replaces, or deletes only changed
dates. Stable IDs are derived from the date. A full owned-alarm rebuild is
bounded to one repair attempt after corrupt inventory or failed verification.

The SQLite `alarm_audit` ledger is a best-effort diagnostic record. The
reconciler attempts to record Computed before platform mutation, Platform
accepted after the scheduling call returns, and Pending verified after exact
post-write comparison. Audit writes are isolated and locally logged: they never
stop scheduling, cancellation, repair, or verification, and they never change
reminder health. Desired plans and observed OS pending inventory are
authoritative. The ledger retains at most 365 days and 1,000 alarm revisions.
Settings → Reminder ledger groups rows by daily alarm and exposes the available
Domain/TLS snapshot history. It explicitly does not claim delivery.

On Android, the plugin schedules with `AlarmManager` and its pending API reads
the plugin's private persisted scheduled-notification cache. On iOS, pending
requests are OS-backed. Akshi uses inexact allow-while-idle scheduling and does
not request exact-alarm access. The operating system controls final delivery.

Settings persistence is desired truth: save first, then reconcile. Failure
keeps the user's choice and exposes Needs attention for a later retry; there is
no compensating rollback. Versioned notification payloads route to the
explanatory expiry-reminder screen with the alarm date and affected monitor
IDs. Generated and observed payloads share a 32 KiB UTF-8 ceiling. Generation
fails before an oversized payload reaches a platform bridge; incoming or
pending oversized values are rejected before JSON decoding.

Akshi does not run a background network checker or keep persistent domain
connections.

## UI, theme, fonts, and icons

`AkshiTheme` builds FlexColorScheme-based light and dark Material themes. Brand
colors, surface colors, radii, input decoration, dividers, typography, and
system-bar appearance are centralized there. Space Grotesk and JetBrains Mono
are bundled assets, so the app never downloads fonts at runtime. JetBrains Mono
is used for fingerprints, hostnames, DNS values, and other copyable technical
strings; slashed-zero and tabular figures improve scanning.

All visible clock values use the centralized `date_time_formatter.dart` helper
with `alwaysUse24HourFormat`; the reminder picker is forced to the same 24-hour
contract. Dates remain locale-aware.

Phosphor Icons are packaged with the app. Duotone icons identify information
sections; regular icons are used where a quiet action glyph reads better. A
widget should use semantic labels or tooltips for icon-only actions. Avoid
inventing one-off painted logos when an existing open-source icon communicates
the intent.

Monitor record cards use the shared `MonitorSurface` and `MonitorIconBadge`
components so Domain, TLS, Email, and DNS have the same clipping, radius, base
surface, and icon geometry on every supported device. Status borders and tints
remain intentional data signals. Interactive cards use `Material` plus `InkWell`
so backgrounds do not hide ink splashes. Attention cards use status-aware
amber/coral/error tints and a short bell pulse. They must respect `MediaQuery.disableAnimations` and
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
| `monitor_entry_test.dart` | model defaults, copy semantics, row mapping, and definition/observation separation |
| `async_concurrency_gate_test.dart` | cap enforcement, FIFO queue order, error release, and invalid limits |
| `monitor_refresh_*_test.dart` | session freshness/progress and controller-level mutation rejection |
| `monitor_check_activity_test.dart` | immutable cross-screen manual-check activity by monitor ID |
| `app_lifecycle_coordinator_test.dart` | startup failure isolation, notification retry, foreground coalescing, and disposal boundaries |
| `notification_service_test.dart` | initialization joining/retry and provider-owned stream disposal |
| `app_database_lifecycle_test.dart` | one in-flight open, retry, terminal close, and disposal ownership |
| `dns_snapshot_test.dart` | repeated values, JSON round-trip, TTL/order-insensitive change detection, failed refreshes |
| `system_dns_service_test.dart` | native decoding for TXT/MX wire data and safe failure mapping |
| `email_posture_service_test.dart` | role-specific mail facts, query isolation, and bounded MTA-STS policy reads |
| `mta_sts_policy_test.dart` | RFC 8461 required fields, repeat rules, MX syntax, and maximum-age limits |
| `http_request_lifecycle_test.dart` | late connection cleanup and active request abortion at header timeout |
| `rdap_service_test.dart` | media types, byte/time bounds, whole-operation deadline, request abortion, JSON shape, registry parsing, and missing fields |
| `site_icon_service_test.dart` | byte-exact image handling, safety/decode bounds, and operation-deadline cancellation |
| `certificate_*_test.dart` | human-readable subject and algorithm formatting |
| `tls_endpoint_test.dart` | protocol-neutral port bounds and DNS/reachability/handshake failures |
| `reminder_*_test.dart` | daily grouping, offsets, duplicate checks, and limits |
| `notification_destination_test.dart` | payload routing, encoding, integrity, byte boundary, and strict calendar dates |
| `async_error_view_test.dart` | safe retryable load failure presentation |
| `settings_alarm_transaction_test.dart` | serialized alarm commit, rollback, and non-schedule settings |
| `settings_navigation_test.dart` | Settings/Tags overlay history, root fallback, and Android/iOS route semantics |
| `settings_reminder_debounce_test.dart` | three-second restartable confirmation and cancel restore |
| `notification_settings_screen_test.dart` | visible permission progress and complete alarm refresh |
| `app_settings_test.dart` / `monitor_tag_test.dart` | settings and tag persistence/domain rules |
| `crash_log_test.dart` | diagnostic serialization, retention, deletion, and concurrent writes |
| `platform_privacy_resources_test.dart` | backup exclusion and release-signing safeguards |

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

### Offline physical-device work

The complete operator runbook is [OFFLINE.md](OFFLINE.md). It is the single
source for online preparation, USB-device release runs, cache locations,
cleanup, platform signing, offline verification, disk-space checks, and
troubleshooting.

Keep operational instructions in that runbook. Do not duplicate shell-script
internals or an alternative workflow in this developer guide.

Before opening a pull request, check:

- no generated build output or local database is tracked;
- only the current application identifier remains after a bundle-id change;
- no deprecated Flutter/Dart API is introduced;
- offline, timeout, absent-record, and partial-success states are visible;
- notification taps reach the exact intended route;
- documentation and tests describe every new user-visible rule.

## Release and F-Droid workflow

Akshi is licensed under `GPL-3.0-or-later`; legal and privacy material lives in
`LICENSE`, `COPYRIGHT`, `PRIVACY.md`, and `THIRD_PARTY_NOTICES.md`. Android and
iOS exclude the application data directories from ordinary device and cloud
backups. The Android release configuration intentionally contains no debug
signing assignment because release channels provide their own signing keys.

Before creating a public release:

1. run formatting, analysis, tests, and both platform builds;
2. verify every direct and transitive dependency remains FLOSS;
3. confirm the public repository and issue-tracker URLs;
4. add the Fastlane icon and representative phone screenshots;
5. update `CHANGELOG.md` and the version-code changelog;
6. commit the verified release state and create a matching immutable tag; and
7. run `fdroid rewritemeta`, `fdroid lint`, and an isolated F-Droid build.

The upstream listing text is in `fastlane/metadata/android/en-US`. The
`fdroid/com.aliyesha.akshi.yml` file is a submission draft; the finalized
version belongs in the external `fdroiddata` repository.

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

## Local crash diagnostics

Top-level Flutter and platform error hooks write a bounded, newest-first JSON
array to the app-private `akshi_crash_logs.json` file. The file is independent
of SQLite, so a database failure does not remove the diagnostics path. Writes
use a temporary sibling file and rename, and retention is capped at 50
entries. The store catches its own errors so diagnostics never create a second
failure.

Crash capture records the exception type, message, stack trace, context,
timestamp, and platform version. The platform handler returns `false`,
preserving normal unhandled-error behavior; logging is observational, not a
crash-recovery mechanism. Users can inspect, copy, or delete individual
reports from Settings. No report is uploaded automatically.

Tests for this subsystem should cover malformed JSON, retention trimming,
deletion, storage-failure boundaries, and the distinction between a saved
monitor with unavailable checks and a failed database transaction.

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
source of messages shown in the UI.
