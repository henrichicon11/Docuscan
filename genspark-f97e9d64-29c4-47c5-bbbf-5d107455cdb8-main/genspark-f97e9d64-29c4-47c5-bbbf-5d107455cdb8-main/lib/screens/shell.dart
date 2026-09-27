import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/doc.dart';
import '../services/capture.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'doc_detail.dart';
import 'library.dart';
import 'settings.dart';
import 'tools.dart';

/// Root navigation shell: Library · Tools · Settings, with the scan
/// action living in a persistent bottom bar.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _tabs = [
    (
      icon: Icons.description_outlined,
      active: Icons.description,
      label: 'Docs',
    ),
    (
      icon: Icons.auto_awesome_outlined,
      active: Icons.auto_awesome,
      label: 'Tools',
    ),
    (icon: Icons.tune_outlined, active: Icons.tune, label: 'Settings'),
  ];

  Future<void> _startScan(BuildContext context) async {
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
    if (!context.mounted) return;

    final doc = await state.createDocFromBytes(pages);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocDetailScreen(docId: doc.id, openedFromScan: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;

    if (!state.initialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: c.solid,
                  borderRadius: BorderRadius.circular(T.rMd),
                ),
                child: Icon(
                  Icons.document_scanner_outlined,
                  color: c.onSolid,
                  size: 26,
                ),
              ),
              const SizedBox(height: T.s20),
              Text('DocuScan Pro', style: context.t.titleLarge),
              const SizedBox(height: T.s6),
              Text('Preparing your library…', style: context.t.bodySmall),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              index: _tab,
              children: const [
                LibraryScreen(),
                ToolsScreen(),
                SettingsScreen(),
              ],
            ),
          ),
          if (state.busy)
            BusyOverlay(label: state.busyLabel, progress: state.busyProgress),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        tabs: _tabs,
        index: _tab,
        onTab: (i) => setState(() => _tab = i),
        onScan: () => _startScan(context),
      ),
    );
  }
}

/// Cross-fade between tab bodies while keeping their state alive.
class AnimatedSwitcher extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const AnimatedSwitcher({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: [
        for (int i = 0; i < children.length; i++)
          _KeepAlive(visible: i == index, child: children[i]),
      ],
    );
  }
}

