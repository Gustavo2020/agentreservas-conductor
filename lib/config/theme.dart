import 'package:flutter/material.dart';

/// Paleta de colores y tema GEB para la app del conductor.
class AppTheme {
  AppTheme._();

  // ── Colores ────────────────────────────────────────────────────────────────
  static const Color primary       = Color(0xFFE8A020);
  static const Color background    = Color(0xFF1A1E25);
  static const Color surface       = Color(0xFF252A33);
  static const Color onPrimary     = Color(0xFFFFFFFF);
  static const Color onBackground  = Color(0xFFE5E7EB);
  static const Color error         = Color(0xFFEF4444);
  static const Color success       = Color(0xFF10B981);
  static const Color warning       = Color(0xFFF59E0B);
  static const Color onSurface     = Color(0xFFCBD5E1);
  static const Color divider       = Color(0xFF374151);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      background: background,
      onBackground: onBackground,
      surface: surface,
      onSurface: onSurface,
      error: error,
      onError: onPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onBackground,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: onBackground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      labelStyle: const TextStyle(color: onSurface),
      hintStyle: TextStyle(color: onSurface.withOpacity(0.5)),
    ),
    dividerTheme: const DividerThemeData(color: divider),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: onBackground),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primary.withOpacity(0.2),
      labelStyle: const TextStyle(color: onBackground),
      side: const BorderSide(color: Color(0xFF374151)),
    ),
  );
}
