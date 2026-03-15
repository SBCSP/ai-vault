// Generates AV logo app icons at all required sizes for macOS.
// Run: dart run tool/generate_icon.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

Future<void> main() async {
  final sizes = [16, 32, 64, 128, 256, 512, 1024];

  for (final size in sizes) {
    final bytes = await renderIcon(size);
    final path =
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png';
    File(path).writeAsBytesSync(bytes);
    print('Generated $path (${size}x$size)');
  }

  print('Done! All icons generated.');
}

Future<Uint8List> renderIcon(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();

  paintAvIcon(canvas, ui.Size(s, s));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void paintAvIcon(ui.Canvas canvas, ui.Size size) {
  final center = ui.Offset(size.width / 2, size.height / 2);
  final radius = size.width / 2;

  // Indigo primary color matching the app theme
  const primaryColor = ui.Color(0xFF3F51B5);

  // --- Background circle with gradient ---
  final bgGradient = ui.Gradient.radial(
    ui.Offset(size.width * 0.35, size.height * 0.35), // light from top-left
    radius * 1.2,
    [
      _lerp(primaryColor, const ui.Color(0xFFFFFFFF), 0.15),
      primaryColor,
      _lerp(primaryColor, const ui.Color(0xFF000000), 0.5),
    ],
    [0.0, 0.5, 1.0],
  );

  final bgPaint = ui.Paint()..shader = bgGradient;
  canvas.drawCircle(center, radius, bgPaint);

  // --- Draw letters at multiple layers for 3D ---
  final scale = size.width / 120;

  // Shadow layer
  _drawLetters(
    canvas,
    size,
    scale,
    _lerp(primaryColor, const ui.Color(0xFF000000), 0.6)
        .withValues(alpha: 0.5),
    offsetY: 2.5 * scale,
  );

  // Main white letters
  _drawLetters(canvas, size, scale, const ui.Color(0xFFFFFFFF));

  // Highlight layer
  _drawLetters(
    canvas,
    size,
    scale,
    const ui.Color(0xFFFFFFFF).withValues(alpha: 0.25),
    offsetY: -1.0 * scale,
  );
}

void _drawLetters(
  ui.Canvas canvas,
  ui.Size size,
  double scale,
  ui.Color color, {
  double offsetY = 0,
}) {
  final strokePaint = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4.5 * scale
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;

  final cx = size.width / 2;
  final cy = size.height / 2 + offsetY;

  // Shared geometry
  final sharedX = cx;
  final aLeft = cx - 28 * scale;
  final aTop = cy - 24 * scale;
  final aBottom = cy + 24 * scale;
  final aMid = (aLeft + sharedX) / 2;
  final aCrossY = cy + 4 * scale;

  // "A" letter
  final aPath = ui.Path()
    ..moveTo(aLeft, aBottom)
    ..lineTo(aMid, aTop)
    ..lineTo(sharedX, aBottom);
  canvas.drawPath(aPath, strokePaint);

  // Crossbar
  final crossLeft = _lerpOffset(aLeft, aBottom, aMid, aTop, aCrossY);
  final crossRight = _lerpOffset(sharedX, aBottom, aMid, aTop, aCrossY);
  canvas.drawLine(
    ui.Offset(crossLeft, aCrossY),
    ui.Offset(crossRight, aCrossY),
    strokePaint..strokeWidth = 3.0 * scale,
  );

  strokePaint.strokeWidth = 4.5 * scale;

  // "V" letter
  final vRight = cx + 28 * scale;
  final vMid = (sharedX + vRight) / 2;
  final vTop = cy - 24 * scale;

  final vPath = ui.Path()
    ..moveTo(sharedX, vTop)
    ..lineTo(vMid, aBottom)
    ..lineTo(vRight, vTop);
  canvas.drawPath(vPath, strokePaint);
}

double _lerpOffset(double x1, double y1, double x2, double y2, double targetY) {
  final t = (targetY - y1) / (y2 - y1);
  return x1 + t * (x2 - x1);
}

ui.Color _lerp(ui.Color a, ui.Color b, double t) {
  return ui.Color.fromARGB(
    255,
    (a.r * 255 * (1 - t) + b.r * 255 * t).round().clamp(0, 255),
    (a.g * 255 * (1 - t) + b.g * 255 * t).round().clamp(0, 255),
    (a.b * 255 * (1 - t) + b.b * 255 * t).round().clamp(0, 255),
  );
}
