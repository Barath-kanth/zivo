import 'dart:async';
import 'package:hyperlocal/core/services/gcp/subscription_handle.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyperlocal/data/repositories/wallet_repository.dart';
import 'package:hyperlocal/data/models/wallet_ledger.dart';

// ── Events ──────────────────────────────────────────────────────────────────
abstract class WalletEvent extends Equatable {
  const WalletEvent();
  @override
  List<Object?> get props => [];
}

class WalletFetchRequested extends WalletEvent {
  const WalletFetchRequested(this.userId);
  final String userId;
  @override
  List<Object?> get props => [userId];
}

class WalletSubscribeRequested extends WalletEvent {
  const WalletSubscribeRequested(this.userId);
  final String userId;
  @override
  List<Object?> get props => [userId];
}

class WalletRefreshQuietly extends WalletEvent {
  const WalletRefreshQuietly(this.userId);
  final String userId;
  @override
  List<Object?> get props => [userId];
}

class WalletUnsubscribeRequested extends WalletEvent {}

// ── States ──────────────────────────────────────────────────────────────────
abstract class WalletState extends Equatable {
  const WalletState();
  @override
  List<Object?> get props => [];
}

class WalletInitial extends WalletState {}
class WalletLoading extends WalletState {}

class WalletLoaded extends WalletState {
  const WalletLoaded({
    required this.walletBalance,
    required this.escrowBalance,
    required this.helperEarnings,
    required this.entries,
  });
  final double walletBalance;
  final double escrowBalance;
  final double helperEarnings;
  final List<WalletLedgerEntry> entries;

  WalletLoaded copyWith({
    double? walletBalance,
    double? escrowBalance,
    double? helperEarnings,
    List<WalletLedgerEntry>? entries,
  }) {
    return WalletLoaded(
      walletBalance: walletBalance ?? this.walletBalance,
      escrowBalance: escrowBalance ?? this.escrowBalance,
      helperEarnings: helperEarnings ?? this.helperEarnings,
      entries: entries ?? this.entries,
    );
  }

  /// Append a ledger row for UI only — never invent balance deltas here.
  /// Server `/me` balances are the source of truth (see [WalletFetchRequested]).
  WalletLoaded copyWithNewEntry(WalletLedgerEntry newEntry) {
    if (entries.any((e) => e.id == newEntry.id)) return this;
    if (newEntry.amount <= 0) return this;
    return WalletLoaded(
      walletBalance: walletBalance,
      escrowBalance: escrowBalance,
      helperEarnings: helperEarnings,
      entries: [newEntry, ...entries],
    );
  }

  @override
  List<Object?> get props => [walletBalance, escrowBalance, helperEarnings, entries];
}

class WalletFailure extends WalletState {
  const WalletFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ── BLoC ────────────────────────────────────────────────────────────────────
class WalletBloc extends Bloc<WalletEvent, WalletState> {
  WalletBloc({required WalletRepository walletRepository})
      : _walletRepository = walletRepository,
        super(WalletInitial()) {
    on<WalletFetchRequested>(_onFetch);
    on<WalletRefreshQuietly>(_onRefreshQuietly);
    on<WalletSubscribeRequested>(_onSubscribe);
    on<WalletUnsubscribeRequested>(_onUnsubscribe);
  }

  final WalletRepository _walletRepository;
  SubscriptionHandle? _channel;

  static const WalletLoaded _emptyLoaded = WalletLoaded(
    walletBalance: 0,
    escrowBalance: 0,
    helperEarnings: 0,
    entries: [],
  );

  Future<void> _onFetch(
    WalletFetchRequested event,
    Emitter<WalletState> emit,
  ) async {
    emit(WalletLoading());
    try {
      emit(await _loadWallet(event.userId));
    } catch (e) {
      emit(_emptyLoaded);
    }
  }

  /// Background poll — keep current UI, replace balances from server.
  Future<void> _onRefreshQuietly(
    WalletRefreshQuietly event,
    Emitter<WalletState> emit,
  ) async {
    try {
      emit(await _loadWallet(event.userId));
    } catch (_) {
      /* keep last good state */
    }
  }

  Future<WalletLoaded> _loadWallet(String userId) async {
    final balances = await _walletRepository.getWalletBalances(userId);
    final entries =
        await _walletRepository.getLedgerEntries(userId: userId);
    // Hide zero-amount noise (e.g. unused goods = 0).
    final visible = entries.where((e) => e.amount > 0).toList();
    return WalletLoaded(
      walletBalance: balances?.walletBalance ?? 0.0,
      escrowBalance: balances?.escrowBalance ?? 0.0,
      helperEarnings: balances?.helperEarnings ?? 0.0,
      entries: visible,
    );
  }

  Future<void> _onSubscribe(
    WalletSubscribeRequested event,
    Emitter<WalletState> emit,
  ) async {
    _channel?.cancel();
    _channel = _walletRepository.subscribeToWalletUpdates(
      userId: event.userId,
      onRefresh: () => add(WalletRefreshQuietly(event.userId)),
    );
  }

  Future<void> _onUnsubscribe(
    WalletUnsubscribeRequested event,
    Emitter<WalletState> emit,
  ) async {
    if (_channel != null) {
      _walletRepository.unsubscribe(_channel!);
      _channel = null;
    }
  }

  @override
  Future<void> close() {
    if (_channel != null) _walletRepository.unsubscribe(_channel!);
    return super.close();
  }
}
