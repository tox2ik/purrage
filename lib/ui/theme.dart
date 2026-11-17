import 'package:flutter/material.dart';

/// The palette: a near-black, low-chrome surface with one indigo accent, plain
/// grey type and hairline dividers. Everything reads as one quiet sheet, which
/// is what makes a dense list of paths easy to scan.
///
/// Contrast (WCAG, computed): `_text` on `_surface` 15.3:1; `_muted` on
/// `_surface` 5.8:1, on `_raised` 5.4:1, on the chosen tint 5.1:1, on the
/// hover 5.1:1 and on the tooltip 4.8:1 (text needs 4.5); the folder amber on
/// the chosen tint 10.1:1. `_line` on `_surface` is only 1.3:1 (a boundary
/// needs 3), so it is never the only thing that shows a control: the `git` chip
/// is told by its text.
const Color _surface = Color(0xFF0D0E10);
const Color _raised = Color(0xFF16171A);
const Color _line = Color(0xFF26282D);
const Color _text = Color(0xFFE4E5E7);
const Color _muted = Color(0xFF8A8D94);
const Color _accent = Color(0xFF6E79D6);
const Color _accentSoft = Color(0xFF232741);
const Color _danger = Color(0xFFEB5757);
const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

const ColorScheme purrageScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: _accent,
  onPrimary: _white,
  primaryContainer: _accentSoft,
  onPrimaryContainer: Color(0xFFE7EAFF),
  secondary: _muted,
  onSecondary: _black,
  secondaryContainer: _raised,
  onSecondaryContainer: _text,
  tertiary: _accent,
  onTertiary: _white,
  tertiaryContainer: _raised,
  onTertiaryContainer: _text,
  error: _danger,
  onError: _white,
  errorContainer: Color(0xFF3A1D1F),
  onErrorContainer: Color(0xFFFFD9DC),
  surface: _surface,
  onSurface: _text,
  surfaceContainerHighest: _raised,
  onSurfaceVariant: _muted,
  outline: _line,
  outlineVariant: Color(0xFF1D1F23),
  shadow: _black,
  scrim: _black,
  inverseSurface: _text,
  onInverseSurface: _surface,
  inversePrimary: _accent,
);

/// The design tokens: the only place with a colour, a font size or family, a
/// radius, an icon size, a gap or a fixed height. Widgets read these; a new look
/// is a new token here, never a number inline (a test greps `lib/ui/`).
abstract final class T {
  // Fixed heights. The file list places a row by its index
  // (`itemExtentBuilder`), so these are exact, not minimums.

  /// One file row in the Changes list.
  static const double rowHeight = 24;

  /// A section heading (`Staged (3)`) in the Changes list.
  static const double sectionHeaderHeight = 30;

  /// A pane's title strip (the ignore pane rail, the Browse bar).
  static const double paneHeaderHeight = 32;

  /// The commit bar across the bottom.
  static const double commitBarHeight = 48;

  /// A row action (`Add`, `Ignore`) inside a row.
  static const double actionHeight = 20;

  // Type. Nothing under 11 px: a dense sheet is read, not glanced at.

  /// Rows and most text.
  static const TextStyle body = TextStyle(fontSize: 12.5, height: 1.25, color: _text);

  /// Secondary text: hints, counts, labels next to a control.
  static const TextStyle small = TextStyle(fontSize: 11.5, height: 1.25, color: _muted);

  /// The smallest text: row actions, badges, chips.
  static const TextStyle tiny = TextStyle(fontSize: 11, height: 1.25, color: _muted);

  /// Section headings inside a list.
  static const TextStyle section =
      TextStyle(fontSize: 11, height: 1.25, letterSpacing: 0.7, color: _muted);

