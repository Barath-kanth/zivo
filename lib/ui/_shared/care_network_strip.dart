import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/l10n/locale_cubit.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/core/utils/humanize_error.dart';
import 'package:hyperlocal/core/utils/speak_text.dart';
import 'package:hyperlocal/core/utils/voice_recorder.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';

/// Home "Care network": weather-aware advice, one-tap care actions, and a
/// plain-language community card — all wired to the voice helper.
class CareNetworkStrip extends StatefulWidget {
  const CareNetworkStrip({super.key});

  @override
  State<CareNetworkStrip> createState() => _CareNetworkStripState();
}

class _CareNetworkStripState extends State<CareNetworkStrip> {
  Map<String, dynamic>? _impact;
  Map<String, dynamic>? _resilience;
  bool _loading = true;
  bool _weatherOpen = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final repo = context.read<TaskRepository>();
      double lat = 6.9271;
      double lon = 79.8612;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (_) {
        /* Colombo default — getLastKnownPosition is unsupported on web */
      }
      final impact = await repo.impactSummary();
      final resilience = await repo.resilienceStatus(lat: lat, lon: lon);
      if (!mounted) return;
      setState(() {
        _impact = impact;
        _resilience = resilience;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Opens the voice helper. Fills [preset] but does **not** auto-ask or speak.
  Future<void> _openHelper({String? preset}) async {
    stopSpeaking();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: ZivoPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HelperSheet(preset: preset),
    );
    stopSpeaking();
    if (result == null || !mounted) return;
    final category = _categoryFrom(result['category']?.toString());
    final draft = <String, dynamic>{
      'category': category.name,
      if ((result['title']?.toString() ?? '').trim().isNotEmpty)
        'title': result['title'].toString().trim(),
      if ((result['description']?.toString() ?? '').trim().isNotEmpty)
        'description': result['description'].toString().trim(),
    };
    final returnTo = AppRoutes.createTask;
    if (!await requireAuth(context, returnTo: returnTo)) return;
    if (!mounted) return;
    if (!await requireVerified(context, returnTo: returnTo)) return;
    if (!mounted) return;
    // Post-frame so the sheet fully finishes closing before route change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.push(AppRoutes.createTask, extra: draft);
    });
  }

  /// Creative path for "Share a trip" — pick a path, always can go back.
  Future<void> _openShareTrip() async {
    stopSpeaking();
    final l = context.read<LocaleCubit>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: ZivoPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ShareTripSheet(
        onBack: () => Navigator.of(ctx).pop(),
        options: [
          (
            Icons.shopping_basket_rounded,
            const Color(0xFF0F766E),
            l.t('care.shareMarket'),
            l.t('care.shareMarketBody'),
            l.t('care.presetShareMarket'),
          ),
          (
            Icons.medication_rounded,
            const Color(0xFFB54708),
            l.t('care.sharePharmacy'),
            l.t('care.sharePharmacyBody'),
            l.t('care.presetSharePharmacy'),
          ),
          (
            Icons.local_shipping_rounded,
            const Color(0xFF1D4ED8),
            l.t('care.shareDrop'),
            l.t('care.shareDropBody'),
            l.t('care.presetShareDrop'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _openHelper(preset: choice);
  }

  static TaskCategory _categoryFrom(String? raw) {
    if (raw == null || raw.isEmpty) return TaskCategory.errandRun;
    final norm = raw.replaceAll(RegExp(r'[_\s-]'), '').toLowerCase();
    const aliases = <String, TaskCategory>{
      'fooddelivery': TaskCategory.groceryRun,
      'food': TaskCategory.groceryRun,
      'grocery': TaskCategory.groceryRun,
      'groceryrun': TaskCategory.groceryRun,
      'medicine': TaskCategory.hospitalCompanion,
      'pharmacy': TaskCategory.hospitalCompanion,
      'hospitalcompanion': TaskCategory.hospitalCompanion,
      'elder': TaskCategory.elderCare,
      'eldercare': TaskCategory.elderCare,
      'errand': TaskCategory.errandRun,
      'errandrun': TaskCategory.errandRun,
      'movinghelp': TaskCategory.movingHelp,
      'queuestanding': TaskCategory.queueStanding,
    };
    final aliased = aliases[norm];
    if (aliased != null) return aliased;
    for (final c in TaskCategory.values) {
      if (c.name.toLowerCase() == norm) return c;
    }
    return TaskCategory.errandRun;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final hazard = _resilience?['hazard']?.toString() ?? 'calm';
    final mm = (_resilience?['precip_mm_next_24h'] as num?)?.toDouble() ?? 0;
    final trips = (_impact?['trips_saved_estimate'] as num?)?.toInt() ?? 0;
    final co2 = (_impact?['co2e_kg_estimate'] as num?)?.toDouble() ?? 0;
    final fair = (_impact?['wage_floor_protections'] as num?)?.toInt() ?? 0;

    // Story-style guide: one clear question → three plain-language paths.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.t('care.guideTitle'),
            style: AppTextStyles.headingSmall.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: -0.2,
            ),
          ),
          const Gap(4),
          Text(
            l.t('care.guideBody'),
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textSecondary,
              height: 1.35,
              fontSize: 13,
            ),
          ),
          const Gap(12),
          if (!_loading || _resilience != null)
            _WeatherCard(
              hazard: hazard,
              mm: mm,
              open: _weatherOpen,
              onToggle: () => setState(() => _weatherOpen = !_weatherOpen),
              onPlan: () => _openHelper(preset: l.t('care.presetRain')),
            ),
          const Gap(10),
          _GuidePath(
            step: '1',
            color: const Color(0xFFBE185D),
            icon: Icons.favorite_rounded,
            title: l.t('care.actElder'),
            subtitle: l.t('care.actElderHint'),
            onTap: () => _openHelper(preset: l.t('care.presetElder')),
          ),
          const Gap(8),
          _GuidePath(
            step: '2',
            color: const Color(0xFFB54708),
            icon: Icons.medication_liquid_rounded,
            title: l.t('care.actMedicine'),
            subtitle: l.t('care.actMedicineHint'),
            onTap: () => _openHelper(preset: l.t('care.presetMedicine')),
          ),
          const Gap(8),
          _GuidePath(
            step: '3',
            color: const Color(0xFF0F766E),
            icon: Icons.diversity_3_rounded,
            title: l.t('care.actShare'),
            subtitle: l.t('care.actShareHint'),
            onTap: _openShareTrip,
          ),
          const Gap(10),
          _CommunityCard(
            trips: trips,
            co2: co2,
            fair: fair,
            onAsk: () => _openHelper(),
          ),
        ],
      ),
    );
  }
}

