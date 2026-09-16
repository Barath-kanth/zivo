import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/phone_utils.dart';
import 'package:hyperlocal/data/repositories/profile_repository.dart';

/// Separate admin console — review each user's KYC documents and set
/// verified / rejected per profile.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _busyId;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await context.read<ProfileRepository>().listPendingKyc();
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  Future<void> _decide(String userId, String status) async {
    setState(() => _busyId = userId);
    try {
      await context.read<ProfileRepository>().reviewKycDecision(
            userId: userId,
            status: status,
            reason: status == 'rejected' ? 'Documents did not match' : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'verified'
                ? 'User marked Verified'
                : 'User marked Rejected',
          ),
          backgroundColor: status == 'verified'
              ? AppColors.successColor
              : AppColors.errorColor,
        ),
      );
      // If admin approved their own account, refresh badge immediately.
      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated && auth.profile.id == userId) {
        context.read<AuthBloc>().add(AuthProfileRefreshRequested());
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Action failed. Check Cloud Run API / KYC endpoints.\n$e',
          ),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _thumb(String? url, String label) {
    final hasHttp = url != null && url.startsWith('http');
    return Expanded(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 1,
              child: hasHttp
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(label),
                    )
                  : _placeholder(label),
            ),
          ),
          const Gap(4),
          Text(label, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  Widget _placeholder(String label) {
    return ColoredBox(
      color: AppColors.borderColor.withValues(alpha: 0.4),
      child: Center(
        child: Text(
          label,
          style: AppTextStyles.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.shell);
            }
          },
        ),
        title: Text(
          'Admin Dashboard',
          style: AppTextStyles.headingMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E5E5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KYC document review',
                    style: AppTextStyles.headingSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(6),
                  Text(
                    'Each submission is one user. Match photo + selfie to NIC, '
                    'then Approve (status → verified) or Reject.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(20),
            Text(
              'Pending (${_pending.length})',
              style: AppTextStyles.headingSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _loadError!,
                  style: AppTextStyles.bodyMedium,
                ),
              )
            else if (_pending.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'No pending KYC. When a user submits NIC + selfie, they appear here.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else
              ..._pending.map((row) {
                final id = row['id']?.toString() ?? '';
                final name = row['full_name']?.toString().trim();
                final nic = row['nic_number']?.toString() ?? '—';
                final phoneRaw = row['phone']?.toString();
                final phone = (phoneRaw != null && phoneRaw.isNotEmpty)
                    ? PhoneUtils.formatDisplay(phoneRaw)
                    : '—';
                final title = (name != null && name.isNotEmpty) ? name : phone;
                final busy = _busyId == id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E5E5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const Gap(4),
                      Text('Phone: $phone', style: AppTextStyles.bodySmall),
                      Text('NIC: $nic', style: AppTextStyles.bodySmall),
                      const Gap(12),
                      Row(
                        children: [
                          _thumb(row['avatar_url']?.toString(), 'Photo'),
                          const Gap(8),
                          _thumb(row['nic_image_url']?.toString(), 'NIC'),
                          const Gap(8),
                          _thumb(row['selfie_image_url']?.toString(), 'Selfie'),
                        ],
                      ),
                      const Gap(14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: busy
                                  ? null
                                  : () => _decide(id, 'verified'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.successColor,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Approve → Verified'),
                            ),
                          ),
                          const Gap(8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _decide(id, 'rejected'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.errorColor,
                                side: const BorderSide(
                                  color: AppColors.errorColor,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Reject'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
