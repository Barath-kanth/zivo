import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/wallet/wallet_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/data/models/wallet_ledger.dart';
import 'package:hyperlocal/data/repositories/payment_repository.dart';
import 'package:hyperlocal/ui/_shared/empty_state_widget.dart';
import 'package:hyperlocal/ui/client/wallet/card_topup_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _toppingUp = false;

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
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: palette.textPrimary, size: 18),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          context.watch<ModeCubit>().isHelperMode
              ? l.t('wallet.earningsTitle')
              : l.t('wallet.title'),
          style: AppTextStyles.headingMedium.copyWith(
            color: palette.textPrimary,
          ),
        ),
        centerTitle: false,
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
              title: 'Wallet unavailable',
              subtitle: state.message,
              color: AppColors.errorColor,
              actionLabel: 'Try again',
              onAction: () {
                final auth = context.read<AuthBloc>().state;
                if (auth is AuthAuthenticated) {
                  context
                      .read<WalletBloc>()
                      .add(WalletFetchRequested(auth.profile.id));
                }
              },
            );
          }
          if (state is WalletLoaded) {
            return _buildBody(state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildBody(WalletLoaded state) {
    final l = context.watch<LocaleCubit>();
    final entries = state.entries.where((e) => e.amount.abs() > 0).toList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('wallet.available'),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Gap(6),
                Text(
                  AppConfig.money(state.walletBalance),
                  style: AppTextStyles.moneyHero,
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: _StatPill(
                        label: l.t('wallet.escrow'),
                        value: AppConfig.money(state.escrowBalance),
                        icon: Icons.lock_outline_rounded,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _StatPill(
                        label: l.t('wallet.helperEarned'),
                        value: AppConfig.money(state.helperEarnings),
                        icon: Icons.trending_up_rounded,
                      ),
                    ),
                  ],
                ),
                const Gap(20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _toppingUp ? null : _showTopUpSheet,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      maximumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _toppingUp
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            l.t('wallet.topUp'),
                            style: AppTextStyles.buttonLabel.copyWith(
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                  ),
                ),
                const Gap(28),
                Text(l.t('wallet.transactions'),
                    style: AppTextStyles.headingSmall),
                const Gap(8),
              ],
            ).animate().fadeIn(duration: 280.ms),
          ),
        ),
        if (entries.isEmpty)
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: 28 + MediaQuery.paddingOf(context).bottom + 80,
            ),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateWidget(
                icon: Icons.receipt_long_outlined,
                title: l.t('wallet.emptyTitle'),
                subtitle: l.t('wallet.emptySubtitle'),
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              28 + MediaQuery.paddingOf(context).bottom + 80,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _LedgerRow(entry: entries[i]),
                childCount: entries.length,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showTopUpSheet() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleCubit>().t('wallet.signIn'))),
      );
      return;
    }
    if (_toppingUp) return;

    final card = await showCardTopUpSheet(context);
    if (card == null || !mounted) return;

    setState(() => _toppingUp = true);
    final messenger = ScaffoldMessenger.of(context);
    final brandLabel = switch (card.brand) {
      CardBrand.visa => 'Visa',
      CardBrand.mastercard => 'Mastercard',
      CardBrand.amex => 'Amex',
      CardBrand.unknown => 'Card',
    };

    try {
      await context.read<PaymentRepository>().startTopUp(
            userId: auth.profile.id,
            amount: card.amount,
            firstName: auth.profile.fullName.split(' ').first,
            phone: auth.profile.phone,
            email: auth.profile.email,
            cardBrand: brandLabel.toLowerCase(),
            cardLast4: card.last4,
          );
      if (!mounted) return;
      context.read<WalletBloc>().add(WalletFetchRequested(auth.profile.id));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${AppConfig.money(card.amount, decimals: 2)} · $brandLabel •••• ${card.last4}',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _toppingUp = false);
    }
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: palette.textMuted),
              const Gap(6),
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Gap(6),
          Text(
            value,
            style: AppTextStyles.moneyStat.copyWith(color: palette.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});
  final WalletLedgerEntry entry;

  String _cleanDesc(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return raw
        .replaceAll(RegExp(r'\s*\(GCP demo\)', caseSensitive: false), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final credit = entry.entryType.isCredit;
    final color = credit ? AppColors.successColor : AppColors.textPrimary;
    final desc = _cleanDesc(entry.description);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: credit
              ? AppColors.brandGreenSoft
              : const Color(0xFFF0F0F0),
          child: Icon(
            credit ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 16,
            color: color,
          ),
        ),
        title: Text(
          entry.entryType.displayName,
          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (desc.isNotEmpty) desc,
            _ago(entry.createdAt),
          ].join(' · '),
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${credit ? '+' : '−'}${AppConfig.money(entry.amount.abs())}',
          style: AppTextStyles.headingSmall.copyWith(
            color: color,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
