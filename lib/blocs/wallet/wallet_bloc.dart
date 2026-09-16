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

class WalletNewEntryReceived extends WalletEvent {
  const WalletNewEntryReceived(this.entry);
  final WalletLedgerEntry entry;
  @override
  List<Object?> get props => [entry];
}

/// Credit helper earnings after End OTP / job complete (local UI update).
class WalletCreditHelperEarnings extends WalletEvent {
  const WalletCreditHelperEarnings({
    required this.userId,
    required this.taskId,
    required this.amount,
    required this.taskTitle,
  });
  final String userId;
  final String taskId;
  final double amount;
  final String taskTitle;
  @override
  List<Object?> get props => [userId, taskId, amount, taskTitle];
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

  WalletLoaded copyWithNewEntry(WalletLedgerEntry newEntry) {
    final credited = newEntry.entryType == LedgerType.escrowReleaseToHelper;
    return WalletLoaded(
      walletBalance: walletBalance,
      escrowBalance: escrowBalance > newEntry.amount && credited
          ? (escrowBalance - newEntry.amount).clamp(0, double.infinity)
          : escrowBalance,
      helperEarnings: credited
          ? helperEarnings + newEntry.amount
          : helperEarnings,
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
    on<WalletSubscribeRequested>(_onSubscribe);
    on<WalletUnsubscribeRequested>(_onUnsubscribe);
    on<WalletNewEntryReceived>(_onNewEntry);
    on<WalletCreditHelperEarnings>(_onCreditHelperEarnings);
  }

  final WalletRepository _walletRepository;
  SubscriptionHandle? _channel;
  final Set<String> _creditedTaskIds = {};

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
      final balances = await _walletRepository.getWalletBalances(event.userId);
      final entries =
          await _walletRepository.getLedgerEntries(userId: event.userId);

      emit(WalletLoaded(
        walletBalance: balances?.walletBalance ?? 0.0,
        escrowBalance: balances?.escrowBalance ?? 0.0,
        helperEarnings: balances?.helperEarnings ?? 0.0,
        entries: entries,
      ));
    } catch (e) {
      emit(_emptyLoaded);
    }
  }

  Future<void> _onCreditHelperEarnings(
    WalletCreditHelperEarnings event,
    Emitter<WalletState> emit,
  ) async {
    if (event.amount <= 0) return;
    if (_creditedTaskIds.contains(event.taskId)) return;
    _creditedTaskIds.add(event.taskId);

    final current = state is WalletLoaded
        ? state as WalletLoaded
        : _emptyLoaded;

    final entry = WalletLedgerEntry(
      id: 'led-${DateTime.now().millisecondsSinceEpoch}',
      userId: event.userId,
      taskId: event.taskId,
      entryType: LedgerType.escrowReleaseToHelper,
      amount: event.amount,
      balanceAfter: current.helperEarnings + event.amount,
      description:
          'Task "${event.taskTitle}" completed — +LKR ${event.amount.toStringAsFixed(2)} earnings',
      createdAt: DateTime.now(),
    );

    emit(current.copyWithNewEntry(entry));
  }

  Future<void> _onSubscribe(
    WalletSubscribeRequested event,
    Emitter<WalletState> emit,
  ) async {
    _channel = _walletRepository.subscribeToWalletUpdates(
      userId: event.userId,
      onNewEntry: (entry) => add(WalletNewEntryReceived(entry)),
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

  Future<void> _onNewEntry(
    WalletNewEntryReceived event,
    Emitter<WalletState> emit,
  ) async {
    if (state is WalletLoaded) {
      emit((state as WalletLoaded).copyWithNewEntry(event.entry));
    }
  }

  @override
  Future<void> close() {
    if (_channel != null) _walletRepository.unsubscribe(_channel!);
    return super.close();
  }
}
