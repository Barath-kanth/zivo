import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/data/models/user_profile.dart';

/// Returns true if the user is signed in; otherwise opens login and returns false.
Future<bool> requireAuth(BuildContext context, {String? returnTo}) async {
  final state = context.read<AuthBloc>().state;
  if (state is AuthAuthenticated) return true;

  final target = returnTo ?? GoRouterState.of(context).uri.toString();
  final q = Uri.encodeComponent(target);
  if (context.mounted) {
    context.push('${AppRoutes.login}?returnTo=$q');
  }
  return false;
}

/// Signed-in + KYC verified. Blocks posting / accepting work until admin approves.
Future<bool> requireVerified(
  BuildContext context, {
  String? returnTo,
  String message =
      'Verify your identity first. Zivo Admin must approve your documents before you can post or help.',
}) async {
  if (!await requireAuth(context, returnTo: returnTo)) return false;
  if (!context.mounted) return false;

  final state = context.read<AuthBloc>().state;
  if (state is! AuthAuthenticated) return false;

  final UserProfile profile = state.profile;
  if (profile.isKycVerified) return true;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        profile.isKycPending
            ? 'Documents under review. You can post or help after Zivo Admin approves you.'
            : message,
      ),
      duration: const Duration(seconds: 4),
    ),
  );
  context.push(AppRoutes.onboarding);
  return false;
}