/// Full-width numbered path — clearer than tiny square tiles for new users.
class _GuidePath extends StatelessWidget {
  const _GuidePath({
    required this.step,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String step;
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? palette.card : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.28 : 0.16),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: AppTextStyles.headingSmall.copyWith(
                    color: isDark ? Colors.white : color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const Gap(12),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: isDark ? palette.accent : color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 280.ms)
        .slideX(begin: 0.04, curve: Curves.easeOutCubic);
  }
}

// ───────────────────────── Weather ─────────────────────────

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.hazard,
    required this.mm,
    required this.open,
    required this.onToggle,
    required this.onPlan,
  });

  final String hazard;
  final double mm;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final calm = hazard == 'calm';
    final color = switch (hazard) {
      'emergency' || 'alert' => const Color(0xFFB42318),
      'watch' => isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      _ => isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
    };
    final key = switch (hazard) {
      'emergency' => 'care.wxEmergency',
      'alert' => 'care.wxAlert',
      'watch' => 'care.wxWatch',
      _ => 'care.wxCalm',
    };
    final level = (mm / 80).clamp(0.04, 1.0);

    return Material(
      color: isDark
          ? palette.card
          : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Stack(
          children: [
            if (!calm)
              Positioned.fill(
                child: IgnorePointer(
                  child: _RainBackdrop(color: color, intense: hazard != 'watch'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          calm
                              ? Icons.wb_sunny_rounded
                              : Icons.water_drop_rounded,
                          color: color,
                          size: 18,
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .moveY(
                              begin: -2,
                              end: 2,
                              duration: 1300.ms,
                              curve: Curves.easeInOut,
                            ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.t(key),
                              style: AppTextStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                                height: 1.25,
                                fontSize: 13,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              l.t(open ? 'care.wxHide' : 'care.wxTap'),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: 200.ms,
                        child: Icon(Icons.expand_more_rounded, color: color),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: 220.ms,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: open
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Rain meter — easy to read at a glance.
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 10,
                                        color: color.withValues(alpha: 0.14),
                                      ),
                                      TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: level),
                                        duration: 700.ms,
                                        curve: Curves.easeOutCubic,
                                        builder: (_, v, __) => FractionallySizedBox(
                                          widthFactor: v,
                                          child: Container(
                                            height: 10,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Gap(6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      l.t('care.rainLight'),
                                      style: _meterStyle(context),
                                    ),
                                    Text(
                                      '${mm.toStringAsFixed(0)} mm',
                                      style: _meterStyle(context).copyWith(
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      l.t('care.rainHeavy'),
                                      style: _meterStyle(context),
                                    ),
                                  ],
                                ),
                                const Gap(10),
                                _Tip(
                                  icon: Icons.elderly_rounded,
                                  text: l.t('care.tip1'),
                                  color: color,
                                ),
                                _Tip(
                                  icon: Icons.directions_walk_rounded,
                                  text: l.t('care.tip2'),
                                  color: color,
                                ),
                                _Tip(
                                  icon: Icons.groups_rounded,
                                  text: l.t('care.tip3'),
                                  color: color,
                                ),
                                const Gap(8),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: onPlan,
                                    icon: const Icon(
                                      Icons.shield_moon_rounded,
                                      size: 18,
                                    ),
                                    label: Text(l.t('care.planSafe')),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: color,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static TextStyle _meterStyle(BuildContext context) =>
      AppTextStyles.bodySmall.copyWith(
        fontSize: 11,
        color: ZivoPalette.of(context).textMuted,
        fontWeight: FontWeight.w600,
      );
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const Gap(8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                height: 1.3,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft falling-rain backdrop (cheap: 14 streaks, one controller).
class _RainBackdrop extends StatefulWidget {
  const _RainBackdrop({required this.color, required this.intense});
  final Color color;
  final bool intense;

  @override
  State<_RainBackdrop> createState() => _RainBackdropState();
}

class _RainBackdropState extends State<_RainBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        painter: _RainPainter(
          t: _c.value,
          color: widget.color.withValues(alpha: widget.intense ? 0.28 : 0.18),
          count: widget.intense ? 22 : 14,
        ),
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  _RainPainter({required this.t, required this.color, required this.count});
  final double t;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final seed = (i * 0.6180339) % 1;
      final x = size.width * ((i * 0.137 + seed * 0.5) % 1);
      final y = ((t + seed) % 1) * (size.height + 20) - 10;
      canvas.drawLine(Offset(x, y), Offset(x - 3, y + 9), p);
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter old) => old.t != t;
}

// ───────────────────────── Quick actions ─────────────────────────

enum _Motion { heartbeat, bounce, sway }

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.motion,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final _Motion motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wash = color.withValues(alpha: isDark ? 0.22 : 0.11);
    Widget glyph = Icon(icon, color: color, size: 20);
    switch (motion) {
      case _Motion.heartbeat:
        glyph = glyph
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1.12, 1.12),
              duration: 650.ms,
              curve: Curves.easeInOut,
            );
      case _Motion.bounce:
        glyph = glyph
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 1.5, end: -2.5, duration: 700.ms, curve: Curves.easeOut);
      case _Motion.sway:
        glyph = glyph
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .rotate(begin: -0.03, end: 0.03, duration: 1100.ms);
    }

    return Material(
      color: wash,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.72),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: glyph,
              ),
              const Gap(6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Community ─────────────────────────

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.trips,
    required this.co2,
    required this.fair,
    required this.onAsk,
  });

  final int trips;
  final double co2;
  final int fair;
  final VoidCallback onAsk;

  static const _goal = 10;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final progress = (trips / _goal).clamp(0.0, 1.0);
    const green = Color(0xFF15803D);

    final palette = ZivoPalette.of(context);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showHow(context, l),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: green.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: 900.ms,
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: v == 0 ? 0.02 : v,
                          strokeWidth: 4.5,
                          strokeCap: StrokeCap.round,
                          backgroundColor: green.withValues(alpha: 0.12),
                          color: green,
                        ),
                      ),
                    ),
                    const Icon(Icons.eco_rounded, color: green, size: 20)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1.08, 1.08),
                          duration: 1400.ms,
                          curve: Curves.easeInOut,
                        ),
                  ],
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('care.commTitle'),
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      trips > 0
                          ? '${l.t('care.commSaved')}: $trips'
                          : l.t('care.commEmpty'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      l.t('care.commHow'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: green,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: green, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _showHow(BuildContext context, LocaleCubit l) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: ZivoPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget row(IconData icon, Color c, String title, String body) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: c, size: 20),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Gap(2),
                        Text(
                          body,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(16),
              Text(
                l.t('care.commTitle'),
                style: AppTextStyles.headingSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(14),
              row(
                Icons.directions_walk_rounded,
                const Color(0xFF0F766E),
                '${l.t('care.fewerTrips')} · $trips',
                l.t('care.howTrips'),
              ),
              row(
                Icons.eco_rounded,
                const Color(0xFF15803D),
                '${l.t('care.cleanerAir')} · ${co2.toStringAsFixed(1)} kg',
                l.t('care.howAir'),
              ),
              row(
                Icons.handshake_rounded,
                const Color(0xFF1D4ED8),
                '${l.t('care.fairPay')} · $fair',
                l.t('care.howPay'),
              ),
              const Gap(4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onAsk();
                  },
                  child: Text(l.t('care.concierge')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Share a trip picker ─────────────────────────

class _ShareTripSheet extends StatelessWidget {
  const _ShareTripSheet({required this.onBack, required this.options});

  final VoidCallback onBack;
  final List<(IconData, Color, String, String, String)> options;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l.t('care.back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  l.t('care.shareTitle'),
                  style: AppTextStyles.headingSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Text(
            l.t('care.shareBody'),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
          const Gap(14),
          for (final o in options) ...[
            Material(
              color: o.$2.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).pop(o.$5),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: o.$2.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(o.$1, color: o.$2),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.$3,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              o.$4,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: o.$2),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(10),
          ],
          TextButton(onPressed: onBack, child: Text(l.t('care.back'))),
        ],
      ),
    );
  }
}

// ───────────────────────── Voice helper sheet ─────────────────────────

class _HelperSheet extends StatefulWidget {
  const _HelperSheet({this.preset});
  final String? preset;

  @override
  State<_HelperSheet> createState() => _HelperSheetState();
}

class _HelperSheetState extends State<_HelperSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _listening = false;
  int _step = 0;
  Timer? _stepTimer;
  Map<String, dynamic>? _result;
  String? _reply;
  String? _error;
  String? _voiceHint;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset?.trim();
    if (preset != null && preset.isNotEmpty) {
      // Prefill only — never auto-ask or auto-speak.
      _controller.text = preset;
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _controller.dispose();
    stopSpeaking();
    super.dispose();
  }

  /// Never show or speak model leakage (tool_code / JSON).
  /// Returns null when the model reply is unusable (caller shows a recoverable error).
  String? _clean(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty ||
        RegExp(r'tool_code|default_api|print\(|```|^\s*[{\[]|"reply"\s*:',
                caseSensitive: false)
            .hasMatch(t)) {
      return null;
    }
    return t;
  }

  /// Infer category + draft when the API is down or returns an empty reply.
  Map<String, dynamic> _localDraftFrom(String text) {
    final lower = text.toLowerCase();
    String category = 'errandRun';
    if (RegExp(r'medicine|pharmacy|மருந்து|බෙහෙත්|hospital|පෙති').hasMatch(lower)) {
      category = 'hospitalCompanion';
    } else if (RegExp(r'elder|mother|ammi|அம்மா|අම්මා|elderly|check on').hasMatch(lower)) {
      category = 'elderCare';
    } else if (RegExp(r'grocery|market|food|groceries|සිල්ලර|மளிகை').hasMatch(lower)) {
      category = 'groceryRun';
    } else if (RegExp(r'share|trip|neighbour|neighbor|බෙදා|பகிர்').hasMatch(lower)) {
      category = 'errandRun';
    }
    final title = text.length > 56 ? '${text.substring(0, 56).trim()}…' : text;
    return {
      'pillar': 'voice_concierge',
      'mode': 'local',
      'reply':
          'Got it. Review the draft below, then post — a neighbour can help.',
      'draft': {
        'category': category,
        'title': title,
        'description': text,
      },
      'safety': {'allowed': true},
    };
  }

  void _applyAskResult(Map<String, dynamic> res, LocaleCubit l) {
    final reply = _clean(res['reply']?.toString());
    final draft = res['draft'];
    if (reply == null && draft is! Map) {
      final local = _localDraftFrom(_controller.text.trim());
      setState(() {
        _busy = false;
        _result = local;
        _reply = local['reply'] as String;
        _error = null;
      });
      return;
    }
    // Prefer API draft; if reply was junk but draft exists, still show success.
    final effective = Map<String, dynamic>.from(res);
    if (reply == null) {
      effective['reply'] =
          'Got it. Review the draft below, then post — a neighbour can help.';
    }
    if (draft is! Map) {
      final local = _localDraftFrom(_controller.text.trim());
      effective['draft'] = local['draft'];
    }
    setState(() {
      _busy = false;
      _result = effective;
      _reply = _clean(effective['reply']?.toString()) ??
          effective['reply']?.toString();
      _error = null;
    });
  }

  void _postTypedFallback() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final local = _localDraftFrom(text);
    final draft = local['draft'] as Map;
    _postDraft(draft);
  }

  Future<void> _ask() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    final l = context.read<LocaleCubit>();
    stopSpeaking();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _step = 0;
      _result = null;
      _reply = null;
      _error = null;
    });
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted && _step < 2) setState(() => _step++);
    });
    try {
      final res = await context
          .read<TaskRepository>()
          .runConcierge(
            utterance: text,
            lang: l.code,
          )
          .timeout(const Duration(seconds: 18));
      _stepTimer?.cancel();
      if (!mounted) return;
      _applyAskResult(Map<String, dynamic>.from(res), l);
    } catch (e) {
      _stepTimer?.cancel();
      if (!mounted) return;
      // API missing/slow — still deliver a usable draft so Ask never dead-ends.
      final local = _localDraftFrom(text);
      setState(() {
        _busy = false;
        _result = local;
        _reply = local['reply'] as String;
        _error = null;
      });
    }
  }

  Future<void> _toggleMic() async {
    final l = context.read<LocaleCubit>();
    if (_busy) return;
    stopSpeaking();

    if (_listening) {
      setState(() {
        _listening = false;
        _voiceHint = l.t('care.voiceWorking');
      });
      try {
        final bytes = await stopVoiceRecording();
        if (!mounted) return;
        if (bytes == null || bytes.isEmpty) {
          setState(() => _voiceHint = l.t('care.voiceEmpty'));
          return;
        }
        setState(() => _voiceHint = l.t('care.voiceTranscribing'));
        final res = await context.read<TaskRepository>().a11yTranscribe(
              audioBytes: bytes,
              lang: l.code,
            );
        if (!mounted) return;
        final caption = res['transcript']?.toString().trim() ?? '';
        if (caption.isEmpty) {
          setState(() => _voiceHint = l.t('care.voiceEmpty'));
          return;
        }
        setState(() {
          _controller.text = caption;
          _voiceHint = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _voiceHint = humanizeError(e));
      }
      return;
    }

    try {
      setState(() {
        _listening = true;
        _voiceHint = l.t('care.voiceListening');
        _error = null;
      });
      await startVoiceRecording(maxDuration: const Duration(seconds: 20));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceHint = humanizeError(e);
      });
    }
  }

  void _postDraft(Map draft) {
    stopSpeaking();
    Navigator.of(context, rootNavigator: true).pop({
      'category': draft['category'],
      'title': draft['title'],
      'description': draft['description'] ?? _controller.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final draft = _result?['draft'];
    final safety = _result?['safety'];
    final allowed = !(safety is Map && safety['allowed'] == false);
    final quote = draft is Map ? draft['quote_lkr'] : null;
    final hazard = (_result?['resilience'] as Map?)?['hazard']?.toString();
    final priority = (_result?['resilience'] as Map?)?['priority']?.toString();

    final presets = [
      l.t('care.presetElder'),
      l.t('care.presetMedicine'),
      l.t('care.presetShare'),
    ];

    return AnimatedPadding(
      duration: 150.ms,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: l.t('care.back'),
                  onPressed: () {
                    stopSpeaking();
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                  icon: Icon(Icons.close_rounded, color: palette.textPrimary),
                ),
                Expanded(
                  child: Text(
                    l.t('care.conciergeTitle'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headingSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Text(
              l.t('care.conciergeBody'),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textSecondary,
                height: 1.35,
                fontSize: 13,
              ),
            ),
            const Gap(14),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _ask(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textPrimary,
              ),
              cursorColor: palette.accent,
              decoration: InputDecoration(
                hintText: l.t('care.conciergeHint'),
                hintStyle: TextStyle(color: palette.textMuted),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
            ),
            const Gap(8),
            if (_result == null && !_busy)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    ActionChip(
                      label: Text(
                        p,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.textPrimary),
                      ),
                      backgroundColor:
                          isDark ? const Color(0xFF2A2A2A) : null,
                      side: BorderSide(color: palette.border),
                      onPressed: () {
                        setState(() {
                          _controller.text = p;
                          _error = null;
                        });
                      },
                    ),
                ],
              ),
            const Gap(8),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: l.t('care.captionVoice'),
                  style: IconButton.styleFrom(
                    backgroundColor: _listening
                        ? AppColors.errorColor.withValues(alpha: 0.15)
                        : (isDark
                            ? palette.accent.withValues(alpha: 0.18)
                            : null),
                    foregroundColor: _listening
                        ? AppColors.errorColor
                        : (isDark ? palette.accent : null),
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _busy ? null : _toggleMic,
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || _listening ? null : _ask,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.onAccent,
                            ),
                          )
                        : Text(l.t('care.conciergeAsk')),
                  ),
                ),
              ],
            ),
            if (_voiceHint != null) ...[
              const Gap(8),
              Text(
                _voiceHint!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: _listening
                      ? const Color(0xFFFF6B6B)
                      : palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_busy) ...[
              const Gap(14),
              _Steps(current: _step),
            ],
            if (_error != null) ...[
              const Gap(12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11900).withValues(alpha: isDark ? 0.22 : 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.7),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? const Color(0xFFFFB4B4)
                            : AppColors.errorColor,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                    const Gap(6),
                    Text(
                      l.t('care.helperRetryHint'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    if (_controller.text.trim().isNotEmpty) ...[
                      const Gap(10),
                      FilledButton.tonal(
                        onPressed: _postTypedFallback,
                        style: FilledButton.styleFrom(
                          foregroundColor: palette.textPrimary,
                          backgroundColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : null,
                        ),
                        child: Text(l.t('care.helperRetryPost')),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_reply != null) ...[
              const Gap(14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (allowed
                          ? AppColors.helperAccent
                          : AppColors.errorColor)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reply!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        height: 1.4,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Gap(10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (quote != null)
                          _Pill(
                            Icons.payments_rounded,
                            'LKR $quote',
                            const Color(0xFF1D4ED8),
                          ),
                        if (hazard != null && hazard != 'unknown')
                          _Pill(
                            hazard == 'calm'
                                ? Icons.wb_sunny_rounded
                                : Icons.water_drop_rounded,
                            l.t('care.hz.$hazard'),
                            const Color(0xFF0F766E),
                          ),
                        if (priority == 'critical' || priority == 'high')
                          _Pill(
                            Icons.priority_high_rounded,
                            l.t('care.urgent'),
                            const Color(0xFFB42318),
                          ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.08, end: 0),
              const Gap(10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      stopSpeaking();
                      speakText(_reply!, lang: l.code);
                    },
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: Text(l.t('care.listen')),
                  ),
                  const Gap(10),
                  if (allowed && draft is Map)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _postDraft(draft),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(l.t('care.postThis')),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              isDark ? palette.accent : Colors.black,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = ZivoPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const Gap(5),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly 3-step progress while the helper works (no tool names).
class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleCubit>();
    final palette = ZivoPalette.of(context);
    final items = [
      (Icons.verified_user_rounded, l.t('care.stepSafe')),
      (Icons.water_drop_rounded, l.t('care.stepRain')),
      (Icons.payments_rounded, l.t('care.stepPrice')),
    ];
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: 250.ms,
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? AppColors.helperAccent
                        : palette.border,
                    shape: BoxShape.circle,
                  ),
                  child: i < current
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : Icon(items[i].$1,
                          size: 15,
                          color: i == current
                              ? Colors.white
                              : palette.textMuted),
                ),
                const Gap(10),
                Text(
                  items[i].$2,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                    color: i <= current
                        ? palette.textPrimary
                        : palette.textMuted,
                  ),
                ),
                if (i == current) ...[
                  const Gap(8),
                  SizedBox(
                    width: math.min(14, 14),
                    height: 14,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
