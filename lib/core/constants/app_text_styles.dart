import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Transit-inspired typography using the bundled Inter family.
///
/// **Do not bake light-mode colors into these styles.** Color comes from
/// [ThemeData.textTheme] / [DefaultTextStyle] so light and dark both work.
/// Override with `ZivoPalette.of(context)` when you need muted / accent roles.
abstract class AppTextStyles {
  AppTextStyles._();

  // ── Display ───────────────────────────────────────────────────────────
  static const TextStyle displayLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.1,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.2,
  );

  // ── Headings ──────────────────────────────────────────────────────────
  static const TextStyle headingLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.3,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  // ── Body ─────────────────────────────────────────────────────────────
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ── Labels & Caps ────────────────────────────────────────────────────
  static const TextStyle labelLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );

  static const TextStyle capsLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  // ── Special ───────────────────────────────────────────────────────────
  static const TextStyle buttonLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.0,
  );

  static const TextStyle otpDigit = TextStyle(
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.otpText,
    letterSpacing: 8,
  );

  /// Wallet page hero balance — same on phone & desktop (was 36–40).
  static const TextStyle moneyHero = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.1,
  );

  /// Alias kept for older call sites.
  static const TextStyle moneyLarge = moneyHero;

  /// Compact strip values (Total Earned / Jobs / Rating / escrow pills).
  static const TextStyle moneyStat = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.15,
  );

  static const TextStyle moneyStatLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Medium emphasis (review totals, earnings callouts).
  static const TextStyle moneyMedium = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.15,
  );

  /// Top-bar wallet pill + inline meta.
  static const TextStyle moneyMeta = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    height: 1.1,
  );

  /// Page titles: slightly smaller on narrow screens for balance.
  static TextStyle pageTitle(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return displayMedium.copyWith(
      fontSize: wide ? 28 : 24,
      height: 1.15,
      letterSpacing: -0.8,
      fontWeight: FontWeight.w800,
    );
  }

  static const TextStyle distanceBadge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.accent,
    letterSpacing: 0.3,
  );

  // ── Material TextTheme (colors applied in AppTheme via .apply) ─────────
  static TextTheme get textTheme => const TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        titleLarge: headingMedium,
        titleMedium: headingSmall,
        titleSmall: labelLarge,
        labelMedium: labelLarge,
        headlineLarge: headingLarge,
        headlineMedium: headingMedium,
        headlineSmall: headingSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelSmall: labelSmall,
      );
}
