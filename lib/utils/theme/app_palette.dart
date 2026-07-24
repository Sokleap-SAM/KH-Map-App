import 'package:flutter/material.dart';

import '../constants/colors.dart';

/// App-specific semantic color tokens that adapt to light/dark mode.
///
/// The rider screens were originally built with a hardcoded navy/white "dark"
/// palette. Rather than scatter `isDarkMode ? ... : ...` checks across every
/// widget, those raw colors are replaced with the tokens below, defined once
/// for [light] and once for [dark]. Read them in widgets via
/// `Theme.of(context).extension<AppPalette>()!` or the `context.palette`
/// shortcut in this file.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.scaffold,
    required this.surface,
    required this.surfaceAlt,
    required this.gradientStart,
    required this.gradientEnd,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.textFaintest,
    required this.accent,
    required this.onAccent,
    required this.subtitle,
  });

  /// Page background.
  final Color scaffold;

  /// Card / sheet / dialog / popup-menu background.
  final Color surface;

  /// Secondary surface: unselected chips, tab buttons, input fills.
  final Color surfaceAlt;

  /// Banner gradient endpoints (top-left → bottom-right).
  final Color gradientStart;
  final Color gradientEnd;

  /// Hairline borders around cards and inputs.
  final Color border;

  /// Divider lines inside surfaces.
  final Color divider;

  /// Primary body text / icons.
  final Color textPrimary;

  /// Secondary text (subtitles, less-emphasised labels).
  final Color textSecondary;

  /// Faint text/icons (hints, metadata).
  final Color textFaint;

  /// Faintest text/icons (disabled, decorative).
  final Color textFaintest;

  /// Gold brand accent (fills, selected states, progress indicators).
  final Color accent;

  /// Text/icon color drawn on top of [accent].
  final Color onAccent;

  /// Blue-ish subtitle used under headers.
  final Color subtitle;

  static const AppPalette light = AppPalette(
    scaffold: Colors.white,
    surface: Color(0xFFF2F5FA),
    surfaceAlt: Color(0xFFE8EEF6),
    gradientStart: Colors.white,
    gradientEnd: Color(0xFFF0F4F8),
    border: Colors.black12,
    divider: Colors.black12,
    textPrimary: Colors.black87,
    textSecondary: Colors.black54,
    textFaint: Colors.black45,
    textFaintest: Colors.black38,
    accent: AppColors.secondaryColor,
    onAccent: AppColors.primaryColor,
    subtitle: Color(0xFF5C7AB3),
  );

  static const AppPalette dark = AppPalette(
    scaffold: AppColors.primaryColor,
    surface: Color(0xFF243456),
    surfaceAlt: Color(0xFF1A2A4C),
    gradientStart: Color(0xFF243456),
    gradientEnd: Color(0xFF1A2A4C),
    border: Colors.white12,
    divider: Colors.white24,
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textFaint: Colors.white54,
    textFaintest: Colors.white38,
    accent: AppColors.secondaryColor,
    onAccent: AppColors.primaryColor,
    subtitle: AppColors.secondaryTextColor,
  );

  @override
  AppPalette copyWith({
    Color? scaffold,
    Color? surface,
    Color? surfaceAlt,
    Color? gradientStart,
    Color? gradientEnd,
    Color? border,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? textFaintest,
    Color? accent,
    Color? onAccent,
    Color? subtitle,
  }) {
    return AppPalette(
      scaffold: scaffold ?? this.scaffold,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textFaint: textFaint ?? this.textFaint,
      textFaintest: textFaintest ?? this.textFaintest,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      textFaintest: Color.lerp(textFaintest, other.textFaintest, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      subtitle: Color.lerp(subtitle, other.subtitle, t)!,
    );
  }
}

/// Convenience access to the active [AppPalette] from any widget context.
///
/// Falls back to the palette matching the theme's brightness when the
/// extension is missing (e.g. a stale ThemeData surviving a hot reload, or a
/// context above the MaterialApp) instead of crashing on a null check.
extension AppPaletteX on BuildContext {
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}
