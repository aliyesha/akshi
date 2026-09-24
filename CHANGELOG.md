# Changelog

All notable changes to Akshi are documented in this file. The project follows
semantic versioning for public releases.

## [1.0.0] - 2026-08-31

### Added

- Local-first monitoring for domain registration and X.509 certificates.
- DNS snapshots and factual email-domain checks for MX, SPF, DMARC, MTA-STS,
  TLS-RPT, and explicit DKIM selectors.
- Consolidated local Domain/TLS expiry reminders with one alarm per calendar
  date, incremental verification, bounded repair, and a local proof ledger.
- Domain, TLS, email, and DNS detail views with focused attention navigation.
- User-created color tags, local crash diagnostics, and light/dark themes.
- Direct RDAP, DNS, TLS, favicon, and MTA-STS checks without an Akshi server.
