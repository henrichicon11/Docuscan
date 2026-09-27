import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/doc.dart';
import '../services/ocr/ocr.dart';
import '../services/text_analysis.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/crop_editor.dart';
import '../widgets/kit.dart';
import 'shell.dart';
import 'signature_screen.dart';

enum _EditTab { filter, crop, adjust }

class PageEditorScreen extends StatefulWidget {
  final String docId;
  final String pageId;

  const PageEditorScreen({
    super.key,
    required this.docId,
    required this.pageId,
  });

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  _EditTab _tab = _EditTab.filter;

  // Working copies so the user can cancel.
  late List<Offset> _corners;
  late double _brightness;
  late double _contrast;
  late double _sharpen;
  bool _cornersDirty = false;

  @override
  void initState() {
    super.initState();
    final page = _page;
    _corners = page?.corners != null
        ? List<Offset>.from(page!.corners!)
        : const [
            Offset(0.04, 0.04),
            Offset(0.96, 0.04),
            Offset(0.96, 0.96),
            Offset(0.04, 0.96),
          ];
    _brightness = page?.brightness ?? 0;
    _contrast = page?.contrast ?? 0;
    _sharpen = page?.sharpen ?? 0;
  }

  ScanPage? get _page {
    final doc = context.read<AppState>().docById(widget.docId);
    if (doc == null) return null;
    for (final p in doc.pages) {
      if (p.id == widget.pageId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final doc = state.docById(widget.docId);
    final page = doc?.pages.where((p) => p.id == widget.pageId).firstOrNull;
    final c = context.c;

    if (doc == null || page == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'Page removed',
          message: 'This page is no longer part of the document.',
        ),
      );
    }

    final index = doc.pages.indexWhere((p) => p.id == page.id);

    return Scaffold(
      backgroundColor: c.canvas,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _EditorTopBar(
                  title: 'Page ${index + 1}',
                  subtitle: '${doc.title} · ${page.filter.label}',
                  onDone: () => Navigator.pop(context),
                  onAnalyze: () => _showAnalysis(context, page),
                ),
                // Canvas
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: context.isDark
                        ? const Color(0xFF08090B)
                        : const Color(0xFFEDEDE8),
                    child: Padding(
                      padding: const EdgeInsets.all(T.s16),
                      child: _tab == _EditTab.crop
                          ? CropEditor(
                              imageBytes: page.original,
                              corners: _corners,
                              onChanged: (pts) {
                                setState(() {
                                  _corners = pts;
                                  _cornersDirty = true;
                                });
                              },
                            )
                          : Center(
                              child: Hero(
                                tag: 'page_${page.id}',
                                child: PaperThumb(
                                  bytes: page.processed,
                                  fit: BoxFit.contain,
                                  radius: T.s4,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                _TabSelector(
                  tab: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                Divider(color: c.hairline, height: 1),
                _panelFor(context, doc, page),
              ],
            ),
          ),
          if (state.busy)
            BusyOverlay(label: state.busyLabel, progress: state.busyProgress),
        ],
      ),
    );
  }

  Widget _panelFor(BuildContext context, ScanDoc doc, ScanPage page) {
    final state = context.read<AppState>();
    switch (_tab) {
      case _EditTab.filter:
        return _FilterStrip(
          page: page,
          onPick: (f) => state.reprocessPage(doc.id, page.id, filter: f),
          onSign: () async {
            final placed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => SignatureScreen(docId: doc.id, pageId: page.id),
              ),
            );
            if (placed == true && context.mounted) {
              toast(context, 'Signature added', icon: Icons.draw_outlined);
            }
          },
        );

      case _EditTab.crop:
        return _CropPanel(
          onAuto: () async {
            final found = await state.autoDetect(doc.id, page.id);
            if (found != null) {
              setState(() {
                _corners = found;
                _cornersDirty = true;
              });
              if (context.mounted) {
                toast(
                  context,
                  'Edges detected',
                  icon: Icons.center_focus_strong,
                );
              }
            } else if (context.mounted) {
              toast(
                context,
                'No clear page border found — adjust manually',
                icon: Icons.info_outline,
              );
            }
          },
          onFull: () {
            setState(() {
              _corners = const [
                Offset(0, 0),
                Offset(1, 0),
                Offset(1, 1),
                Offset(0, 1),
              ];
              _cornersDirty = true;
            });
          },
          onRotate: () =>
              state.reprocessPage(doc.id, page.id, rotation: page.rotation + 1),
          onApply: _cornersDirty
              ? () async {
                  await state.reprocessPage(doc.id, page.id, corners: _corners);
                  setState(() {
                    _cornersDirty = false;
                    _tab = _EditTab.filter;
                  });
                  if (context.mounted) {
                    toast(context, 'Crop applied', icon: Icons.crop);
                  }
                }
              : null,
        );

