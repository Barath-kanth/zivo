import 'package:flutter/material.dart';

/// Lightweight vector scenery. No network images or animation controllers.
class NeighbourhoodArt extends StatelessWidget {
  const NeighbourhoodArt({super.key, this.helper = false});
  final bool helper;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(painter: _NeighbourhoodPainter(helper)),
  );
}

class _NeighbourhoodPainter extends CustomPainter {
  const _NeighbourhoodPainter(this.helper);
  final bool helper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 800, size.height / 220);
    final paint = Paint();
    void rect(double x, double y, double w, double h, Color color) {
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint..color = color);
    }

    void poly(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, paint..color = color);
    }

    rect(0, 0, 800, 220, const Color(0xFFE7F5FC));
    for (var i = 0; i < 17; i++) {
      final height = 26.0 + (i % 5) * 12;
      rect(i * 52.0, 150 - height, 38, height, const Color(0xFFCCE5F0));
    }
    poly([
      const Offset(0, 156),
      const Offset(380, 124),
      const Offset(800, 153),
      const Offset(800, 220),
      const Offset(0, 220),
    ], const Color(0xFFECF4DC));
    poly([
      const Offset(343, 140),
      const Offset(396, 140),
      const Offset(620, 220),
      const Offset(196, 220),
    ], Colors.white);
    poly([
      const Offset(358, 145),
      const Offset(382, 145),
      const Offset(514, 220),
      const Offset(288, 220),
    ], const Color(0xFFDDE9EA));
    void building(double x, double y, double w, double h, Color colour) {
      rect(x, y, w, h, colour);
      poly([
        Offset(x, y),
        Offset(x + w * .5, y - 24),
        Offset(x + w, y),
      ], const Color(0xFF234F46));
      rect(x + 12, y + 14, w * .30, h * .40, const Color(0xFFBDE3F3));
      rect(x + w * .57, y + 14, w * .28, h * .40, const Color(0xFFBDE3F3));
      rect(x + w * .42, y + h * .58, w * .20, h * .42, Colors.white);
    }

    building(20, 134, 118, 66, const Color(0xFFFFCF6B));
    building(150, 136, 94, 49, Colors.white);
    building(544, 122, 120, 71, const Color(0xFFFFD780));
    building(682, 142, 98, 62, Colors.white);
    for (final x in [6.0, 263.0, 525.0, 670.0, 788.0]) {
      rect(x - 2, 170, 4, 32, const Color(0xFF789278));
      canvas.drawCircle(
        Offset(x, 163),
        16,
        paint..color = const Color(0xFF6DAD74),
      );
      canvas.drawCircle(
        Offset(x + 6, 158),
        12,
        paint..color = const Color(0xFFA0CF86),
      );
    }
    // Small service vehicle on the neighbourhood road.
    final x = helper ? 380.0 : 430.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 178, 40, 19),
        const Radius.circular(5),
      ),
      paint..color = const Color(0xFF0A885A),
    );
    rect(x + 6, 174, 22, 12, const Color(0xFF0A885A));
    rect(x + 9, 176, 16, 8, const Color(0xFFBDE3F3));
    canvas.drawCircle(
      Offset(x + 9, 199),
      5,
      paint..color = const Color(0xFF20312B),
    );
    canvas.drawCircle(
      Offset(x + 32, 199),
      5,
      paint..color = const Color(0xFF20312B),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NeighbourhoodPainter oldDelegate) =>
      oldDelegate.helper != helper;
}
