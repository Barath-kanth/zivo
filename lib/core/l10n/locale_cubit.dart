import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyperlocal/core/l10n/app_strings.dart';
import 'package:hyperlocal/data/models/task.dart';

/// App UI language — English / Sinhala / Tamil (Sri Lanka).
/// Client-only; API responses stay English.
class LocaleCubit extends Cubit<Locale> {
  LocaleCubit() : super(const Locale('en')) {
    _load();
  }

  static const _key = 'zivo_locale';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key) ?? 'en';
      if (AppStrings.supported.contains(code)) {
        emit(Locale(code));
      }
    } catch (_) {
      /* keep default */
    }
  }

  /// Optional server sync (preferred_lang for cross-language chat).
  Future<void> Function(String code)? onLocaleChanged;

  Future<void> setLocale(String code) async {
    if (!AppStrings.supported.contains(code)) return;
    emit(Locale(code));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
    } catch (_) {
      /* ignore */
    }
    try {
      await onLocaleChanged?.call(code);
    } catch (_) {
      /* best-effort */
    }
  }

  String get code => state.languageCode;

  String t(String key) => AppStrings.t(code, key);

  /// Localized service category label (falls back to English display name).
  String category(TaskCategory cat) {
    final key = 'cat.${cat.name}';
    final value = t(key);
    // Missing i18n keys used to show raw "cat.readingAloud" — never do that.
    if (value == key || value.startsWith('cat.')) return cat.displayName;
    return value;
  }

  /// Short lang code for speechSynthesis (`en` / `si` / `ta` / …).
  String get speechLang => code;
}

extension LocaleCubitX on BuildContext {
  LocaleCubit get localeCubit => read<LocaleCubit>();
  String tr(String key) => read<LocaleCubit>().t(key);
}
