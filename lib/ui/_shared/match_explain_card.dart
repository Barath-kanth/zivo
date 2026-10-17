import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/ui/_shared/a11y_widgets.dart';

/// Strip Vertex / HTTP / JSON error tails from match explanations.
String sanitizeMatchExplanation(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return 'Matched using skills, distance, availability and trust.';
  }
  final cutMarkers = [
    '(Gemini tools unavailable',
    'Gemini tools unavailable',
    '[VertexAI',
    'VertexAI.ClientError',
    'got status:',
    'RESOURCE_EXHAUSTED',
    '"error":',
    'Please refer to https://cloud.google.com',
  ];
  for (final m in cutMarkers) {
    final i = text.indexOf(m);
    if (i >= 0) {
      text = text.substring(0, i).trim();
      break;
    }
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.endsWith('(') || text.endsWith('·') || text.endsWith(':')) {
    text = text.substring(0, text.length - 1).trim();
  }
  if (text.isEmpty || text.length < 12) {
    return 'Matched using skills, distance, availability and trust.';
  }
  return text;
}

/// Client-facing "Explain my match" — skills, distance, trust, disputes.
class MatchExplainCard extends StatefulWidget {
  const MatchExplainCard({
    super.key,
    required this.explanation,
    this.reasons = const [],
    this.helperName,
    this.mode,
    this.nearestDeprioritized = false,
    this.compact = false,
  });

  final String explanation;
  final List<String> reasons;
  final String? helperName;
  final String? mode;
  final bool nearestDeprioritized;
  final bool compact;

  @override
  State<MatchExplainCard> createState() => _MatchExplainCardState();
}

class _MatchExplainCardState extends State<MatchExplainCard> {
  String? _plain;
  List<String> _bullets = const [];

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clean = sanitizeMatchExplanation(
      _plain ?? widget.explanation,
    );
    final explanation = widget.explanation;
    final reasons = widget.reasons;
    final helperName = widget.helperName;
    final mode = widget.mode;
    final nearestDeprioritized = widget.nearestDeprioritized;
    final compact = widget.compact;
    final chips = reasons
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty && !r.toLowerCase().contains('vertex'))
        .take(6)
        .toList();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.helperAccent.withValues(alpha: 0.22)
                      : AppColors.brandGreenSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  color: AppColors.helperAccent,
                  size: 20,
                ),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      helperName == null || helperName.isEmpty
                          ? 'Explain my match'
                          : 'Why ${helperName.split(' ').first} fits',
                      style: AppTextStyles.headingSmall.copyWith(
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (mode != null && mode.isNotEmpty)
                      Text(
                        mode == 'dispatch'
                            ? 'Instant Dispatch'
                            : mode == 'gemini'
                                ? 'AI-ranked match'
                                : 'Constraint match',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          Text(
            clean,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 13,
              height: 1.45,
              color: palette.textPrimary,
            ),
          ),
          if (_bullets.isNotEmpty) ...[
            const Gap(8),
            ..._bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $b',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ],
          Row(
            children: [
              A11yReadButton(text: clean),
              A11ySimplifyButton(
                text: explanation,
                onSimplified: (plain, bullets) {
                  setState(() {
                    _plain = plain;
                    _bullets = bullets;
                  });
                },
              ),
            ],
          ),
          if (nearestDeprioritized) ...[
            const Gap(10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningColor.withValues(alpha: isDark ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.warningColor,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      'A nearer helper was skipped due to trust or dispute history.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.warningColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips
                  .map(
                    (r) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        r,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class MatchCandidateTile extends StatelessWidget {
  const MatchCandidateTile({
    super.key,
    required this.name,
    required this.distanceKm,
    required this.score,
    required this.reasons,
    this.trustTier,
    this.disputeCount,
    this.recommended = false,
    this.onHire,
    this.hiring = false,
  });

  final String name;
  final double distanceKm;
  final int score;
  final List<String> reasons;
  final String? trustTier;
  final int? disputeCount;
  final bool recommended;
  final VoidCallback? onHire;
  final bool hiring;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: recommended ? AppColors.helperAccent : palette.border,
          width: recommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isDark
                    ? palette.accent.withValues(alpha: 0.22)
                    : AppColors.surfaceDark,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: AppTextStyles.headingSmall.copyWith(
                              fontSize: 14,
                              color: palette.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (recommended) ...[
                          const Gap(6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.helperAccent.withValues(alpha: 0.22)
                                  : AppColors.brandGreenSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Best fit',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.helperAccent,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km'
                      '${trustTier != null ? ' · $trustTier trust' : ''}'
                      '${disputeCount != null && disputeCount! > 0 ? ' · $disputeCount dispute(s)' : ''}'
                      ' · score $score',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const Gap(10),
            ...reasons.take(3).map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: AppColors.helperAccent,
                        ),
                        const Gap(6),
                        Expanded(
                          child: Text(
                            r,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (onHire != null) ...[
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: hiring ? null : onHire,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  disabledBackgroundColor: palette.border,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: hiring
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.onAccent,
                        ),
                      )
                    : Text(
                        'Hire ${name.split(' ').first}',
                        style: AppTextStyles.buttonLabel.copyWith(
                          color: palette.onAccent,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
