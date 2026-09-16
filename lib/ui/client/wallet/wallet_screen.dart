import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/wallet/wallet_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/wallet_ledger.dart';
import 'package:hyperlocal/data/repositories/payment_repository.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:go_router/go_router.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated) {
      context.read<WalletBloc>()
        ..add(WalletFetchRequested(auth.profile.id))
        ..add(WalletSubscribeRequested(auth.profile.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Wallet'),
        centerTitle: true,
      ),
      body: BlocBuilder<WalletBloc, WalletState>(
        builder: (context, state) {
          if (state is WalletInitial || state is WalletLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (state is WalletFailure) {
            return EmptyStateWidget(
              icon: Icons.error_outline_rounded,
              title: 'Load Failed',
              subtitle: state.message,
              color: AppColors.errorColor,
            );
          }

          if (state is WalletLoaded) {
            return _buildWalletBody(
              walletBalance: state.walletBalance,
              escrowBalance: state.escrowBalance,
              helperEarnings: state.helperEarnings,
              entries: state.entries,
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildWalletBody({
    required double walletBalance,
    required double escrowBalance,
    required double helperEarnings,
    required List<WalletLedgerEntry> entries,
  }) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        _buildHeroCard(walletBalance, escrowBalance, helperEarnings),
        _buildActionButtons(),
        _buildLedgerHeader(),
        _buildLedger(entries),
        const SliverToBoxAdapter(child: Gap(100)),
      ],
    );
  }

  // ── Hero balance card ─────────────────────────────────────────────────────

  Widget _buildHeroCard(
      double wallet, double escrow, double earnings) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white70, size: 18),
                const Gap(8),
                Text(
                  'Available Balance',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white70),
                ),
              ],
            ),
            const Gap(10),
            Text(
              'LKR ${wallet.toStringAsFixed(2)}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const Gap(16),
            Row(
              children: [
                _MiniStat(
                  icon: Icons.lock_clock_rounded,
                  label: 'In Escrow',
                   value: 'LKR ${escrow.toStringAsFixed(2)}',
                  color: AppColors.statusMatched,
                ),
                Container(
                    width: 1,
                    height: 30,
                    color: Colors.white.withValues(alpha: 0.2),
                    margin: const EdgeInsets.symmetric(horizontal: 16)),
                _MiniStat(
                  icon: Icons.savings_rounded,
                  label: 'Helper Earned',
                   value: 'LKR ${earnings.toStringAsFixed(2)}',
                  color: AppColors.helperAccent,
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: _ActionBtn(
                icon: Icons.add_rounded,
                label: 'Top Up',
                color: AppColors.accent,
                onTap: _showTopUpSheet,
              ).animate(delay: 80.ms).fadeIn(),
            ),
            const Gap(10),
            Expanded(
              child: _ActionBtn(
                icon: Icons.send_rounded,
                label: 'Transfer',
                color: AppColors.helperAccent,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Transfer — coming soon')),
                ),
              ).animate(delay: 140.ms).fadeIn(),
            ),
            const Gap(10),
            Expanded(
              child: _ActionBtn(
                icon: Icons.history_rounded,
                label: 'History',
                color: AppColors.catDocument,
                onTap: () {
                  _scrollController.animateTo(
                    310,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                  );
                },
              ).animate(delay: 200.ms).fadeIn(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ledger ────────────────────────────────────────────────────────────────

  Widget _buildLedgerHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Row(
          children: [
            Text('Transactions', style: AppTextStyles.headingSmall),
          ],
        ),
      ),
    );
  }

  Widget _buildLedger(List<WalletLedgerEntry> entries) {
    if (entries.isEmpty) {
      return SliverFillRemaining(
        child: EmptyStateWidget(
          icon: Icons.receipt_long_outlined,
          title: 'No transactions yet',
          subtitle: 'Top up your wallet to start posting tasks',
          color: AppColors.textMuted,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _LedgerTile(entry: entries[i], index: i),
          childCount: entries.length,
        ),
      ),
    );
  }

  // ── Top-up sheet ──────────────────────────────────────────────────────────

  Future<void> _startTopUp(double amount) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to top up')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          AppConfig.demoAllowed
              ? 'Crediting ${AppConfig.money(amount, decimals: 2)}…'
              : 'Opening PayHere for ${AppConfig.money(amount, decimals: 2)}…',
        ),
      ),
    );

    try {
      final result = await context.read<PaymentRepository>().startTopUp(
            userId: auth.profile.id,
            amount: amount,
            firstName: auth.profile.fullName.split(' ').first,
            phone: auth.profile.phone,
            email: auth.profile.email,
          );

      if (!mounted) return;

      if (result == 'demo_credited') {
        context.read<WalletBloc>().add(WalletFetchRequested(auth.profile.id));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${AppConfig.money(amount, decimals: 2)} added to wallet (demo).',
            ),
            backgroundColor: AppColors.successColor,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Complete payment in PayHere. Your wallet updates when payment succeeds.',
            ),
          ),
        );
        // Refresh after user returns from browser
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          context.read<WalletBloc>().add(WalletFetchRequested(auth.profile.id));
        });
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  void _showTopUpSheet() {
    // LKR top-up amounts
    final amounts = [1000.0, 2500.0, 5000.0, 10000.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Gap(20),
            Text('Top Up Wallet', style: AppTextStyles.headingMedium),
            const Gap(4),
            Text(
              AppConfig.demoAllowed
                  ? 'Demo mode — credits instantly (no card charge).'
                  : 'Pay securely with PayHere (card / LankaQR).',
              style: AppTextStyles.bodyMedium,
            ),
            const Gap(20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: amounts
                  .map((amt) => GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _startTopUp(amt);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          decoration: BoxDecoration(
                            color:
                                AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.accent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            AppConfig.money(amt, decimals: 0),
                            style: AppTextStyles.headingSmall
                                .copyWith(color: AppColors.accent),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const Gap(12),
            Text(
              AppConfig.demoAllowed
                  ? 'Production builds use PayHere — merchant secrets stay on the server.'
                  : 'Payments via PayHere (Sampath / ComBank / BOC / LankaQR).',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 12),
            const Gap(4),
            Text(label,
                style: AppTextStyles.bodySmall
                    .copyWith(color: Colors.white60, fontSize: 10)),
          ],
        ),
        const Gap(2),
        Text(value,
            style: AppTextStyles.headingSmall
                .copyWith(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const Gap(5),
            Text(
              label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry, required this.index});
  final WalletLedgerEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.entryType.isCredit;
    final color =
        isCredit ? AppColors.successColor : AppColors.errorColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCredit
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              color: color,
              size: 17,
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.entryType.displayName,
                    style: AppTextStyles.headingSmall
                        .copyWith(fontSize: 13)),
                if (entry.description != null)
                  Text(
                    entry.description!,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  _formatDate(entry.createdAt),
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}LKR ${entry.amount.toStringAsFixed(2)}',
            style:
                AppTextStyles.headingSmall.copyWith(color: color, fontSize: 13),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: index * 40))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.05);
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
