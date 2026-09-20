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

## Add a website

1. Open Akshi and select the **Add** (`+`) button.
2. Enter a domain or hostname, such as `example.com`. A complete URL is also
   accepted; Akshi extracts the hostname.
3. Keep port `443` for a standard secure website, or enter the TLS port used by
   the service.
4. Optionally add a recognizable label such as “Main store.”
5. Save the monitor. Akshi checks it immediately and may ask for notification
   permission.

Each monitor can show two independent dates:

- **Domain expiry** comes from public registration data when the registry makes
  it available.
- **Certificate expiry** comes directly from the TLS certificate presented by
  the configured hostname and port.

It is possible for one date to be available while the other is not.

## Read the dashboard

The first screen lists all monitored websites and emphasizes the most urgent
status. Use search to find a hostname or label, pull down to refresh everything,
or use the refresh button and wait for its completion message. Tag chips
filter the list; tap the selected tag again to clear that filter. Select a
website for its complete details. Swipe a monitor to the right to request
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
websites need attention together, their events are combined. A notification may
look like this:

> 6 websites need attention  
> example.com, shop.example, status.example, and 3 more

A website is listed only once in the daily notification even when both its
domain and certificate reach a warning point together. Open Akshi to see every
website and the precise reason it needs attention.

Whenever the app returns to the foreground, it refreshes available information
and rebuilds future reminders from the latest results. Editing or deleting a
monitor and changing reminder settings also rebuilds the shared schedule.

Changes discovered during the same refresh are consolidated too. If several
websites receive renewed certificates or revised domain dates together, Akshi
reports one change summary rather than notifying once per website.

## Respond to a warning

1. Open the affected website in Akshi.
2. Determine whether the domain registration, TLS certificate, or both require
   attention.
3. Renew through the relevant registrar, certificate authority, or hosting
   provider.
4. Return to Akshi and refresh the monitor.
5. Confirm that the new expiry information appears. Akshi reports when it
   detects a changed certificate or domain-expiry date.

Renewal data can take time to propagate. If a registrar reports success but
Akshi still shows the old date, wait briefly and refresh again.

## Settings

In **Settings**, you can:

- choose the two early-warning intervals;
- create, edit, and remove reusable color tags for grouping websites;
- select the preferred local reminder time;
- request notification permission again;
- follow the device appearance or choose light or dark mode.

The first warning must remain earlier than the second. The one-day reminder is
fixed as a final safety prompt.

## Privacy and connectivity

Akshi stores its monitor list and results locally. Checking still requires an
internet connection: the app contacts public registration services and the
configured website to obtain current information. Those external services can
observe ordinary network request information such as the requesting IP address.

Removing the app normally removes its local data. If the monitor list is
important, keep an independent record of the domains you manage.

## When information is unavailable

Some domain registries do not publish a usable expiry date through RDAP, and
temporary network, DNS, firewall, or TLS problems can prevent a check. Akshi
preserves the last useful result where possible and displays the latest error.
Try again on a reliable connection before treating an unavailable result as a
registration or certificate failure.
