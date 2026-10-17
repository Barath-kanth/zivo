import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/community_guidelines.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings — privacy, guidelines, mode info, sign out (Uber-style account).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZivoPalette.of(context).canvas,
      appBar: AppBar(
        title: Text('Settings', style: AppTextStyles.headingMedium),
        backgroundColor: ZivoPalette.of(context).canvas,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('Account', style: AppTextStyles.labelLarge),
          const Gap(8),
          _card(context, [
            _row(
              context,
              Icons.person_outline,
              'Edit profile / KYC',
              () => context.push(AppRoutes.onboarding),
            ),
            _row(
              context,
              Icons.badge_outlined,
              'Qualifications',
              () => context.push(AppRoutes.qualifications),
            ),
            _row(
              context,
              Icons.phone_iphone_outlined,
              'Phone & recovery',
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Phone is verified via OTP (+94). Use recovery email from the login screen if needed.',
                    ),
                  ),
                );
              },
            ),
          ]),
          const Gap(20),
          Text('Safety & legal', style: AppTextStyles.labelLarge),
          const Gap(8),
          _card(context, [
            _row(
              context,
              Icons.gavel_outlined,
              'Community guidelines',
              () => context.push(AppRoutes.guidelines),
            ),
            _row(
              context,
              Icons.privacy_tip_outlined,
              'Privacy & data',
              () => _showPrivacy(context),
            ),
            _row(
              context,
              Icons.admin_panel_settings_outlined,
              'Admin Dashboard (KYC)',
              () => context.push(AppRoutes.admin),
            ),
            _row(
              context,
              Icons.report_outlined,
              'Report a safety issue',
              () => _showReport(context),
            ),
          ]),
          const Gap(20),
          Text('App', style: AppTextStyles.labelLarge),
          const Gap(8),
          _card(context, [
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Guidelines version', style: AppTextStyles.bodyLarge),
              subtitle: Text(
                CommunityGuidelines.currentVersion,
                style: AppTextStyles.bodySmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: Text('Operating region', style: AppTextStyles.bodyLarge),
              subtitle: Text(
                'Sri Lanka · LKR · PostGIS local dispatch (not Google S2)',
                style: AppTextStyles.bodySmall,
              ),
            ),
          ]),
          const Gap(28),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout, color: AppColors.errorColor),
              label: Text(
                'Sign out',
                style: AppTextStyles.buttonLabel.copyWith(
                  color: AppColors.errorColor,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.errorColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const Gap(12),
          Text(
            'Signing out clears your session on this device. '
            'Demo sessions expire automatically after 10 minutes.',
            style: AppTextStyles.bodySmall.copyWith(color: ZivoPalette.of(context).textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Material(
      color: ZivoPalette.of(context).surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title, style: AppTextStyles.bodyLarge),
      trailing: Icon(Icons.chevron_right, color: ZivoPalette.of(context).textMuted),
      onTap: onTap,
    );
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Privacy & data', style: AppTextStyles.headingMedium),
            const Gap(12),
            Text(
              'We store phone, NIC images, and qualification docs in private storage for verification. '
              'KYC fields are not publicly readable. Policy violations store hashed snippets only. '
              'Do not upload documents that are not yours — impersonation is prohibited under Sri Lankan law.',
              style: AppTextStyles.bodyMedium.copyWith(height: 1.45),
            ),
            if (AppConfig.privacyPolicyUrl != null) ...[
              const Gap(16),
              TextButton(
                onPressed: () {
                  // ignore: discarded_futures
                  launchUrl(
                    Uri.parse(AppConfig.privacyPolicyUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('Open full Privacy Policy'),
              ),
            ],
            if (AppConfig.accountDeletionUrl != null) ...[
              TextButton(
                onPressed: () {
                  launchUrl(
                    Uri.parse(AppConfig.accountDeletionUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('Account deletion'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report a safety issue', style: AppTextStyles.headingMedium),
            const Gap(12),
            Text(
              'If someone asks you to move cash, weapons, drugs, or fake IDs — decline and report. '
              'In an emergency, contact local police (119) first. ${AppBrand.name} support reviews flagged accounts.',
              style: AppTextStyles.bodyMedium.copyWith(height: 1.45),
            ),
            const Gap(16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Thanks — safety reports are logged for review.',
                      ),
                    ),
                  );
                },
                child: Text(
                  'I understand',
                  style: AppTextStyles.buttonLabel.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
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
            child: const Text('Sign out',
                style: TextStyle(color: AppColors.errorColor)),
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
