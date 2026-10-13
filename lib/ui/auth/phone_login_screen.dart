import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/services/device_account_store.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';

/// Uber LK–inspired login: bold brand intro + phone OTP / demo.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _showRecovery = false;
  bool _addingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    final adding = await DeviceAccountStore.isAddingAccount();
    final prefill = await DeviceAccountStore.prefillPhone();
    if (!mounted) return;
    setState(() => _addingAccount = adding);
    if (prefill != null && prefill.isNotEmpty) {
      // Strip +94 for the field (UI already shows +94 prefix)
      var local = prefill.replaceAll(RegExp(r'[^\d]'), '');
      if (local.startsWith('94') && local.length > 9) {
        local = local.substring(2);
      }
      if (local.startsWith('0')) local = local.substring(1);
      _phoneCtrl.text = local;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _sendOtp() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(
          AuthPhoneOtpRequested(phone: _phoneCtrl.text.trim()),
        );
  }

  void _sendRecovery() {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid recovery email')),
      );
      return;
    }
    context.read<AuthBloc>().add(AuthRecoveryEmailLinkRequested(email: email));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthOtpSent) {
            context.go(AppRoutes.otpVerify, extra: {
              'phone': state.phone,
              'freeCode': state.freeDevOtpCode,
            });
          } else if (state is AuthAuthenticated) {
            context.go(AppRoutes.shell);
          } else if (state is AuthNeedsOnboarding) {
            context.go(AppRoutes.shell);
          } else if (state is AuthRecoveryEmailSent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Recovery link sent to ${state.email}'),
                backgroundColor: AppColors.successColor,
              ),
            );
          } else if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.errorColor,
              ),
            );
          }
        },
        builder: (context, state) {
          final loading = state is AuthLoading;
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 5, child: _buildFormPane(loading)),
                Expanded(flex: 5, child: _buildHeroPane()),
              ],
            );
          }
          return Column(
            children: [
              SizedBox(height: 200, child: _buildHeroPane(compact: true)),
              Expanded(child: _buildFormPane(loading)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroPane({bool compact = false}) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF171717), Color(0xFF171717)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            bottom: -30,
            child: Icon(
              Icons.handshake_rounded,
              size: compact ? 160 : 280,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            left: compact ? 24 : 40,
            top: compact ? 28 : 48,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Sri Lanka · LKR',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const Gap(28),
                  const Text(
                    'Ready to help\nnearby?',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 42,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const Gap(12),
                  Text(
                    'Post a task or earn as a Helper — verified people, local work.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPane(bool loading) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ZivoLogo(size: 40, showWordmark: true)
                  .animate()
                  .fadeIn(duration: 300.ms),
              const Gap(12),
              const A11yAuthBar(
                readText:
                    'Zivo phone login. Enter your Sri Lanka mobile number starting with plus 94, then continue for a free OTP code. Accessibility Mode can read this screen aloud.',
                hint: 'Zivo phone login — enter mobile and continue for OTP',
              ),
              if (_addingAccount) ...[
                const Gap(16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.helperAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.helperAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Adding another person on this phone. Enter their mobile to create or sign in — perfect when they don’t have a smartphone.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const Gap(28),
              Text(
                _addingAccount
                    ? 'Add their\n${AppBrand.name} profile.'
                    : '${AppBrand.tagline}\nwith ${AppBrand.name}.',
                style: AppTextStyles.displayLarge.copyWith(
                  fontSize: 36,
                  height: 1.05,
                ),
              ).animate().fadeIn(delay: 60.ms, duration: 400.ms),
              const Gap(10),
              Text(
                _addingAccount
                    ? 'One phone, many neighbors. Each profile keeps its own wallet, jobs, and verification.'
                    : AppBrand.story,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
              const Gap(28),
              Text('Mobile number', style: AppTextStyles.labelLarge),
              const Gap(8),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: AppTextStyles.bodyLarge,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d+\s-]')),
                ],
                decoration: InputDecoration(
                  hintText: '77 123 4567',
                  filled: true,
                  fillColor: const Color(0xFFF3F3F3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 14, right: 6),
                    child: Text(
                      '+94',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                ),
                validator: (v) {
                  if (!PhoneUtils.isValidSriLankaMobile(v ?? '')) {
                    return 'Enter a valid 9-digit mobile';
                  }
                  return null;
                },
              ),
              const Gap(16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _addingAccount
                              ? 'Continue for this person'
                              : 'Continue',
                          style: AppTextStyles.buttonLabel.copyWith(
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const Gap(8),
              Text(
                'We’ll text a one-time code. No password to steal.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const Gap(12),
              TextButton(
                onPressed: () =>
                    setState(() => _showRecovery = !_showRecovery),
                child: Text(
                  _showRecovery
                      ? 'Hide recovery email'
                      : 'Account recovery email (optional)',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_showRecovery) ...[
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Recovery email',
                    filled: true,
                    fillColor: const Color(0xFFF3F3F3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const Gap(10),
                OutlinedButton(
                  onPressed: loading ? null : _sendRecovery,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Send recovery link'),
                ),
              ],
              if (AppConfig.demoAllowed) ...[
              const Gap(24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textMuted)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const Gap(16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => context
                          .read<AuthBloc>()
                          .add(AuthDemoLoginRequested()),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.black, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    'Explore Demo Mode',
                    style: AppTextStyles.buttonLabel.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              ],
              const Gap(20),
              Text(
                'By continuing you agree to ${AppBrand.name} Community Guidelines for Sri Lanka. Unlawful tasks are blocked.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
