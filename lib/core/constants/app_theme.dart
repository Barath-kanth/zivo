import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'zivo_palette.dart';

/// Shared visual system — light (Zivo mint) + dark (Uber black / blue).
abstract class AppTheme {
  static ThemeData get light => _build(Brightness.light, ZivoPalette.light);
  static ThemeData get dark => _build(Brightness.dark, ZivoPalette.dark);

  static ThemeData _build(Brightness brightness, ZivoPalette p) {
    final isDark = brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    // Light: mint CTA. Dark: UberX blue — never mint-on-black.
    final interactive = p.accent;
    final onInteractive = p.onAccent;

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: interactive,
      foregroundColor: onInteractive,
      disabledBackgroundColor: p.border,
      disabledForegroundColor: p.textMuted,
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: shape,
      textStyle: AppTextStyles.buttonLabel,
    );
    OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    final baseText = AppTextStyles.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    ).copyWith(
      bodyMedium: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      bodySmall: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
      labelLarge: AppTextStyles.labelLarge.copyWith(color: p.textSecondary),
      labelSmall: AppTextStyles.labelSmall.copyWith(color: p.textMuted),
      titleSmall: AppTextStyles.labelLarge.copyWith(color: p.textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      textTheme: baseText,
      primaryTextTheme: baseText,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      dividerColor: p.border,
      extensions: [p],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: interactive,
        onPrimary: onInteractive,
        primaryContainer: p.surface,
        onPrimaryContainer: p.textPrimary,
        secondary: isDark ? AppColors.brandGreen : AppColors.helperAccent,
        onSecondary: Colors.white,
        secondaryContainer: p.helperSoft,
        onSecondaryContainer:
            isDark ? AppColors.uberBlue : AppColors.helperAccentDim,
        surface: p.canvas,
        onSurface: p.textPrimary,
        onSurfaceVariant: p.textSecondary,
        surfaceTint: Colors.transparent,
        outline: p.textMuted,
        outlineVariant: p.border,
        error: AppColors.errorColor,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.card,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 64,
        titleTextStyle: AppTextStyles.headingMedium.copyWith(
          color: p.textPrimary,
        ),
        iconTheme: IconThemeData(color: p.textPrimary, size: 24),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          side: BorderSide(color: p.border),
          shape: shape,
          textStyle: AppTextStyles.buttonLabel.copyWith(color: p.textPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: const Size(48, 48),
          textStyle: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          shape: shape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: fieldBorder(p.border),
        enabledBorder: fieldBorder(p.border),
        focusedBorder: fieldBorder(interactive, 2),
        errorBorder: fieldBorder(AppColors.errorColor),
        focusedErrorBorder: fieldBorder(AppColors.errorColor, 2),
        labelStyle: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: p.textMuted),
        errorStyle: AppTextStyles.bodySmall.copyWith(
          color: AppColors.errorColor,
        ),
        errorMaxLines: 3,
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        selectedColor: p.helperSoft,
        secondarySelectedColor: p.helperSoft,
        labelStyle: AppTextStyles.labelLarge.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: AppTextStyles.labelLarge.copyWith(
          color: interactive,
          fontWeight: FontWeight.w700,
        ),
        disabledColor: p.surface,
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.card,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.card,
        selectedItemColor: interactive,
        unselectedItemColor: p.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: interactive,
        foregroundColor: onInteractive,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: AppTextStyles.headingMedium.copyWith(
          color: p.textPrimary,
        ),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: p.textSecondary,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: interactive,
        unselectedLabelColor: p.textMuted,
        indicatorColor: interactive,
        dividerColor: p.border,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? interactive
              : p.border,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textPrimary,
        textColor: p.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: 1,
        space: 24,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: interactive,
        linearTrackColor: p.border,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: interactive,
        selectionColor: interactive.withValues(alpha: 0.2),
        selectionHandleColor: interactive,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? p.surface : AppColors.textPrimary,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: Colors.white,
        ),
        actionTextColor: Colors.white,
        shape: shape,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        textStyle: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
      ),
    );
  }
}
