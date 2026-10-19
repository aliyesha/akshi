# Using Akshi

Akshi is a private domain portfolio companion. It helps you review domain
registration, TLS certificates, DNS records, and published email configuration,
then reminds you about known registration and certificate expiry dates.

The name comes from the Sanskrit word **akṣi** (अक्षि), meaning **eye**. Its
guiding line is **Watch what matters.**

Akshi checks while the app is open. It is not a continuous uptime monitor and
should not be your only renewal safeguard for business-critical domains. There
is no Akshi account, advertising, analytics, or Akshi-operated server.

## Quick start

1. Open Akshi and select **Add** (+).
2. Enter a domain or hostname, such as `example.com`. You can also paste a
   complete URL; Akshi uses its hostname.
3. Choose whether to check the TLS certificate, email configuration, or both.
   Leave both off if you want registration information only.
4. Optionally add a recognizable name and color tags.
5. Save while the device is online.
6. Wait for the first check to finish, then open the Domain, TLS, Email, or DNS
   section for more detail.

## Choose what to check

Every saved entry includes a **Domain registration** check. Two optional checks
can be enabled independently:

- **TLS certificate** checks the certificate presented by the domain or by a
  separate TLS hostname and port. Leave the hostname blank and use port 443 for
  normal HTTPS. When this check is enabled, Akshi also tries to find the site's
  icon.
- **Email configuration** examines published MX, SPF, DMARC, DKIM, MTA-STS, and
  TLS-RPT information. It reports configuration facts and visible problems; it
  does not test message delivery, reputation, or live mail flow.

For Email, choose **Sends email from this domain**, **Receives email at this
domain**, or both. Add DKIM selectors only when you know them; selectors cannot
be discovered reliably for every provider.

TLS and Email checks are off by default. Changing either option does not affect
the registration check.

## Add and edit a domain

The domain form accepts these choices:

- **Domain or hostname:** the portfolio entry Akshi will save.
- **Name:** an optional friendly label such as “Production Website.”
- **Tags:** optional color labels used only for organizing the portfolio.
- **TLS hostname and port:** an optional endpoint different from the saved
  domain. Ports from 1 through 65535 are accepted.
- **Email roles and DKIM selectors:** the published email configuration you
  want Akshi to inspect.
- **Expiry reminders:** available after the domain is first saved. Turning this
  off excludes only this domain from expiry reminders; checks and saved results
  remain available.

Add and edit saves require a network connection because Akshi checks the
updated entry before finishing. The summary screen shows progress and then
presents the available results. Public services and network conditions can
affect how long this takes.

To change an existing entry, swipe it to the left or open its edit action. To
delete it, swipe it to the right and confirm. Deleting removes the entry and its
future reminders from Akshi.

## Understand the results

A saved domain can contain four independent areas:

- **Domain** shows registration and expiry information published by the
  registry. Depending on the registry, this can include the registrar,
  registration and update dates, nameservers, and a public registrant.
- **TLS** shows certificate validity, trust, hostname matching, issuer, subject,
  alternative names, cryptographic details, and fingerprint. A certificate can
  require attention even when its expiry date is still distant.
- **Email** shows the selected sending and receiving records. Missing optional
  records can be informational, while malformed, duplicated, or explicitly
  requested but missing records can require review.
- **DNS** shows A, AAAA, CNAME, MX, NS, TXT, and CAA records returned by the
  device's DNS resolver. Values can be copied, and each displayed record
  includes its TTL.

DNS is an inventory, not a general health score. A record type that is not
published can be perfectly normal. A successful result means records were
returned; **Not published** means the resolver confirmed no record of that type;
an unavailable result means the latest lookup failed.

Email results describe published configuration rather than guaranteeing
deliverability or security. For example, Akshi can identify an MTA-STS policy
and whether its published mode and MX coverage agree, but it cannot simulate
every sender, receiver, or provider.

Public registration data varies between registries. A public registrant can be
missing, redacted, or replaced by a privacy service. Akshi does not treat that
field as proof of legal ownership.

## Use the portfolio and Attention view

The portfolio emphasizes the most urgent enabled result for each domain.
Statuses distinguish healthy, approaching expiry, critical, expired,
unavailable, and failed checks.

You can:

- search by domain, friendly name, or tag;
- select a tag to filter the list and select it again to clear the filter;
- pull down or use Refresh to check all saved domains;
- open a domain for a compact overview;
- continue into Domain, TLS, Email, or DNS details;
- use **Attention** to see the exact items that currently need review.

One source can succeed while another is unavailable. Open the focused detail
screen to see which result produced the portfolio status.

## Read freshness information

Each domain shows two times:

- **Last attempted** is the most recent completed check, including a check in
  which one or more sources failed.
- **Last verified** advances only when registration and every enabled check
  complete with usable evidence.

A failed attempt keeps the earlier verified time so that old information does
not appear newly confirmed. Verified also does not mean healthy: an expired
certificate or an invalid email policy can be verified evidence.

Because Akshi does not check continuously, use these times to decide whether the
saved result is recent enough for your needs.

## Understand expiry reminders

Akshi uses two configurable early warnings—10 and 5 days by default—and always
includes a final reminder one day before expiry. The reminder time is selected
in Settings, but delivery remains approximate because Android or iOS controls
the final delivery moment.

