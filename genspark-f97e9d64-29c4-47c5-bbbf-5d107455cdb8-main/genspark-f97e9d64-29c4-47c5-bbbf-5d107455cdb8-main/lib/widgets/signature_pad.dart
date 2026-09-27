import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class Stroke {
  final List<Offset> points = [];
  final List<double> widths = [];
  final Color color;
  final double baseWidth;
  Stroke(this.color, this.baseWidth);
}

/// Signature canvas with velocity-based variable stroke width, which is
/// what makes a drawn signature look like ink rather than a marker line.
class SignaturePad extends StatefulWidget {
  final Color inkColor;
  final double strokeWidth;
  final SignaturePadController controller;

  const SignaturePad({
    super.key,
    required this.controller,
    this.inkColor = const Color(0xFF15264F),
    this.strokeWidth = 3.2,
  });

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class SignaturePadController extends ChangeNotifier {
  final List<Stroke> strokes = [];
  Size size = Size.zero;

  bool get isEmpty => strokes.isEmpty;

  /// Public hook so the pad can announce stroke completion.
  void strokeCompleted() => notifyListeners();

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  void undo() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
      notifyListeners();
    }
  }

  /// Rasterise the signature to transparent PNG bytes.
  Future<Uint8List?> toPng({double scale = 3.0}) async {
    if (strokes.isEmpty || size == Size.zero) return null;

    // Tight bounding box around the ink.
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final s in strokes) {
      for (int i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final w = s.widths[i];
        minX = math.min(minX, p.dx - w);
        minY = math.min(minY, p.dy - w);
        maxX = math.max(maxX, p.dx + w);
        maxY = math.max(maxY, p.dy + w);
      }
    }
    const pad = 10.0;
    minX = math.max(0, minX - pad);
    minY = math.max(0, minY - pad);
    maxX = math.min(size.width, maxX + pad);
    maxY = math.min(size.height, maxY + pad);
    final w = math.max(1.0, maxX - minX);
    final h = math.max(1.0, maxY - minY);

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    canvas.translate(-minX, -minY);
    _paintStrokes(canvas, strokes);
    final pic = rec.endRecording();
    final image = await pic.toImage(
      (w * scale).round().clamp(1, 4096),
      (h * scale).round().clamp(1, 4096),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

void _paintStrokes(Canvas canvas, List<Stroke> strokes) {
  for (final s in strokes) {
    if (s.points.length == 1) {
      canvas.drawCircle(
        s.points.first,
        s.widths.first / 2,
        Paint()..color = s.color,
      );
      continue;
    }
    for (int i = 1; i < s.points.length; i++) {
      final p = Paint()
        ..color = s.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s.widths[i - 1] + s.widths[i]) / 2;
      canvas.drawLine(s.points[i - 1], s.points[i], p);
    }
  }
}

class _SignaturePadState extends State<SignaturePad> {
  Stroke? _active;
  Offset? _last;
  double _lastWidth = 0;

  void _start(Offset p) {
    _active = Stroke(widget.inkColor, widget.strokeWidth);
    _lastWidth = widget.strokeWidth;
    _active!.points.add(p);
    _active!.widths.add(_lastWidth);
    widget.controller.strokes.add(_active!);
    _last = p;
    setState(() {});
  }

  void _extend(Offset p) {
    final a = _active;
    if (a == null) return;
    final d = _last == null ? 0.0 : (p - _last!).distance;
    // Faster movement => thinner stroke (simulated pen pressure).
    final target = (widget.strokeWidth * (1.45 - (d / 26).clamp(0.0, 0.85)))
        .clamp(widget.strokeWidth * 0.42, widget.strokeWidth * 1.5);
    _lastWidth = _lastWidth + (target - _lastWidth) * 0.35;
    a.points.add(p);
    a.widths.add(_lastWidth);
    _last = p;
    setState(() {});
  }

