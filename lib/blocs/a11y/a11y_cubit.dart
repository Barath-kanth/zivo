import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accessibility Mode — larger text, Speak, Describe, Read aloud.
/// Opt-in: no permanent top banner; hub FAB / Account / desktop sidebar.
class A11yCubit extends Cubit<bool> {
  A11yCubit() : super(false) {
    _load();
  }

  static const _key = 'zivo_a11y_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      emit(prefs.getBool(_key) ?? false);
    } catch (_) {
      emit(false);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    emit(enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> toggle() => setEnabled(!state);

  bool get enabled => state;
}
