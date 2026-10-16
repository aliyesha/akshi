import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

typedef AkshiSurfaceColors = ({
  Color background,
  Color foreground,
  Color accent,
  Color border,
});

abstract final class AkshiTheme {
  static const String uiFontFamily = 'SpaceGrotesk';
  static const String monoFontFamily = 'JetBrainsMono';
  static const Color brandCyan = Color(0xFF5893AD);
  static const Color brandPlum = Color(0xFF913160);
  static const Color brandRose = Color(0xFFBB386F);

  static Color domainMetricAccent(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF93C5FD)
      : const Color(0xFF2563EB);
  static Color certificateMetricAccent(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFC4B5FD)
      : const Color(0xFF7C3AED);
  static Color emailMetricAccent(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF5EEAD4)
      : const Color(0xFF0F766E);
  static const Color night = Color(0xFF0B090C);
  static const Color paper = Color(0xFFFBF8FA);

  static ThemeData get light => _base(brightness: Brightness.light);

  static ThemeData get dark => _base(brightness: Brightness.dark);

  /// High-contrast blue surface for neutral information and connectivity.
  static AkshiSurfaceColors infoSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? (
          background: const Color(0xFF122B36),
          foreground: const Color(0xFFEAF8FD),
          accent: const Color(0xFF8ECDE0),
          border: const Color(0xFF3B697A),
        )
      : (
          background: const Color(0xFFEAF5FA),
          foreground: const Color(0xFF153644),
          accent: const Color(0xFF28677F),
          border: const Color(0xFFA6CFDD),
        );

  /// Semantic green surface for completed actions.
  static AkshiSurfaceColors successSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? (
          background: const Color(0xFF123324),
          foreground: const Color(0xFFE8FFF0),
          accent: const Color(0xFF75D69B),
          border: const Color(0xFF3C7454),
        )
      : (
          background: const Color(0xFFE7F6ED),
          foreground: const Color(0xFF123D27),
          accent: const Color(0xFF1E7A45),
          border: const Color(0xFFA4D6B8),
        );

  /// Semantic amber surface for actions that need attention.
  static AkshiSurfaceColors warningSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? (
          background: const Color(0xFF352A0F),
          foreground: const Color(0xFFFFF4D6),
          accent: const Color(0xFFF3C75F),
          border: const Color(0xFF7A642E),
        )
      : (
          background: const Color(0xFFFFF4D8),
          foreground: const Color(0xFF4A3400),
          accent: const Color(0xFF9A6700),
          border: const Color(0xFFE0C276),
        );

  /// Semantic red surface for actions that could not be completed.
  static AkshiSurfaceColors errorSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? (
          background: const Color(0xFF3B1717),
          foreground: const Color(0xFFFFEDEA),
          accent: const Color(0xFFFFB4AB),
          border: const Color(0xFF84504C),
        )
      : (
          background: const Color(0xFFFCEBEA),
          foreground: const Color(0xFF551714),
          accent: const Color(0xFFB3261E),
          border: const Color(0xFFE3AAA6),
        );

  /// Brand-aligned surface whose text remains readable during long saves.
  static AkshiSurfaceColors progressSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? (
          background: const Color(0xFF2B1822),
          foreground: const Color(0xFFFFEAF3),
          accent: const Color(0xFFF1A1C4),
          border: const Color(0xFF70445A),
        )
      : (
          background: const Color(0xFFF6EAF0),
          foreground: const Color(0xFF3E152A),
          accent: const Color(0xFF7B2952),
          border: const Color(0xFFD7A8BD),
        );

  static ThemeData _base({required Brightness brightness}) {
    final dark = brightness == Brightness.dark;
    final theme = dark
        ? FlexThemeData.dark(
            colors: const FlexSchemeColor(
              primary: Color(0xFFE18AB2),
              secondary: Color(0xFF86C1D5),
              tertiary: Color(0xFFD878A2),
            ),
            fontFamily: uiFontFamily,
            subThemesData: _subThemes,
          )
        : FlexThemeData.light(
            colors: const FlexSchemeColor(
              primary: brandPlum,
              secondary: brandCyan,
              tertiary: brandRose,
            ),
            fontFamily: uiFontFamily,
            subThemesData: _subThemes,
          );
    final scheme = theme.colorScheme;
    return theme.copyWith(
      scaffoldBackgroundColor: dark ? night : paper,
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xFF171015)
            : const Color(0xFFF4E7ED),
        foregroundColor: dark
            ? const Color(0xFFFFEAF3)
            : const Color(0xFF44172E),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      textTheme: theme.textTheme.copyWith(
        displaySmall: theme.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          height: 1.05,
        ),
        headlineMedium: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleLarge: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleMedium: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: (100) / 255),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: (110) / 255),
        space: 1,
      ),
    );
  }

  static const FlexSubThemesData _subThemes = FlexSubThemesData(
    interactionEffects: true,
    blendOnColors: true,
    useM2StyleDividerInM3: false,
    defaultRadius: 18,
    inputDecoratorRadius: 18,
    cardRadius: 24,
    elevatedButtonRadius: 18,
    filledButtonRadius: 18,
    outlinedButtonRadius: 18,
    snackBarRadius: 16,
    dialogRadius: 28,
    bottomSheetRadius: 28,
  );
}
