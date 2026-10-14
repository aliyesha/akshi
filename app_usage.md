# Using Akshi

Akshi is a quiet expiry monitor for the domains and secure certificates you
care about. It is designed to answer a practical question whenever you open it:
**what is healthy, and what needs my attention?**

## The name Akshi

**Akshi** comes from the Sanskrit word **akṣi** (अक्षि), meaning **eye**. The
name reflects the app's purpose: it keeps an attentive eye on the dates that
protect your online presence—without demanding constant attention from you.

An eye notices change, helps us remain aware, and focuses attention where it is
needed. Akshi follows the same idea. It checks when opened or refreshed,
remembers what it last observed, and gives a clear warning when a domain or
certificate is moving toward expiry. It is watchful rather than intrusive: no
continuous background surveillance, no remote account, and no flood of
alarms.

That philosophy also shapes the daily digest. If several websites need action
on the same day, Akshi presents them as one clear signal. The goal is not to
make you look at the app constantly; it is to help you look at the right thing
at the right time.

## The Akshi philosophy

Akshi is designed for indie developers, freelancers, small product teams,
consultants, and hands-on operators who manage a useful collection of domains
but do not need—or want to operate—a monitoring platform.

Many monitoring products introduce another system to maintain: a hosted
account, recurring subscription, central database, background workers, alert
routes, credentials, and a service that must itself remain healthy. That model
is valuable for large operational environments, but it can be disproportionate
for a personal portfolio, client sites, experiments, and small production
services.

Akshi intentionally chooses a smaller model. The phone is the application and
the local record. Checks run when the app is in the foreground, and the latest
known dates are used to prepare local reminders. There is nothing to deploy,
no Akshi account to create, no monitoring server to secure, and no continuous
scanner generating traffic while the app is closed.

This is a deliberate trade-off, not a claim of uninterrupted infrastructure
monitoring. Akshi favors ownership, privacy, low operational cost, and calm
awareness. Teams that require real-time outage detection or compliance-grade
coverage should use dedicated infrastructure monitoring alongside it.

Monitoring should create confidence, not noise. Akshi keeps the experience
deliberately focused:

- Your monitor list stays on your device.
- There is no account, advertising, analytics, or Akshi-operated server.
- Network checks happen visibly when Akshi is opened, resumed, refreshed, or
  updated—not through continuous background scanning.
- Reminders are consolidated so several websites do not produce a burst of
  separate alerts.
- Unknown or unavailable information is shown honestly rather than presented as
  a successful check.

Akshi complements registrar and hosting-provider notices. It should not be the
only renewal safeguard for business-critical infrastructure.

## Who Akshi is for

Akshi is especially useful if you maintain side projects, client websites,
small business domains, portfolio sites, self-hosted tools, staging systems, or
other endpoints that matter but do not justify another operations stack.

If that sounds familiar, add the websites you are responsible for, open Akshi
as part of your normal maintenance rhythm, and let its consolidated reminders
bring the next renewal into focus. Akshi is meant to reduce the mental list you
carry, without creating another service that requires ongoing administration.

## Choose what to monitor

Akshi treats a domain as one asset. Domain registration is always checked. On
that same asset, independently enable either or both of:

- **TLS certificate**, using the domain itself or a separate TLS hostname and
  port. When enabled, Akshi also discovers and locally caches the site's icon.
- **Email configuration**, covering published MX, SPF, DMARC, MTA-STS,
  TLS-RPT, and optional user-supplied DKIM selectors. Akshi reports verifiable
  facts and configuration problems; it does not show a reputation, deliverability,
  or security score that could become stale.

TLS and Email checks are disabled by default. Leave both disabled to monitor
registration alone. The
service icon remains visible, while the circle at the end of each row shows
whether that optional check is selected. For Email checks, select **Sends email
from this domain** to inspect published SPF, DMARC, and user-supplied DKIM
selectors. Select **Receives email at this domain** to inspect published MX,
MTA-STS, and TLS-RPT configuration. Akshi evaluates published configuration;
it does not send messages or test delivery, reputation, or live mail flow.
DKIM selectors are optional and must be entered explicitly because there is no
reliable universal selector-discovery mechanism.

## Add a monitor

1. Open Akshi and select the **Add** (+) button.
2. Enter a domain or hostname, such as example.com. A complete URL is also
   accepted; Akshi extracts the hostname.
