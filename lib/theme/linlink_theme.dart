import 'package:flutter/material.dart';

class LinLinkColors {
  // Neutral Canvas & Surface hierarchy (Clean Slate Charcoal)
  static const Color background = Color(0xFF0F1216);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceDim = Color(0xFF0E1116);
  static const Color surfaceBright = Color(0xFF212631);

  // Surface containers (elevation stepping)
  static const Color surfaceContainerLowest = Color(0xFF0A0D11);
  static const Color surfaceContainerLow = Color(0xFF13171E);
  static const Color surfaceContainer = Color(0xFF191F28);
  static const Color surfaceContainerHigh = Color(0xFF222935);
  static const Color surfaceContainerHighest = Color(0xFF2C3544);
  static const Color surfaceVariant = Color(0xFF222935);

  // Text & Content
  static const Color onSurface = Color(0xFFF1F5F9);
  static const Color onSurfaceVariant = Color(0xFF94A3B8);
  static const Color onBackground = Color(0xFFF1F5F9);
  static const Color outline = Color(0xFF3B4454);
  static const Color outlineVariant = Color(0xFF262E3B);

  // Primary Accent - Technical Azure Blue (High legibility, utilitarian, non-neon)
  static const Color primary = Color(0xFF4B8EFF);
  static const Color primaryContainer = Color(0xFF1E3A68);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFD6E4FF);
  static const Color surfaceTint = Color(0xFF4B8EFF);
  static const Color inversePrimary = Color(0xFF2563EB);

  // Success / Connected / Active status (Terminal Green)
  static const Color secondary = Color(0xFF10B981);
  static const Color secondaryContainer = Color(0xFF064E3B);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFFA7F3D0);

  // Warning / Attention
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFF78350F);

  // Destructive / Error / Disconnect
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFF7F1D1D);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFFFEE2E2);
  static const Color tertiary = Color(0xFF94A3B8);
  static const Color tertiaryContainer = Color(0xFF334155);
}

class LinLinkTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: LinLinkColors.background,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: LinLinkColors.primary,
        onPrimary: LinLinkColors.onPrimary,
        primaryContainer: LinLinkColors.primaryContainer,
        onPrimaryContainer: LinLinkColors.onPrimaryContainer,
        secondary: LinLinkColors.secondary,
        onSecondary: LinLinkColors.onSecondary,
        secondaryContainer: LinLinkColors.secondaryContainer,
        onSecondaryContainer: LinLinkColors.onSecondaryContainer,
        error: LinLinkColors.error,
        onError: LinLinkColors.onError,
        errorContainer: LinLinkColors.errorContainer,
        onErrorContainer: LinLinkColors.onErrorContainer,
        surface: LinLinkColors.surface,
        onSurface: LinLinkColors.onSurface,
        onSurfaceVariant: LinLinkColors.onSurfaceVariant,
        outline: LinLinkColors.outline,
        outlineVariant: LinLinkColors.outlineVariant,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: LinLinkColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: LinLinkColors.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: LinLinkColors.onSurface, size: 20),
      ),
      cardTheme: CardThemeData(
        color: LinLinkColors.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: LinLinkColors.outlineVariant, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LinLinkColors.surfaceContainer,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: LinLinkColors.outlineVariant, width: 1),
        ),
        titleTextStyle: const TextStyle(
          color: LinLinkColors.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: LinLinkColors.onSurfaceVariant,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LinLinkColors.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: LinLinkColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: LinLinkColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: LinLinkColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: LinLinkColors.onSurfaceVariant, fontSize: 13),
        hintStyle: const TextStyle(color: LinLinkColors.outline, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LinLinkColors.primary,
          foregroundColor: LinLinkColors.onPrimary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LinLinkColors.onSurface,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          side: const BorderSide(color: LinLinkColors.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LinLinkColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LinLinkColors.surfaceContainerHighest,
        contentTextStyle: const TextStyle(color: LinLinkColors.onSurface, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: LinLinkColors.outlineVariant),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: LinLinkColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return LinLinkColors.onPrimary;
          }
          return LinLinkColors.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return LinLinkColors.primary;
          }
          return LinLinkColors.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
