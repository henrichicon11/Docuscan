import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Interactive perspective-crop surface with four draggable corners,
/// a magnifier loupe, and a thirds grid.
class CropEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Offset> corners; // normalised tl, tr, br, bl
  final ValueChanged<List<Offset>> onChanged;

  const CropEditor({
    super.key,
    required this.imageBytes,
    required this.corners,
    required this.onChanged,
  });

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  ui.Image? _image;
  late List<Offset> _pts;
  int _dragIndex = -1;
  Offset? _loupeAt;
  Size _canvas = Size.zero;

  @override
  void initState() {
    super.initState();
    _pts = List<Offset>.from(widget.corners);
    _decode();
  }

  @override
  void didUpdateWidget(CropEditor old) {
    super.didUpdateWidget(old);
    if (old.imageBytes != widget.imageBytes) _decode();
    if (old.corners != widget.corners && _dragIndex == -1) {
      _pts = List<Offset>.from(widget.corners);
    }
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  /// The rect the image occupies inside the canvas (BoxFit.contain).
  Rect _imageRect(Size canvas) {
    final img = _image;
    if (img == null) return Rect.fromLTWH(0, 0, canvas.width, canvas.height);
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final scale = math.min(canvas.width / iw, canvas.height / ih);
    final w = iw * scale, h = ih * scale;
    return Rect.fromLTWH((canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
  }

  Offset _toScreen(Offset norm, Rect r) =>
      Offset(r.left + norm.dx * r.width, r.top + norm.dy * r.height);

  Offset _toNorm(Offset screen, Rect r) => Offset(
    ((screen.dx - r.left) / r.width).clamp(0.0, 1.0),
    ((screen.dy - r.top) / r.height).clamp(0.0, 1.0),
  );

  void _onDown(Offset local) {
    final r = _imageRect(_canvas);
    double best = 44;
    int idx = -1;
    for (int i = 0; i < _pts.length; i++) {
      final d = (_toScreen(_pts[i], r) - local).distance;
      if (d < best) {
        best = d;
        idx = i;
      }
    }
    if (idx >= 0) {
      HapticFeedback.selectionClick();
      setState(() {
        _dragIndex = idx;
        _loupeAt = local;
      });
    }
  }

  void _onMove(Offset local) {
    if (_dragIndex < 0) return;
    final r = _imageRect(_canvas);
    setState(() {
      _pts[_dragIndex] = _toNorm(local, r);
      _loupeAt = local;
    });
  }

  void _onUp() {
    if (_dragIndex < 0) return;
    setState(() {
      _dragIndex = -1;
      _loupeAt = null;
    });
    widget.onChanged(List<Offset>.from(_pts));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_image == null) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.ink),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        _canvas = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _onDown(d.localPosition),
          onPanUpdate: (d) => _onMove(d.localPosition),
          onPanEnd: (_) => _onUp(),
          onPanCancel: _onUp,
          child: CustomPaint(
            size: _canvas,
            painter: _CropPainter(
              image: _image!,
              pts: _pts,
              imageRect: _imageRect(_canvas),
              accent: c.accent,
              dragIndex: _dragIndex,
              loupeAt: _loupeAt,
              isDark: context.isDark,
            ),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> pts;
  final Rect imageRect;
  final Color accent;
  final int dragIndex;
  final Offset? loupeAt;
  final bool isDark;

  _CropPainter({
    required this.image,
    required this.pts,
    required this.imageRect,
    required this.accent,
    required this.dragIndex,
    required this.loupeAt,
    required this.isDark,
  });

  Offset _s(Offset n) => Offset(
    imageRect.left + n.dx * imageRect.width,
    imageRect.top + n.dy * imageRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final imgPaint = Paint()..filterQuality = FilterQuality.medium;

    // 1. Image
    canvas.drawImageRect(image, src, imageRect, imgPaint);

    final screen = pts.map(_s).toList();
    final path = Path()..moveTo(screen[0].dx, screen[0].dy);
    for (int i = 1; i < screen.length; i++) {
      path.lineTo(screen[i].dx, screen[i].dy);
    }
    path.close();

    // 2. Dim everything, then restore the selection by re-drawing the
    //    image clipped to the quad.
    //
    //    Boolean path ops (Path.combine) resolve sub-path winding
    //    inconsistently across the HTML/CanvasKit/Skia backends, which
    //    dimmed the *inside* of the quad on web. Clip-and-redraw is
    //    backend-independent and just as cheap.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawImageRect(image, src, imageRect, imgPaint);
    canvas.restore();

    // 3. Quad outline
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );

    // 4. Thirds grid inside the quad (helps align to text baselines)
    canvas.save();
    canvas.clipPath(path);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.32);
    for (int i = 1; i < 3; i++) {
      final f = i / 3;
      // Interpolate along opposite edges for a perspective-correct grid.
      final topP = Offset.lerp(screen[0], screen[1], f)!;
      final botP = Offset.lerp(screen[3], screen[2], f)!;
      canvas.drawLine(topP, botP, grid);
      final leftP = Offset.lerp(screen[0], screen[3], f)!;
      final rightP = Offset.lerp(screen[1], screen[2], f)!;
      canvas.drawLine(leftP, rightP, grid);
    }
    canvas.restore();

    // 5. Corner handles
    for (int i = 0; i < screen.length; i++) {
      final p = screen[i];
      final active = i == dragIndex;
      final r = active ? 15.0 : 12.0;
      canvas.drawCircle(
        p,
        r + 3,
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );
      canvas.drawCircle(p, r, Paint()..color = Colors.white);
      canvas.drawCircle(p, r - 4.5, Paint()..color = accent);
      // Corner elbow lines for a "precision" feel
      final elbow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9);
      final nextIdx = (i + 1) % 4;
      final prevIdx = (i + 3) % 4;
      final dirNext = (screen[nextIdx] - p);
      final dirPrev = (screen[prevIdx] - p);
      if (dirNext.distance > 1) {
        final u = dirNext / dirNext.distance;
        canvas.drawLine(p + u * (r + 2), p + u * (r + 16), elbow);
      }
      if (dirPrev.distance > 1) {
        final u = dirPrev / dirPrev.distance;
        canvas.drawLine(p + u * (r + 2), p + u * (r + 16), elbow);
      }
    }

    // 6. Magnifier loupe while dragging
    final at = loupeAt;
    if (at != null && dragIndex >= 0) {
      const lr = 52.0;
      const zoom = 2.6;
      // Place the loupe away from the finger.
      var center = at + const Offset(0, -96);
      if (center.dy - lr < 0) center = at + const Offset(0, 96);
      if (center.dx - lr < 0) center = Offset(lr + 6, center.dy);
      if (center.dx + lr > size.width) {
        center = Offset(size.width - lr - 6, center.dy);
      }

      final clip = Path()..addOval(Rect.fromCircle(center: center, radius: lr));
      canvas.save();
      canvas.clipPath(clip);
      canvas.drawRect(
        Rect.fromCircle(center: center, radius: lr),
        Paint()..color = isDark ? const Color(0xFF15161A) : Colors.white,
      );
      // Draw the image magnified around the touch point.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(zoom);
      canvas.translate(-at.dx, -at.dy);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        imageRect,
        Paint()..filterQuality = FilterQuality.high,
      );
      // Quad outline inside the loupe
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / zoom
          ..color = accent,
      );
      canvas.restore();
      // Crosshair
      final ch = Paint()
        ..color = accent
        ..strokeWidth = 1.2;
      canvas.drawLine(
        center - const Offset(12, 0),
        center + const Offset(12, 0),
        ch,
      );
      canvas.drawLine(
        center - const Offset(0, 12),
        center + const Offset(0, 12),
        ch,
      );
      canvas.restore();
      // Loupe ring
      canvas.drawCircle(
        center,
        lr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white,
      );
      canvas.drawCircle(
        center,
        lr + 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.pts != pts ||
      old.imageRect != imageRect ||
      old.dragIndex != dragIndex ||
      old.loupeAt != loupeAt;
}
