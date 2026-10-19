# Alarm Engine Design

This document defines Akshi's local expiry-alarm engine and the invariants its
tests enforce.

## Product contract

Akshi creates local notifications only for approaching:

- domain-registration expiry;
- TLS-certificate expiry.

Ordinary refresh changes, DNS changes, Email posture changes, certificate
replacement, connectivity failures, and application lifecycle events must never
produce an immediate notification.

The user configures two distinct warning offsets. Both must be at least two
days, and the first must be greater than the second. Akshi separately includes
the fixed one-day warning. The default delivery time is 09:00 in the device's
current time zone.

An app-level `remindersEnabled` preference controls participation in the
engine. It defaults to true on a fresh installation. Alarm scheduling still
requires operating-system notification permission; without that permission,
Akshi records the unavailable state and schedules nothing. The app preference
and operating-system permission remain separate controls.

The configured time is a requested local delivery time, not a promise of exact
delivery. Android and iOS ultimately control delivery. Akshi must never silently
replace the device time zone with UTC.

## Final architecture decision

The engine is a desired-state reconciler:

1. Read the latest persisted domains and reminder settings.
2. Compute a complete desired alarm plan in memory.
3. Read Akshi's pending notification inventory.
4. Compare desired and observed alarms by stable alarm identity.
5. Apply only create, replace, and delete operations.
6. Re-read pending inventory and verify that it matches desired state.
7. Recompute failed work from persisted domains/settings on the next request.

This follows the established controller pattern: continuously move observed
state toward desired state with idempotent operations.

A full cancel-and-rebuild is not the normal algorithm. It is reserved for one
bounded automatic or user-requested repair when the owned inventory cannot be
normalized or verified.

## Desired and pending state

Cross-platform pending-alarm inventory has an important constraint:

- iOS exposes pending notification requests and their triggers.
- Android's AlarmManager has no API that enumerates every alarm owned by an app.
- `flutter_local_notifications.pendingNotificationRequests()` returns an ID,
  title, body, and payload, but not the scheduled date/time.
- On Android, the plugin reconstructs that list from its own persisted cache.

Akshi therefore uses two views:

- **Desired plan:** freshly computed from domains, settings, current time, and
  the device time zone. This is authoritative.
- **Pending inventory:** the plugin's pending requests, filtered to Akshi expiry
  alarms. This is evidence of what the platform adapter believes is scheduled.

The pending payload includes the local date, requested time, time-zone ID, and
complete canonical plan snapshot and revision. This makes the plugin's
otherwise date-less inventory useful without pretending that Android provides
an authoritative alarm database.

## Domain model

### Alarm date

There is at most one Akshi expiry notification for a local calendar date.

`AlarmDate` is therefore the local calendar date, represented without a time
zone or clock component:

```text
AlarmDate(year, month, day)
```

A date key is stable when the user changes the reminder time. That change
becomes a replace operation rather than a delete plus create.

### Alarm item

An `ExpiryAlarmItem` identifies one domain participating in that date's
reminder:

```text
ExpiryAlarmItem
  domainId
  hostname
  reasons[]
```

Each reason records:

```text
ExpiryAlarmReason
  kind: domainRegistration | tlsCertificate
  expiryDate
  warningDays
```

The domain ID is the durable alarm identity. The database also requires each
saved hostname to be unique, but alarm reconciliation does not use a mutable
label or tag as identity. Labels and tags never affect an alarm plan.

### Alarm specification

```text
ExpiryAlarmSpec
  date
  scheduledAt
  timeZoneId
  items[]
  derived: notificationId, title, body, revision, payload
```

The revision is SHA-256 calculated from a canonical representation of every
field that affects delivery or content. Collections are sorted before hashing.
Runtime object hashes must not be used because they are not stable across
processes.

### Stable notification ID

The notification ID is a deterministic function of the local calendar date,
using a reserved Akshi expiry-alarm namespace plus the date's epoch-day value.

Consequences:

- the same date always has the same ID;
- changing content or reminder time replaces the same pending request;
- adding an earlier date does not renumber every later alarm;
- reconciliation is idempotent;
- unrelated or foreign notifications are never cancelled.

### Alarm comparison

Dirty state is derived, not mutable state stored inside an alarm:

```text
AlarmComparison
  date
  current: ObservedExpiryAlarm?
  desired: ExpiryAlarmSpec?
  change: create | replace | delete | unchanged

  isDirty = change != unchanged
```

This provides the requested date-to-domains plus dirty view without allowing an
`isDirty` Boolean to drift out of sync with the actual comparison.

## Desired-plan computation

The planner is pure. It receives domains, reminder settings, an explicit
current instant, and an explicit time-zone location. It performs no database,
clock, plugin, or platform calls.

For each reminder-enabled domain:

1. Include domain registration when an expiry exists.
2. Include TLS only when certificate checking is enabled and an expiry exists.
3. Convert the expiry instant to its local calendar date.
4. For each distinct warning offset—first, second, and one day—subtract calendar
   days from the local expiry date.
5. Combine that date with the configured local reminder time.
6. Resolve it in the explicit device time zone.
7. Exclude the candidate when its instant is equal to or earlier than `now`.
8. Add the reason to that domain's item for the alarm date.
9. Deduplicate the same domain/reason/offset tuple.
10. Sort reasons, items, and alarm dates deterministically.

Different reasons for the same domain and date become one item. Different
domains for the same date become one date-grouped reminder.

The final plan is capped to the earliest 60 dates. This stays below iOS's
64-pending-notification limit and leaves room for platform behavior. The cap is
applied before any platform call.

Every domain, expiry reason, and warning offset is evaluated independently. A
past candidate for one domain never suppresses a future candidate for another.
If at least one future candidate remains, the planner schedules that resulting
date group and omits only the passed candidates.

An empty domain set or a set with no usable future scheduled instant produces
an empty desired plan. This is a healthy result rather than an error: no
platform alarm is created, valid settings remain persisted, and future saved
expiry data is evaluated against those settings during the next reconciliation.

## One alarm per local calendar date

This is a hard engine invariant:

```text
number of pending Akshi expiry alarms for one local date <= 1
```

The desired plan is a map whose key is the local date:

```text
Map<AlarmDate, ExpiryAlarmSpec>
```

It is never a map from one date to a list of separate alarms. Domains and
reasons are collected inside that date's single `ExpiryAlarmSpec`.

### Example: one domain with two reasons on the same day

Assume:

- today is 10 May 2026;
- reminder time is 09:00;
- warning offsets are 10, 5, and 1 day;
- `alpha.example` has both domain registration and TLS certificate expiry on
  24 May 2026.

The plan is:

```text
14 May 2026 at 09:00
  one OS alarm
  alpha.example
    domain registration expires 24 May · 10-day warning
    TLS certificate expires 24 May · 10-day warning

19 May 2026 at 09:00
  one OS alarm
  alpha.example
    domain registration expires 24 May · 5-day warning
    TLS certificate expires 24 May · 5-day warning

23 May 2026 at 09:00
  one OS alarm
  alpha.example
    domain registration expires 24 May · 1-day warning
    TLS certificate expires 24 May · 1-day warning
```

The result is three alarms on three different dates. It is not six alarms.
Within each date, the two expiry reasons are merged into the one
`alpha.example` item.

### Example: multiple domains collide on the same day

Assume the same current date, time, and offsets:

- `alpha.example` TLS certificate expires 24 May, producing its 10-day
  warning on 14 May;
- `beta.example` domain registration expires 19 May, producing its 5-day
  warning on 14 May;
- `gamma.example` TLS certificate expires 15 May, producing its 1-day
  warning on 14 May.

The desired map contains:

```text
AlarmDate(2026-05-14) -> ExpiryAlarmSpec
  notificationId: stable ID for 2026-05-14
  scheduledAt: 2026-05-14 09:00 in the device time zone
  items:
    alpha.example
      TLS certificate expires 24 May · 10-day warning
    beta.example
      domain registration expires 19 May · 5-day warning
    gamma.example
      TLS certificate expires 15 May · 1-day warning
```

The adapter makes exactly one `zonedSchedule` call for 14 May. Its notification
can be rendered as:

```text
3 expiry reminders
alpha.example · TLS certificate expires in 10 days;
beta.example · domain expires in 5 days;
gamma.example · TLS certificate expires in 1 day
```

If another domain later joins 14 May, the reconciler replaces the existing
14 May request using the same stable notification ID. It does not create a
second alarm. If one domain leaves, it replaces the same request with the
remaining items. It deletes the alarm only when no item remains for that date.