3. Enable **TLS certificate**, **Email configuration**, both, or neither.
4. For TLS, leave the hostname blank to use the domain and keep port 443 for
   standard HTTPS, or enter the actual direct-TLS endpoint. Every numeric port
   from 1 through 65535 is accepted; Akshi does not guess the protocol from the
   port number. If that endpoint is closed or speaks something other than TLS,
   the summary reports the reachability or handshake failure explicitly. For Email, choose sending
   and receiving roles and optionally add known DKIM selectors.
5. Optionally add a recognizable **Name**, such as “Production Website”, and
   tags. The name appears prominently while the domain remains visible. Tags
   organize monitors and never change which checks run.
6. Save the asset while the device is online. Add and edit saves are disabled
   when the operating system reports no network transport, so Akshi does not
   create an unverified monitor or silently change an existing one offline.
   Akshi commits the complete monitor definition and tags in
   one local transaction, then opens its summary immediately. Selected initial
   checks continue there with a live stage and progress indicator. Independent
   network work runs in parallel through the shared window of at most ten
   operations; Email analysis follows its captured DNS snapshot. Results join
   before one consistent snapshot is saved. These checks can take time and
   depend on the connection and public sources, so please be patient.

Each domain can show separate results:

- **Domain expiry** comes from public registration data when the registry makes
  it available. The details screen also shows the registrar, registration and
  change dates, nameservers, and public registrant when those fields are
  published.
- **Certificate expiry** comes directly from the X.509 certificate presented by
  the configured TLS hostname and port when TLS checking is enabled. The TLS
  details also show platform trust, hostname matching, validity dates, subject,
  issuer, subject alternative names, serial number, signature and public-key
  information, and the SHA-256 fingerprint. A trust or hostname failure is
  visible even when the certificate has not expired.
- **Email configuration** shows published records and concrete issues when Email
  checking is enabled. Recognizable policy text is reported as published
  information, not as proof of deliverability or complete operational validity.
  Email configuration has no expiry date.
- **DNS records** shows the latest A, AAAA, CNAME, MX, NS, TXT, and CAA
  observations returned by the device's resolver. Each lookup asks for one name
  and record type. A single answer can contain several values—such as several MX
  routes or TXT strings—which together form one RRset. Akshi preserves every
  value in that RRset; each visible record includes its TTL and can be copied.

In that DNS inventory, A and AAAA are IPv4 and IPv6 addresses, CNAME is an alias,
MX identifies inbound mail exchangers, NS identifies authoritative name
servers, TXT carries arbitrary text such as verification and mail-policy values,
and CAA states which certificate authorities may issue certificates. Akshi
shows these as DNS facts. ACME, Let’s Encrypt, and other provider values remain
ordinary DNS records: they receive no different lookup, storage, health, or
alert behaviour. A recognizable display label, when available, is explanatory
presentation only and never changes the underlying result.

DNS is neutral inventory, not a health score. A type that is not published is
normal. This does not change monitor health or create an attention item.
DNS cards keep the same neutral surface in every state. A green check means
records were returned, a neutral minus means the RRset was conclusively not
published, and a rose cloud-slash means the latest lookup failed. Failed
lookups retain any previously verified records or verified absence.

A missing optional Email record is informational; an invalid or
expected-but-missing record needs review. Records are read through the device's
configured DNS resolver. Each RRset has its own latest-attempt and
latest-verified time. A complete changed answer replaces that RRset; a complete
unchanged answer refreshes its verification time; and a confirmed absence
replaces it with verified absence. If the device is already offline, Akshi does
not start the check or change any RRset activity. If connectivity disappears
mid-check, a timeout, malformed answer, or resolver failure retains the complete
saved RRset and is reported as a lookup failure—not as proof that records are
missing. The dashboard
uses the most urgent enabled result as the asset's overall status, while the
Attention screen always names the exact component or components involved.

For Email findings, an observed MX route is healthy as a publication fact.
A recognizable single SPF, DMARC, TLS-RPT, or DKIM record is informational
because deeper validity depends on senders, receivers, referenced records, or
provider behavior that Akshi does not simulate. MTA-STS is checked further:
when its DNS marker exists, Akshi fetches the standard HTTPS policy and compares
its MX patterns with the current MX records. Only a covered `enforce` policy is
healthy; covered `testing` or `none` policies are informational. Duplicate,
malformed, explicitly requested but missing, or uncovered values are shown for
review rather than silently accepted.

