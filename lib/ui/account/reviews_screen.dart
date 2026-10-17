import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/user_review.dart';
import 'package:hyperlocal/data/repositories/trust_repository.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  List<UserReview> _items = [];
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
        await context.read<TrustRepository>().getReviewsForUser(auth.profile.id);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZivoPalette.of(context).canvas,
      appBar: AppBar(
        title: Text('Reviews', style: AppTextStyles.headingMedium),
        backgroundColor: ZivoPalette.of(context).canvas,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Reviews unlock after completed jobs only. '
                      'This prevents fake ratings before real work.',
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
                    final r = _items[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ZivoPalette.of(context).surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '★' * r.rating + '☆' * (5 - r.rating),
                                style: const TextStyle(
                                  color: AppColors.warningColor,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                r.reviewerName ?? 'User',
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          ),
                          if (r.comment != null) ...[
                            const Gap(8),
                            Text(r.comment!, style: AppTextStyles.bodyMedium),
                          ],
                          const Gap(6),
                          Text(
                            r.isAboutHelper ? 'As helper' : 'As client',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: ZivoPalette.of(context).textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
