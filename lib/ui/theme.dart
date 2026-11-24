/// One dark palette, used everywhere so the screens feel like one app.
library;

import 'package:flutter/material.dart';

const Color kBg = Color(0xFF0A111C);
const Color kSurface = Color(0xFF131C2B);
const Color kSurfaceAlt = Color(0xFF1B2638);
const Color kLine = Color(0xFF2A3A52);
const Color kAccent = Color(0xFF22D3EE);
const Color kAccentDeep = Color(0xFF6366F1);
const Color kGood = Color(0xFF34D399);
const Color kWarn = Color(0xFFFBBF24);
const Color kBad = Color(0xFFFB7185);
const Color kText = Color(0xFFE8EFF9);
const Color kMuted = Color(0xFF93A4BD);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      surface: kBg,
      primary: kAccent,
      onPrimary: Color(0xFF04222A),
      secondary: kAccentDeep,
      onSecondary: Colors.white,
      error: kBad,
      onSurface: kText,
    ),
    scaffoldBackgroundColor: kBg,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: kText,
      displayColor: kText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: kText,
      ),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kLine, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: kText,
        side: const BorderSide(color: kLine),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceAlt,
      hintStyle: const TextStyle(color: kMuted),
      labelStyle: const TextStyle(color: kMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccent, width: 1.6),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: kAccent,
      inactiveTrackColor: kLine,
      thumbColor: kAccent,
      overlayColor: kAccent.withValues(alpha: 0.12),
      valueIndicatorColor: kSurfaceAlt,
      valueIndicatorTextStyle: const TextStyle(color: kText),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kSurfaceAlt,
      contentTextStyle: TextStyle(color: kText),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: kLine, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: kSurfaceAlt,
      side: const BorderSide(color: kLine),
      labelStyle: const TextStyle(color: kText, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// A small uppercase label, for section headers.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: kMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

/// A rounded, bordered panel used across the screens.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: kLine),
    ),
    child: child,
  );
}