## Observed inventory

Every Akshi expiry payload uses a versioned schema. Its compact shape is:

```json
{
  "version": 1,
  "type": "expiry_alarm",
  "date": "2026-05-14",
  "scheduledUtc": "2026-05-14T03:30:00.000Z",
  "timeZone": "Asia/Kolkata",
  "items": [
    {
      "id": "...",
      "hostname": "alpha.example",
      "reasons": [
        {"kind": "tls", "expiry": "2026-05-24", "days": 10}
      ]
    }
  ],
  "revision": "sha256-of-canonical-content"
}
```

The notification ID is not duplicated inside the payload. It is derived from
the date and validated against the reserved ID namespace while decoding.

Pending requests are normalized as follows:

- valid owned expiry payload: include in the observed map;
- foreign notification: ignore completely;
- duplicate owned date or ID: mark for repair;
- malformed payload in the owned ID namespace: mark for repair;
- desired request absent from pending inventory: create;
- pending request present but absent from the desired plan: delete;
- matching ID, title, body, and complete canonical payload: unchanged.

## Set comparison

Let `C` be current keys and `D` be desired keys.

- Create keys: `D - C`
- Delete keys: `C - D`
- Common keys: `C ∩ D`
- Replace a common key when its ID, requested time, time zone, scheduled
  instant, revision, content, or payload differs.
- Leave a common key unchanged only when the complete normalized
  specification matches.

Input ordering has no semantic effect.

## Reconciliation algorithm

Only one reconciliation may execute at a time. Requests are serialized, and
each queued run reads repositories at execution time rather than using a stale
domain snapshot captured when it was queued. An unchanged follow-up performs
zero platform writes.

The sequence is:

1. Initialize the notification adapter and resolve the device time zone.
2. If time-zone resolution fails, stop. Keep existing alarms untouched and
   report the engine as needing repair. Never fall back to UTC.
3. Read the newest persisted domains and reminder settings.
4. Build and validate the entire desired plan before changing platform state.
5. Attempt to record each desired date/revision as **Computed** in the local
   proof ledger.
6. Read pending notification requests and normalize ownership.
7. Apply replacements first. They reuse stable IDs and do not increase the
   pending count. After each successful scheduling call, attempt to record
   **Platform accepted**.
8. Cancel deletions and attempt to mark their latest ledger entries cancelled.
9. Schedule creations in chronological order and attempt to record each
   accepted handoff.
10. On the first platform failure, stop, attempt to record the failure, and
    retry from persisted desired state on the next reconciliation.
11. Re-read pending inventory. Report healthy only when the complete inventory
    matches desired state, then attempt to record **Pending verified**.

Every audit attempt is isolated and locally logged. Audit storage cannot stop
platform convergence and cannot change reminder health.

Deleting before creating prevents temporarily exceeding iOS's pending limit.
A crash can leave a partial plan, but it cannot make the local desired state
ambiguous; startup/resume reconciliation converges it again.

Calling reconciliation twice with unchanged inputs performs zero platform
writes on the second call.

## Events that request reconciliation

All callers use one `AlarmReconciler.reconcile()` entry point:

- initial application startup;
- application resume;
- initial domain check after an add;
- domain edit;
- domain delete;
- one-domain refresh;
- refresh all;
- reminder warning-day change;
- reminder-time change;
- notification permission returning to allowed;
- explicit “Repair reminders” action;
- application resume after a device time-zone change.

Calling the engine for an edit that cannot affect alarms is safe. The pure diff
returns only unchanged entries and performs no platform work. An optimization
may later skip those calls, but correctness does not depend on that optimization.

Theme, tag, label, DNS, Email, and connectivity-only changes cannot alter the
desired plan.

## Persistence and failure policy

Domain/settings persistence and operating-system scheduling cannot form one
atomic transaction.

Akshi treats persisted user data as desired truth and platform alarms as a
reconcilable side effect:

- save the user's domain or reminder setting;
- invoke reconciliation;
- if scheduling fails, keep the saved user choice;
- expose “reminders need repair” rather than rolling the user choice back;
- retry at the next startup, resume, relevant action, or explicit refresh.

This is safer than compensating rollback, which can itself fail and can leave
both settings and alarms uncertain.