      case _EditTab.adjust:
        return _AdjustPanel(
          brightness: _brightness,
          contrast: _contrast,
          sharpen: _sharpen,
          onChanged: (b, ct, s) => setState(() {
            _brightness = b;
            _contrast = ct;
            _sharpen = s;
          }),
          onCommit: () => state.reprocessPage(
            doc.id,
            page.id,
            brightness: _brightness,
            contrast: _contrast,
            sharpen: _sharpen,
          ),
          onReset: () {
            setState(() {
              _brightness = 0;
              _contrast = 0;
              _sharpen = 0;
            });
            state.reprocessPage(
              doc.id,
              page.id,
              brightness: 0,
              contrast: 0,
              sharpen: 0,
            );
          },
        );
    }
  }

  void _showAnalysis(BuildContext context, ScanPage page) {
    showAppSheet(
      context,
      scroll: true,
      child: _AnalysisSheet(docId: widget.docId, page: page),
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────

class _EditorTopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onDone;
  final VoidCallback onAnalyze;

  const _EditorTopBar({
    required this.title,
    required this.subtitle,
    required this.onDone,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s8, T.s4, T.s16, T.s8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            iconSize: 21,
            onPressed: onDone,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.titleMedium),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
          RingIconButton(
            icon: Icons.text_snippet_outlined,
            size: 38,
            tooltip: 'Analyse page text',
            onTap: onAnalyze,
          ),
        ],
      ),
    );
  }
}

// ── Tab selector ─────────────────────────────────────────────────────

class _TabSelector extends StatelessWidget {
  final _EditTab tab;
  final ValueChanged<_EditTab> onChanged;

