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
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/ui/_shared/zivo_logo.dart';

/// Phone-first login (free OTP) + Google; email under "More options".
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.returnTo});

  final String? returnTo;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  bool _showEmail = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  String? get _returnTo {
    final fromWidget = widget.returnTo;
    if (fromWidget != null && fromWidget.isNotEmpty) {
      try {
        return Uri.decodeComponent(fromWidget);
      } catch (_) {
        return fromWidget;
      }
    }
    return GoRouterState.of(context).uri.queryParameters['returnTo'];
  }

  /// Admin console login — phone OTP only (no email signup / rate limits).
  bool get _adminLogin {
    final r = (_returnTo ?? '').toLowerCase();
    return r.contains('/admin') || r.contains('/ops/kyc');
  }

  void _goAfterAuth() {
    final dest = _returnTo;
    if (dest != null && dest.isNotEmpty) {
      try {
        context.go(Uri.decodeComponent(dest));
        return;
      } catch (_) {
        context.go(dest);
        return;
      }
    }
    context.go(AppRoutes.shell);
  }

  void _sendOtp() {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(
          AuthPhoneOtpRequested(phone: _phoneCtrl.text.trim()),
        );
  }

  void _submitEmail() {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    if (_isSignUp) {
      context.read<AuthBloc>().add(AuthSignUpRequested(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            fullName: _nameCtrl.text.trim(),
            username: _usernameCtrl.text.trim().isEmpty
                ? null
                : _usernameCtrl.text.trim(),
          ));
    } else {
      context.read<AuthBloc>().add(AuthSignInRequested(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          ));
    }
  }

  Future<void> _showGoogleSqlFixDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Sign-In'),
        content: const Text(
          'Google Sign-In will use Firebase Auth on GCP. '
          'For the Cup demo, sign in with phone OTP (code shown on screen) '
          'or email/password against the Cloud Run API.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final freeOtp = AppConfig.freeOtpAllowed;

    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          setState(() => _busy = state is AuthLoading);
          if (state is AuthOtpSent) {
            context.go(AppRoutes.otpVerify, extra: {
              'phone': state.phone,
              'freeCode': state.freeDevOtpCode,
              'returnTo': _returnTo,
              'deliveryWarning': state.deliveryWarning,
              'viaTextBee': state.viaTextBee,
            });
          } else if (state is AuthAuthenticated) {
            _goAfterAuth();
          } else if (state is AuthNeedsOnboarding) {
            _goAfterAuth();
          } else if (state is AuthFailure) {
            final isProfileFix =
                state.message.toLowerCase().contains('profile') ||
                    state.message.toLowerCase().contains('database error') ||
                    state.message.toLowerCase().contains('007_fix');
            if (isProfileFix) {
              _showGoogleSqlFixDialog(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.errorColor,
                ),
              );
            }
          }
        },
        builder: (context, state) {
          return Row(
            children: [
              if (wide) Expanded(child: _brandPanel()),
              Expanded(
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: () => context.go(AppRoutes.shell),
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Continue browsing',
                              ),
                            ),
                            if (!wide) ...[
                              const Center(
                                child: ZivoLogo(
                                  size: 52,
                                  showWordmark: true,
                                ),
                              ),
                              const Gap(8),
                              Text(
                                AppBrand.tagline,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Gap(24),
                            ] else ...[
                              Text(
                                'Sign in to continue',
                                style: AppTextStyles.headingLarge.copyWith(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Gap(6),
                              Text(
                                'Post tasks or help nearby — same phone OTP as Uber.',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Gap(24),
                            ],
                            Form(
                              key: _phoneFormKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Mobile number',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Gap(8),
                                  TextFormField(
                                    controller: _phoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(9),
                                    ],
                                    validator: (v) {
                                      final e164 = PhoneUtils.toE164(v ?? '');
                                      if (e164 == null) {
                                        return 'Enter a valid LK mobile';
                                      }
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      prefixIcon: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 14,
                                          right: 8,
                                        ),
                                        child: Text(
                                          AppConfig.defaultCountryCode,
                                          style: AppTextStyles.bodyLarge
                                              .copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      prefixIconConstraints:
                                          const BoxConstraints(minWidth: 0),
                                      hintText: '7X XXX XXXX',
                                      filled: true,
                                      fillColor: AppColors.surfaceDark,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Colors.black,
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Gap(8),
                                  Text(
                                    freeOtp
                                        ? (_adminLogin
                                            ? 'Admin: use phone OTP (no email signup).'
                                            : 'Free OTP (no SMS cost) — code shown on next screen.')
                                        : 'We’ll text a 6-digit code.',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  const Gap(16),
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _busy ? null : _sendOtp,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: _busy
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              _adminLogin
                                                  ? 'Admin continue with phone'
                                                  : 'Continue with phone',
                                              style: AppTextStyles.buttonLabel
                                                  .copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_adminLogin) ...[
                            const Gap(20),
                            _divider('or'),
                            const Gap(16),
                            _googleButton(),
                            const Gap(12),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(
                                        () => _showEmail = !_showEmail,
                                      ),
                              child: Text(
                                _showEmail
                                    ? 'Hide email options'
                                    : 'More options (email)',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_showEmail) ...[
                              const Gap(8),
                              Form(
                                key: _emailFormKey,
                                child: Column(
                                  children: [
                                    if (_isSignUp) ...[
                                      _field(
                                        controller: _nameCtrl,
                                        label: 'Full name',
                                        icon: Icons.person_outline_rounded,
                                        validator: (v) =>
                                            (v == null || v.trim().length < 2)
                                                ? 'Enter your full name'
                                                : null,
                                      ),
                                      const Gap(12),
                                    ],
                                    _field(
                                      controller: _emailCtrl,
                                      label: _isSignUp
                                          ? 'Email'
                                          : 'Email or username',
                                      icon: Icons.mail_outline_rounded,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Required';
                                        }
                                        return null;
                                      },
                                    ),
                                    const Gap(12),
                                    _field(
                                      controller: _passwordCtrl,
                                      label: 'Password',
                                      icon: Icons.lock_outline_rounded,
                                      obscure: _obscurePassword,
                                      suffix: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 20,
                                        ),
                                        onPressed: () => setState(() =>
                                            _obscurePassword =
                                                !_obscurePassword),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Required';
                                        }
                                        if (_isSignUp && v.length < 8) {
                                          return 'At least 8 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                    if (_isSignUp) ...[
                                      const Gap(12),
                                      _field(
                                        controller: _confirmCtrl,
                                        label: 'Confirm password',
                                        icon: Icons.lock_outline_rounded,
                                        obscure: _obscureConfirm,
                                        suffix: IconButton(
                                          icon: Icon(
                                            _obscureConfirm
                                                ? Icons.visibility_outlined
                                                : Icons
                                                    .visibility_off_outlined,
                                            size: 20,
                                          ),
                                          onPressed: () => setState(() =>
                                              _obscureConfirm =
                                                  !_obscureConfirm),
                                        ),
                                        validator: (v) {
                                          if (v != _passwordCtrl.text) {
                                            return 'Passwords do not match';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                    const Gap(16),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: OutlinedButton(
                                        onPressed:
                                            _busy ? null : _submitEmail,
                                        child: Text(
                                          _isSignUp
                                              ? 'Create account'
                                              : 'Sign in with email',
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(
                                                () => _isSignUp = !_isSignUp,
                                              ),
                                      child: Text(
                                        _isSignUp
                                            ? 'Have an account? Sign in'
                                            : 'New? Create email account',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            ], // end !_adminLogin
                            if (AppConfig.demoAllowed) ...[
                              const Gap(8),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => context
                                        .read<AuthBloc>()
                                        .add(AuthDemoLoginRequested()),
                                child: Text(
                                  'Explore demo (dev only)',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ).animate().fadeIn(duration: 350.ms),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _brandPanel() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(48),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ZivoLogo(size: 64, showWordmark: true, markOnDark: true),
          Gap(24),
          Text(
            'Browse freely. Sign in when you post a task or help nearby.',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.white70,
              fontSize: 18,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _busy
            ? null
            : () => context.read<AuthBloc>().add(AuthGoogleSignInRequested()),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundColor: Colors.black,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: const Text(
                'G',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF4285F4),
                ),
              ),
            ),
            const Gap(10),
            Text(
              'Continue with Google',
              style: AppTextStyles.buttonLabel.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.borderColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.borderColor)),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.4),
        ),
      ),
    );
  }
}
