import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Cup-unique: runs Gemini Trust Arbitrator over the job evidence pack.
Future<void> showTrustReviewSheet(
  BuildContext context, {
  required String taskId,
  String? receiptNote,
}) async {
  final reasonCtrl = TextEditingController();
  var loading = false;
  Map<String, dynamic>? result;
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.backgroundDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> run() async {
            setLocal(() {
              loading = true;
              error = null;
              result = null;
            });
            try {
              final res = await ctx.read<TaskRepository>().runTrustReview(
                    taskId: taskId,
                    reason: reasonCtrl.text.trim(),
                    receiptNote: receiptNote,
                  );
              setLocal(() {
                result = res;
                loading = false;
              });
            } catch (e) {
              setLocal(() {
                loading = false;
                error = '$e'.replaceFirst('Exception: ', '');
              });
            }
          }

          final verdict = result?['verdict']?.toString();
          final Color verdictColor = switch (verdict) {
            'continue' => AppColors.successColor,
            'hold_escrow' => AppColors.warningColor,
            'escalate' => AppColors.errorColor,
            _ => AppColors.accent,
          };

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const Gap(14),
                  Text('Trust Arbitrator', style: AppTextStyles.headingMedium),
                  const Gap(4),
                  Text(
                    'Reviews chat, timeline, neighbor vouch, and purchase signals — then can hold escrow. Not a generic ticket form.',
                    style: AppTextStyles.bodySmall.copyWith(height: 1.35),
                  ),
                  const Gap(14),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'What’s wrong? (optional)',
                      hintText: 'e.g. helper asked to pay cash outside app',
                    ),
                  ),
                  const Gap(12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: loading ? null : run,
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.gavel_rounded, size: 18),
                      label: Text(
                        loading ? 'Reviewing evidence…' : 'Run trust review',
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const Gap(12),
                    Text(
                      error!,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.errorColor),
                    ),
                  ],
                  if (result != null) ...[
                    const Gap(16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: verdictColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: verdictColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verdict: ${verdict ?? '—'}'
                            '${result!['confidence'] != null ? ' · ${(100 * (result!['confidence'] as num)).round()}% confidence' : ''}',
                            style: AppTextStyles.headingSmall
                                .copyWith(color: verdictColor),
                          ),
                          const Gap(8),
                          Text(
                            '${result!['summary'] ?? ''}',
                            style: AppTextStyles.bodyMedium
                                .copyWith(height: 1.4),
                          ),
                          if ((result!['evidence_used'] as List?)
                                  ?.isNotEmpty ==
                              true) ...[
                            const Gap(10),
                            Text(
                              'Evidence: ${(result!['evidence_used'] as List).join(' · ')}',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if ((result!['recommended_actions'] as List?)
                                  ?.isNotEmpty ==
                              true) ...[
                            const Gap(8),
                            for (final a
                                in (result!['recommended_actions'] as List))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $a',
                                  style: AppTextStyles.bodySmall,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const Gap(8),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  reasonCtrl.dispose();
}
