class _CertificateName {
  const _CertificateName._(this.attributes);

  final Map<String, List<String>> attributes;

  factory _CertificateName.parse(String distinguishedName) {
    final input = distinguishedName.trim();
    final matches = RegExp(r'(?:^|[/,])\s*([A-Za-z][A-Za-z0-9.]*)\s*=\s*')
        .allMatches(input)
        .toList(growable: false);
    final attributes = <String, List<String>>{};
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final key = match.group(1)!.toUpperCase();
      final end = index + 1 < matches.length
          ? matches[index + 1].start
          : input.length;
      final value = _cleanValue(input.substring(match.end, end));
      if (value.isNotEmpty) {
        attributes.putIfAbsent(key, () => <String>[]).add(value);
      }
    }
    return _CertificateName._(attributes);
  }

  String? get commonName => _first('CN');
  String? get organization => _first('O');
  List<String> get organizationalUnits => attributes['OU'] ?? const <String>[];
  String? get locality => _first('L');
  String? get state => _first('ST');
  String? get country => _first('C');

  String? _first(String key) {
    final values = attributes[key];
    return values == null || values.isEmpty ? null : values.first;
  }
}

String formatCertificateSubject(String distinguishedName) {
  final input = distinguishedName.trim();
  if (input.isEmpty) return 'Unknown subject';
  final name = _CertificateName.parse(input);
  return name.commonName ?? name.organization ?? _summarize(name) ?? input;
}

String formatCertificateIssuer(String distinguishedName) {
  final input = distinguishedName.trim();
  if (input.isEmpty) return 'Unknown issuer';
  final name = _CertificateName.parse(input);
  return _summarize(name) ?? input;
}

String? _summarize(_CertificateName name) {
  final values = <String>[
    ?name.organization,
    ?name.commonName,
    ...name.organizationalUnits,
    ?name.locality,
    ?name.state,
    ?name.country,
  ];
  final seen = <String>{};
  final unique = values
      .where((value) => seen.add(value.toLowerCase()))
      .toList();
  return unique.isEmpty ? null : unique.join(' · ');
}

String _cleanValue(String raw) {
  var value = raw.trim();
  final quote = String.fromCharCode(34);
  if (value.length >= 2 && value.startsWith(quote) && value.endsWith(quote)) {
    value = value.substring(1, value.length - 1).trim();
  }
  final escape = String.fromCharCode(92);
  return value
      .replaceAll('$escape,', ',')
      .replaceAll('$escape/', '/')
      .replaceAll('$escape=', '=');
}
