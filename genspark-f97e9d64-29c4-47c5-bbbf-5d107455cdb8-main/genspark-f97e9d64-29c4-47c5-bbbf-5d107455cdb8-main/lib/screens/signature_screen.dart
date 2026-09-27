import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import '../widgets/signature_pad.dart';

/// Two-step flow: draw the signature, then place it on the page.
class SignatureScreen extends StatefulWidget {
  final String docId;
  final String pageId;

  const SignatureScreen({super.key, required this.docId, required this.pageId});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _ctl = SignaturePadController();
  final _placerKey = GlobalKey<StampPlacerState>();

  Uint8List? _stamp;
  bool _working = false;

  int _inkIndex = 0;
  double _stroke = 3.2;
  double _size = 0.34;
  double _rotation = 0;

  static const _inks = [
    Color(0xFF15264F), // navy
    Color(0xFF111214), // black
    Color(0xFF9C2A20), // red
  ];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_ctl.isEmpty) return;
    setState(() => _working = true);
    final png = await _ctl.toPng(scale: 3.0);
    setState(() {
      _stamp = png;
      _working = false;
    });
  }

  /// Composite the signature PNG onto the page at the chosen transform.
  Future<void> _apply() async {
    final state = context.read<AppState>();
    final doc = state.docById(widget.docId);
    if (doc == null || _stamp == null) return;
    final page = doc.pages.firstWhere((p) => p.id == widget.pageId);
    final placer = _placerKey.currentState;
    if (placer == null) return;

    setState(() => _working = true);

    final centerNorm = placer.center;
    final scale = placer.scale;
    final rot = placer.rotation;

    final result = await _composite(
      pageBytes: page.processed,
      stampBytes: _stamp!,
      centerNorm: centerNorm,
      widthFrac: scale,
      rotation: rot,
    );

    // Write into both original and processed so re-filtering keeps the mark.
    page.processed = result;
    page.original = result;
    page.corners = null;
    await state.persist(doc.id);

    if (mounted) {
      setState(() => _working = false);
      Navigator.pop(context, true);
    }
  }

  /// Alpha-composite using dart:ui so we get proper antialiased rotation.
  static Future<Uint8List> _composite({
    required Uint8List pageBytes,
    required Uint8List stampBytes,
    required Offset centerNorm,
    required double widthFrac,
    required double rotation,
  }) async {
    final pageCodec = await ui.instantiateImageCodec(pageBytes);
    final pageFrame = await pageCodec.getNextFrame();
    final pageImg = pageFrame.image;

    final stampCodec = await ui.instantiateImageCodec(stampBytes);
    final stampFrame = await stampCodec.getNextFrame();
    final stampImg = stampFrame.image;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);

    // Page
    canvas.drawImage(pageImg, Offset.zero, Paint());

    // Stamp, scaled to a fraction of the page width, keeping its aspect.
    final targetW = pageImg.width * widthFrac;
    final targetH = targetW * stampImg.height / stampImg.width;
    final cx = centerNorm.dx * pageImg.width;
    final cy = centerNorm.dy * pageImg.height;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);
    canvas.drawImageRect(
      stampImg,
      Rect.fromLTWH(
        0,
        0,
        stampImg.width.toDouble(),
        stampImg.height.toDouble(),
      ),
      Rect.fromCenter(center: Offset.zero, width: targetW, height: targetH),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    final pic = rec.endRecording();
    final out = await pic.toImage(pageImg.width, pageImg.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    final png = data!.buffer.asUint8List();

    // Re-encode as JPEG to keep document sizes sane.
    final decoded = img.decodePng(png);
    if (decoded == null) return png;
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.watch<AppState>();
    final doc = state.docById(widget.docId);
    if (doc == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    final page = doc.pages.firstWhere(
      (p) => p.id == widget.pageId,
      orElse: () => doc.pages.first,
    );

    final drawing = _stamp == null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(T.s8, T.s4, T.s16, T.s8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        iconSize: 21,
                        onPressed: () {
                          if (drawing) {
                            Navigator.pop(context);
                          } else {
                            setState(() => _stamp = null);
                          }
                        },
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              drawing ? 'Draw signature' : 'Place signature',
                              style: context.t.titleMedium,
                            ),
                            Text(
                              drawing
                                  ? 'Sign with your finger'
                                  : 'Drag to position, then resize',
                              style: context.t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (drawing) ...[
                        RingIconButton(
                          icon: Icons.undo,
                          size: 38,
                          tooltip: 'Undo stroke',
                          onTap: () => setState(_ctl.undo),
                        ),
                        const SizedBox(width: T.s8),
                        RingIconButton(
                          icon: Icons.delete_outline,
                          size: 38,
                          tooltip: 'Clear',
                          onTap: () => setState(_ctl.clear),
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(color: c.hairline, height: 1),

                // Body
                Expanded(
                  child: drawing
                      ? Container(
                          color: c.surface,
                          margin: const EdgeInsets.all(T.s16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: c.hairline),
                              borderRadius: BorderRadius.circular(T.rMd),
                            ),
                            child: SignaturePad(
                              controller: _ctl,
                              inkColor: _inks[_inkIndex],
                              strokeWidth: _stroke,
                            ),
                          ),
                        )
                      : Container(
                          color: context.isDark
                              ? const Color(0xFF08090B)
                              : const Color(0xFFEDEDE8),
                          padding: const EdgeInsets.all(T.s16),
                          child: StampPlacer(
                            key: _placerKey,
                            pageBytes: page.processed,
                            stampBytes: _stamp!,
                            onConfirm: (_, __, ___) {},
                          ),
                        ),
                ),

                // Controls
                Container(
                  color: c.canvas,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        T.s20,
                        T.s12,
                        T.s20,
                        T.s12,
                      ),
                      child: drawing
                          ? _drawControls(context)
                          : _placeControls(context),
                    ),
                  ),
                ),
              ],
            ),
            if (_working) const BusyOverlay(label: 'Applying signature'),
          ],
        ),
      ),
    );
  }

  Widget _drawControls(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Row(
          children: [
            Text('Ink', style: context.t.labelMedium),
            const SizedBox(width: T.s12),
            for (int i = 0; i < _inks.length; i++) ...[
              GestureDetector(
                onTap: () => setState(() => _inkIndex = i),
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: T.s8),
                  decoration: BoxDecoration(
                    color: _inks[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _inkIndex == i ? c.accent : c.hairline,
                      width: _inkIndex == i ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text('Nib', style: context.t.labelMedium),
            SizedBox(
              width: 110,
              child: Slider(
                value: _stroke,
                min: 1.6,
                max: 6.0,
                onChanged: (v) => setState(() => _stroke = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: T.s4),
        SolidButton(
          label: 'Use this signature',
          icon: Icons.check,
          expand: true,
          loading: _working,
          onTap: _ctl.isEmpty ? null : _capture,
        ),
      ],
    );
  }

  Widget _placeControls(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text('Size', style: context.t.labelMedium),
            ),
            Expanded(
              child: Slider(
                value: _size,
                min: 0.12,
                max: 0.75,
                onChanged: (v) {
                  setState(() => _size = v);
                  _placerKey.currentState?.setScale(v);
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text('Angle', style: context.t.labelMedium),
            ),
            Expanded(
              child: Slider(
                value: _rotation,
                min: -math.pi / 8,
                max: math.pi / 8,
                onChanged: (v) {
                  setState(() => _rotation = v);
                  _placerKey.currentState?.setRotation(v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: T.s4),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: 'Redraw',
                icon: Icons.edit_outlined,
                expand: true,
                onTap: () => setState(() => _stamp = null),
              ),
            ),
            const SizedBox(width: T.s12),
            Expanded(
              child: SolidButton(
                label: 'Apply',
                icon: Icons.check,
                expand: true,
                loading: _working,
                onTap: _apply,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
