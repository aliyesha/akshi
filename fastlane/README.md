# Store metadata guide

This directory is the canonical source for Akshi's upstream Android store
metadata. F-Droid can import this Fastlane-compatible structure when it builds
the application, keeping the public listing reviewable in the same repository
as the code it describes.

## Layout

    fastlane/metadata/android/en-US/
    ├── title.txt
    ├── short_description.txt
    ├── full_description.txt
    ├── changelogs/
    │   └── 1.txt
    └── images/
        ├── icon.png
        └── phoneScreenshots/
            ├── 01-portfolio.png
            ├── 02-domain-overview.png
            ├── 03-domain-registration.png
            ├── 04-tls-certificate.png
            ├── 05-dns-records.png
            ├── 06-email-configuration.png
            ├── 07-settings.png
            └── 08-reminder-ledger.png

**en-US** is the source locale. Add another complete locale directory only when
the translated copy and images can be maintained through future releases.

## Text fields

| File | Purpose | Release limit |
| --- | --- | ---: |
| **title.txt** | Public application name | 30 characters |
| **short_description.txt** | Search and list summary | 80 characters |
| **full_description.txt** | Complete product description | 4,000 characters |
| **changelogs/<versionCode>.txt** | Changes for one version code | 500 characters |

Keep these files as plain UTF-8 text. The descriptions may contain intentional
Unicode, including **akṣi (अक्षि)** and typographic punctuation. Do not add
HTML, tracking links, keyword lists, review quotations, or unsupported claims.

## Product claims that must remain true

Store copy must match the shipped application:

- Akshi is a private domain portfolio companion, not a continuous uptime
  service.
- Network checks run when the application is active: launch, foreground
  return, manual refresh, initial domain creation, or relevant configuration
  changes.
- There is no Akshi account, analytics SDK, advertising, cloud database, or
  Akshi-operated backend.
- Expiry reminders are enabled by default but remain user-controlled.
- Reminders are one-shot notifications at configured Domain/TLS warning points;
  they are not daily alarms or DNS and email change alerts.
- Email checks report published configuration facts, not reputation,
  deliverability, or guaranteed security.
- Registry fields can be incomplete, redacted, or unavailable.

The public name is **Akshi**. Its Sanskrit source is **akṣi (अक्षि)**, meaning
“eye,” and its guiding line is **Watch what matters.**

## Image requirements

- **icon.png** is the store icon and must be a 512 × 512 PNG.
- Phone screenshots must be PNG files with consistent device dimensions and no
  private notifications, accounts, or unrelated status-bar information.
- Numeric filename prefixes define display order; do not rely on filesystem or
  upload order.
- Screenshots must depict the released UI and use plausible demonstration
  domains rather than private production data.
- Keep source captures outside this directory. Only reviewed release assets
  belong in the Fastlane metadata tree.

The screenshot sequence is intentional: portfolio, domain overview,
registration, TLS certificate, DNS records, email configuration, settings, and
reminder ledger. It introduces the product before showing technical depth and
ends with its local reminder evidence.

## Review commands

Before tagging a release, inspect every text file and asset rather than relying
only on automated limits:

    wc -m \
      fastlane/metadata/android/en-US/title.txt \
      fastlane/metadata/android/en-US/short_description.txt \
      fastlane/metadata/android/en-US/full_description.txt \
      fastlane/metadata/android/en-US/changelogs/*.txt

    find fastlane/metadata/android/en-US/images/phoneScreenshots \
      -maxdepth 1 -type f -name '*.png' -print | sort

Also verify PNG dimensions with an image inspection tool available on the
release workstation and visually inspect light/dark contrast, cropping,
spelling, domain data, and screenshot order.

## Updating a release

Create a new changelog file named after the new integer version code. Preserve
older changelog files because they describe already published builds. Update
descriptions or screenshots only when the product behavior or presentation has
actually changed.

The corresponding F-Droid recipe and submission procedure are documented in
[the F-Droid release guide](../fdroid/README.md).