  void _end() {
    _active = null;
    _last = null;
    widget.controller.strokeCompleted();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        widget.controller.size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _start(d.localPosition),
          onPanUpdate: (d) => _extend(d.localPosition),
          onPanEnd: (_) => _end(),
          child: CustomPaint(
            painter: _SigPainter(
              strokes: widget.controller.strokes,
              guide: c.hairline,
            ),
            size: Size(box.maxWidth, box.maxHeight),
          ),
        );
      },
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Color guide;
  _SigPainter({required this.strokes, required this.guide});

  @override
  void paint(Canvas canvas, Size size) {
    // Signature baseline
    final y = size.height * 0.72;
    final dash = Paint()
      ..color = guide
      ..strokeWidth = 1;
    const dashW = 7.0, gap = 6.0;
    for (double x = 24; x < size.width - 24; x += dashW + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dashW, size.width - 24), y),
        dash,
      );
    }
    _paintStrokes(canvas, strokes);
  }

  @override
  bool shouldRepaint(_SigPainter old) => true;
}

/// Overlay editor: place a signature/stamp image on top of a page and
/// drag / scale / rotate it into position.
class StampPlacer extends StatefulWidget {
  final Uint8List pageBytes;
  final Uint8List stampBytes;
  final void Function(Offset centerNorm, double scale, double rotation)
  onConfirm;

  const StampPlacer({
    super.key,
    required this.pageBytes,
    required this.stampBytes,
    required this.onConfirm,
  });

  @override
  State<StampPlacer> createState() => StampPlacerState();
}

class StampPlacerState extends State<StampPlacer> {
  Offset _center = const Offset(0.6, 0.78);
  double _scale = 0.32;
  double _rotation = 0;
  Size _canvas = Size.zero;

  double get scale => _scale;
  double get rotation => _rotation;
  Offset get center => _center;

  void setScale(double v) => setState(() => _scale = v);
  void setRotation(double v) => setState(() => _rotation = v);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        _canvas = Size(box.maxWidth, box.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: Image.memory(widget.pageBytes, fit: BoxFit.contain),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  setState(() {
                    _center = Offset(
                      (_center.dx + d.delta.dx / _canvas.width).clamp(
                        0.05,
                        0.95,
                      ),
                      (_center.dy + d.delta.dy / _canvas.height).clamp(
                        0.05,
                        0.95,
                      ),
                    );
                  });
                },
                child: CustomPaint(
                  painter: _StampFrame(
                    center: _center,
                    scale: _scale,
                    accent: c.accent,
                  ),
                ),
              ),
            ),
            // The stamp itself, positioned & transformed
            Positioned(
              left: _center.dx * _canvas.width - (_canvas.width * _scale) / 2,
              top: _center.dy * _canvas.height - (_canvas.width * _scale) / 2,
              width: _canvas.width * _scale,
              height: _canvas.width * _scale,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: _rotation,
                  child: Image.memory(widget.stampBytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StampFrame extends CustomPainter {
  final Offset center;
  final double scale;
  final Color accent;
  _StampFrame({
    required this.center,
    required this.scale,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width * scale;
    final rect = Rect.fromCenter(
      center: Offset(center.dx * size.width, center.dy * size.height),
      width: s,
      height: s,
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = accent.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      p,
    );
    // Corner ticks
    const t = 10.0;
    final tick = Paint()
      ..color = accent
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final corners = <(Offset, Offset, Offset)>[
      (rect.topLeft, const Offset(1, 0), const Offset(0, 1)),
      (rect.topRight, const Offset(-1, 0), const Offset(0, 1)),
      (rect.bottomLeft, const Offset(1, 0), const Offset(0, -1)),
      (rect.bottomRight, const Offset(-1, 0), const Offset(0, -1)),
    ];
    for (final (o, a, b) in corners) {
      canvas.drawLine(o, o + a * t, tick);
      canvas.drawLine(o, o + b * t, tick);
    }
  }

  @override
  bool shouldRepaint(_StampFrame old) =>
      old.center != center || old.scale != scale;
}
