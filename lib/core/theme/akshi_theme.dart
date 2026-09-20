import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AkshiTheme {
  static const String uiFontFamily = 'SpaceGrotesk';
  static const String monoFontFamily = 'JetBrainsMono';
  static const Color brandCyan = Color(0xFF5893AD);
  static const Color brandPlum = Color(0xFF913160);
  static const Color brandRose = Color(0xFFBB386F);
  static const Color night = Color(0xFF0B090C);
  static const Color paper = Color(0xFFFBF8FA);

  static ThemeData get light => _base(brightness: Brightness.light);

  static ThemeData get dark => _base(brightness: Brightness.dark);

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
