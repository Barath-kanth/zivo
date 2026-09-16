import 'package:flutter/material.dart';

/// Clean, minimal light theme inspired by modern mobility apps (Uber-style)
abstract class AppColors {
  AppColors._();

  // ── Backgrounds — crisp whites and light grays ─────────────────────────────
  static const Color backgroundDark  = Color(0xFFFFFFFF); // solid white
  static const Color surfaceDark     = Color(0xFFF6F6F6); // light gray surface
  static const Color cardDark        = Color(0xFFF3F3F3); // light gray card
  static const Color cardElevated    = Color(0xFFFFFFFF); // elevated white

  // ── Borders ───────────────────────────────────────────────────────────────
  static const Color borderColor     = Color(0xFFE5E5E5);
  static const Color borderActive    = Color(0xFF000000);

  // ── Accent — Classic Black (Uber primary color) ───────────────────────────
  static const Color accent          = Color(0xFF000000); 
  static const Color accentBright    = Color(0xFF333333);
  static const Color accentGlow      = Color(0xFF000000);
  static const Color accentSecondary = Color(0xFF000000); 

  // ── Helper Mode Accent — Trustworthy Green or Blue ────────────────────────
  static const Color helperAccent    = Color(0xFF05A357); // Uber green
  static const Color helperAccentDim = Color(0xFF048747);

  // ── Task Category Colors (clean and unified) ─────────────────────────────
  // Uber uses mostly uniform light gray or subtle tints.
  static const Color catQueue       = Color(0xFF000000);
  static const Color catLaundry     = Color(0xFF000000);
  static const Color catGrocery     = Color(0xFF000000);
  static const Color catCleaning    = Color(0xFF000000);
  static const Color catCooking     = Color(0xFF000000);
  static const Color catMoving      = Color(0xFF000000);
  static const Color catTutoring    = Color(0xFF000000);
  static const Color catTech        = Color(0xFF000000);
  static const Color catPetCare     = Color(0xFF000000);
  static const Color catTailoring   = Color(0xFF000000);
  static const Color catDriver      = Color(0xFF000000);
  static const Color catErrand      = Color(0xFF000000);
  static const Color catGarden      = Color(0xFF000000);
  static const Color catDocument    = Color(0xFF000000);
  static const Color catHospital    = Color(0xFF000000);
  static const Color catBabysit     = Color(0xFF000000);
  static const Color catElderCare   = Color(0xFF000000);
  static const Color catEvent       = Color(0xFF000000);
  static const Color catPhoto       = Color(0xFF000000);
  static const Color catRepair      = Color(0xFF000000);

  // ── Status Colors ─────────────────────────────────────────────────────────
  static const Color statusOpen       = Color(0xFF05A357); // green
  static const Color statusMatched    = Color(0xFF276EF1); // blue
  static const Color statusInProgress = Color(0xFF000000); // black
  static const Color statusCompleted  = Color(0xFF545454); // dark gray
  static const Color statusCancelled  = Color(0xFFE11900); // red

  // ── Text — High contrast ──────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF000000); // solid black
  static const Color textSecondary = Color(0xFF545454); // dark gray
  static const Color textMuted     = Color(0xFF8F8F8F); // light gray

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color successColor  = Color(0xFF05A357);
  static const Color warningColor  = Color(0xFFF5B300);
  static const Color errorColor    = Color(0xFFE11900);
  static const Color infoColor     = Color(0xFF276EF1);

  // ── Gradients ────────────────────────────────────────────────────────────
  // Clean flat styles instead of rich gradients
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF222222), Color(0xFF000000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient helperGradient = LinearGradient(
    colors: [Color(0xFF048747), Color(0xFF05A357)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmHomeGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF6F6F6)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient escrowGradient = LinearGradient(
    colors: [Color(0xFFEEEEEE), Color(0xFFE5E5E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── OTP Display ──────────────────────────────────────────────────────────
  static const Color otpBoxBg     = Color(0xFFF3F3F3);
  static const Color otpBoxBorder = Color(0xFF000000);
  static const Color otpText      = Color(0xFF000000);
}
