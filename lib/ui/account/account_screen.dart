import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/a11y/a11y_cubit.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
import 'package:hyperlocal/ui/_shared/task_bundle_sheet.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/community_guidelines.dart';
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

          return Scaffold(
            backgroundColor: const Color(0xFFF6F6F6),
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
                            'Account',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headingMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _close,
                          icon: const Icon(Icons.close, size: 26),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        children: [
                          _profileCard(p),
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
                          _menuCard(p, isHelper),
                          const Gap(14),
                          _signOutButton(),
                          const Gap(16),
                          Text(
                            '${AppBrand.name} · Sri Lanka · Guidelines ${CommunityGuidelines.currentVersion}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textMuted,
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_outline, size: 22),
                const Gap(8),
                Text(
                  'Accounts on this phone',
                  style: AppTextStyles.headingSmall.copyWith(
                    fontWeight: FontWeight.w700,
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
                color: AppColors.textMuted,
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
                      : const Color(0xFFF6F6F6),
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
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      child: Text(
                        a.initial,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(
                      a.fullName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      active
                          ? 'Active · ${a.phone}'
                          : (a.phone.isEmpty ? 'Tap to switch' : a.phone),
                      style: AppTextStyles.bodySmall,
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
                    label: const Text('Add account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
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
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                  ),
                ),
                if (p.phone != null && !p.hasPlaceholderName) ...[
                  const Gap(4),
                  Text(
                    PhoneUtils.formatDisplay(p.phone!),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const Gap(8),
                Row(
                  children: [
                    const Icon(Icons.star, size: 18, color: Colors.black),
                    const Gap(4),
                    Text(
                      rating.toStringAsFixed(2),
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
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
                    color: AppColors.textMuted,
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
              backgroundColor: const Color(0xFFE8E8E8),
              backgroundImage: (p.avatarUrl != null &&
                      p.avatarUrl!.startsWith('http'))
                  ? NetworkImage(p.avatarUrl!)
                  : null,
              child: (p.avatarUrl != null && p.avatarUrl!.startsWith('http'))
                  ? null
                  : Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom_outlined, size: 22),
                const Gap(8),
                Text(
                  'Family Assist',
                  style: AppTextStyles.headingSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Gap(6),
            Text(
              'Book help for a parent or relative, then share a live link so family can see when a helper is coming — without OTP codes.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
            const Gap(12),
            if (others.isEmpty)
              Text(
                'Add another profile on this phone first (Accounts above), then book for them here.',
                style: AppTextStyles.bodySmall,
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
                      foregroundColor: Colors.black,
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
              label: const Text('Split one problem into several tasks'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _a11yCard() {
    return BlocBuilder<A11yCubit, bool>(
      builder: (context, on) {
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  onChanged: (v) => context.read<A11yCubit>().setEnabled(v),
                  title: Text(
                    'Accessibility Mode',
                    style: AppTextStyles.headingSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Opt-in. When on, use the Access button (mobile) or Accessibility in the sidebar (desktop) for Speak & Describe — no top banner.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.helperAccent,
                ),
                if (on) ...[
                  const Gap(4),
                  TextButton.icon(
                    onPressed: () => showA11yDescribeSheet(
                      context,
                      hint: 'Zivo Account screen — accessibility settings',
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Describe this screen'),
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

    return Material(
      color: Colors.white,
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
                      ),
                    ),
                    const Gap(4),
                    Text(
                      body,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Gap(10),
                    Text(
                      cta,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black54),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
              Icon(icon, size: 26, color: Colors.black),
              const Gap(8),
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCard(UserProfile p, bool isHelper) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          _menuRow(
            Icons.person_outline,
            'Manage account',
            () => context.push(AppRoutes.settings),
          ),
          _divider(),
          _menuRow(
            Icons.admin_panel_settings_outlined,
            'Admin Dashboard',
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
            Icons.handshake_outlined,
            isHelper ? 'Helper job feed' : 'Switch to Helper mode',
            () {
              if (isHelper) {
                context.go(AppRoutes.shell);
              } else {
                context.read<ModeCubit>().toggleMode().catchError((_) {});
                context.go(AppRoutes.shell);
              }
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(icon, color: accent ?? Colors.black, size: 24),
      title: Text(
        title,
        style: AppTextStyles.bodyLarge.copyWith(
          fontWeight: FontWeight.w500,
          color: accent ?? Colors.black,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }

  Widget _signOutButton() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: const Color(0xFFEEEEEE),
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