  /// Titles of a pane or a dialog.
  static const TextStyle title =
      TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w600, color: _text);

  /// Monospace: paths, rules, command lines. `monospace` is not a family
  /// DirectWrite knows, so the font is named, with fallbacks.
  static const String codeFamily = 'Consolas';
  static const List<String> codeFallback = ['Cascadia Mono', 'Courier New'];
  static const TextStyle code = TextStyle(
    fontFamily: codeFamily,
    fontFamilyFallback: codeFallback,
    fontSize: 12,
    height: 1.25,
    color: _text,
  );

  /// Monospace at the small size: the folder column, the console.
  static final TextStyle codeSmall = code.copyWith(fontSize: 11.5);

  /// Monospace at the tiny size: the status letter.
  static final TextStyle codeTiny = code.copyWith(fontSize: 11);

  // Shapes and sizes.

  static const double radiusSmall = 4;
  static const double radius = 6;
  static const double radiusPill = 999;

  static const double iconSmall = 14;
  static const double icon = 16;
  static const double iconLarge = 20;

  /// The accent bar on the cursor row and the current checkout.
  static const double barWidth = 3;

  // Gaps: 2 / 4 / 6 / 8 / 12 / 16 / 24.
  static const double gap2 = 2;
  static const double gap4 = 4;
  static const double gap6 = 6;
  static const double gap8 = 8;
  static const double gap12 = 12;
  static const double gap16 = 16;
  static const double gap24 = 24;

  // Colours with a meaning. Each is also told apart by something other than
  // colour: the cursor has its bar, a folder its trailing slash, a failure its
  // code badge.

  /// A highlighted (chosen) row: the accent container at 55 %.
  static const Color chosen = Color(0x8C232741);

  /// The cursor row when it is not chosen: the raised surface at 35 %.
  static const Color cursor = Color(0x5916171A);

  /// The checkout that is open now, in Browse: the accent container at 45 %.
  static const Color current = Color(0x73232741);

  /// Under the mouse: flat, instant, from the palette (no ripple).
  static const Color hover = Color(0xFF1A1C21);

  /// No colour: the accent bar's place on a row without the cursor.
  static const Color none = Color(0x00000000);

  /// Directories take Windows Explorer's folder amber, muted for a dark sheet.
  static const Color folder = Color(0xFFE8C46B);

  /// The tooltip's background.
  static const Color tooltip = Color(0xFF202226);

  /// The scrollbar thumb.
  static const Color thumb = Color(0xFF3A3D44);
}

/// The app theme: compact density, hairline dividers, quiet buttons, a flat
/// hover and no ripple.
ThemeData buildTheme() {
  final base = ThemeData(
    colorScheme: purrageScheme,
    useMaterial3: true,
    brightness: Brightness.dark,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: _surface,
    canvasColor: _surface,
    splashFactory: NoSplash.splashFactory,
    hoverColor: T.hover,
    highlightColor: T.none,
    splashColor: T.none,
    focusColor: T.hover,
  );

  return base.copyWith(
    dividerTheme: const DividerThemeData(color: _line, thickness: 1, space: 1),
    textTheme: base.textTheme.copyWith(
      bodyMedium: T.body,
      bodySmall: T.small,
      labelMedium: T.section,
      labelSmall: T.tiny,
      titleMedium: T.title,
    ),
    iconTheme: const IconThemeData(color: _muted, size: T.icon),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: const BoxDecoration(
        color: T.tooltip,
        borderRadius: BorderRadius.all(Radius.circular(T.radiusSmall)),
      ),
      textStyle: T.small.copyWith(color: _text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: _raised,
      hintStyle: T.small,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: T.gap8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.radius),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.radius),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.radius),
        borderSide: const BorderSide(color: _accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: T.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.radius)),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: T.body.copyWith(fontSize: 12),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(splashFactory: NoSplash.splashFactory),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.radius)),
    ),
    popupMenuTheme: const PopupMenuThemeData(color: _raised),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      thumbColor: WidgetStateProperty.all(T.thumb),
      radius: const Radius.circular(T.radiusSmall),
    ),
  );
}
