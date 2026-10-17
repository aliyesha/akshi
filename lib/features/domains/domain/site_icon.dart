import 'dart:typed_data';

enum SiteIconFormat {
  svg,
  png,
  jpeg,
  ico,
  webp,
  gif,
  bmp;

  String get storageValue => name;

  static SiteIconFormat fromStorage(String value) => values.firstWhere(
    (candidate) => candidate.storageValue == value,
    orElse: () => SiteIconFormat.png,
  );
}

class SiteIcon {
  const SiteIcon({
    required this.format,
    required this.bytes,
    required this.sourceUrl,
    required this.checkedAt,
  });

  final SiteIconFormat format;
  final Uint8List bytes;
  final String sourceUrl;
  final DateTime checkedAt;
}
