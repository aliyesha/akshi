# Using Akshi

Akshi is a quiet expiry monitor for the domains and secure certificates you
care about. It is designed to answer a practical question whenever you open it:
**what is healthy, and what needs my attention?**

## The name Akshi

**Akshi** comes from the Sanskrit word **akṣi** (अक्षि), meaning **eye**. The
name reflects the app's purpose: it keeps an attentive eye on the dates that
protect your online presence—without demanding constant attention from you.

An eye notices change, helps us remain aware, and focuses attention where it is
needed. Akshi follows the same idea. It checks when invited, remembers what it
last observed, and gives a calm warning when a domain or certificate is moving
toward expiry. It is watchful rather than intrusive: no continuous background
surveillance, no remote account, and no flood of alarms.

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
carry—not create a new service you must babysit.

## Choose what to monitor

Akshi treats a domain as one asset. Domain registration is always checked. On
that same asset, independently enable either or both of:

- **TLS certificate**, using the domain itself or a separate TLS hostname and
  port. When enabled, Akshi also discovers and locally caches the site's icon.
- **Email configuration**, covering published MX, SPF, DMARC, MTA-STS,
  TLS-RPT, and optional user-supplied DKIM selectors. Akshi reports verifiable
  facts and configuration problems; it does not show a reputation, deliverability,
  or security score that could become stale.

TLS and Email start off; leave both off to monitor registration alone. The
service icon remains visible, while the circle at the end of each row shows
whether that optional check is selected. For Email checks, tell Akshi whether
the domain sends mail, receives mail, or both. DKIM selectors
are optional and must be entered explicitly because there is no reliable
universal selector-discovery mechanism.

## Add a monitor

1. Open Akshi and select the **Add** (+) button.
2. Enter a domain or hostname, such as example.com. A complete URL is also
   accepted; Akshi extracts the hostname.
3. Enable **TLS certificate**, **Email configuration**, both, or neither.
4. For TLS, leave the hostname blank to use the domain and keep port 443 for
   standard HTTPS, or enter the actual TLS endpoint. For Email, choose sending
   and receiving roles and optionally add known DKIM selectors.
5. Optionally add a recognizable **Name**, such as “Production mail”, and
   tags. The name appears prominently while the domain remains visible; tags only organize
   monitors and never change which checks run.
6. Save the asset. Akshi checks it immediately and may ask for notification
   permission.

Each domain can show separate results:

- **Domain expiry** comes from public registration data when the registry makes
  it available. The details screen also shows the registrar, registration and
  change dates, nameservers, and public registrant when those fields are
  published.
- **Certificate expiry** comes directly from the X.509 certificate presented by
  the configured TLS hostname and port when TLS checking is enabled.
- **Email configuration** shows published records and concrete issues when Email
  checking is enabled. Email configuration has no expiry date.

A missing optional Email record is informational; an invalid or
expected-but-missing record needs review. Records are read through the device's
configured DNS resolver. An offline device, timeout, or resolver failure is
reported as a lookup failure—not as proof that records are missing. The dashboard
uses the most urgent enabled result as the asset's overall status, while the
Attention screen always names the exact component or components involved.

Public registration records vary. “Public registrant” can be missing, redacted,
or name a privacy service, so Akshi does not present it as verified legal
ownership and does not scrape legacy WHOIS data to fill an unpublished field.

It is possible for one source to be available while another is not.

## Read the dashboard

The first screen lists all monitored domains and emphasizes the most urgent
status. Use search to find a hostname or label, pull down to refresh everything,
or use the refresh button and wait for its completion message. Tag chips
filter the list; tap the selected tag again to clear that filter. Select a
monitor for its complete details. Swipe a monitor to the right to request
deletion; Akshi always asks for confirmation before removing it. Swipe
it to the left to edit it.

Status indicators distinguish healthy, approaching, critical, expired,
unavailable, and failed checks. Certificate trust problems are treated as
critical even when the certificate expiry date is still distant.

The “last checked” time matters: because Akshi does not scan in the background,
results reflect the most recent time the app was active.

## Understand reminders

Akshi uses two configurable early warnings—10 and 5 days by default—and always
includes a final reminder one day before expiry. Delivery time can be selected
in Settings and remains approximate because the operating system controls the
exact delivery moment.

Akshi sends at most one scheduled expiry reminder on a calendar day. If several
monitors need attention together, their events are combined. A notification may
look like this:

> 6 monitors need attention
> example.com, shop.example, status.example, and 3 more

A monitor is listed only once in the daily notification even when both its
domain and certificate reach a warning point together. Open Akshi to see every
monitor and the precise reason it needs attention.

Whenever the app returns to the foreground, it refreshes available information
and rebuilds future reminders from the latest results. Editing or deleting a
monitor and changing reminder settings also rebuilds the shared schedule.

Changes discovered during the same refresh are consolidated too. If several
monitors receive renewed certificates, revised domain dates, or Email configuration changes together, Akshi
reports one change summary rather than notifying once per monitor.

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
- request notification permission again;
- follow the device appearance or choose light or dark mode;
- read the name, philosophy, privacy model, and intended audience in About Akshi.

The first warning must remain earlier than the second. The one-day reminder is
fixed as a final safety prompt.

## Privacy and connectivity

Akshi has no central server. Your monitor list, cached site icons, check results,
tags, and preferences remain in the local application database. Akshi has no
account, sign-up, analytics, advertising, font download, remote scoring service,
or Akshi-operated API. Nothing is sent to aliyesha.com.

Checking still requires network access. While the app is active it can contact:

- **https://data.iana.org/rdap/dns.json**, followed by the registry RDAP HTTPS
  server listed there and its **domain/&lt;registered-domain&gt;** path;
- the configured TLS endpoint through a direct TLS connection and
  **https://&lt;TLS-hostname&gt;[:port]/**, declared HTTPS icon URLs, and
  **https://&lt;TLS-hostname&gt;[:port]/favicon.ico** when TLS checking is enabled;
- the device-configured DNS resolver for MX and TXT records at the domain,
  **_dmarc.&lt;domain&gt;**, **_mta-sts.&lt;domain&gt;**,
  **_smtp._tls.&lt;domain&gt;**, and any user-entered
  **&lt;selector&gt;._domainkey.&lt;domain&gt;**;
- **https://mta-sts.&lt;domain&gt;/.well-known/mta-sts.txt** when that domain
  publishes an MTA-STS DNS record.

Akshi does not use a third-party favicon proxy or public DNS-over-HTTPS provider.
The registries, configured sites, mail-policy sites, and DNS resolver can observe
ordinary connection information such as the requesting IP address and queried
names. Removing the app normally removes its local data. If the monitor list is
important, keep an independent record of the domains you manage.

## When information is unavailable

Some domain registries do not publish a usable expiry date through RDAP, and
temporary network, DNS, firewall, or TLS problems can prevent a check. Akshi
preserves the last useful result where possible and displays the latest error.
If the device is offline, Akshi says so directly and continues to show the last
saved values. A timeout, DNS failure, unavailable source, invalid response, and TLS
connection failure are kept distinct. Try again on a reliable connection before
treating an unavailable result as a registration, certificate, or mail problem.
