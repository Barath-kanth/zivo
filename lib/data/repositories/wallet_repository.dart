import 'dart:async';

import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:hyperlocal/core/services/gcp/subscription_handle.dart';
import 'package:hyperlocal/data/models/user_profile.dart';
import 'package:hyperlocal/data/models/wallet_ledger.dart';

class WalletRepository {
  WalletRepository(this._api);

  final GcpApiClient _api;

  Future<UserProfile?> getWalletBalances(String userId) async {
    try {
      final data = await _api.getJson('/me');
      return UserProfile.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<WalletLedgerEntry>> getLedgerEntries({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _api.getJson('/wallet/ledger');
    final list = data['entries'] as List? ?? [];
    return list
        .skip(offset)
        .take(limit)
        .map((e) => WalletLedgerEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Poll for balance + ledger refresh. Do **not** invent incremental
  /// earnings from the latest ledger row — that caused Helper Earned /
  /// Escrow to drift every tick.
  SubscriptionHandle subscribeToWalletUpdates({
    required String userId,
    required void Function() onRefresh,
  }) {
    final timer = Timer.periodic(const Duration(seconds: 12), (_) {
      onRefresh();
    });
    return SubscriptionHandle(timer.cancel);
  }

  void unsubscribe(SubscriptionHandle channel) {
    channel.cancel();
  }
}
