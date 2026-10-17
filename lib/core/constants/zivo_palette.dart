import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';

/// Semantic colors that flip with light / dark theme.
/// Prefer `ZivoPalette.of(context)` over hardcoded whites in new UI.
@immutable
class ZivoPalette extends ThemeExtension<ZivoPalette> {
  const ZivoPalette({
    required this.canvas,
    required this.surface,
    required this.card,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.glass,
    required this.glassSelection,
    required this.coverTint,
    required this.accent,
    required this.onAccent,
    required this.helperSoft,
  });

  final Color canvas;
  final Color surface;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color glass;
  final Color glassSelection;
  final Color coverTint;
  /// Interactive / nav / CTA — mint in light, UberX blue in dark.
  final Color accent;
  final Color onAccent;
  final Color helperSoft;

  static ZivoPalette of(BuildContext context) {
    final ext = Theme.of(context).extension<ZivoPalette>();
    return ext ?? light;
  }

  static const light = ZivoPalette(
    canvas: AppColors.backgroundDark,
    surface: AppColors.surfaceDark,
    card: Colors.white,
    border: AppColors.borderColor,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    glass: AppColors.glassSurface,
    glassSelection: AppColors.glassSelection,
    coverTint: Color(0xFFE7F5FC),
    accent: AppColors.helperAccent,
    onAccent: Colors.white,
    helperSoft: AppColors.brandGreenSoft,
  );

  /// Dark — pure black surfaces + white type + UberX blue interactive.
  /// No navy/slate tint (#09091A) — canvas stays #000000 end-to-end.
  static const dark = ZivoPalette(
    canvas: AppColors.uberBlack,
    surface: AppColors.uberBlack,
    card: Color(0xFF1A1A1A),
    border: Color(0xFF2A2A2A),
    textPrimary: Color(0xFFFFFFFF),
    // Slightly brighter than Uber muted so labels stay readable on #000.
    textSecondary: Color(0xFFE5E5E4),
    textMuted: Color(0xFFB0B0B0),
    glass: Color(0xE61A1A1A),
    glassSelection: Color(0x33276EF1),
    coverTint: AppColors.uberBlack,
    accent: AppColors.uberBlue,
    onAccent: Color(0xFFFFFFFF),
    helperSoft: Color(0xFF1A1A1A),
  );

  @override
  ZivoPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? card,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? glass,
    Color? glassSelection,
    Color? coverTint,
    Color? accent,
    Color? onAccent,
    Color? helperSoft,
  }) {
    return ZivoPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      glass: glass ?? this.glass,
      glassSelection: glassSelection ?? this.glassSelection,
      coverTint: coverTint ?? this.coverTint,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      helperSoft: helperSoft ?? this.helperSoft,
    );
  }

  @override
  ZivoPalette lerp(ThemeExtension<ZivoPalette>? other, double t) {
    if (other is! ZivoPalette) return this;
    return ZivoPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassSelection: Color.lerp(glassSelection, other.glassSelection, t)!,
      coverTint: Color.lerp(coverTint, other.coverTint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      helperSoft: Color.lerp(helperSoft, other.helperSoft, t)!,
    );
  }
}