class _KeepAlive extends StatelessWidget {
  final bool visible;
  final Widget child;
  const _KeepAlive({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: T.fast,
        child: child,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<({IconData icon, IconData active, String label})> tabs;
  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onScan;

  const _BottomBar({
    required this.tabs,
    required this.index,
    required this.onTab,
    required this.onScan,
  });

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
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (int i = 0; i < tabs.length; i++)
                Expanded(
                  child: _TabButton(
                    icon: index == i ? tabs[i].active : tabs[i].icon,
                    label: tabs[i].label,
                    active: index == i,
                    onTap: () => onTab(i),
                  ),
                ),
              // Scan action — visually the heaviest element on screen.
              Padding(
                padding: const EdgeInsets.only(left: T.s8, right: T.s16),
                child: _ScanButton(onTap: onScan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21, color: active ? c.ink : c.inkFaint),
          const SizedBox(height: 3),
          Text(
            label,
            style: context.t.labelMedium?.copyWith(
              color: active ? c.ink : c.inkFaint,
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ScanButton({required this.onTap});

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: T.fast,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: T.s16),
          decoration: BoxDecoration(
            color: c.solid,
            borderRadius: BorderRadius.circular(T.rPill),
          ),
          child: Row(
            children: [
              Icon(Icons.center_focus_strong, size: 19, color: c.onSolid),
              const SizedBox(width: T.s6),
              Text(
                'Scan',
                style: context.t.labelLarge?.copyWith(color: c.onSolid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scan source picker ───────────────────────────────────────────────

enum ScanSource { camera, gallery, files }

Future<ScanSource?> showScanSourceSheet(BuildContext context) {
  return showModalBottomSheet<ScanSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(
            title: 'New scan',
            subtitle: 'Pages are auto-cropped and enhanced',
          ),
          SheetTile(
            icon: Icons.photo_camera_outlined,
            title: 'Camera',
            subtitle: 'Capture a document now',
            onTap: () => Navigator.pop(ctx, ScanSource.camera),
          ),
          SheetTile(
            icon: Icons.photo_library_outlined,
            title: 'Photo library',
            subtitle: 'Import one or more images',
            onTap: () => Navigator.pop(ctx, ScanSource.gallery),
          ),
          SheetTile(
            icon: Icons.folder_open_outlined,
            title: 'Browse files',
            subtitle: 'JPG, PNG, WEBP or BMP',
            onTap: () => Navigator.pop(ctx, ScanSource.files),
          ),
          const SizedBox(height: T.s8),
        ],
      ),
    ),
  );
}

/// Shared bottom-sheet chrome with safe-area padding.
class _SheetShell extends StatelessWidget {
  final Widget child;
  const _SheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(T.rXl)),
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// Reusable sheet wrapper for other screens.
Future<R?> showAppSheet<R>(
  BuildContext context, {
  required Widget child,
  bool scroll = false,
}) {
  return showModalBottomSheet<R>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: scroll,
    builder: (_) => _SheetShell(child: child),
  );
}

/// Folder chooser used by "Move to folder".
Future<String?> pickFolderSheet(
  BuildContext context, {
  String? currentId,
}) async {
  final state = context.read<AppState>();
  return showAppSheet<String>(
    context,
    scroll: true,
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, controller) => Column(
        children: [
          const SheetHeader(title: 'Move to folder'),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                SheetTile(
                  icon: Icons.inbox_outlined,
                  title: 'No folder',
                  subtitle: 'Keep in the main library',
                  trailing: currentId == null
                      ? Icon(Icons.check, size: 18, color: ctx.c.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, '__none__'),
                ),
                for (final f in state.folders)
                  SheetTile(
                    icon: Icons.folder_outlined,
                    title: f.name,
                    subtitle: '${state.docCountInFolder(f.id)} documents',
                    trailing: currentId == f.id
                        ? Icon(Icons.check, size: 18, color: ctx.c.accent)
                        : null,
                    onTap: () => Navigator.pop(ctx, f.id),
                  ),
                const SizedBox(height: T.s12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: T.s20),
                  child: GhostButton(
                    label: 'New folder',
                    icon: Icons.add,
                    expand: true,
                    onTap: () async {
                      final name = await promptText(
                        ctx,
                        title: 'New folder',
                        hint: 'Folder name',
                      );
                      if (name == null || name.trim().isEmpty) return;
                      final f = await state.createFolder(name.trim());
                      if (ctx.mounted) Navigator.pop(ctx, f.id);
                    },
                  ),
                ),
                const SizedBox(height: T.s20),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Single-field text prompt with the editorial styling.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  String confirmLabel = 'Save',
}) {
  final ctl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(T.s16, 0, T.s16, T.s12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: TextStyle(color: ctx.c.inkMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: Text(
            confirmLabel,
            style: TextStyle(color: ctx.c.ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Destructive confirmation dialog.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(T.s16, 0, T.s16, T.s12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: ctx.c.inkMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: TextStyle(color: ctx.c.danger, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return res == true;
}

/// Sort picker.
Future<void> showSortSheet(BuildContext context) async {
  final state = context.read<AppState>();
  await showAppSheet(
    context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeader(title: 'Sort documents'),
        for (final s in SortMode.values)
          SheetTile(
            icon: switch (s) {
              SortMode.newest => Icons.schedule,
              SortMode.oldest => Icons.history,
              SortMode.nameAsc => Icons.sort_by_alpha,
              SortMode.nameDesc => Icons.sort_by_alpha,
              SortMode.pages => Icons.layers_outlined,
            },
            title: s.label,
            trailing: state.sort == s
                ? Icon(Icons.check, size: 18, color: context.c.accent)
                : null,
            onTap: () {
              state.setSort(s);
              Navigator.pop(context);
            },
          ),
        const SizedBox(height: T.s8),
      ],
    ),
  );
}