Public registration records vary. “Public registrant” can be missing, redacted,
or name a privacy service, so Akshi does not present it as verified legal
ownership and does not scrape legacy WHOIS data to fill an unpublished field.

It is possible for one source to be available while another is not.

## Read the dashboard

The first screen lists all monitored domains and emphasizes the most urgent
status. Use search to find a domain, name, or tag. Pull down to refresh
everything, or use the refresh button and wait for its completion message. Tag
chips filter the list; tap the selected tag again to clear that filter. Select a
monitor to open its compact overview. From there, open only the Domain, TLS,
Email, or DNS details you need. This keeps the main decision page short without
using crowded tabs. An Attention result opens the affected focused page
directly.

Swipe a monitor to the right to request deletion; Akshi asks for confirmation
before removing it. Swipe the monitor to the left to edit it.

Status indicators distinguish healthy, approaching, critical, expired,
unavailable, and failed checks. Certificate trust problems are treated as
critical even when the certificate expiry date is still distant.

Each monitor shows two freshness times. **Last attempted** is the most recent
completed run, including one in which a source or DNS query failed. **Last
verified** advances only when Domain, every enabled TLS or Email check, and all
requested DNS queries complete without unavailable evidence. A failed attempt
keeps the previous verified time so a new failure cannot make older observations
look fresh.

Verified does not mean healthy. An expired or untrusted certificate, an invalid
mail policy, or another observed configuration problem is verified evidence.
Because Akshi does not scan continuously, check both freshness times when
deciding whether the saved result is current enough.

## Understand reminders

Akshi uses two configurable early warnings—10 and 5 days by default—and always
includes a final reminder one day before expiry. Delivery time can be selected
in Settings and remains approximate because the operating system controls the
exact delivery moment.

Akshi sends scheduled reminders only when a saved domain registration or TLS
certificate expiry reaches one of those warning points. Ordinary check-result,
DNS, or Email configuration changes do not send notifications. If several
monitors reach a warning point together, their events are combined. A
notification may look like this:

> 6 expiry reminders
> example.com · domain expires in 10 days; shop.example · TLS certificate expires in 10 days; and 4 more

A monitor is listed only once in the daily notification even when both its
domain and certificate reach a warning point together. Opening it shows every
affected monitor, explains that the alert used saved expiry dates, and marks
entries that have since been resolved.

Whenever the app returns to the foreground, it refreshes available information
and rebuilds future reminders from the latest results. Editing or deleting a
monitor and changing reminder settings also rebuilds the shared schedule.

## Respond to a warning

1. Open the affected monitor in Akshi.
2. Read the affected registration, certificate, or Email configuration finding.
3. Correct it through the relevant registrar, certificate authority, hosting,
   DNS, or mail provider.
4. Return to Akshi and refresh the monitor.
5. Confirm that the new expiry information appears. Akshi reports when it
   detects a changed certificate or domain-expiry date.

Renewal data can take time to propagate. If a registrar reports success but
Akshi still shows the old date, wait briefly and refresh again.

## Settings

In **Settings**, you can:

- choose the two early-warning intervals;
- create, edit, and remove reusable color tags for grouping monitors;
- select the preferred local reminder time;
- see Akshi reminder state separately from OS notification permission;
- review the local Reminder Ledger and repair/verify expiry alarms;
- follow the device appearance or choose light or dark mode;
- read the name, philosophy, privacy model, and intended audience in About Akshi;
- review Akshi's GPL license and included open-source software notices.

Settings always offers **Back to monitors**. It returns to the calling screen
when history exists and returns to the monitor portfolio when Settings was
opened directly without prior route history.

The first warning must remain earlier than the second. The one-day reminder is
fixed as a final safety prompt. Warning-day and reminder-time edits are staged
for three seconds; each further edit restarts that quiet period. Akshi then asks
for confirmation. Confirming saves the desired settings and incrementally
reconciles only alarm dates whose contents or timing changed. Cancel restores
the persisted values.

