import 'package:flutter/material.dart';

import '../core/content/models.dart';

/// Calm, paper-and-ink palette with a single saffron-gold accent.
/// All text colours meet WCAG AA (4.5:1) against their backgrounds.
class GitaPalette {
  const GitaPalette._({
    required this.background,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.line,
    required this.brightness,
  });

  final Color background;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color accentSoft;
  final Color line;
  final Brightness brightness;

  static const light = GitaPalette._(
    background: Color(0xFFFAF6EE),
    surface: Color(0xFFFFFDF8),
    ink: Color(0xFF2A2420),
    muted: Color(0xFF6B6158),
    accent: Color(0xFF8A5A12),
    accentSoft: Color(0xFFF3E6CC),
    line: Color(0xFFE6DCCB),
    brightness: Brightness.light,
  );

  static const dark = GitaPalette._(
    background: Color(0xFF12131A),
    surface: Color(0xFF1B1D26),
    ink: Color(0xFFECE5D8),
    muted: Color(0xFFA9A196),
    accent: Color(0xFFE2AE5C),
    accentSoft: Color(0xFF3A2E1A),
    line: Color(0xFF2E313D),
    brightness: Brightness.dark,
  );
}

const _uiFallback = ['NotoSansTelugu', 'NotoSerifDevanagari'];

ThemeData buildTheme(GitaPalette c) {
  final scheme = ColorScheme(
    brightness: c.brightness,
    primary: c.accent,
    onPrimary: c.brightness == Brightness.light ? Colors.white : const Color(0xFF241A08),
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.ink,
    secondary: c.accent,
    onSecondary: c.surface,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    outline: c.line,
    outlineVariant: c.line,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: c.brightness);
  final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamilyFallback: _uiFallback);
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(color: c.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1),
    listTileTheme: ListTileThemeData(iconColor: c.muted),
    // Gentle, short transitions; no decorative animation.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

/// Text styles for scripture, by script. Sizes scale with the user's
/// "scripture text size" setting on top of the system font scale.
class ScriptureStyles {
  static TextStyle verse(BuildContext context, VerseScript script, double scale) {
    final color = Theme.of(context).colorScheme.onSurface;
    return switch (script) {
      VerseScript.devanagari => TextStyle(
        fontFamily: 'NotoSerifDevanagari',
        fontSize: 24 * scale,
        height: 1.85,
        color: color,
        fontVariations: const [FontVariation('wght', 450)],
      ),
      VerseScript.telugu => TextStyle(
        fontFamily: 'NotoSansTelugu',
        fontSize: 22 * scale,
        height: 1.9,
        color: color,
        fontVariations: const [FontVariation('wght', 420)],
      ),
      VerseScript.iast => TextStyle(fontFamily: 'NotoSerif', fontSize: 19 * scale, height: 1.7, color: color),
    };
  }

  static TextStyle transliteration(BuildContext context, double scale) => TextStyle(
    fontFamily: 'NotoSerif',
    // Danda glyphs come from the Devanagari font.
    fontFamilyFallback: const ['NotoSerifDevanagari'],
    fontSize: 16 * scale,
    height: 1.65,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle speaker(BuildContext context, VerseScript script, double scale) =>
      verse(context, script, scale * 0.72).copyWith(color: Theme.of(context).colorScheme.primary);
}
