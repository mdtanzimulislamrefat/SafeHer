import 'package:flutter/material.dart';

/// Colour tokens from the "Ink & Paper" design (Figma page v2).
abstract final class SafeColors {
  static const paper = Color(0xFFFAF6F1);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F1A24);
  static const muted = Color(0xFF6B6270);
  // Too light for text on paper (under 4.5:1); use for icons and dividers only.
  static const faint = Color(0xFF9A919E);
  static const line = Color(0xFFE8E0D7);
  static const plum = Color(0xFF4B1D6B);
  static const plumSoft = Color(0xFFEFE6F4);
  static const red = Color(0xFFD7263D);
  static const redDeep = Color(0xFF9E1328);
  static const redSoft = Color(0xFFFCE4E6);
  static const green = Color(0xFF1E7A4F);
  static const amber = Color(0xFFA85A06);
  static const amberSoft = Color(0xFFFBEBD3);
  static const teal = Color(0xFF0F5E63);
  static const tealSoft = Color(0xFFDDEDEE);

  /// The logo's dot only; never used for text or status.
  static const amberMark = Color(0xFFF2B544);
}

abstract final class SafeText {
  /// Anek Bangla is a variable font, so weight is set through its axis.
  static TextStyle heading(double size, {Color color = SafeColors.ink}) {
    return TextStyle(
      fontFamily: 'AnekBangla',
      fontSize: size,
      height: 1.15,
      letterSpacing: -0.3,
      color: color,
      fontVariations: const [FontVariation('wght', 600)],
    );
  }

  static const body = TextStyle(fontSize: 15, height: 1.5, color: SafeColors.ink);
  static const bodyStrong = TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600, color: SafeColors.ink);
  static const small = TextStyle(fontSize: 13, height: 1.45, color: SafeColors.muted);
  static const caption = TextStyle(fontSize: 12, height: 1.4, color: SafeColors.muted);
  static const section = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    color: SafeColors.muted,
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: SafeColors.plum,
    onPrimary: Colors.white,
    primaryContainer: SafeColors.plumSoft,
    onPrimaryContainer: SafeColors.plum,
    secondary: SafeColors.teal,
    onSecondary: Colors.white,
    error: SafeColors.red,
    onError: Colors.white,
    surface: SafeColors.paper,
    onSurface: SafeColors.ink,
    onSurfaceVariant: SafeColors.muted,
    outline: SafeColors.line,
    outlineVariant: SafeColors.line,
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const buttonText = TextStyle(fontFamily: 'HindSiliguri', fontSize: 16, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'HindSiliguri',
    scaffoldBackgroundColor: SafeColors.paper,
    dividerTheme: const DividerThemeData(color: SafeColors.line, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: SafeColors.paper,
      foregroundColor: SafeColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: buttonShape, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: buttonShape,
        textStyle: buttonText,
        foregroundColor: SafeColors.ink,
        backgroundColor: SafeColors.card,
        side: const BorderSide(color: SafeColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SafeColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SafeColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SafeColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SafeColors.paper,
      indicatorColor: SafeColors.plumSoft,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? SafeColors.plum : SafeColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? SafeColors.plum : SafeColors.faint),
      ),
    ),
    switchTheme: SwitchThemeData(trackOutlineColor: WidgetStateProperty.all(Colors.transparent)),
  );
}
