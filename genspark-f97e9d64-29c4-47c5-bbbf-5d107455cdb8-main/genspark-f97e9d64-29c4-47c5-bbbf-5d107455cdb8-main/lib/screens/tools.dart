import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/doc.dart';
import '../services/capture.dart';
import '../services/pdf_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'doc_detail.dart';
import 'export_sheet.dart';
import 'shell.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;

    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s20, T.s32),
      children: [
        const Eyebrow('Toolkit'),
        const SizedBox(height: T.s6),
        Text('Get things done', style: context.t.displaySmall),
        const SizedBox(height: T.s6),
        Text(
          'Batch actions that work across your whole library.',
          style: context.t.bodyMedium,
        ),
        const SizedBox(height: T.s24),

        // ── Capture ─────────────────────────────────────────
        const Eyebrow('Capture'),
        const SizedBox(height: T.s12),
        _ToolCard(
          icon: Icons.photo_camera_outlined,
          title: 'Quick scan',
          blurb:
              'Camera capture with automatic edge detection and '
              'Magic Color enhancement.',
          onTap: () => _quickScan(context, ScanSource.camera),
        ),
        _ToolCard(
          icon: Icons.burst_mode_outlined,
          title: 'Batch import',
          blurb:
              'Pick many photos at once — each becomes a page in one '
              'new document.',
          onTap: () => _quickScan(context, ScanSource.gallery),
        ),
        _ToolCard(
          icon: Icons.folder_open_outlined,
          title: 'Import from files',
          blurb: 'Bring in JPG, PNG, WEBP or BMP images.',
          onTap: () => _quickScan(context, ScanSource.files),
        ),

        const SizedBox(height: T.s24),

        // ── Organise ────────────────────────────────────────
        const Eyebrow('Organise'),
        const SizedBox(height: T.s12),
        _ToolCard(
          icon: Icons.merge_type,
          title: 'Merge documents',
          blurb: state.allDocs.length < 2
              ? 'Needs at least two documents in your library.'
              : 'Combine several documents into one, in the order you '
                    'choose.',
          onTap: state.allDocs.length < 2 ? null : () => _mergePicker(context),
        ),
        _ToolCard(
          icon: Icons.auto_awesome,
          title: 'Re-enhance a document',
          blurb:
              'Apply one filter to every page so a document looks '
              'consistent throughout.',
          onTap: state.allDocs.isEmpty
              ? null
              : () => _pickDocThen(context, 'Re-enhance', (doc) {
                  _filterAllSheet(context, doc);
                }),
        ),
        _ToolCard(
          icon: Icons.create_new_folder_outlined,
          title: 'New folder',
          blurb: 'Group related scans — receipts, IDs, contracts.',
          onTap: () async {
            final name = await promptText(
              context,
              title: 'New folder',
              hint: 'e.g. Tax 2025',
            );
            if (name != null && name.trim().isNotEmpty) {
              await state.createFolder(name.trim());
              if (context.mounted) {
                toast(
                  context,
                  'Folder created',
                  icon: Icons.create_new_folder_outlined,
                );
              }
            }
          },
        ),

        const SizedBox(height: T.s24),

        // ── Share ───────────────────────────────────────────
        const Eyebrow('Share'),
        const SizedBox(height: T.s12),
        _ToolCard(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Export a PDF',
          blurb: 'Choose page size, quality, watermark and page numbers.',
          onTap: state.allDocs.isEmpty
              ? null
              : () => _pickDocThen(context, 'Export', (doc) {
                  showExportSheet(context, doc);
                }),
        ),
        _ToolCard(
          icon: Icons.print_outlined,
          title: 'Print a document',
          blurb: 'Send straight to a printer or save as PDF.',
          onTap: state.allDocs.isEmpty
              ? null
              : () => _pickDocThen(context, 'Print', (doc) async {
                  try {
                    await PdfService.printDoc(doc, state.pdfOptions);
                  } catch (e) {
                    if (context.mounted) {
                      toast(context, 'Could not print: $e');
                    }
                  }
                }),
        ),

        const SizedBox(height: T.s24),

        // ── Library stats ───────────────────────────────────
        Container(
          padding: const EdgeInsets.all(T.s20),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(T.rMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Library'),
              const SizedBox(height: T.s12),
              Row(
                children: [
                  _Stat(value: '${state.allDocs.length}', label: 'documents'),
                  _Stat(value: '${state.totalPages}', label: 'pages'),
                  _Stat(value: state.librarySize, label: 'on device'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _quickScan(BuildContext context, ScanSource source) async {
    final state = context.read<AppState>();
    List<Uint8List> pages = [];
    switch (source) {
      case ScanSource.camera:
        final b = await Capture.fromCamera();
        if (b != null) pages = [b];
        break;
      case ScanSource.gallery:
        pages = await Capture.fromGallery();
        break;
      case ScanSource.files:
        pages = await Capture.fromFiles();
        break;
    }
    if (pages.isEmpty || !context.mounted) return;
    final doc = await state.createDocFromBytes(pages);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocDetailScreen(docId: doc.id, openedFromScan: true),
      ),
    );
  }

  /// Pick a single document, then run a callback with it.
  void _pickDocThen(
    BuildContext context,
    String title,
    void Function(ScanDoc) then,
  ) {
    final state = context.read<AppState>();
    showAppSheet(
      context,
      scroll: true,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, ctl) => Column(
          children: [
            SheetHeader(title: title, subtitle: 'Choose a document'),
            Expanded(
              child: ListView.builder(
                controller: ctl,
                itemCount: state.allDocs.length,
                itemBuilder: (_, i) {
                  final d = state.allDocs[i];
                  return _DocPickRow(
                    doc: d,
                    onTap: () {
                      Navigator.pop(ctx);
                      then(d);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Multi-select merge flow with explicit ordering.
  void _mergePicker(BuildContext context) {
    final state = context.read<AppState>();
    final chosen = <String>[];

    showAppSheet(
      context,
      scroll: true,
      child: StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, ctl) => Column(
            children: [
              SheetHeader(
                title: 'Merge documents',
                subtitle: chosen.isEmpty
                    ? 'Tap documents in the order you want them'
                    : '${chosen.length} selected · tap again to remove',
              ),
              Expanded(
                child: ListView.builder(
                  controller: ctl,
                  itemCount: state.allDocs.length,
                  itemBuilder: (_, i) {
                    final d = state.allDocs[i];
                    final order = chosen.indexOf(d.id);
                    return _DocPickRow(
                      doc: d,
                      order: order >= 0 ? order + 1 : null,
                      onTap: () => setSheet(() {
                        if (order >= 0) {
                          chosen.remove(d.id);
                        } else {
                          chosen.add(d.id);
                        }
                      }),
                    );
                  },
                ),
              ),
              Divider(color: ctx.c.hairline, height: 1),
              Padding(
                padding: const EdgeInsets.all(T.s20),
                child: SolidButton(
                  label: chosen.length < 2
                      ? 'Select at least two'
                      : 'Merge ${chosen.length} documents',
                  icon: Icons.merge_type,
                  expand: true,
                  onTap: chosen.length < 2
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final name = await promptText(
                            context,
                            title: 'Merged document',
                            hint: 'Name',
                            initial: 'Merged document',
                            confirmLabel: 'Merge',
                          );
                          if (name == null || name.trim().isEmpty) {
                            return;
                          }
                          final merged = await state.mergeDocs(
                            chosen,
                            name.trim(),
                          );
                          if (merged != null && context.mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DocDetailScreen(docId: merged.id),
                              ),
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _filterAllSheet(BuildContext context, ScanDoc doc) {
    final state = context.read<AppState>();
    showAppSheet(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: 'Re-enhance “${doc.title}”',
            subtitle: 'Applies to all ${doc.pageCount} pages',
          ),
          for (final f in ScanFilter.values)
            SheetTile(
              icon: switch (f) {
                ScanFilter.original => Icons.image_outlined,
                ScanFilter.magic => Icons.auto_awesome,
                ScanFilter.lighten => Icons.light_mode_outlined,
                ScanFilter.grayscale => Icons.gradient,
                ScanFilter.bw => Icons.contrast,
                ScanFilter.ink => Icons.edit_note,
              },
              title: f.label,
              subtitle: f.blurb,
              onTap: () async {
                Navigator.pop(context);
                await state.applyFilterToAll(doc.id, f);
                if (context.mounted) {
                  toast(context, '${f.label} applied', icon: Icons.check);
                }
              },
            ),
          const SizedBox(height: T.s8),
        ],
      ),
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String blurb;
  final VoidCallback? onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.blurb,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: T.s10),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(T.rMd),
            side: BorderSide(color: c.hairline),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(T.rMd),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(T.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(T.rSm),
                    ),
                    child: Icon(icon, size: 19, color: c.ink),
                  ),
                  const SizedBox(width: T.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.t.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          blurb,
                          style: context.t.bodySmall?.copyWith(height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: T.s8),
                  Padding(
                    padding: const EdgeInsets.only(top: T.s10),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocPickRow extends StatelessWidget {
  final ScanDoc doc;
  final VoidCallback onTap;
  final int? order;

  const _DocPickRow({required this.doc, required this.onTap, this.order});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s20, vertical: T.s10),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: PaperThumb(
                bytes: doc.pages.first.processed,
                aspectRatio: 0.72,
                shadow: false,
              ),
            ),
            const SizedBox(width: T.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleMedium,
                  ),
                  Text(
                    '${doc.pageCount} pages · ${doc.sizeLabel}',
                    style: context.t.bodySmall,
                  ),
                ],
              ),
            ),
            if (order != null)
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.solid,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$order',
                  style: context.t.labelMedium?.copyWith(
                    color: c.onSolid,
                    fontSize: 11,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right, size: 18, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
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
