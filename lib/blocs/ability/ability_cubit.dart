import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in, private ability profile. Zivo uses it to offer the right tools and to write
/// ability-aware job briefs. It never changes a helper's ranking, price floor or pay.
const kAbilityKeys = ['visual', 'hearing', 'speech', 'mobility', 'cognitive'];

class AbilityProfile extends Equatable {
  const AbilityProfile({
    this.abilities = const {},
    this.disclose = false,
    this.note = '',
  });

  final Set<String> abilities;

  /// Helper chose to tell clients (they can hire or decline knowingly).
  final bool disclose;
  final String note;

  bool has(String key) => abilities.contains(key);
  bool get isEmpty => abilities.isEmpty;

  AbilityProfile copyWith({Set<String>? abilities, bool? disclose, String? note}) =>
      AbilityProfile(
        abilities: abilities ?? this.abilities,
        disclose: disclose ?? this.disclose,
        note: note ?? this.note,
      );

  @override
  List<Object?> get props => [abilities.toList()..sort(), disclose, note];
}

class AbilityCubit extends Cubit<AbilityProfile> {
  AbilityCubit({this.onChanged}) : super(const AbilityProfile()) {
    _load();
  }

  /// Server sync hook (best-effort).
  final Future<void> Function(AbilityProfile profile)? onChanged;

  static const _kAbilities = 'zivo_abilities';
  static const _kDisclose = 'zivo_ability_disclose';
  static const _kNote = 'zivo_ability_note';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      emit(AbilityProfile(
        abilities: (p.getStringList(_kAbilities) ?? const [])
            .where(kAbilityKeys.contains)
            .toSet(),
        disclose: p.getBool(_kDisclose) ?? false,
        note: p.getString(_kNote) ?? '',
      ));
    } catch (_) {
      /* defaults */
    }
  }

  Future<void> _commit(AbilityProfile next) async {
    emit(next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kAbilities, next.abilities.toList());
      await p.setBool(_kDisclose, next.disclose);
      await p.setString(_kNote, next.note);
    } catch (_) {}
    try {
      await onChanged?.call(next);
    } catch (_) {
      /* offline / signed out: local copy is still saved */
    }
  }

  /// Push the local profile to the server (call when signed in, e.g. when the hub opens).
  Future<void> resync() async {
    try {
      await onChanged?.call(state);
    } catch (_) {}
  }

  Future<void> toggle(String key) {
    final next = {...state.abilities};
    if (!next.remove(key)) next.add(key);
    // Nothing selected → nothing to disclose.
    return _commit(state.copyWith(
      abilities: next,
      disclose: next.isEmpty ? false : state.disclose,
    ));
  }

  Future<void> setDisclose(bool v) => _commit(state.copyWith(disclose: v));
  Future<void> setNote(String v) => _commit(state.copyWith(note: v.trim()));
}
