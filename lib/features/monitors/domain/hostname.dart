String normalizeHostname(String input) {
  final trimmed = input.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  return (uri?.host ?? '').replaceFirst(RegExp(r'\.$'), '');
}

String? validateHostname(String input) {
  final host = normalizeHostname(input);
  if (host.isEmpty) return 'Enter a domain or hostname';
  if (host.length > 253) return 'Hostname is too long';
  final labels = host.split('.');
  final validLabel = RegExp(r'^(?!-)[a-z0-9-]{1,63}(?<!-)$');
  if (labels.any((label) => !validLabel.hasMatch(label))) {
    return 'Enter a valid hostname';
  }
  return null;
}