Reminders use saved domain-registration and TLS-certificate expiry dates.
DNS and Email changes do not create notifications, and reminders are not daily
alarms. If several expiry events fall on the same date, Akshi combines them
into one notification.

A notification can look like this:

> **6 expiry reminders**
>
> example.com · domain expires in 10 days; shop.example · TLS certificate
> expires in 10 days; and 4 more

A domain appears once in a date's notification even when both its registration
and certificate need attention. Opening the notification shows the affected
domains and indicates items that have since been resolved.

Akshi updates future reminders when relevant saved information changes, when a
domain is edited or deleted, and when reminder settings change.

## Respond to an expiry warning

1. Open the affected domain in Akshi.
2. Read whether the warning concerns registration or a TLS certificate.
3. Renew or correct it through the relevant registrar, certificate authority,
   or hosting provider.
4. Return to Akshi and refresh the domain.
5. Confirm that the new expiry information appears.

Renewal information can take time to propagate. If the provider reports success
but Akshi still shows the old date, wait briefly and refresh again.

## Use Settings

In **Settings**, you can:

- choose the two early-warning intervals;
- select the preferred local reminder time;
- enable or turn off Akshi reminders;
- see Akshi reminder state separately from OS notification permission;
- review the Reminder Ledger or repair reminders that need attention;
- create, edit, and remove reusable color tags;
- follow the device appearance or choose light or dark mode;
- read About Akshi, its license, and included open-source notices;
- review network destinations and private crash reports.

### Change warning days

The first warning must remain earlier than the second. Both must be at least two
days before expiry, the first warning can be at most 90 days before expiry, and
the final one-day reminder is fixed.

Tap + or − to move one day. Press and hold to move through several days. The
control stops at a valid boundary. At 90 days, **Maximum reached** remains
visible below the first warning until you reduce it.

After the last valid day adjustment, Akshi shows a subtly highlighted
three-second countdown—3, 2, 1—so you can finish adjusting the values. It has
no buttons, and another valid adjustment restarts it. The notice disappears
before confirmation opens. You can then update the reminder schedule or cancel
and restore the saved values.

Akshi keeps only reminder times that are still in the future. A warning that
has already passed for one domain does not prevent valid warnings for other
domains from being scheduled. If there are currently no upcoming reminders,
your settings remain saved and Akshi will use them when a future saved expiry
matches.

### Change reminder time

The time picker provides **Cancel** and **OK**. Cancel leaves the saved time
unchanged. OK proceeds directly to reminder confirmation without the
day-change pause.

### Understand reminder status

Akshi shows its reminder switch separately from the operating system's
notification permission. Turning reminders off in Akshi removes its scheduled
expiry alerts; it does not stop domain checks or change the system permission.

The Reminder Ledger shows Akshi's local history for scheduled expiry reminders.
It can help confirm that a reminder was prepared and was still known to the
device, but it cannot prove that Android or iOS displayed it. If reminder health
needs attention, use **Repair reminders** and review the result.

## Privacy and network access

Your portfolio, saved results, tags, preferences, cached site icons, and crash
reports remain in the app's private storage. Akshi has no sign-up, analytics,
advertising, tracking SDK, cloud database, remote scoring service, or
Akshi-operated API. Nothing is sent to Aliyesha.

Checks still require internet access. Depending on the checks you enable, Akshi
can contact public registration services, your configured TLS or website
endpoint, the device's DNS resolver, and a domain's published MTA-STS policy
site. Those services can observe ordinary connection information such as your
IP address and the requested domain.

Akshi does not use a third-party favicon proxy or a public DNS-over-HTTPS
provider. Open **Settings → Network destinations** to see the kinds of
destinations the app can contact and the destinations derived from your saved
domains.

Read the complete [Akshi Privacy Policy](PRIVACY.md) for storage, retention,
network recipients, backups, and contact information.

## When information is unavailable

A registry might not publish an expiry date, and network, DNS, firewall, or TLS
problems can prevent a check. Akshi keeps the last useful result when possible
and shows the latest problem instead of presenting a failed lookup as new
evidence.

If the device is offline before a check starts, Akshi continues to show saved
values and explains that the network is unavailable. Try again on a reliable
connection before treating an unavailable result as a domain, certificate, DNS,
or email problem.

A confirmed **Not published** DNS result is different from a failed lookup.
Likewise, one unavailable Email record does not mean every other email result
failed.

## If adding or editing fails

Akshi requires a connection before adding or changing a domain. If a remote
source fails during the check, the domain can still show a clear unavailable
result that you can refresh later.

A validation or device-storage error prevents the change from being saved.
Correct the value or follow the message shown by Akshi, then try again.

## If a reminder does not appear

Check these items:

1. Reminders are enabled in Akshi.
2. **Expiry reminders** is enabled for the affected domain.
3. The operating system allows notifications for Akshi.
4. The saved registration or certificate has a usable future expiry date.
5. The Reminder Ledger shows the expected date.

Android and iOS can delay local notifications because of battery policy, Focus
modes, or notification settings. Use **Repair reminders** when Settings reports
that reminder health needs attention. The ledger can help diagnose scheduling,
but it cannot prove delivery.

## Crash reports

If Akshi encounters an unexpected error, it can save a private diagnostic on
the device. Akshi does not upload it. Open **Settings → Crash reports** to read,
copy, or delete reports. A report can help investigate a later problem, but it
does not guarantee that the app can recover from the error that created it.
