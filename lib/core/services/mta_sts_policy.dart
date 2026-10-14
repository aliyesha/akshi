/// The validated fields Akshi uses from an RFC 8461 policy document.
final class MtaStsPolicy {
  const MtaStsPolicy._({
    required this.mode,
    required this.maxAgeSeconds,
    required this.mxPatterns,
  });

  /// Largest policy lifetime permitted by RFC 8461 section 3.2.
  static const maximumAgeSeconds = 31557600;
  static final _maxAgeSyntax = RegExp(r'^[0-9]{1,10}$');
  static final _fieldNameSyntax = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$');
  static final _domainLabel = RegExp(
    r'^(?!-)[a-z0-9-]{1,63}(?<!-)$',
    caseSensitive: false,
  );

  /// Parses one policy, returning null when its required syntax is invalid.
  ///
  /// Unknown extension fields are accepted. In accordance with RFC 8461,
  /// later occurrences of a non-repeatable field are ignored; every `mx`
  /// occurrence is retained, and at least one is required unless mode
  /// is `none`.
  static MtaStsPolicy? tryParse(String source) {
    final fields = <String, List<String>>{};
    final lines = source.split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index];
      if (rawLine.isEmpty) {
        if (index == lines.length - 1) continue;
        return null;
      }
      final separator = rawLine.indexOf(':');
      if (separator < 1) return null;
      final name = rawLine.substring(0, separator);
      final value = rawLine.substring(separator + 1).trim();
      if (!_fieldNameSyntax.hasMatch(name) || value.isEmpty) return null;
      final values = fields.putIfAbsent(name, () => <String>[]);
      if (name == 'mx' || values.isEmpty) values.add(value);
    }

    String? firstValue(String name) => fields[name]?.firstOrNull;

    if (firstValue('version') != 'STSv1') return null;
    final mode = firstValue('mode');
    if (mode == null ||
        !const <String>{'none', 'testing', 'enforce'}.contains(mode)) {
      return null;
    }
    final maxAgeText = firstValue('max_age');
    if (maxAgeText == null || !_maxAgeSyntax.hasMatch(maxAgeText)) return null;
    final maxAge = int.parse(maxAgeText);
    if (maxAge > maximumAgeSeconds) return null;

    final mxPatterns = fields['mx'] ?? const <String>[];
    if (mxPatterns.any((pattern) => !_isValidMxPattern(pattern)) ||
        (mode != 'none' && mxPatterns.isEmpty)) {
      return null;
    }
    return MtaStsPolicy._(
      mode: mode,
      maxAgeSeconds: maxAge,
      mxPatterns: List<String>.unmodifiable(mxPatterns),
    );
  }

  static bool _isValidMxPattern(String pattern) {
    final domain = pattern.startsWith('*.') ? pattern.substring(2) : pattern;
    if (domain.isEmpty || domain.length > 253) return false;
    return domain.split('.').every(_domainLabel.hasMatch);
  }

  /// Whether receiving MTAs should enforce, test, or disable the policy.
  final String mode;

  /// Maximum sender cache lifetime in seconds.
  final int maxAgeSeconds;

  /// Repeated MX hostname patterns published by the policy.
  final List<String> mxPatterns;
}
