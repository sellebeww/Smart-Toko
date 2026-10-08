import 'package:flutter/material.dart';

/// Warna identitas SmartToko, diambil dari logo yang disediakan pemilik.
abstract final class SmartTokoTheme {
  static const forest = Color(0xFF176448);
  static const green = Color(0xFF25834D);
  static const lime = Color(0xFFC1EE72);
  static const canvas = Color(0xFFF7F7F1);
  static const ink = Color(0xFF20382E);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: forest).copyWith(
      primary: forest,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE8F2E9),
      onPrimaryContainer: forest,
      secondary: green,
      secondaryContainer: const Color(0xFFE8F2E9),
      onSecondaryContainer: forest,
      tertiary: const Color(0xFF596C29),
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: canvas,
      surfaceContainer: const Color(0xFFF0F4EB),
      surfaceContainerHigh: const Color(0xFFEAF0E5),
      surfaceContainerHighest: const Color(0xFFE4ECDD),
      onSurface: ink,
      onSurfaceVariant: const Color(0xFF718077),
      outline: const Color(0xFF81917D),
      outlineVariant: const Color(0xFFE2E7DE),
      error: const Color(0xFFB64A35),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: ink,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 27,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
          color: ink,
        ),
        titleLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
          color: ink,
        ),
        titleMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          height: 1.5,
          color: ink,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: forest, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 54),
          shape: shape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: forest,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: canvas,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      ),
    );
  }
}
