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
      final semanticSurfaces = <String, AkshiSurfaceColors>{
        'information': AkshiTheme.infoSurface(scheme),
        'success': AkshiTheme.successSurface(scheme),
        'warning': AkshiTheme.warningSurface(scheme),
        'error': AkshiTheme.errorSurface(scheme),
      };
      final progress = AkshiTheme.progressSurface(scheme);

      for (final entry in semanticSurfaces.entries) {
        expect(
          _contrast(entry.value.background, entry.value.foreground),
          greaterThanOrEqualTo(7),
          reason: '${scheme.brightness.name} ${entry.key} surface',
        );
        expect(
          _contrast(entry.value.background, entry.value.accent),
          greaterThanOrEqualTo(3),
          reason: '${scheme.brightness.name} ${entry.key} icon',
        );
      }
      expect(
        _contrast(progress.background, progress.foreground),
        greaterThanOrEqualTo(7),
        reason: '${scheme.brightness.name} progress surface',
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