The reconciler is idempotent and uses stable IDs. Desired work never needs a
separate dirty record because it is recomputed from persisted user data.

The alarm ledger is best-effort evidence, not desired state. It cannot recreate
alarms and is never read by the planner, set comparison, repair decision, or
health calculation. A failed ledger write is logged and platform reconciliation
continues. Ledger rows are retained for up to 365 days and capped at 1,000 alarm
revisions; cleanup runs transactionally when computed entries are inserted.

## Reminder health and permission UX

The Settings card has one primary action that changes meaning with the current
state. It controls Akshi's `remindersEnabled` preference; it does not claim to
grant or revoke operating-system permission directly.

### Ready

Use a positive bell/alarm-with-check treatment and the label
**Expiry reminders ready** when:

- reminders are enabled in Akshi;
- notification permission is allowed;
- the desired plan was computed successfully;
- every desired alarm is present with the expected revision;
- no stale owned alarm remains pending.

An empty desired plan is still Ready when permission is allowed and no owned
alarm is pending. The supporting text is **No upcoming expiry reminders**. The
primary action is **Turn off reminders**.

Turning off performs this sequence:

1. Persist `remindersEnabled = false` first so a crash cannot recreate alarms
   against the user's intent.
2. Cancel every owned pending expiry alarm.
3. Verify that no owned pending alarm remains.

The operating-system permission may remain allowed. Akshi simply stops using it.

### Paused in Akshi

Use a neutral slashed-bell icon and the label **Expiry reminders off** when the
user has turned reminders off in Akshi. No alarm is scheduled even if device
permission remains allowed. The primary action is **Enable reminders**.

### Permission needed

Use a neutral slashed-bell icon and the label **Notification permission
needed** when the user is enabling reminders but device permission is denied or
has not been granted.

Enabling performs this sequence:

1. Record the user's enable intent.
2. If permission is undetermined, request it.
3. If permission was denied previously, open the app's system notification
   settings after explaining why.
4. Refresh permission when the app resumes.
5. Once allowed, compute, schedule, and verify the desired alarms.

Until permission becomes allowed, Akshi schedules no new alarms and removes any
owned pending expiry alarms. The card never describes this state as healthy.
Choosing **Not now** leaves the Akshi preference enabled and the card in
**Notification permission needed**; it does not mislabel the preference as off.

### Needs attention

Use a warning treatment and the label **Reminders need attention** only when
reminders are enabled and permission is allowed, but desired and pending state
could not be reconciled or verified.

The card explains the concrete reason, such as time-zone detection failure or a
rejected platform operation, and offers **Retry reminder setup**. Akshi must not
show the Ready state merely because a scheduling API call returned; it verifies
the resulting pending inventory first.

An optional secondary **System notification settings** action lets a user
revoke or restore operating-system permission. Akshi does not present its own
control as an operating-system permission switch.

The current permission and reminder-health state is refreshed on application
startup and resume, including return from system notification settings.

## Timing policy

Akshi uses one-shot zoned notifications, never repeating alarms.

Android uses `inexactAllowWhileIdle`. Expiry reminders are day-scale events and
do not justify Android's exact-alarm special access. Android documents that an
inexact alarm is not delivered before its trigger, but battery restrictions may
delay it.

The Settings UI describes the time as approximate, for example
**Around 09:00 local time**.

If exact-to-the-minute delivery becomes a product requirement, that is a
separate product and permission decision. It must not be introduced silently
inside this engine.

The versioned payload and local proof ledger retain the requested date/time,
time-zone identifier, resolved UTC instant, alarm contents, platform, revision,
and handoff timestamps. This makes a report such as “09:00 fired in the
afternoon” diagnosable without claiming the operating system delivered it on
time.

## Explaining a notification

Title and body are generated only from `ExpiryAlarmSpec`. They state the actual
reason and remaining time, for example:

```text
Expiry reminder for example.com
example.com · TLS certificate expires in 5 days
```

The payload routes to the expiry-reminder screen with the affected domain IDs,
alarm date, and canonical revision. The screen explains that the notification
used the saved expiry information available when the alarm was created and
identifies results that have since been resolved.

## Repair operation

Normal reconciliation never cancels every notification first.

The `AlarmReconciler` owns repair. It first performs ordinary comparison and
incremental reconciliation. It may run one automatic repair attempt when:

