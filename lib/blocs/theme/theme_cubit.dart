import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance — Light (default), Dark, or System. Persisted across launches.
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.light) {
    _load();
  }

  static const _key = 'zivo_theme_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      // First launch (no key) → Light. Never inherit OS dark for new users.
      if (raw == null || raw.isEmpty) {
        await prefs.setString(_key, 'light');
        emit(ThemeMode.light);
        return;
      }
      emit(_fromKey(raw));
    } catch (_) {
      emit(ThemeMode.light);
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    emit(mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _toKey(mode));
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> cycle() {
    final next = switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    return setMode(next);
  }

  static String _toKey(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  /// Missing / unknown prefs → Light (product default).
  static ThemeMode _fromKey(String? key) => switch (key) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  String get label => switch (state) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };
}
