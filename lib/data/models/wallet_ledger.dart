import 'package:equatable/equatable.dart';

enum LedgerType {
  walletTopup,
  escrowHold,
  escrowReleaseToHelper,
  escrowRefundToClient,
  platformFee,
  helperWithdrawal;

  String get displayName {
    switch (this) {
      case LedgerType.walletTopup:            return 'Wallet Top-up';
      case LedgerType.escrowHold:             return 'Held in Escrow';
      case LedgerType.escrowReleaseToHelper:  return 'Earnings Credited';
      case LedgerType.escrowRefundToClient:   return 'Escrow Refund';
      case LedgerType.platformFee:            return 'Platform Fee';
      case LedgerType.helperWithdrawal:       return 'Withdrawal';
    }
  }

  /// Positive = credit, Negative = debit from user's perspective.
  bool get isCredit {
    switch (this) {
      case LedgerType.walletTopup:           return true;
      case LedgerType.escrowReleaseToHelper: return true;
      case LedgerType.escrowRefundToClient:  return true;
      case LedgerType.escrowHold:            return false;
      case LedgerType.platformFee:           return false;
      case LedgerType.helperWithdrawal:      return false;
    }
  }

  static LedgerType fromString(String value) {
    switch (value) {
      case 'wallet_topup':
      case 'topup':
        return LedgerType.walletTopup;
      case 'escrow_hold':
        return LedgerType.escrowHold;
      case 'escrow_release_to_helper':
      case 'release':
        return LedgerType.escrowReleaseToHelper;
      case 'escrow_refund_to_client':
        return LedgerType.escrowRefundToClient;
      case 'platform_fee':
        return LedgerType.platformFee;
      case 'helper_withdrawal':
        return LedgerType.helperWithdrawal;
      default:
        return LedgerType.walletTopup;
    }
  }
}

class WalletLedgerEntry extends Equatable {
  const WalletLedgerEntry({
    required this.id,
    required this.userId,
    this.taskId,
    required this.entryType,
    required this.amount,
    required this.balanceAfter,
    this.description,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String? taskId;
  final LedgerType entryType;
  final double amount;
  final double balanceAfter;
  final String? description;
  final DateTime createdAt;

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> json) =>
      WalletLedgerEntry(
        id:           json['id'] as String,
        userId:       json['user_id'] as String,
        taskId:       json['task_id'] as String?,
        entryType:    LedgerType.fromString(json['entry_type'] as String),
        amount:       (json['amount'] as num).toDouble(),
        balanceAfter: (json['balance_after'] as num).toDouble(),
        description:  json['description'] as String?,
        createdAt:    DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [id, userId, entryType, amount, createdAt];
}
