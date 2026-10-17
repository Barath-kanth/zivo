import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/services/auth_service.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({
    super.key,
    required this.phone,
    this.freeDevOtpCode,
    this.returnTo,
    this.deliveryWarning,
    this.viaTextBee = false,
  });

  final String phone;
  final String? freeDevOtpCode;
  final String? returnTo;
  final String? deliveryWarning;
  final bool viaTextBee;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _otpCtrl = TextEditingController();
  Timer? _timer;
  int _secondsLeft = AuthService.otpResendCooldownSeconds;
  String? _freeCode;
  String? _warning;
  bool _viaTextBee = false;

  @override
  void initState() {
    super.initState();
    _freeCode = widget.freeDevOtpCode;
    _warning = widget.deliveryWarning;
    _viaTextBee = widget.viaTextBee;
    if (_freeCode != null) {
      _otpCtrl.text = _freeCode!;
    }
    _startCooldown();
  }

  void _startCooldown([int? seconds]) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds ?? AuthService.otpResendCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _verify() {
    final token = _otpCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (token.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code (digits only)')),
      );
      return;
    }
    context.read<AuthBloc>().add(
          AuthPhoneOtpVerified(
            phone: widget.phone,
            token: token,
            issuedCode: _freeCode ?? widget.freeDevOtpCode,
          ),
        );
  }

  void _resend() {
    if (_secondsLeft > 0) return;
    context.read<AuthBloc>().add(AuthPhoneOtpRequested(phone: widget.phone));
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated || state is AuthNeedsOnboarding) {
            context.go(AppRoutes.afterLogin(widget.returnTo));
          } else if (state is AuthOtpSent) {
            setState(() {
              _freeCode = state.freeDevOtpCode;
              _warning = state.deliveryWarning;
              _viaTextBee = state.viaTextBee;
              if (_freeCode != null) {
                _otpCtrl.text = _freeCode!;
              } else {
                _otpCtrl.clear();
              }
            });
            if (state.deliveryWarning != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.deliveryWarning!),
                  backgroundColor: AppColors.warningColor,
                  duration: const Duration(seconds: 6),
                ),
              );
            }
            _startCooldown();
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
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter OTP', style: AppTextStyles.displayMedium),
                  const Gap(8),
                  Text(
                    _viaTextBee
                        ? 'SMS sent via free gateway to ${PhoneUtils.formatDisplay(widget.phone)}'
                        : 'Sent to ${PhoneUtils.formatDisplay(widget.phone)}',
                    style: AppTextStyles.bodyLarge,
                  ),
                  if (_viaTextBee && _freeCode == null) ...[
                    const Gap(16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Check your SMS for the 6-digit code. The message starts with ZIVO:.\n'
                        'Sender name (e.g. a saved contact) is your phone’s address book — '
                        'other users see the gateway number. Uber-style “ZIVO” as From needs a paid SMS brand (Twilio), not TextBee.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (_warning != null && _freeCode != null) ...[
                    const Gap(12),
                    Text(
                      _warning!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.warningColor,
                      ),
                    ),
                  ],
                  if (_freeCode != null) ...[
                    const Gap(16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.successColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.successColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _viaTextBee
                            ? 'Code: $_freeCode'
                            : 'Free test mode (SMS not delivered): your code is $_freeCode',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.successColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Gap(32),
                  TextFormField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: AppTextStyles.displayMedium.copyWith(letterSpacing: 8),
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      counterText: '',
                      labelText: '6-digit code',
                    ),
                    onFieldSubmitted: (_) => _verify(),
                  ),
                  const Gap(24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : Text('Verify', style: AppTextStyles.buttonLabel),
                    ),
                  ),
                  const Gap(16),
                  Center(
                    child: TextButton(
                      onPressed: (_secondsLeft > 0 || loading) ? null : _resend,
                      child: Text(
                        _secondsLeft > 0
                            ? 'Resend in ${_secondsLeft}s'
                            : 'Resend OTP',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _secondsLeft > 0
                              ? AppColors.textMuted
                              : AppColors.accent,
                        ),
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
}
