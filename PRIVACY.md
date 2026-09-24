# Akshi Privacy Policy

**Effective date:** 31 August 2026

Akshi is developed and maintained by aliyesha.com (Aliyesha). This policy
explains what the application stores, which external systems it contacts, and
the choices available to you. Questions may be sent to
[ops@aliyeshamail.com](mailto:ops@aliyeshamail.com).

## Summary

Akshi has no account system, analytics, advertising, tracking SDK, or central
monitoring server. Aliyesha does not receive your monitor list, check results,
diagnostic reports, or notification history. The application performs checks
directly from your device while it is active.

## Information stored on your device

Akshi stores the following information in its private application storage:

- domains, optional display names, tags, and selected checks;
- TLS hostnames, ports, certificate observations, and registration results;
- DNS records, published email-domain configuration, and check history;
- locally cached website icons;
- reminder, notification, and appearance preferences;
- reminder-ledger snapshots containing alarm dates, domains, Domain/TLS expiry
  reasons, platform details, and scheduling/verification timestamps; and
- bounded local crash diagnostics containing the time, error type, message,
  technical context, stack trace, and operating-system version.

Crash diagnostics are stored separately from the monitor database and are
limited to the 50 most recent entries. They are never uploaded automatically.
You may inspect, copy, or delete individual reports, or clear all reports, from
Settings.

Akshi's console logging is intended for local development and troubleshooting.
The application does not transmit or retain those console logs. A device,
development tool, or operating system may retain logs under its own controls.

## Network activity

Akshi uses network access only to perform checks selected by you. Depending on
the enabled checks, it may contact:

- `https://data.iana.org/rdap/dns.json` and the registry RDAP services listed
  in that document;
- the TLS hostname and port configured for a monitor;
- HTTPS pages and icon URLs on the configured website;
- the DNS resolver configured by the device or network; and
- `https://mta-sts.<domain>/.well-known/mta-sts.txt` when the domain publishes
  an MTA-STS record.

These operators can receive ordinary connection information such as your IP
address, the requested domain name, request time, and protocol metadata. Their
handling of that information is governed by their own policies. Akshi does not
send this information through an Aliyesha proxy or API.

Akshi does not use a public DNS-over-HTTPS provider, favicon proxy, remote
scoring service, font service, update tracker, or telemetry endpoint.

## Notifications

Only Domain-registration and TLS-certificate expiry notifications are
calculated and scheduled on the device. Akshi requests notification permission
through the operating system. It does not use push-notification infrastructure
or send notification or reminder-ledger data to Aliyesha.

The local Reminder Ledger records what Akshi computed, handed to the platform,
and later found in pending notification inventory. It does not prove delivery.
You may inspect a domain-bearing snapshot in Settings and explicitly copy a
proof receipt that omits raw payloads and internal monitor IDs.

## Backups

Akshi opts its private application data out of Android and iOS device and cloud
backups. Operating-system modifications, rooted or jailbroken devices,
developer tools, or copies made explicitly by the device owner can operate
outside these application controls.

## Retention and deletion

Monitor data remains on the device until you delete the corresponding monitor
or remove the application. Reminder-ledger revisions are retained for at most
365 days and are capped at 1,000 entries. Crash diagnostics remain until
removed by you or discarded by the 50-entry retention limit. Uninstalling the application
normally removes its private data, subject to operating-system behavior.

Akshi has no server-side copy to retrieve, export, correct, or delete. You can
copy individual technical values, reminder proof receipts, and crash reports
through the application.

## Children and sensitive information

Akshi is a technical operations utility and is not directed specifically at
children. Aliyesha does not knowingly collect personal information through
Akshi. Avoid placing confidential or personal information in monitor names,
tags, or diagnostic reports that you choose to share.

## Policy changes

Material changes to this policy will be published with the corresponding
source release and noted in the project changelog. The effective date above
identifies the current policy version.