The reminder card separately shows Akshi's On/Off choice and current OS
notification permission. Enabling requests permission only when needed;
turning reminders off cancels Akshi-owned expiry alarms but does not pretend to
revoke OS permission. The Reminder Ledger groups available diagnostic entries
as one card per daily alarm. Its detail can show Computed, Platform accepted,
and Pending verified steps, while stating that Android or iOS controls final
delivery. A missing ledger step means local diagnostic proof was not stored; it
does not mean the OS notification failed. Reminder readiness comes from the
observed OS pending inventory. Repair performs one bounded rebuild and
verification when normal reconciliation needs help.

## Privacy and connectivity

Akshi has no central server. Your monitor list, cached site icons, check results,
tags, preferences, and local crash diagnostics remain in private application
storage. Akshi has no account, sign-up, analytics, advertising, font download,
remote scoring service, or Akshi-operated API. Nothing is sent to Aliyesha.

The portfolio's no-network notice follows the device's current network
transport and clears when a connection returns. Reconnection does not silently
claim that saved observations are current or start another check: the previous
attempt result remains visible until the normal foreground or manual refresh
finishes with a conclusive answer.

Checking still requires network access. While the app is active it can contact:

- `https://data.iana.org/rdap/dns.json`, followed by the registry RDAP HTTPS
  server listed there and its `domain/<registered-domain>` path;
- the configured TLS endpoint through a direct TLS connection and
  `https://<TLS-hostname>[:port]/`, declared HTTPS icon URLs, and
  `https://<TLS-hostname>[:port]/favicon.ico` when TLS checking is enabled;
- the device-configured DNS resolver for explicit A, AAAA, CNAME, MX, NS, TXT,
  and CAA lookups at the monitored domain;
- the same resolver for role-appropriate Email TXT lookups at
  `_dmarc.<domain>`, `_mta-sts.<domain>`,
  `_smtp._tls.<domain>`, and any user-entered
  `<selector>._domainkey.<domain>`;
- `https://mta-sts.<domain>/.well-known/mta-sts.txt` when that domain
  publishes an MTA-STS DNS record.

Akshi does not use a third-party favicon proxy or public DNS-over-HTTPS provider.
The registries, configured sites, mail-policy sites, and DNS resolver can observe
ordinary connection information such as the requesting IP address and queried
names. Akshi opts its private data out of ordinary Android and iOS device and
cloud backups. Removing the app normally removes its local data, subject to
operating-system behavior.

Open **Settings → Network destinations** to review network activity. It shows
the fixed IANA bootstrap, the system resolver, destinations derived from every
saved monitor, the most recently used dynamic RDAP and icon sources when known,
and the project website that opens only after an explicit tap.

Read the complete [Akshi Privacy Policy](PRIVACY.md) for storage, retention,
network-recipient, backup, and contact details.

## When information is unavailable

Some domain registries do not publish a usable expiry date through RDAP, and
temporary network, DNS, firewall, or TLS problems can prevent a check. Akshi
preserves the last useful result and displays the latest error. If the device
is already offline, Akshi says so directly, does not start remote work, and
continues to show the last saved values without changing attempt timestamps.
A timeout, DNS failure, unavailable source, invalid response, and TLS connection
failure are kept distinct.

DNS is reconciled per requested name and type. A successful answer replaces
that item, and an authoritative empty answer is saved as “not published.” A
failed lookup is not an empty answer: it keeps that item's last verified records
and their time. Email findings are reconciled independently in the same way, so
one unavailable MX, SPF, DMARC, DKIM, MTA-STS, or TLS-reporting dependency
cannot erase the others. A partial run advances the latest-attempt time but not
the monitor's complete verification time. Try again on a reliable connection
before treating an unavailable result as a registration, certificate, or mail
problem.

## If a check fails while adding a monitor

Akshi prepares the domain, certificate, icon, DNS, and Email observations while
the app is open. A temporary network problem is saved as a clear unavailable
result alongside the monitor; it does not create a misleading duplicate on the
next attempt. A device-storage or validation failure is different: the monitor
is not saved, and Akshi explains that directly.

## Crash reports

If Akshi encounters an unexpected error, it records a private diagnostic on the
device containing the time, error type, message, technical context, stack trace,
and platform version. Akshi does not upload it. Open **Settings → Crash reports**
to read, copy, or delete reports. These diagnostics do not prevent a serious
unhandled error from closing the app; they are a record for the next launch,
not a promise that the app can recover.
