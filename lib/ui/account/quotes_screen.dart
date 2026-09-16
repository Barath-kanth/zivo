import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/user_review.dart';
import 'package:hyperlocal/data/repositories/trust_repository.dart';

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  List<JobQuote> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final list =
        await context.read<TrustRepository>().getMyQuotes(auth.profile.id);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: Text('Job quotes', style: AppTextStyles.headingMedium),
        backgroundColor: AppColors.backgroundDark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Helpers can send a price quote before accepting a job. '
                      'Only KYC-verified helpers may quote. Quote messages are policy-scanned.',
                      style: AppTextStyles.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Gap(10),
                  itemBuilder: (_, i) {
                    final q = _items[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'LKR ${q.amountLkr.toStringAsFixed(0)}',
                                style: AppTextStyles.headingSmall,
                              ),
                              const Spacer(),
                              Text(
                                q.status.toUpperCase(),
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          if (q.message != null) ...[
                            const Gap(6),
                            Text(q.message!, style: AppTextStyles.bodyMedium),
                          ],
                          if (q.estimatedHours != null) ...[
                            const Gap(4),
                            Text(
                              '~${q.estimatedHours} h',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
