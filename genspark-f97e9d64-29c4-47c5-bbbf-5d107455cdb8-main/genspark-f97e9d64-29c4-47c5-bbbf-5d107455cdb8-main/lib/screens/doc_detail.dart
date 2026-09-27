import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/doc.dart';
import '../services/capture.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'export_sheet.dart';
import 'page_editor.dart';
import 'page_viewer.dart';
import 'shell.dart';

class DocDetailScreen extends StatefulWidget {
  final String docId;
  final bool openedFromScan;

  const DocDetailScreen({
    super.key,
    required this.docId,
    this.openedFromScan = false,
  });

  @override
  State<DocDetailScreen> createState() => _DocDetailScreenState();
}

class _DocDetailScreenState extends State<DocDetailScreen> {
  bool _reordering = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final doc = state.docById(widget.docId);
    final c = context.c;

    if (doc == null) {
      // Document was deleted while this screen was open.
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'Document removed',
          message: 'This document is no longer in your library.',
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _DetailHeader(
                  doc: doc,
                  reordering: _reordering,
                  onToggleReorder: () =>
                      setState(() => _reordering = !_reordering),
                ),
                Divider(color: c.hairline, height: 1),
                Expanded(
                  child: _reordering
                      ? _ReorderGrid(doc: doc)
                      : _PageGrid(doc: doc),
                ),
              ],
            ),
          ),
          if (state.busy)
            BusyOverlay(label: state.busyLabel, progress: state.busyProgress),
        ],
      ),
      bottomNavigationBar: _DetailActions(doc: doc),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final ScanDoc doc;
  final bool reordering;
  final VoidCallback onToggleReorder;

  const _DetailHeader({
    required this.doc,
    required this.reordering,
    required this.onToggleReorder,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final c = context.c;

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s8, T.s4, T.s12, T.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                iconSize: 21,
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              RingIconButton(
                icon: doc.favorite ? Icons.star_rounded : Icons.star_border,
                size: 38,
                tooltip: 'Star',
                onTap: () => state.toggleFavorite(doc.id),
              ),
              const SizedBox(width: T.s8),
              RingIconButton(
                icon: reordering
                    ? Icons.check
                    : Icons.swap_vert_circle_outlined,
                size: 38,
                active: reordering,
                tooltip: reordering ? 'Done reordering' : 'Reorder pages',
                onTap: onToggleReorder,
              ),
              const SizedBox(width: T.s8),
              RingIconButton(
                icon: Icons.more_horiz,
                size: 38,
                tooltip: 'More',
                onTap: () => _moreOptions(context, doc),
              ),
            ],
          ),
          const SizedBox(height: T.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () async {
                    final name = await promptText(
                      context,
                      title: 'Rename document',
                      initial: doc.title,
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await state.renameDoc(doc.id, name.trim());
                    }
                  },
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          doc.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.headlineMedium,
                        ),
                      ),
                      const SizedBox(width: T.s8),
                      Icon(Icons.edit_outlined, size: 15, color: c.inkFaint),
                    ],
                  ),
                ),
                const SizedBox(height: T.s6),
                Text(
                  '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}'
                  '  ·  ${doc.sizeLabel}'
                  '  ·  Updated ${DateFormat('MMM d, HH:mm').format(doc.updatedAt)}',
                  style: context.t.bodySmall,
                ),
                if (reordering) ...[
                  const SizedBox(height: T.s10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: T.s10,
                      vertical: T.s6,
                    ),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(T.rSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drag_indicator, size: 14, color: c.accent),
                        const SizedBox(width: T.s6),
                        Text(
                          'Drag pages to reorder',
                          style: context.t.labelMedium?.copyWith(
                            color: c.accent,
                          ),
                        ),
                      ],
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

  void _moreOptions(BuildContext context, ScanDoc doc) {
    final state = context.read<AppState>();
    showAppSheet(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Document'),
          SheetTile(
            icon: Icons.auto_fix_high_outlined,
            title: 'Apply filter to all pages',
            subtitle: 'Make every page look consistent',
            onTap: () {
              Navigator.pop(context);
              _filterAllSheet(context, doc);
            },
          ),
          SheetTile(
            icon: Icons.call_split,
            title: 'Split document',
            subtitle: 'Break into two documents',
            onTap: doc.pageCount < 2
                ? null
                : () {
                    Navigator.pop(context);
                    _splitSheet(context, doc);
                  },
          ),
          SheetTile(
            icon: Icons.drive_file_move_outlined,
            title: 'Move to folder',
            onTap: () async {
              Navigator.pop(context);
              final id = await pickFolderSheet(
                context,
                currentId: doc.folderId,
              );
              if (id == null) return;
              await state.moveDoc(doc.id, id == '__none__' ? null : id);
            },
          ),
          SheetTile(
            icon: Icons.copy_all_outlined,
            title: 'Duplicate document',
            onTap: () async {
              Navigator.pop(context);
              await state.duplicateDoc(doc.id);
              if (context.mounted) {
                toast(context, 'Duplicated', icon: Icons.check);
              }
            },
          ),
          SheetTile(
            icon: Icons.delete_outline,
            title: 'Delete document',
            tint: context.c.danger,
            onTap: () async {
              Navigator.pop(context);
              final ok = await confirmDestructive(
                context,
                title: 'Delete “${doc.title}”?',
                message: 'This cannot be undone.',
              );
              if (ok) {
                await state.deleteDoc(doc.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: T.s8),
        ],
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
          const SheetHeader(
            title: 'Apply to all pages',
            subtitle: 'Every page is re-processed from the original',
          ),
          for (final f in ScanFilter.values)
            SheetTile(
              icon: _filterIcon(f),
              title: f.label,
              subtitle: f.blurb,
              onTap: () async {
                Navigator.pop(context);
                await state.applyFilterToAll(doc.id, f);
                if (context.mounted) {
                  toast(
                    context,
                    '${f.label} applied to all pages',
                    icon: Icons.check,
                  );
                }
              },
            ),
          const SizedBox(height: T.s8),
        ],
      ),
    );
  }

  void _splitSheet(BuildContext context, ScanDoc doc) {
    final state = context.read<AppState>();
    showAppSheet(
      context,
      scroll: true,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, ctl) => Column(
          children: [
            const SheetHeader(
              title: 'Split document',
              subtitle: 'Choose where the second document begins',
            ),
            Expanded(
              child: ListView.builder(
                controller: ctl,
                itemCount: doc.pageCount - 1,
                itemBuilder: (_, i) {
                  final at = i + 1;
                  return SheetTile(
                    icon: Icons.horizontal_rule,
                    title: 'Before page ${at + 1}',
                    subtitle:
                        'Pages 1–$at  ·  Pages ${at + 1}–${doc.pageCount}',
                    onTap: () async {
                      Navigator.pop(ctx);
                      await state.splitDoc(doc.id, at);
                      if (context.mounted) {
                        toast(
                          context,
                          'Document split',
                          icon: Icons.call_split,
                        );
                      }
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
}

IconData _filterIcon(ScanFilter f) => switch (f) {
  ScanFilter.original => Icons.image_outlined,
  ScanFilter.magic => Icons.auto_awesome,
  ScanFilter.lighten => Icons.light_mode_outlined,
  ScanFilter.grayscale => Icons.gradient,
  ScanFilter.bw => Icons.contrast,
  ScanFilter.ink => Icons.edit_note,
};

// ── Page grid ────────────────────────────────────────────────────────

class _PageGrid extends StatelessWidget {
  final ScanDoc doc;
  const _PageGrid({required this.doc});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s20, T.s32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: T.s16,
        mainAxisSpacing: T.s20,
        childAspectRatio: 0.64,
      ),
      itemCount: doc.pageCount,
      itemBuilder: (context, i) {
        final page = doc.pages[i];
        return Reveal(
          index: i,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PageViewerScreen(docId: doc.id, initialIndex: i),
                    ),
                  ),
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    _pageOptions(context, doc, page, i);
                  },
                  child: Hero(
                    tag: 'page_${page.id}',
                    child: PaperThumb(bytes: page.processed, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: T.s8),
              Row(
                children: [
                  Text(
                    '${i + 1}',
                    style: context.t.titleSmall?.copyWith(
                      color: context.c.inkMuted,
                    ),
                  ),
                  const SizedBox(width: T.s8),
                  Expanded(
                    child: Text(
                      page.filter.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PageEditorScreen(docId: doc.id, pageId: page.id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.tune,
                        size: 16,
                        color: context.c.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _pageOptions(
    BuildContext context,
    ScanDoc doc,
    ScanPage page,
    int index,
  ) {
    final state = context.read<AppState>();
    showAppSheet(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Page ${index + 1}', subtitle: page.filter.label),
          SheetTile(
            icon: Icons.tune,
            title: 'Edit page',
            subtitle: 'Crop, filter, rotate, adjust',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PageEditorScreen(docId: doc.id, pageId: page.id),
                ),
              );
            },
          ),
          SheetTile(
            icon: Icons.rotate_right,
            title: 'Rotate 90°',
            onTap: () async {
              Navigator.pop(context);
              await state.reprocessPage(
                doc.id,
                page.id,
                rotation: page.rotation + 1,
              );
            },
          ),
          SheetTile(
            icon: Icons.copy_all_outlined,
            title: 'Duplicate page',
            onTap: () {
              Navigator.pop(context);
              state.duplicatePage(doc.id, page.id);
            },
          ),
          SheetTile(
            icon: Icons.delete_outline,
            title: 'Delete page',
            tint: context.c.danger,
            onTap: () async {
              Navigator.pop(context);
              final ok = await confirmDestructive(
                context,
                title: 'Delete page ${index + 1}?',
                message: doc.pageCount == 1
                    ? 'This is the only page — the document will be '
                          'deleted too.'
                    : 'The page is removed from this document.',
              );
              if (!ok) return;
              final wasLast = doc.pageCount == 1;
              await state.deletePage(doc.id, page.id);
              if (wasLast && context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: T.s8),
        ],
      ),
    );
  }
}

// ── Reorder grid ─────────────────────────────────────────────────────

class _ReorderGrid extends StatelessWidget {
  final ScanDoc doc;
  const _ReorderGrid({required this.doc});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final c = context.c;

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s20, T.s32),
      itemCount: doc.pageCount,
      onReorder: (from, to) {
        HapticFeedback.selectionClick();
        state.reorderPage(doc.id, from, to > from ? to - 1 : to);
      },
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.03, child: child),
      ),
      itemBuilder: (context, i) {
        final page = doc.pages[i];
        return Container(
          key: ValueKey(page.id),
          margin: const EdgeInsets.only(bottom: T.s12),
          padding: const EdgeInsets.all(T.s10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(T.rMd),
            border: Border.all(color: c.hairline),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: PaperThumb(
                  bytes: page.processed,
                  aspectRatio: 0.72,
                  shadow: false,
                ),
              ),
              const SizedBox(width: T.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Page ${i + 1}', style: context.t.titleMedium),
                    const SizedBox(height: 2),
                    Text(page.filter.label, style: context.t.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.drag_handle, color: c.inkFaint, size: 20),
            ],
          ),
        );
      },
    );
  }
}

// ── Bottom actions ───────────────────────────────────────────────────

class _DetailActions extends StatelessWidget {
  final ScanDoc doc;
  const _DetailActions({required this.doc});

  Future<void> _addPages(BuildContext context) async {
    final choice = await showScanSourceSheet(context);
    if (choice == null || !context.mounted) return;
    final state = context.read<AppState>();
    List<Uint8List> pages = [];
    switch (choice) {
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
    if (pages.isEmpty) return;
    await state.addPagesToDoc(doc.id, pages);
    if (context.mounted) {
      toast(
        context,
        'Added ${pages.length} page(s)',
        icon: Icons.add_a_photo_outlined,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.canvas,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.s20, T.s12, T.s20, T.s12),
          child: Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Add pages',
                  icon: Icons.add,
                  expand: true,
                  onTap: () => _addPages(context),
                ),
              ),
              const SizedBox(width: T.s12),
              Expanded(
                child: SolidButton(
                  label: 'Export',
                  icon: Icons.ios_share,
                  expand: true,
                  onTap: () => showExportSheet(context, doc),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
