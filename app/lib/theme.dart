import 'package:flutter/material.dart';

/// Melopet palette — pastel pink as the brand colour, with a mint complement
/// (opposite on the colour wheel), lavender as an analogous accent and a deep
/// plum for text/dark surfaces so everything keeps WCAG-friendly contrast.
class MP {
  static const pink = Color(0xFFF4A6C0); // brand pastel pink
  static const pinkSoft = Color(0xFFFCE4EC);
  static const pinkDeep = Color(0xFFD9668F); // for icons / text on light bg
  static const mint = Color(0xFF8FD8C8); // complementary
  static const mintDeep = Color(0xFF2E9C86);
  static const lavender = Color(0xFFC7B5F2); // analogous accent
  static const lavenderDeep = Color(0xFF7C62C9);
  static const peach = Color(0xFFFFCBA8);
  static const peachDeep = Color(0xFFE08A4F);
  static const sky = Color(0xFFA9D4F5);
  static const plum = Color(0xFF3D1630); // on-pink text
  static const ink = Color(0xFF2B1F28);

  static const lightBg = Color(0xFFFFF6F9);
  static const darkBg = Color(0xFF140D13);
  static const darkSurface = Color(0xFF221620);

  static const success = Color(0xFF3FB68B);
  static const danger = Color(0xFFE5546B);
  static const warning = Color(0xFFF2A541);

  static const brandGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFFF9B8CF), Color(0xFFE79AC0), Color(0xFFC7B5F2)],
  );
}

const _font = 'Vazirmatn';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: MP.pink, brightness: b).copyWith(
    primary: dark ? const Color(0xFFF7B6CE) : MP.pinkDeep,
    onPrimary: dark ? MP.plum : Colors.white,
    primaryContainer: dark ? const Color(0xFF5A2843) : MP.pinkSoft,
    onPrimaryContainer: dark ? const Color(0xFFFFD9E6) : MP.plum,
    secondary: dark ? MP.mint : MP.mintDeep,
    onSecondary: dark ? const Color(0xFF00382F) : Colors.white,
    secondaryContainer: dark ? const Color(0xFF1F4A42) : const Color(0xFFD7F3EC),
    onSecondaryContainer: dark ? const Color(0xFFD7F3EC) : const Color(0xFF0E3B32),
    tertiary: dark ? MP.lavender : MP.lavenderDeep,
    surface: dark ? MP.darkSurface : Colors.white,
    onSurface: dark ? const Color(0xFFF5E9F0) : MP.ink,
    error: MP.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: _font,
    scaffoldBackgroundColor: dark ? MP.darkBg : MP.lightBg,
  );

  final radius = BorderRadius.circular(18);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _font),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: .06) : Colors.white.withValues(alpha: .75),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: .18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // explicit colours: the default chip text can end up dark-on-dark / light-on-light
      labelStyle: TextStyle(fontFamily: _font, color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(fontFamily: _font, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
      backgroundColor: dark ? Colors.white.withValues(alpha: .06) : Colors.white.withValues(alpha: .7),
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.primary,
      iconTheme: IconThemeData(color: scheme.onSurface.withValues(alpha: .8)),
      side: BorderSide(color: scheme.onSurface.withValues(alpha: .16)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? scheme.primaryContainer : Colors.transparent,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.onSurface.withValues(alpha: .16))),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
      contentTextStyle: const TextStyle(fontFamily: _font),
    ),
    dividerTheme: DividerThemeData(color: scheme.onSurface.withValues(alpha: .08)),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
  );
}
