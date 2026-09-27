import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/doc.dart';
import '../services/pdf_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'doc_detail.dart';
import 'shell.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchCtl = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final docs = state.visibleDocs;
    final c = context.c;

    return Column(
      children: [
        _Header(
          searching: _searching,
          controller: _searchCtl,
          onToggleSearch: () {
            setState(() => _searching = !_searching);
            if (!_searching) {
              _searchCtl.clear();
              state.setQuery('');
            }
          },
        ),
        _FolderTabs(),
        Divider(color: c.hairline, height: 1),
        Expanded(
          child: docs.isEmpty
              ? _emptyFor(context, state)
              : RefreshIndicator(
                  color: c.ink,
                  backgroundColor: c.surface,
                  onRefresh: () async {
                    await Future.delayed(const Duration(milliseconds: 420));
                  },
                  child: state.gridView
                      ? _DocGrid(docs: docs)
                      : _DocList(docs: docs),
                ),
        ),
        if (state.selecting) _SelectionBar(),
      ],
    );
  }

  Widget _emptyFor(BuildContext context, AppState state) {
    if (state.query.trim().isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No matches',
        message: 'Nothing in your library matches “${state.query.trim()}”.',
        action: GhostButton(
          label: 'Clear search',
          onTap: () {
            _searchCtl.clear();
            state.setQuery('');
          },
        ),
      );
    }
    if (state.onlyFavorites) {
      return const EmptyState(
        icon: Icons.star_border,
        title: 'No starred documents',
        message: 'Star a document to keep it within easy reach.',
      );
    }
    if (state.activeFolderId != null) {
      return const EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'This folder is empty',
        message: 'Scan something new, or move a document in here.',
      );
    }
    return const EmptyState(
      icon: Icons.document_scanner_outlined,
      title: 'Your library is empty',
      message:
          'Tap Scan to capture your first document. Edges are detected '
          'and the page is enhanced automatically.',
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool searching;
  final TextEditingController controller;
  final VoidCallback onToggleSearch;

  const _Header({
    required this.searching,
    required this.controller,
    required this.onToggleSearch,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s16, T.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Documents'),
                    const SizedBox(height: T.s6),
                    // Big editorial stat line.
                    AnimatedSize(
                      duration: T.med,
                      curve: T.ease,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${state.allDocs.length}',
                            style: context.t.displaySmall,
                          ),
                          const SizedBox(width: T.s8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              state.allDocs.length == 1 ? 'scan' : 'scans',
                              style: context.t.titleMedium?.copyWith(
                                color: c.inkMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: T.s10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: MetaPill(text: '${state.totalPages} pages'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: T.s8),
              RingIconButton(
                icon: searching ? Icons.close : Icons.search,
                tooltip: searching ? 'Close search' : 'Search',
                onTap: onToggleSearch,
              ),
              const SizedBox(width: T.s8),
              RingIconButton(
                icon: state.gridView
                    ? Icons.view_agenda_outlined
                    : Icons.grid_view_outlined,
                tooltip: state.gridView ? 'List view' : 'Grid view',
                onTap: state.toggleGrid,
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: T.med,
            sizeCurve: T.ease,
            crossFadeState: searching
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: T.s12, right: T.s4),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: context.t.bodyLarge,
                onChanged: context.read<AppState>().setQuery,
                decoration: InputDecoration(
                  hintText: 'Search titles and page text…',
                  prefixIcon: Icon(Icons.search, size: 19, color: c.inkFaint),
                  isDense: true,
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
          const SizedBox(height: T.s4),
          // Quick filter row
          Padding(
            padding: const EdgeInsets.only(top: T.s8),
            child: Row(
              children: [
                _MicroToggle(
                  label: 'Starred',
                  icon: Icons.star_rounded,
                  active: state.onlyFavorites,
                  onTap: state.toggleOnlyFavorites,
                ),
                const SizedBox(width: T.s8),
                _MicroToggle(
                  label: state.sort.label,
                  icon: Icons.swap_vert,
                  active: false,
                  onTap: () => showSortSheet(context),
                ),
                const Spacer(),
                Text(state.librarySize, style: context.t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _MicroToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: active ? c.accentSoft : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(T.rPill),
        side: BorderSide(color: active ? c.accent : c.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.rPill),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: T.s10,
            vertical: T.s6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? c.accent : c.inkMuted),
              const SizedBox(width: T.s4),
              Text(
                label,
                style: context.t.labelMedium?.copyWith(
                  color: active ? c.accent : c.inkMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Folder tabs ──────────────────────────────────────────────────────

class _FolderTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    // Fade the trailing edge so clipped tabs read as "more to scroll".
    return SizedBox(
      height: 46,
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [c.canvas, c.canvas, Colors.transparent],
          stops: const [0.0, 0.92, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: T.s20),
          children: [
            UnderlineTab(
              label: 'All',
              count: state.docCountInFolder(null),
              active: state.activeFolderId == null,
              onTap: () => state.setFolder(null),
            ),
            const SizedBox(width: T.s20),
            for (final f in state.folders) ...[
              GestureDetector(
                onLongPress: () => _folderOptions(context, f),
                child: UnderlineTab(
                  label: f.name,
                  count: state.docCountInFolder(f.id),
                  active: state.activeFolderId == f.id,
                  onTap: () => state.setFolder(f.id),
                ),
              ),
              const SizedBox(width: T.s20),
            ],
            Center(
              child: RingIconButton(
                icon: Icons.add,
                size: 30,
                tooltip: 'New folder',
                onTap: () async {
                  final name = await promptText(
                    context,
                    title: 'New folder',
                    hint: 'e.g. Tax 2025',
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await state.createFolder(name.trim());
                  }
                },
              ),
            ),
            const SizedBox(width: T.s20),
          ],
        ),
      ),
    );
  }

  void _folderOptions(BuildContext context, Folder f) {
    final state = context.read<AppState>();
    showAppSheet(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: f.name,
            subtitle: '${state.docCountInFolder(f.id)} documents',
          ),
          SheetTile(
            icon: Icons.edit_outlined,
            title: 'Rename folder',
            onTap: () async {
              Navigator.pop(context);
              final name = await promptText(
                context,
                title: 'Rename folder',
                initial: f.name,
              );
              if (name != null && name.trim().isNotEmpty) {
                await state.renameFolder(f.id, name.trim());
              }
            },
          ),
          SheetTile(
            icon: Icons.delete_outline,
            title: 'Delete folder',
            subtitle: 'Documents move back to the main library',
            tint: context.c.danger,
            onTap: () async {
              Navigator.pop(context);
              final ok = await confirmDestructive(
                context,
                title: 'Delete “${f.name}”?',
                message:
                    'The folder is removed. Its documents stay in your '
                    'library.',
              );
              if (ok) await state.deleteFolder(f.id);
            },
          ),
          const SizedBox(height: T.s8),
        ],
      ),
    );
  }
}

// ── List view ────────────────────────────────────────────────────────

class _DocList extends StatelessWidget {
  final List<ScanDoc> docs;
  const _DocList({required this.docs});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s8, T.s20, T.s32),
      itemCount: docs.length,
      separatorBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s4),
        child: Divider(color: context.c.hairline, height: 1),
      ),
      itemBuilder: (context, i) => Reveal(
        index: i,
        child: _DocRow(doc: docs[i]),
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final ScanDoc doc;
  const _DocRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final selected = state.selected.contains(doc.id);

    return InkWell(
      borderRadius: BorderRadius.circular(T.rMd),
      onTap: () {
        if (state.selecting) {
          state.toggleSelect(doc.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DocDetailScreen(docId: doc.id)),
          );
        }
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        state.toggleSelect(doc.id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // In a scanner the page should be the hero, so the row
                // thumbnail is generous and uses true A4 proportions.
                SizedBox(
                  width: 78,
                  child: PaperThumb(
                    bytes: doc.pages.first.processed,
                    aspectRatio: 1 / 1.414,
                  ),
                ),
                if (doc.pageCount > 1)
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.solid,
                        borderRadius: BorderRadius.circular(T.rPill),
                        border: Border.all(color: c.canvas, width: 1.5),
                      ),
                      child: Text(
                        '${doc.pageCount}',
                        style: context.t.labelMedium?.copyWith(
                          color: c.onSolid,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(T.rSm),
                        border: Border.all(color: c.accent, width: 2),
                      ),
                      child: Icon(
                        Icons.check_circle,
                        color: c.accent,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: T.s16),
            // Text block is centred against the taller thumbnail so the
            // row reads as one balanced unit instead of top-heavy text
            // with dead space beneath it.
            Expanded(
              child: SizedBox(
                height: 78 * 1.414,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            doc.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.titleMedium,
                          ),
                        ),
                        if (doc.favorite)
                          Icon(Icons.star_rounded, size: 16, color: c.accent),
                      ],
                    ),
                    const SizedBox(height: T.s6),
                    Text(
                      '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}'
                      '  ·  ${doc.sizeLabel}'
                      '  ·  ${DateFormat('MMM d').format(doc.updatedAt)}',
                      style: context.t.bodySmall,
                    ),
                    if (doc.folderId != null) ...[
                      const SizedBox(height: T.s8),
                      MetaPill(
                        text: state.folders
                            .firstWhere(
                              (f) => f.id == doc.folderId,
                              orElse: () => Folder(id: '', name: 'Folder'),
                            )
                            .name,
                        icon: Icons.folder_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: T.s4),
            IconButton(
              icon: Icon(Icons.more_horiz, color: c.inkFaint),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: () => showDocOptions(context, doc),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grid view ────────────────────────────────────────────────────────

class _DocGrid extends StatelessWidget {
  final List<ScanDoc> docs;
  const _DocGrid({required this.docs});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s20, T.s32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: T.s16,
        mainAxisSpacing: T.s20,
        childAspectRatio: 0.58,
      ),
      itemCount: docs.length,
      itemBuilder: (context, i) => Reveal(
        index: i,
        child: _DocCard(doc: docs[i]),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final ScanDoc doc;
  const _DocCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final selected = state.selected.contains(doc.id);

    return GestureDetector(
      onTap: () {
        if (state.selecting) {
          state.toggleSelect(doc.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DocDetailScreen(docId: doc.id)),
          );
        }
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        state.toggleSelect(doc.id);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: PaperThumb(
                    bytes: doc.pages.first.processed,
                    fit: BoxFit.cover,
                    radius: T.rSm,
                  ),
                ),
                if (doc.pageCount > 1)
                  Positioned(
                    top: T.s8,
                    right: T.s8,
                    child: MetaPill(
                      text: '${doc.pageCount}',
                      icon: Icons.layers_outlined,
                      bg: c.solid.withValues(alpha: 0.82),
                      fg: c.onSolid,
                    ),
                  ),
                if (doc.favorite)
                  Positioned(
                    top: T.s8,
                    left: T.s8,
                    child: Icon(Icons.star_rounded, size: 17, color: c.accent),
                  ),
                if (selected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(T.rSm),
                        border: Border.all(color: c.accent, width: 2.5),
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.check_circle,
                          color: c.accent,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: T.s10),
          Text(
            doc.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            '${doc.pageCount} pg · ${DateFormat('MMM d').format(doc.updatedAt)}',
            style: context.t.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Selection action bar ─────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final n = state.selected.length;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: T.s16, vertical: T.s12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            onPressed: state.clearSelection,
          ),
          Text('$n selected', style: context.t.titleSmall),
          const Spacer(),
          if (n >= 2)
            RingIconButton(
              icon: Icons.merge_type,
              tooltip: 'Merge into one document',
              onTap: () async {
                final name = await promptText(
                  context,
                  title: 'Merge $n documents',
                  hint: 'New document name',
                  initial: 'Merged document',
                  confirmLabel: 'Merge',
                );
                if (name == null || name.trim().isEmpty) return;
                final ids = state.selected.toList();
                final merged = await state.mergeDocs(ids, name.trim());
                if (merged != null && context.mounted) {
                  toast(
                    context,
                    'Merged into “${merged.title}”',
                    icon: Icons.merge_type,
                  );
                }
              },
            ),
          const SizedBox(width: T.s8),
          RingIconButton(
            icon: Icons.drive_file_move_outlined,
            tooltip: 'Move to folder',
            onTap: () async {
              final id = await pickFolderSheet(context);
              if (id == null) return;
              await state.moveSelected(id == '__none__' ? null : id);
              if (context.mounted) {
                toast(
                  context,
                  'Moved $n document${n == 1 ? '' : 's'}',
                  icon: Icons.check,
                );
              }
            },
          ),
          const SizedBox(width: T.s8),
          RingIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            onTap: () async {
              final ok = await confirmDestructive(
                context,
                title: 'Delete $n document${n == 1 ? '' : 's'}?',
                message: 'This cannot be undone.',
              );
              if (ok) await state.deleteSelected();
            },
          ),
        ],
      ),
    );
  }
}

