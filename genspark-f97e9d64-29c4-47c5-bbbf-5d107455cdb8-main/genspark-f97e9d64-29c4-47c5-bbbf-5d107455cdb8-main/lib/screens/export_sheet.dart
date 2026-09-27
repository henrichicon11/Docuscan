import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/doc.dart';
import '../services/pdf_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'shell.dart';

/// PDF export configuration + actions.
void showExportSheet(BuildContext context, ScanDoc doc) {
  showAppSheet(context, scroll: true, child: _ExportSheet(doc: doc));
}

class _ExportSheet extends StatefulWidget {
  final ScanDoc doc;
  const _ExportSheet({required this.doc});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late PdfOptions _o;
  final _watermarkCtl = TextEditingController();
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _o = context.read<AppState>().pdfOptions;
    _watermarkCtl.text = _o.watermark ?? '';
  }

  @override
  void dispose() {
    _watermarkCtl.dispose();
    super.dispose();
  }

  void _update(PdfOptions o) {
    setState(() => _o = o);
    context.read<AppState>().setPdfOptions(o);
  }

  Future<void> _run(Future<void> Function() action, String failMsg) async {
    setState(() => _working = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _working = false);
        toast(context, '$failMsg: $e', icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final doc = widget.doc;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      builder: (ctx, ctl) => Stack(
        children: [
          ListView(
            controller: ctl,
            padding: EdgeInsets.zero,
            children: [
              SheetHeader(
                title: 'Export',
                subtitle:
                    '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}'
                    ' · ${PdfService.fileName(doc)}',
              ),

              // Page size
              _section(context, 'Page size'),
              for (final s in PageSize.values)
                _radioRow(
                  context,
                  label: s.label,
                  selected: _o.size == s,
                  onTap: () => _update(_o.copyWith(size: s)),
                ),

              // Quality
              _section(context, 'Image quality'),
              for (final q in ExportQuality.values)
                _radioRow(
                  context,
                  label: q.label,
                  trailing: '${q.maxEdge}px',
                  selected: _o.quality == q,
                  onTap: () => _update(_o.copyWith(quality: q)),
                ),

              // Extras
              _section(context, 'Extras'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Page numbers', style: context.t.titleMedium),
                          Text(
                            'Printed bottom-right',
                            style: context.t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _o.includePageNumbers,
                      onChanged: (v) =>
                          _update(_o.copyWith(includePageNumbers: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: T.s12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s20),
                child: TextField(
                  controller: _watermarkCtl,
                  style: context.t.bodyLarge,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Watermark text',
                    hintText: 'e.g. CONFIDENTIAL',
                    isDense: true,
                  ),
                  onChanged: (v) => _update(_o.copyWith(watermark: v)),
                ),
              ),
              if (_watermarkCtl.text.trim().isNotEmpty) ...[
                const SizedBox(height: T.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: T.s20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text('Opacity', style: context.t.labelMedium),
                      ),
                      Expanded(
                        child: Slider(
                          value: _o.watermarkOpacity,
                          min: 0.04,
                          max: 0.4,
                          onChanged: (v) =>
                              _update(_o.copyWith(watermarkOpacity: v)),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${(_o.watermarkOpacity * 100).round()}',
                          textAlign: TextAlign.right,
                          style: context.t.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: T.s24),
              Divider(color: c.hairline, height: 1),

              // Actions
              Padding(
                padding: const EdgeInsets.all(T.s20),
                child: Column(
                  children: [
                    SolidButton(
                      label: 'Share PDF',
                      icon: Icons.ios_share,
                      expand: true,
                      loading: _working,
                      onTap: () => _run(
                        () => PdfService.shareDoc(doc, _o),
                        'Share failed',
                      ),
                    ),
                    const SizedBox(height: T.s10),
                    GhostButton(
                      label: 'Print or save as PDF',
                      icon: Icons.print_outlined,
                      expand: true,
                      onTap: () => _run(
                        () => PdfService.printDoc(doc, _o),
                        'Print failed',
                      ),
                    ),
                    const SizedBox(height: T.s10),
                    GhostButton(
                      label: 'Share page images',
                      icon: Icons.image_outlined,
                      expand: true,
                      onTap: () => _run(
                        () => PdfService.shareImages(doc),
                        'Share failed',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_working) const BusyOverlay(label: 'Building PDF'),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(T.s20, T.s20, T.s20, T.s8),
    child: Eyebrow(label),
  );

  Widget _radioRow(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? trailing,
  }) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s20, vertical: T.s10),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? c.ink : c.hairline,
                  width: selected ? 5.5 : 1.4,
                ),
              ),
            ),
            const SizedBox(width: T.s12),
            Expanded(child: Text(label, style: context.t.bodyLarge)),
            if (trailing != null) Text(trailing, style: context.t.bodySmall),
          ],
        ),
      ),
    );
  }
}
