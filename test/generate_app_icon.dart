// Headless iOS app-icon generator.
//
// Paints the GroupApp "Unity" brass mark on a navy rounded-square field and
// writes every size the iOS AppIcon.appiconset needs, straight to disk.
//
// Run with:  flutter test test/generate_app_icon.dart
//
// This is a build-time tool, not a real test — it just uses the Flutter test
// harness because that gives us a working engine for Canvas -> PNG rasterizing.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Palette (copied so this tool has no app imports).
const _brass = Color(0xFFC9A227);
const _brassLight = Color(0xFFE6C55A);
const _brassDeep = Color(0xFF9A7B1B);
const _navy = Color(0xFF0A1836);
const _navyMid = Color(0xFF14294F);

/// All icon files iOS needs. name -> pixel size.
const _icons = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

void main() {
  test('generate iOS app icons', () async {
    const outDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

    for (final entry in _icons.entries) {
      final bytes = await _renderIcon(entry.value);
      final file = File('$outDir/${entry.key}');
      await file.writeAsBytes(bytes);
      // ignore: avoid_print
      print('wrote ${entry.key} (${entry.value}px)');
    }
  });
}

Future<List<int>> _renderIcon(int px) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(px.toDouble(), px.toDouble());

  _paintIcon(canvas, size);

  final picture = recorder.endRecording();
  final image = await picture.toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void _paintIcon(Canvas canvas, Size size) {
  final w = size.width;

  // Navy gradient field (App Store 1024 must be fully opaque — no alpha).
  final bgRect = Rect.fromLTWH(0, 0, w, w);
  final bgPaint = Paint()
    ..shader = const LinearGradient(
      colors: [_navyMid, _navy],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(bgRect);
  canvas.drawRect(bgRect, bgPaint);

  // The brass Unity mark, centered, scaled to fill ~62% of the field.
  final center = Offset(w / 2, w / 2);
  final r = w * 0.62 * 0.36; // mirrors UnityLogo's r = size*0.36 at 62% box

  const shardColors = [_brass, _brassLight, _brassDeep];

  for (int i = 0; i < 3; i++) {
    final angle = -math.pi / 2 + i * (2 * math.pi / 3);
    final dir = Offset(math.cos(angle), math.sin(angle));
    final shardCenter = center + dir * (r * 0.42);

    final paint = Paint()
      ..color = shardColors[i]
      ..style = PaintingStyle.fill;

    canvas.drawPath(_shardPath(shardCenter, r, angle), paint);
  }

  // White core dot.
  canvas.drawCircle(center, r * 0.14, Paint()..color = Colors.white);
}

Path _shardPath(Offset c, double r, double angle) {
  final s = r * 0.95;
  final tip = Offset(0, -s * 0.55);
  final baseL = Offset(-s * 0.5, s * 0.45);
  final baseR = Offset(s * 0.5, s * 0.45);

  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(baseR.dx, baseR.dy)
    ..lineTo(baseL.dx, baseL.dy)
    ..close();

  final m = Matrix4.identity()
    ..translateByDouble(c.dx, c.dy, 0, 1)
    ..rotateZ(angle + math.pi / 2);
  return path.transform(m.storage);
}