  const _TabSelector({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (_EditTab.filter, Icons.auto_awesome, 'Enhance'),
      (_EditTab.crop, Icons.crop, 'Crop'),
      (_EditTab.adjust, Icons.tune, 'Adjust'),
    ];
    final c = context.c;
    return Container(
      color: c.canvas,
      padding: const EdgeInsets.symmetric(horizontal: T.s20, vertical: T.s10),
      child: Row(
        children: [
          for (final it in items) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(it.$1);
                },
                child: AnimatedContainer(
                  duration: T.fast,
                  padding: const EdgeInsets.symmetric(vertical: T.s8),
                  decoration: BoxDecoration(
                    color: tab == it.$1 ? c.surfaceAlt : null,
                    borderRadius: BorderRadius.circular(T.rSm),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        it.$2,
                        size: 19,
                        color: tab == it.$1 ? c.ink : c.inkFaint,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        it.$3,
                        style: context.t.labelMedium?.copyWith(
                          fontSize: 11,
                          color: tab == it.$1 ? c.ink : c.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Filter strip ─────────────────────────────────────────────────────

class _FilterStrip extends StatelessWidget {
  final ScanPage page;
  final ValueChanged<ScanFilter> onPick;
  final VoidCallback onSign;

  const _FilterStrip({
    required this.page,
    required this.onPick,
    required this.onSign,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.canvas,
      padding: const EdgeInsets.only(top: T.s12),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: T.s20),
                itemCount: ScanFilter.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: T.s12),
                itemBuilder: (context, i) {
                  final f = ScanFilter.values[i];
                  final active = page.filter == f;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onPick(f);
                    },
                    child: SizedBox(
                      width: 68,
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: T.fast,
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: active ? c.solid : c.surfaceAlt,
                              borderRadius: BorderRadius.circular(T.rMd),
                              border: Border.all(
                                color: active ? c.solid : c.hairline,
                              ),
                            ),
                            child: Icon(
                              _filterGlyph(f),
                              size: 22,
                              color: active ? c.onSolid : c.inkMuted,
                            ),
                          ),
                          const SizedBox(height: T.s6),
                          Text(
                            f.label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: context.t.labelMedium?.copyWith(
                              fontSize: 10.5,
                              height: 1.15,
                              color: active ? c.ink : c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(T.s20, T.s4, T.s20, T.s12),
              child: GhostButton(
                label: 'Add signature or stamp',
                icon: Icons.draw_outlined,
                expand: true,
                onTap: onSign,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _filterGlyph(ScanFilter f) => switch (f) {
  ScanFilter.original => Icons.image_outlined,
  ScanFilter.magic => Icons.auto_awesome,
  ScanFilter.lighten => Icons.light_mode_outlined,
  ScanFilter.grayscale => Icons.gradient,
  ScanFilter.bw => Icons.contrast,
  ScanFilter.ink => Icons.edit_note,
};

// ── Crop panel ───────────────────────────────────────────────────────

class _CropPanel extends StatelessWidget {
  final VoidCallback onAuto;
  final VoidCallback onFull;
  final VoidCallback onRotate;
  final VoidCallback? onApply;

  const _CropPanel({
    required this.onAuto,
    required this.onFull,
    required this.onRotate,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s20, T.s12),
          child: Column(
            children: [
              Text(
                'Drag the corners onto the page edges. '
                'A magnifier appears while you drag.',
                textAlign: TextAlign.center,
                style: context.t.bodySmall,
              ),
              const SizedBox(height: T.s16),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Auto',
                      icon: Icons.center_focus_strong,
                      expand: true,
                      onTap: onAuto,
                    ),
                  ),
                  const SizedBox(width: T.s8),
                  Expanded(
                    child: GhostButton(
                      label: 'Full',
                      icon: Icons.fullscreen,
                      expand: true,
                      onTap: onFull,
                    ),
                  ),
                  const SizedBox(width: T.s8),
                  RingIconButton(
                    icon: Icons.rotate_right,
                    size: 50,
                    tooltip: 'Rotate 90°',
                    onTap: onRotate,
                  ),
                ],
              ),
              const SizedBox(height: T.s10),
              SolidButton(
                label: 'Apply crop',
                icon: Icons.check,
                expand: true,
                onTap: onApply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Adjust panel ─────────────────────────────────────────────────────

class _AdjustPanel extends StatelessWidget {
  final double brightness;
  final double contrast;
  final double sharpen;
  final void Function(double, double, double) onChanged;
  final VoidCallback onCommit;
  final VoidCallback onReset;

  const _AdjustPanel({
    required this.brightness,
    required this.contrast,
    required this.sharpen,
    required this.onChanged,
    required this.onCommit,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.s20, T.s12, T.s20, T.s12),
          child: Column(
            children: [
              _Slider(
                label: 'Brightness',
                value: brightness,
                min: -1,
                max: 1,
                onChanged: (v) => onChanged(v, contrast, sharpen),
                onEnd: onCommit,
              ),
              _Slider(
                label: 'Contrast',
                value: contrast,
                min: -1,
                max: 1,
                onChanged: (v) => onChanged(brightness, v, sharpen),
                onEnd: onCommit,
              ),
              _Slider(
                label: 'Sharpness',
                value: sharpen,
                min: 0,
                max: 1,
                onChanged: (v) => onChanged(brightness, contrast, v),
                onEnd: onCommit,
              ),
              const SizedBox(height: T.s4),
              GhostButton(
                label: 'Reset adjustments',
                icon: Icons.restart_alt,
                expand: true,
                onTap: onReset,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final pct = ((value - min) / (max - min) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s4),
      child: Row(
        children: [
          SizedBox(width: 78, child: Text(label, style: context.t.labelMedium)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (_) => onEnd(),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$pct',
              textAlign: TextAlign.right,
              style: context.t.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Text recognition sheet ───────────────────────────────────────────

/// Shows real OCR text when the platform supports it, and always shows
/// layout metrics measured from the scan itself.
class _AnalysisSheet extends StatefulWidget {
  final String docId;
  final ScanPage page;
  const _AnalysisSheet({required this.docId, required this.page});

  @override
  State<_AnalysisSheet> createState() => _AnalysisSheetState();
}

class _AnalysisSheetState extends State<_AnalysisSheet> {
  TextLayout? _layout;
  OcrResult? _ocr;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    // Capture the state object before any await so we never touch
    // BuildContext across an async gap.
    final appState = context.read<AppState>();

    // Let the sheet paint before the heavy work starts.
    await Future.delayed(const Duration(milliseconds: 40));

    final layout = TextAnalysis.analyze(widget.page.processed);
    if (mounted) setState(() => _layout = layout);

    final ocr =
        await appState.recognisePage(widget.docId, widget.page.id);

    if (mounted) {
      setState(() {
        _ocr = ocr;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ocr = _ocr;
    final hasText = ocr != null && ocr.recognised && !ocr.isEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, ctl) => Column(
        children: [
          SheetHeader(
            title: hasText ? 'Recognised text' : 'Page analysis',
            subtitle: hasText
                ? '${ocr.wordCount} words · ${ocr.readingTime}'
                : 'Measured directly from the scan',
            trailing: hasText
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RingIconButton(
                        icon: Icons.copy_all_outlined,
                        size: 38,
                        tooltip: 'Copy all text',
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: ocr.text));
                          toast(context, 'Text copied to clipboard',
                              icon: Icons.check);
                        },
                      ),
                      const SizedBox(width: T.s8),
                      RingIconButton(
                        icon: Icons.ios_share,
                        size: 38,
                        tooltip: 'Share text',
                        onTap: () => Share.share(ocr.text),
                      ),
                    ],
                  )
                : null,
          ),
          Expanded(
            child: ListView(
              controller: ctl,
              padding: const EdgeInsets.only(bottom: T.s24),
              children: [
                if (_loading) _busy(context),

                // ── Recognised text ──────────────────────────────
                if (hasText) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: T.s20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(T.s16),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(T.rMd),
                      ),
                      child: SelectableText(
                        ocr.text,
                        style: context.t.bodyLarge?.copyWith(height: 1.55),
                      ),
                    ),
                  ),
                  const SizedBox(height: T.s16),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: T.s20),
                    child: Row(
                      children: [
                        _Stat(value: '${ocr.wordCount}', label: 'words'),
                        _Stat(
                            value: '${ocr.lineCount}', label: 'lines'),
                        _Stat(
                            value: '${ocr.charCount}',
                            label: 'characters'),
                      ],
                    ),
                  ),
                  const SizedBox(height: T.s16),
                  _note(
                    context,
                    Icons.lock_outline,
                    'Recognised on-device with Google ML Kit. '
                    'This text is saved with the page, so the document '
                    'is now searchable from your library.',
                  ),
                ],

                // ── OCR ran but found nothing ────────────────────
                if (ocr != null && ocr.recognised && ocr.isEmpty)
                  _note(
                    context,
                    Icons.search_off,
                    'No readable text was found on this page. Try the '
                    'B & W filter or a tighter crop, then run it again.',
                  ),

                // ── Platform has no OCR engine ───────────────────
                if (ocr != null && !ocr.recognised) ...[
                  _note(
                    context,
                    Icons.info_outline,
                    ocr.unavailableReason ??
                        'Text recognition is unavailable here.',
                  ),
                  const SizedBox(height: T.s8),
                ],

                // ── Layout metrics (always available) ────────────
                if (_layout != null) ...[
                  const SizedBox(height: T.s20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: T.s20),
                    child: Eyebrow('Layout'),
                  ),
                  const SizedBox(height: T.s12),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: T.s20),
                    child: Row(
                      children: [
                        _Stat(
                            value: '${_layout!.lineCount}',
                            label: 'text lines'),
                        _Stat(
                            value: '${_layout!.blockCount}',
                            label: 'blocks'),
                        _Stat(
                          value:
                              '${(_layout!.inkCoverage * 100).toStringAsFixed(1)}%',
                          label: 'ink',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: T.s16),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: T.s20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(T.s16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(T.rMd),
                        border: Border.all(color: c.hairline),
                      ),
                      child: Text(
                        TextAnalysis.summarize(_layout!),
                        style:
                            context.t.bodyLarge?.copyWith(height: 1.55),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _busy(BuildContext context) => Padding(
        padding: const EdgeInsets.all(T.s32),
        child: Column(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.c.ink),
            ),
            const SizedBox(height: T.s16),
            Text(
              OcrEngine.isSupported
                  ? 'Reading the page…'
                  : 'Measuring page layout…',
              style: context.t.bodySmall,
            ),
          ],
        ),
      );

  Widget _note(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: context.c.inkFaint),
            const SizedBox(width: T.s6),
            Expanded(
              child: Text(text,
                  style: context.t.bodySmall?.copyWith(height: 1.45)),
            ),
          ],
        ),
      );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.t.headlineMedium),
          const SizedBox(height: 2),
          Text(label, style: context.t.bodySmall),
        ],
      ),
    );
  }
}
