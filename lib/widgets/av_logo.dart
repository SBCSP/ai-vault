import 'package:flutter/material.dart';

/// Animated 3D-style "AV" logo with glow and pulse effect.
class AvLogo extends StatefulWidget {
  final double size;

  const AvLogo({super.key, this.size = 120});

  @override
  State<AvLogo> createState() => _AvLogoState();
}

class _AvLogoState extends State<AvLogo> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _glowController;
  late final AnimationController _rotateController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // Slow, breathing pulse scale
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Glow intensity oscillation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Very slow subtle Y-axis rotation for 3D feel
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseAnimation,
        _glowAnimation,
        _rotateController,
      ]),
      builder: (context, child) {
        final rotateValue =
            Tween<double>(begin: -0.06, end: 0.06).evaluate(
          CurvedAnimation(parent: _rotateController, curve: Curves.easeInOut),
        );

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspective
            ..rotateY(rotateValue)
            // ignore: deprecated_member_use
            ..scale(_pulseAnimation.value),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                // Outer glow
                BoxShadow(
                  color: primaryColor.withValues(
                    alpha: 0.3 * _glowAnimation.value,
                  ),
                  blurRadius: 40 * _glowAnimation.value,
                  spreadRadius: 8 * _glowAnimation.value,
                ),
                // Inner glow
                BoxShadow(
                  color: primaryColor.withValues(
                    alpha: 0.5 * _glowAnimation.value,
                  ),
                  blurRadius: 20 * _glowAnimation.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _AvLogoPainter(
                primaryColor: primaryColor,
                glowIntensity: _glowAnimation.value,
                brightness: theme.brightness,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AvLogoPainter extends CustomPainter {
  final Color primaryColor;
  final double glowIntensity;
  final Brightness brightness;

  _AvLogoPainter({
    required this.primaryColor,
    required this.glowIntensity,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // --- Background circle with gradient ---
    final bgGradient = RadialGradient(
      center: const Alignment(-0.3, -0.3), // light from top-left
      radius: 1.0,
      colors: brightness == Brightness.dark
          ? [
              Color.lerp(primaryColor, Colors.white, 0.15)!,
              primaryColor,
              Color.lerp(primaryColor, Colors.black, 0.5)!,
            ]
          : [
              Color.lerp(primaryColor, Colors.white, 0.3)!,
              primaryColor,
              Color.lerp(primaryColor, Colors.black, 0.3)!,
            ],
      stops: const [0.0, 0.5, 1.0],
    );

    final bgPaint = Paint()
      ..shader = bgGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, bgPaint);

    // --- Subtle ring highlight for 3D depth ---
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = SweepGradient(
        center: const Alignment(-0.2, -0.2),
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.35 * glowIntensity),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.1),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.2, 0.5, 0.7, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius - 1),
      );
    canvas.drawCircle(center, radius - 1, ringPaint);

    // --- Draw the "A" and "V" letters ---
    final letterScale = size.width / 120; // normalise to design size 120
    final letterColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.white;

    // 3D shadow / depth layer
    _drawLetters(
      canvas,
      size,
      letterScale,
      Color.lerp(primaryColor, Colors.black, 0.6)!.withValues(alpha: 0.5),
      offsetY: 2.5 * letterScale,
    );

    // Main letter layer
    _drawLetters(canvas, size, letterScale, letterColor);

    // Specular highlight layer (subtle)
    _drawLetters(
      canvas,
      size,
      letterScale,
      Colors.white.withValues(alpha: 0.2 * glowIntensity),
      offsetY: -1.0 * letterScale,
    );
  }

  void _drawLetters(
    Canvas canvas,
    Size size,
    double scale,
    Color color, {
    double offsetY = 0,
  }) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2 + offsetY;

    // ---- Shared geometry ----
    // The right leg of A and left leg of V share the same line
    final sharedX = cx; // center line where A and V meet
    final aLeft = cx - 28 * scale;
    final aTop = cy - 24 * scale;
    final aBottom = cy + 24 * scale;
    final aMid = (aLeft + sharedX) / 2; // apex of A
    final aCrossY = cy + 4 * scale;

    // ---- "A" letter ----
    final aPath = Path()
      ..moveTo(aLeft, aBottom)
      ..lineTo(aMid, aTop)
      // Right leg goes to shared center line
      ..lineTo(sharedX, aBottom);
    canvas.drawPath(aPath, strokePaint);

    // Crossbar of A
    final crossLeft = _lerpOffset(aLeft, aBottom, aMid, aTop, aCrossY);
    final crossRight = _lerpOffset(sharedX, aBottom, aMid, aTop, aCrossY);
    canvas.drawLine(
      Offset(crossLeft, aCrossY),
      Offset(crossRight, aCrossY),
      strokePaint..strokeWidth = 3.0 * scale,
    );

    // Reset stroke width
    strokePaint.strokeWidth = 4.5 * scale;

    // ---- "V" letter ----
    // Left leg starts at the same shared center line
    final vRight = cx + 28 * scale;
    final vMid = (sharedX + vRight) / 2; // bottom point of V
    final vTop = cy - 24 * scale;
    final vBottom = cy + 24 * scale;

    final vPath = Path()
      ..moveTo(sharedX, vTop)
      ..lineTo(vMid, vBottom)
      ..lineTo(vRight, vTop);
    canvas.drawPath(vPath, strokePaint);
  }

  /// Compute the x-position on a line from (x1,y1)→(x2,y2) at a given y.
  double _lerpOffset(
      double x1, double y1, double x2, double y2, double targetY) {
    final t = (targetY - y1) / (y2 - y1);
    return x1 + t * (x2 - x1);
  }

  @override
  bool shouldRepaint(covariant _AvLogoPainter oldDelegate) {
    return oldDelegate.glowIntensity != glowIntensity ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.brightness != brightness;
  }
}