// ── Document options sheet ───────────────────────────────────────────

void showDocOptions(BuildContext context, ScanDoc doc) {
  final state = context.read<AppState>();
  showAppSheet(
    context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: doc.title,
          subtitle: '${doc.pageCount} pages · ${doc.sizeLabel}',
        ),
        SheetTile(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Share as PDF',
          onTap: () async {
            Navigator.pop(context);
            try {
              await PdfService.shareDoc(doc, state.pdfOptions);
            } catch (e) {
              if (context.mounted) {
                toast(context, 'Could not share: $e');
              }
            }
          },
        ),
        SheetTile(
          icon: Icons.print_outlined,
          title: 'Print / Save as PDF',
          onTap: () async {
            Navigator.pop(context);
            try {
              await PdfService.printDoc(doc, state.pdfOptions);
            } catch (e) {
              if (context.mounted) {
                toast(context, 'Could not print: $e');
              }
            }
          },
        ),
        Divider(color: context.c.hairline, height: T.s16),
        SheetTile(
          icon: doc.favorite ? Icons.star_rounded : Icons.star_border,
          title: doc.favorite ? 'Remove star' : 'Star document',
          onTap: () {
            Navigator.pop(context);
            state.toggleFavorite(doc.id);
          },
        ),
        SheetTile(
          icon: Icons.edit_outlined,
          title: 'Rename',
          onTap: () async {
            Navigator.pop(context);
            final name = await promptText(
              context,
              title: 'Rename document',
              initial: doc.title,
            );
            if (name != null && name.trim().isNotEmpty) {
              await state.renameDoc(doc.id, name.trim());
            }
          },
        ),
        SheetTile(
          icon: Icons.drive_file_move_outlined,
          title: 'Move to folder',
          onTap: () async {
            Navigator.pop(context);
            final id = await pickFolderSheet(context, currentId: doc.folderId);
            if (id == null) return;
            await state.moveDoc(doc.id, id == '__none__' ? null : id);
            if (context.mounted) {
              toast(context, 'Moved', icon: Icons.check);
            }
          },
        ),
        SheetTile(
          icon: Icons.copy_all_outlined,
          title: 'Duplicate',
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
          title: 'Delete',
          tint: context.c.danger,
          onTap: () async {
            Navigator.pop(context);
            final ok = await confirmDestructive(
              context,
              title: 'Delete “${doc.title}”?',
              message:
                  'All ${doc.pageCount} page(s) will be removed. '
                  'This cannot be undone.',
            );
            if (ok) await state.deleteDoc(doc.id);
          },
        ),
        const SizedBox(height: T.s8),
      ],
    ),
  );
}
