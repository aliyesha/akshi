import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('semantic surface text meets enhanced contrast in both themes', () {
    final schemes = <ColorScheme>[
      AkshiTheme.light.colorScheme,
      AkshiTheme.dark.colorScheme,
    ];

    for (final scheme in schemes) {
      final info = AkshiTheme.infoSurface(scheme);
      final progress = AkshiTheme.progressSurface(scheme);

      expect(
        _contrast(info.background, info.foreground),
        greaterThanOrEqualTo(7),
        reason: '${scheme.brightness.name} information surface',
      );
      expect(
        _contrast(progress.background, progress.foreground),
        greaterThanOrEqualTo(7),
        reason: '${scheme.brightness.name} progress surface',
      );
      expect(
        _contrast(info.background, info.accent),
        greaterThanOrEqualTo(3),
        reason: '${scheme.brightness.name} information icon',
      );
      expect(
        _contrast(progress.background, progress.accent),
        greaterThanOrEqualTo(3),
        reason: '${scheme.brightness.name} progress indicator',
      );
    }
  });
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}
