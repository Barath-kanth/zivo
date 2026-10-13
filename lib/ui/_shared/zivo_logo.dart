import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_brand.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';

/// Zivo mark: a living “Z” path — helper → you — with a green pulse of arrival.
///
/// Reads as motion + nearby help (route), not a generic letter badge.
class ZivoLogo extends StatelessWidget {
  const ZivoLogo({
    super.key,
    this.size = 36,
    this.showWordmark = false,
    this.wordmarkColor,
    this.markOnDark = false,
  });

  final double size;
  final bool showWordmark;
  final Color? wordmarkColor;
  final bool markOnDark;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ZivoMarkPainter(
          onDark: markOnDark,
          accent: AppColors.brandGreen,
        ),
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.26),
        Text(
          AppBrand.name,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: size * 0.56,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: wordmarkColor ??
                (markOnDark ? Colors.white : Colors.black),
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _ZivoMarkPainter extends CustomPainter {
  _ZivoMarkPainter({required this.onDark, required this.accent});

  final bool onDark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final bg = onDark ? Colors.white : Colors.black;
    final fg = onDark ? Colors.black : Colors.white;

    // Soft app-icon tile
    final tile = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: s * 0.92, height: s * 0.92),
      Radius.circular(s * 0.24),
    );
    canvas.drawRRect(tile, Paint()..color = bg);

    // Neighborhood radius (subtle arc) — “nearby”
    final ringPaint = Paint()
      ..color = (onDark ? Colors.black : Colors.white).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: s * 0.34),
      -math.pi * 0.15,
      math.pi * 1.1,
      false,
      ringPaint,
    );

    // Living Z as a help route (start → diagonal → arrive)
    final z = Path()
      ..moveTo(cx - s * 0.22, cy - s * 0.2)
      ..lineTo(cx + s * 0.22, cy - s * 0.2)
      ..lineTo(cx - s * 0.22, cy + s * 0.2)
      ..lineTo(cx + s * 0.22, cy + s * 0.2);

    final route = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(z, route);

    // Green life pulse at destination (help arrived)
    final end = Offset(cx + s * 0.22, cy + s * 0.2);
    canvas.drawCircle(
      end,
      s * 0.095,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      end,
      s * 0.045,
      Paint()..color = fg,
    );

    // Origin node (helper leaving)
    final start = Offset(cx - s * 0.22, cy - s * 0.2);
    canvas.drawCircle(start, s * 0.055, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _ZivoMarkPainter oldDelegate) =>
      oldDelegate.onDark != onDark || oldDelegate.accent != accent;
}

/// Compact badge for lists / nav.
class ZivoMarkBadge extends StatelessWidget {
  const ZivoMarkBadge({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: ZivoLogo(size: size),
    );
  }
}

/// Hero treatment with a soft pulse ring (alive / nearby).
class ZivoLogoHero extends StatelessWidget {
  const ZivoLogoHero({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _PulseRingPainter(color: AppColors.helperAccent),
          ),
          ZivoMarkBadge(size: size * 0.72),
        ],
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.46;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final start = i * (math.pi * 2 / 5) + 0.2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        0.4,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Backward-compatible aliases while screens migrate.
typedef NaborLogo = ZivoLogo;
typedef NaborMarkBadge = ZivoMarkBadge;
typedef NaborLogoHero = ZivoLogoHero;
