import 'package:flutter/material.dart';

/// The palette: a near-black, low-chrome surface with one indigo accent, plain
/// grey type and hairline dividers. Everything reads as one quiet sheet, which
/// is what makes a dense list of paths easy to scan.
const Color _surface = Color(0xFF0D0E10);
const Color _raised = Color(0xFF16171A);
const Color _line = Color(0xFF26282D);
const Color _text = Color(0xFFE4E5E7);
const Color _muted = Color(0xFF8A8D94);
const Color _accent = Color(0xFF6E79D6);
const Color _accentSoft = Color(0xFF232741);
const Color _danger = Color(0xFFEB5757);

/// Directories take Windows Explorer's folder amber, muted for a dark sheet.
const Color purrageFolder = Color(0xFFE8C46B);

const ColorScheme purrageScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: _accent,
  onPrimary: Colors.white,
  primaryContainer: _accentSoft,
  onPrimaryContainer: Color(0xFFE7EAFF),
  secondary: _muted,
  onSecondary: Colors.black,
  secondaryContainer: _raised,
  onSecondaryContainer: _text,
  tertiary: _accent,
  onTertiary: Colors.white,
  tertiaryContainer: _raised,
  onTertiaryContainer: _text,
  error: _danger,
  onError: Colors.white,
  errorContainer: Color(0xFF3A1D1F),
  onErrorContainer: Color(0xFFFFD9DC),
  surface: _surface,
  onSurface: _text,
  surfaceContainerHighest: _raised,
  onSurfaceVariant: _muted,
  outline: _line,
  outlineVariant: Color(0xFF1D1F23),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: _text,
  onInverseSurface: _surface,
  inversePrimary: _accent,
);

// Linear-style type: small, tight, no drama.
const _rows = TextStyle(fontSize: 12.5, height: 1.25, color: _text);

/// The app theme: compact density, hairline dividers, quiet buttons.
ThemeData buildTheme() {
  final base = ThemeData(
    colorScheme: purrageScheme,
    useMaterial3: true,
    brightness: Brightness.dark,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: _surface,
    canvasColor: _surface,
  );

  return base.copyWith(
    dividerTheme: const DividerThemeData(color: _line, thickness: 1, space: 1),
    textTheme: base.textTheme.copyWith(
      bodyMedium: _rows,
      bodySmall: _rows.copyWith(fontSize: 11.5, color: _muted),
      labelMedium: _rows.copyWith(fontSize: 10.5, letterSpacing: 0.7, color: _muted),
      labelSmall: _rows.copyWith(fontSize: 10, color: _muted),
      titleMedium: _rows.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    iconTheme: const IconThemeData(color: _muted, size: 18),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: Color(0xFF202226),
        borderRadius: BorderRadius.all(Radius.circular(5)),
      ),
      textStyle: TextStyle(fontSize: 11.5, color: _text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: _raised,
      hintStyle: const TextStyle(fontSize: 12, color: _muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    popupMenuTheme: const PopupMenuThemeData(color: _raised),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      thumbColor: WidgetStateProperty.all(const Color(0xFF3A3D44)),
      radius: const Radius.circular(3),
    ),
  );
}
