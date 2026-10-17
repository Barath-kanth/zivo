import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/blocs/theme/theme_cubit.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/ui/_shared/task_bundle_sheet.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/community_guidelines.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/services/device_account_store.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/data/models/device_account.dart';
import 'package:hyperlocal/data/models/helper_qualification.dart';
import 'package:hyperlocal/data/models/user_profile.dart';
import 'package:hyperlocal/data/models/user_review.dart';
import 'package:hyperlocal/data/repositories/trust_repository.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';
import 'package:hyperlocal/core/l10n/app_strings.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/ui/_shared/a11y_hub.dart';
import 'package:hyperlocal/ui/_shared/mode_switch_card.dart';

/// Uber Rider-home style Account panel with close (X) back to home.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<UserReview> _reviews = [];
  List<HelperQualification> _quals = [];
  List<DeviceAccount> _deviceAccounts = [];
  String? _activeProfileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    context.read<AuthBloc>().add(AuthProfileRefreshRequested());
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final trust = context.read<TrustRepository>();
    final reviews = await trust.getReviewsForUser(auth.profile.id);
    final quals = await trust.getQualifications(auth.profile.id);
    final accounts = await DeviceAccountStore.list();
    if (!mounted) return;
    setState(() {
      _reviews = reviews;
      _quals = quals;
      _deviceAccounts = accounts;
    });
  }

  void _close() => context.go(AppRoutes.shell);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, next) =>
          next is AuthAuthenticated || next is AuthUnauthenticated,
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(AppRoutes.login);
          return;
        }
        if (state is AuthAuthenticated) {
          final switched =
              _activeProfileId != null && _activeProfileId != state.profile.id;
          _activeProfileId = state.profile.id;
          _load();
          if (switched) context.go(AppRoutes.shell);
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is! AuthAuthenticated) {
            return const Scaffold(
              body: Center(child: Text('Sign in required')),
            );
          }
          _activeProfileId ??= state.profile.id;
          final p = state.profile;
          final isHelper = context.watch<ModeCubit>().isHelperMode;
          final palette = ZivoPalette.of(context);

          return Scaffold(
            backgroundColor: palette.canvas,
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: ZivoLogo(size: 28),
                        ),
                        Expanded(
                          child: Text(
                            context.watch<LocaleCubit>().t('account.title'),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headingMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.watch<LocaleCubit>().t('common.close'),
                          onPressed: _close,
                          icon: const Icon(Icons.close, size: 26),
                          style: IconButton.styleFrom(
                            backgroundColor: palette.card,
                            foregroundColor: palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          28 + MediaQuery.paddingOf(context).bottom + 80,
                        ),
                        children: [
                          _profileCard(p),
                          const Gap(14),
                          // Mode switch near top so mobile users always find it.
                          const ModeSwitchCard(),
                          const Gap(14),
                          _appearanceCard(),
                          const Gap(14),
                          _verificationCard(p),
                          const Gap(14),
                          _quickActions(isHelper),
                          const Gap(14),
                          _multiAccountCard(p),
                          const Gap(14),
                          _familyAssistCard(p),
                          const Gap(14),
                          _a11yCard(),
                          const Gap(14),
                          _menuCard(p),
                          const Gap(14),
                          _signOutButton(),
                          const Gap(16),
                          Text(
                            '${AppBrand.name} · Sri Lanka · Guidelines ${CommunityGuidelines.currentVersion}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _multiAccountCard(UserProfile current) {
    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_outline, size: 22, color: palette.textPrimary),
                const Gap(8),
                Text(
                  'Accounts on this phone',
                  style: AppTextStyles.headingSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
            const Gap(6),
            Text(
              AppConfig.demoAllowed
                  ? 'Share one handset with family — create a profile for someone without a smartphone.'
                  : 'Switch between accounts signed in on this device.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
              ),
            ),
            const Gap(12),
            ..._deviceAccounts.map((a) {
              final active = a.id == current.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: active
                      ? AppColors.helperAccent.withValues(alpha: 0.08)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    onTap: active
                        ? null
                        : () => context.read<AuthBloc>().add(
                              AuthSwitchDeviceAccountRequested(a),
                            ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: CircleAvatar(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                      child: Text(
                        a.initial,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(
                      a.fullName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      active
                          ? 'Active · ${a.phone}'
                          : (a.phone.isEmpty ? 'Tap to switch' : a.phone),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    trailing: active
                        ? const Icon(Icons.check_circle,
                            color: AppColors.helperAccent)
                        : IconButton(
                            tooltip: 'Remove from this phone',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => context.read<AuthBloc>().add(
                                  AuthRemoveDeviceAccountRequested(a.id),
                                ),
                          ),
                  ),
                ),
              );
            }),
            const Gap(4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<AuthBloc>().add(AuthAddAccountRequested());
                      context.go(AppRoutes.login);
                    },
                    icon: const Icon(Icons.login, size: 18),
                    label: Text(context.watch<LocaleCubit>().t('account.addAccount')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (AppConfig.demoAllowed) ...[
                  const Gap(8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showCreateSharedProfile,
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('New profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.onAccent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _appearanceCard() {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, mode) {
        final palette = ZivoPalette.of(context);
        final cubit = context.read<ThemeCubit>();
        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.brightness_6_rounded,
                      size: 22,
                      color: palette.textPrimary,
                    ),
                    const Gap(8),
                    Text(
                      'Appearance',
                      style: AppTextStyles.headingSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const Gap(6),
                Text(
                  'Light is the default. Dark uses Uber black (#000) with blue accents.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    height: 1.35,
                  ),
                ),
                const Gap(12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.phonelink_setup_rounded, size: 16),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (set) {
                    if (set.isEmpty) return;
                    cubit.setMode(set.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateSharedProfile() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profile for someone else'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use this when a parent or relative has no phone. Their profile lives on this device.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const Gap(14),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const Gap(10),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Their number (optional)',
                hintText: '77 123 4567',
                border: OutlineInputBorder(),
                prefixText: '+94 ',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create & switch'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    context.read<AuthBloc>().add(
          AuthCreateSharedDemoProfileRequested(
            fullName: nameCtrl.text,
            phone: phoneCtrl.text.isEmpty ? '771119999' : phoneCtrl.text,
          ),
        );
  }

  Widget _profileCard(UserProfile p) {
    final initial = p.displayInitial;
    final rating = p.ratingAsHelper;
    final title = p.displayLabel;
    final palette = ZivoPalette.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.headingLarge.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: palette.textPrimary,
                  ),
                ),
                if (p.phone != null && !p.hasPlaceholderName) ...[
                  const Gap(4),
                  Text(
                    PhoneUtils.formatDisplay(p.phone!),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
                const Gap(8),
                Row(
                  children: [
                    Icon(Icons.star, size: 18, color: palette.textPrimary),
                    const Gap(4),
                    Text(
                      rating.toStringAsFixed(2),
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Gap(10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: p.isKycVerified
                            ? AppColors.successColor.withValues(alpha: 0.12)
                            : AppColors.warningColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.isKycVerified
                            ? 'Verified'
                            : p.isKycPending
                                ? 'KYC pending'
                                : 'Unverified',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: p.isKycVerified
                              ? AppColors.successColor
                              : AppColors.warningColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(6),
                Text(
                  '${p.totalTasksHelped} helped · ${p.totalTasksPosted} posted'
                  '${_quals.isNotEmpty ? ' · ${_quals.where((q) => q.isVerified).length} quals' : ''}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          GestureDetector(
            onTap: () => context.push(AppRoutes.onboarding),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: palette.surface,
              backgroundImage: (p.avatarUrl != null &&
                      p.avatarUrl!.startsWith('http'))
                  ? NetworkImage(p.avatarUrl!)
                  : null,
              child: (p.avatarUrl != null && p.avatarUrl!.startsWith('http'))
                  ? null
                  : Text(
                      initial,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _familyAssistCard(UserProfile current) {
    final others = _deviceAccounts.where((a) => a.id != current.id).toList();
    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom_outlined,
                    size: 22, color: palette.textPrimary),
                const Gap(8),
                Text(
                  context.watch<LocaleCubit>().t('account.family'),
                  style: AppTextStyles.headingSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
            const Gap(6),
            Text(
              context.watch<LocaleCubit>().t('account.familyBody'),
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                height: 1.35,
              ),
            ),
            const Gap(12),
            if (others.isEmpty)
              Text(
                context.watch<LocaleCubit>().t('account.familyHint'),
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              )
            else
              ...others.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => showTaskBundlePlanner(
                      context,
                      initialProblem:
                          'Help for ${a.fullName} — grocery or errand nearby',
                      bookedForName: a.fullName,
                      bookedForUserId: a.id,
                    ),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text('Book for ${a.fullName}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: () => showTaskBundlePlanner(
                context,
                initialProblem:
                    'Moving / packing / cleaning this weekend for my family',
              ),
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: Text(context.watch<LocaleCubit>().t('account.split')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _a11yCard() {
    return BlocBuilder<A11yCubit, bool>(
      builder: (context, on) {
        final l = context.watch<LocaleCubit>();
        final palette = ZivoPalette.of(context);
        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(16),
          // Don't clip Arabic / CJK chip glyphs on the last Wrap row.
          clipBehavior: Clip.none,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  onChanged: (v) => context.read<A11yCubit>().setEnabled(v),
                  title: Text(
                    l.t('account.a11y'),
                    style: AppTextStyles.headingSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    l.t('account.a11yBody'),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                      height: 1.35,
                    ),
                  ),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.helperAccent,
                ),
                const Gap(10),
                Text(
                  l.t('account.language'),
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const Gap(10),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final code in AppStrings.supported)
                      ChoiceChip(
                        label: Text(
                          l.t('lang.$code'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.standard,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        selected: l.code == code,
                        onSelected: (_) =>
                            context.read<LocaleCubit>().setLocale(code),
                      ),
                  ],
                ),
                if (on) ...[
                  const Gap(8),
                  TextButton.icon(
                    onPressed: () => showA11yHub(
                      context,
                      screenHint: 'Zivo Account screen',
                    ),
                    icon: const Icon(Icons.accessibility_new_rounded, size: 18),
                    label: Text(l.t('a11y.title')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _verificationCard(UserProfile p) {
    final Color accent;
    final String headline;
    final String body;
    final String cta;
    if (p.isKycVerified) {
      accent = AppColors.successColor;
      headline = 'Identity verified';
      body = p.kycVerifiedAt != null
          ? 'Your documents were approved. You can use Helper mode.'
          : 'Your documents were approved.';
      cta = 'View profile';
    } else if (p.isKycPending) {
      accent = AppColors.warningColor;
      headline = 'Documents under review';
      body =
          'We received your NIC and selfie. Status updates here once an admin approves.';
      cta = 'Update documents';
    } else if (p.kycStatus == 'rejected') {
      accent = AppColors.errorColor;
      headline = 'Verification rejected';
      body = p.kycRejectionReason?.trim().isNotEmpty == true
          ? p.kycRejectionReason!
          : 'Please resubmit clearer NIC and selfie photos.';
      cta = 'Resubmit KYC';
    } else {
      accent = AppColors.textMuted;
      headline = 'Verify your identity';
      body =
          'Submit NIC + selfie to get a Verified badge. Required before Helper mode.';
      cta = 'Submit documents';
    }

    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.onboarding),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  p.isKycVerified
                      ? Icons.verified_rounded
                      : Icons.badge_outlined,
                  color: accent,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: AppTextStyles.headingSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      body,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const Gap(10),
                    Text(
                      cta,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActions(bool isHelper) {
    return Row(
      children: [
        Expanded(
          child: _quickTile(
            icon: Icons.help_outline,
            label: 'Help',
            onTap: () => context.push(AppRoutes.guidelines),
          ),
        ),
        const Gap(10),
        Expanded(
          child: _quickTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Wallet',
            onTap: () => context.go(AppRoutes.wallet),
          ),
        ),
        const Gap(10),
        Expanded(
          child: _quickTile(
            icon: Icons.receipt_long_outlined,
            label: 'Activity',
            onTap: () => context.go(AppRoutes.shell),
          ),
        ),
      ],
    );
  }

  Widget _quickTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, size: 26, color: palette.textPrimary),
              const Gap(8),
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCard(UserProfile p) {
    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          _menuRow(
            Icons.person_outline,
            context.watch<LocaleCubit>().t('account.manage'),
            () => context.push(AppRoutes.settings),
          ),
          _divider(),
          _menuRow(
            Icons.admin_panel_settings_outlined,
            context.watch<LocaleCubit>().t('account.admin'),
            () => context.push(AppRoutes.admin),
          ),
          _divider(),
          _menuRow(
            Icons.add_circle_outline,
            'Post a task',
            () async {
              if (!await requireVerified(
                context,
                returnTo: AppRoutes.createTask,
              )) {
                return;
              }
              if (!context.mounted) return;
              context.push(AppRoutes.createTask);
            },
          ),
          _divider(),
          _menuRow(
            Icons.badge_outlined,
            'Qualifications & licences',
            () => context.push(AppRoutes.qualifications),
          ),
          _divider(),
          _menuRow(
            Icons.star_outline,
            'Reviews (${_reviews.length})',
            () => context.push(AppRoutes.reviews),
          ),
          _divider(),
          _menuRow(
            Icons.request_quote_outlined,
            'Job quotes',
            () => context.push(AppRoutes.quotes),
          ),
          _divider(),
          _menuRow(
            Icons.gavel_outlined,
            'Community guidelines',
            () => context.push(AppRoutes.guidelines),
          ),
          if (!p.isKycVerified) ...[
            _divider(),
            _menuRow(
              Icons.verified_user_outlined,
              'Complete identity verification',
              () => context.push(AppRoutes.onboarding),
              accent: AppColors.warningColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56);

  Widget _menuRow(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? accent,
  }) {
    final palette = ZivoPalette.of(context);
    final color = accent ?? palette.textPrimary;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(icon, color: color, size: 24),
      title: Text(
        title,
        style: AppTextStyles.bodyLarge.copyWith(
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: palette.textMuted),
    );
  }

  Widget _signOutButton() {
    final palette = ZivoPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _confirmSignOut(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Sign out',
              textAlign: TextAlign.center,
              style: AppTextStyles.buttonLabel.copyWith(
                color: AppColors.errorColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to verify your phone again to use ${AppBrand.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: AppColors.errorColor),
            ),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true && context.mounted) {
        context.read<AuthBloc>().add(AuthSignOutRequested());
        context.go(AppRoutes.login);
      }
    });
  }
}
