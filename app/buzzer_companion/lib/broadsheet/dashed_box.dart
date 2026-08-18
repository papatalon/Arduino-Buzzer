import 'package:flutter/material.dart';

import 'tokens.dart';

// Bordure 1px tiretée : utilisée par l'emplacement de logo du pop-out
// (design_handoff_buzzer_console/README.md, écran du châssis pop-out) et,
// plus tard, par d'autres états "en attente" du même design system.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.width,
    required this.height,
    this.child,
    this.dashColor = BSColors.neutral400,
    this.fillColor = BSColors.neutral200,
  });

  final double width;
  final double height;
  final Widget? child;
  final Color dashColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: dashColor, fill: fillColor),
        child: Center(child: child),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.fill});
  final Color color;
  final Color fill;

  static const _dash = 4.0;
  static const _gap = 3.0;

  void _drawDashedLine(Canvas canvas, Paint paint, Offset a, Offset b) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var dist = 0.0;
    while (dist < total) {
      final segmentEnd = dist + _dash > total ? total : dist + _dash;
      canvas.drawLine(a + dir * dist, a + dir * segmentEnd, paint);
      dist += _dash + _gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = fill);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    _drawDashedLine(canvas, paint, rect.topLeft, rect.topRight);
    _drawDashedLine(canvas, paint, rect.topRight, rect.bottomRight);
    _drawDashedLine(canvas, paint, rect.bottomRight, rect.bottomLeft);
    _drawDashedLine(canvas, paint, rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fill != fill;
}
