import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Transit-inspired typography using the bundled Inter family.
/// Display: compact bold. Text: natural spacing and a legible line height.
abstract class AppTextStyles {
  AppTextStyles._();

  // ── Display ───────────────────────────────────────────────────────────
  static const TextStyle displayLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -1.1,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
    height: 1.2,
  );

  // ── Headings ──────────────────────────────────────────────────────────
  static const TextStyle headingLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.3,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  // ── Body ─────────────────────────────────────────────────────────────
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.5,
  );

  // ── Labels & Caps ────────────────────────────────────────────────────
  static const TextStyle labelLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
    letterSpacing: 0.4,
  );

  static const TextStyle capsLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
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

  static const TextStyle moneyLarge = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'Inter',
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
  );

  static const TextStyle moneyMedium = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle distanceBadge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.accent,
    letterSpacing: 0.3,
  );

  // ── Material TextTheme ────────────────────────────────────────────────
  static TextTheme get textTheme => const TextTheme(
    displayLarge:  displayLarge,
    displayMedium: displayMedium,
    titleLarge: headingMedium,
    titleMedium: headingSmall,
    titleSmall: labelLarge,
    labelMedium: labelLarge,
    headlineLarge: headingLarge,
    headlineMedium: headingMedium,
    headlineSmall: headingSmall,
    bodyLarge:     bodyLarge,
    bodyMedium:    bodyMedium,
    bodySmall:     bodySmall,
    labelLarge:    labelLarge,
    labelSmall:    labelSmall,
  );
}
