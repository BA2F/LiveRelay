import 'package:flutter/material.dart';

/// Static product mark from the accepted 2026-10-04 assets. Native paths keep
/// it sharp at every density; only the supplied micro optical variant differs.
class LiveRelayLogo extends StatelessWidget {
  const LiveRelayLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '留灯 LiveRelay',
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LogoPainter(
          dark: Theme.of(context).brightness == Brightness.dark,
          micro: size <= 24,
        ),
      ),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.dark, required this.micro});
  final bool dark, micro;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    if (micro) {
      canvas.translate(-38.4, -38.4);
      canvas.scale(1.15);
    }
    final ink = Paint()
      ..color = dark ? const Color(0xfff8f5ed) : const Color(0xff272620);
    canvas.drawPath(_masterLeft, ink);
    canvas.drawPath(micro ? _microRight : _masterRight, ink);
    canvas.drawPath(
      micro ? _microFlame : _masterFlame,
      Paint()
        ..color = micro ? const Color(0xffdba042) : const Color(0xfff3c477),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) =>
      dark != oldDelegate.dark || micro != oldDelegate.micro;
}

final _masterLeft = Path()
  ..moveTo(298.76, 78)
  ..cubicTo(290.56, 90.3, 279.9, 96.86, 268.42, 102.6)
  ..lineTo(161.82, 149.34)
  ..cubicTo(135.58, 163.28, 120, 178.86, 120, 204.28)
  ..lineTo(120, 378.12)
  ..cubicTo(120, 396.16, 130.66, 407.64, 148.7, 415.02)
  ..lineTo(197.9, 433.06)
  ..quadraticBezierTo(201.18, 434.7, 201.18, 431.42)
  ..lineTo(201.18, 296.12)
  ..cubicTo(201.18, 275.62, 213.48, 266.6, 238.08, 253.48)
  ..lineTo(270.88, 234.62)
  ..cubicTo(289.74, 223.96, 299.58, 211.66, 299.58, 192.8)
  ..lineTo(299.58, 79.64)
  ..quadraticBezierTo(299.58, 77.18, 298.76, 78)
  ..close();

final _masterRight = Path()
  ..moveTo(284, 257.58)
  ..lineTo(356.16, 287.1)
  ..cubicTo(379.94, 296.94, 392.24, 308.42, 392.24, 327.28)
  ..lineTo(392.24, 425.68)
  ..quadraticBezierTo(392.24, 434.7, 382.4, 434.7)
  ..cubicTo(357.8, 433.88, 329.92, 423.22, 304.5, 410.92)
  ..cubicTo(290.56, 404.36, 284, 394.52, 284, 381.4)
  ..close();

final _masterFlame = Path()
  ..moveTo(249.56, 244.46)
  ..cubicTo(265.14, 248.56, 274.16, 255.12, 274.16, 269.88)
  ..lineTo(274.16, 328.1)
  ..cubicTo(259.4, 324, 249.56, 314.16, 249.56, 300.22)
  ..close();

final _microRight = Path()
  ..moveTo(295.48, 257.58)
  ..lineTo(367.64, 287.1)
  ..cubicTo(391.42, 296.94, 403.72, 308.42, 403.72, 327.28)
  ..lineTo(403.72, 425.68)
  ..quadraticBezierTo(403.72, 434.7, 393.88, 434.7)
  ..cubicTo(369.28, 433.88, 341.4, 423.22, 315.98, 410.92)
  ..cubicTo(302.04, 404.36, 295.48, 394.52, 295.48, 381.4)
  ..close();

final _microFlame = Path()
  ..moveTo(246.28, 244.46)
  ..cubicTo(267.6, 249.38, 280.72, 257.58, 280.72, 272.34)
  ..lineTo(280.72, 328.1)
  ..cubicTo(260.22, 324, 246.28, 312.52, 246.28, 297.76)
  ..close();
