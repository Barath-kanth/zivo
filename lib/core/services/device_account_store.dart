import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyperlocal/data/models/device_account.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

/// Persists multiple accounts on one device (family phone / shared handset).
class DeviceAccountStore {
  DeviceAccountStore._();

  static const _keyAccounts = 'device_accounts_v1';
  static const _keyActiveId = 'device_active_account_id';
  static const _keyAdding = 'device_adding_account';
  static const _keyPrefillPhone = 'device_prefill_phone';

  static Future<List<DeviceAccount>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAccounts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final accounts = list
          .map((e) => DeviceAccount.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return accounts;
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsertFromProfile(
    UserProfile profile, {
    required bool isDemo,
  }) async {
    final accounts = await list();
    final next = DeviceAccount.fromProfile(profile, isDemo: isDemo);
    accounts.removeWhere((a) => a.id == next.id);
    accounts.insert(0, next);
    await _save(accounts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveId, next.id);
    await prefs.remove(_keyAdding);
    await prefs.remove(_keyPrefillPhone);
  }

  static Future<void> remove(String id) async {
    final accounts = await list();
    accounts.removeWhere((a) => a.id == id);
    await _save(accounts);
  }

  static Future<String?> activeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveId);
  }

  static Future<void> setAddingAccount({String? prefillPhone}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAdding, true);
    if (prefillPhone != null && prefillPhone.isNotEmpty) {
      await prefs.setString(_keyPrefillPhone, prefillPhone);
    } else {
      await prefs.remove(_keyPrefillPhone);
    }
  }

  static Future<bool> isAddingAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAdding) ?? false;
  }

  static Future<String?> prefillPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPrefillPhone);
  }

  static Future<void> clearPendingSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAdding);
    await prefs.remove(_keyPrefillPhone);
  }

  static Future<void> _save(List<DeviceAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyAccounts,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }
}