- the owned pending inventory has duplicate IDs/dates;
- owned payloads cannot be decoded;
- post-reconciliation verification cannot converge.

Automatic repair is bounded to one attempt for a reconciliation request. It
must not enter a cancel/rebuild loop.

Repair performs:

1. compute and validate desired state;
2. cancel only Akshi-owned pending expiry notifications;
3. schedule the earliest 60 desired alarms chronologically;
4. re-read and verify pending inventory against desired state.

If automatic repair succeeds, the user sees the normal Ready state. If it
fails, the Settings card shows **Reminders need attention**, the concrete
reason, the last attempted time, and a **Repair reminders** action. Manual
repair runs the same bounded operation; it does not modify domains, expiry
dates, warning settings, tags, or other user data.

Because expiry reminders are Akshi's only notification type,
`cancelAllPendingNotifications()` may be used only as the last recovery option
when ownership cannot be established. It is never used during routine refresh.

## Reminder proof ledger

**Settings → Reminder ledger** is a user-visible, local proof-of-work surface.
It answers one precise question: did Akshi compute this alarm, receive a
successful return from the platform scheduling adapter, and then observe the
same request in pending inventory?

It never claims the notification fired, was displayed, made a sound, or was
seen. After a verified handoff, delivery is controlled by Android or iOS,
including battery policy, Focus modes, and notification settings.

One list card represents one scheduled alarm date, matching the engine
invariant. Multiple domains and registration/TLS reasons are shown inside that
card rather than as separate alarms. The newest revision is visible; prior
revisions are nested in the detail screen as replaced/cancelled history.

Each immutable date/revision snapshot contains:

- alarm date, stable notification ID, requested local time, time zone, and UTC
  instant;
- canonical revision and full grouped registration/TLS items;
- domain and reason counts;
- platform and OS version;
- `computedAt`, `submittedAt`, `verifiedAt`, `cancelledAt`, or `failedAt`;
- a sanitized error category when work fails.

The detail timeline describes the audit entries that were successfully stored:

1. **Computed** — desired-plan calculation produced this snapshot.
2. **Platform accepted** — the scheduling API returned without throwing.
3. **Pending verified** — the post-write inventory exactly matched the desired
   request.

A missing ledger entry means that diagnostic proof was not stored. It does not
override the OS pending inventory and does not mean the notification failed.

On iOS, pending notification requests come from
`UNUserNotificationCenter`. On Android, `flutter_local_notifications` schedules
through `AlarmManager` and then persists its own private scheduled-notification
JSON; `pendingNotificationRequests()` reads that plugin cache because Android
does not offer application alarm enumeration. The Android ledger therefore
states this distinction plainly.

The ledger is private application data. Domain names appear because the user
explicitly opened a local alarm snapshot. A copied proof receipt excludes raw
payload JSON and domain IDs but includes the date, timing, notification ID,
revision, counts, platform, and proof timestamps.

Repair remains available on the ledger screen and uses the same bounded engine
operation. The ledger itself is never a repair input.

## External platform facts

- Android alarm guidance:
  https://developer.android.com/develop/background-work/services/alarms
- Apple pending notification requests:
  https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:)
- Apple local notification scheduling:
  https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- Flutter local notifications:
  https://pub.dev/packages/flutter_local_notifications
- Desired/current controller pattern:
  https://kubernetes.io/docs/concepts/architecture/controller/

## Test matrix

All alarm-engine fixtures use February through August 2026. The suite covers:

- one domain and multiple domains, including same-day reason collisions;
- add, delete, replace, and unchanged set comparisons;
- stable IDs when an earlier date is inserted or reminder time changes;
- globally disabled reminders, per-domain reminder exclusion, null/past
  expiries, and the exact-now boundary;
- February/March calendar boundaries and explicit time-zone conversion;
- deterministic ordering, canonical payload integrity, and the 60-date cap;
- zero-write idempotence on a second unchanged reconciliation;
- malformed owned inventory, bounded automatic repair, and verification;
- schedule failure without routine cancel-all, plus bounded failed repair;
- empty desired state cancelling and verifying all owned alarms;
- notification routing with affected domain IDs and alarm date;
- ledger snapshot decoding, one-card-per-date grouping, revision ordering,
  lifecycle ordering, failure recording, and isolation of every audit-write
  failure from scheduling, repair, verification, and reminder health.
