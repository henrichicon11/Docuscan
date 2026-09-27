import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'shell.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;

    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s20, T.s16, T.s20, T.s32),
      children: [
        const Eyebrow('Settings'),
        const SizedBox(height: T.s6),
        Text('Preferences', style: context.t.displaySmall),
        const SizedBox(height: T.s24),

        // ── Appearance ──────────────────────────────────────
        const Eyebrow('Appearance'),
        const SizedBox(height: T.s12),
        _Card(
          child: Column(
            children: [
              _ThemeRow(
                label: 'Match system',
                icon: Icons.brightness_auto_outlined,
                selected: state.themeMode == 0,
                onTap: () => state.setThemeMode(0),
              ),
              _divider(context),
              _ThemeRow(
                label: 'Light',
                icon: Icons.light_mode_outlined,
                selected: state.themeMode == 1,
                onTap: () => state.setThemeMode(1),
              ),
              _divider(context),
              _ThemeRow(
                label: 'Dark',
                icon: Icons.dark_mode_outlined,
                selected: state.themeMode == 2,
                onTap: () => state.setThemeMode(2),
              ),
            ],
          ),
        ),

        const SizedBox(height: T.s24),

        // ── Library ─────────────────────────────────────────
        const Eyebrow('Library'),
        const SizedBox(height: T.s12),
        _Card(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.description_outlined,
                label: 'Documents',
                value: '${state.allDocs.length}',
              ),
              _divider(context),
              _InfoRow(
                icon: Icons.layers_outlined,
                label: 'Total pages',
                value: '${state.totalPages}',
              ),
              _divider(context),
              _InfoRow(
                icon: Icons.sd_storage_outlined,
                label: 'Storage used',
                value: state.librarySize,
              ),
              _divider(context),
              _InfoRow(
                icon: Icons.folder_outlined,
                label: 'Folders',
                value: '${state.folders.length}',
              ),
            ],
          ),
        ),

        const SizedBox(height: T.s12),
        _Card(
          child: Column(
            children: [
              SheetTile(
                icon: Icons.view_agenda_outlined,
                title: 'Default view',
                subtitle: state.gridView ? 'Grid' : 'List',
                trailing: Switch(
                  value: state.gridView,
                  onChanged: (_) => state.toggleGrid(),
                ),
              ),
              _divider(context),
              SheetTile(
                icon: Icons.swap_vert,
                title: 'Sort order',
                subtitle: state.sort.label,
                onTap: () => showSortSheet(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: T.s24),

        // ── Data ────────────────────────────────────────────
        const Eyebrow('Data'),
        const SizedBox(height: T.s12),
        _Card(
          child: Column(
            children: [
              SheetTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear all documents',
                subtitle: 'Removes every scan from this device',
                tint: c.danger,
                onTap: state.allDocs.isEmpty
                    ? null
                    : () async {
                        final ok = await confirmDestructive(
                          context,
                          title: 'Delete everything?',
                          message:
                              'All ${state.allDocs.length} documents '
                              'and ${state.totalPages} pages will be '
                              'permanently removed.',
                          confirmLabel: 'Delete all',
                        );
                        if (!ok) return;
                        for (final d in state.allDocs.toList()) {
                          await state.deleteDoc(d.id);
                        }
                        if (context.mounted) {
                          toast(context, 'Library cleared', icon: Icons.check);
                        }
                      },
              ),
            ],
          ),
        ),

        const SizedBox(height: T.s24),

        // ── How it works ────────────────────────────────────
        const Eyebrow('How scanning works'),
        const SizedBox(height: T.s12),
        Container(
          padding: const EdgeInsets.all(T.s16),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(T.rMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Step(
                n: '1',
                title: 'Edge detection',
                body:
                    'A Hough-transform line detector finds the four '
                    'page borders and their intersections.',
              ),
              _Step(
                n: '2',
                title: 'Perspective correction',
                body:
                    'A homography is solved from those corners and the '
                    'page is bilinearly re-sampled flat.',
              ),
              _Step(
                n: '3',
                title: 'Illumination flattening',
                body:
                    'The image is divided by its own blurred luma to '
                    'erase shadows and vignetting.',
              ),
              _Step(
                n: '4',
                title: 'Enhancement',
                body:
                    'Histogram auto-levels whiten the paper; B&W mode '
                    'uses Bradley adaptive thresholding.',
                last: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: T.s24),

        // ── About ───────────────────────────────────────────
        const Eyebrow('About'),
        const SizedBox(height: T.s12),
        _Card(
          child: Column(
            children: [
              const _InfoRow(
                icon: Icons.info_outline,
                label: 'Version',
                value: '1.0.0',
              ),
              _divider(context),
              _InfoRow(
                icon: Icons.devices_outlined,
                label: 'Platform',
                value: kIsWeb ? 'Web preview' : 'Android',
              ),
              _divider(context),
              const _InfoRow(
                icon: Icons.lock_outline,
                label: 'Privacy',
                value: 'On-device only',
              ),
            ],
          ),
        ),

        const SizedBox(height: T.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s4),
          child: Text(
            'Every scan, filter and PDF is produced entirely on this '
            'device. Nothing is uploaded, and there is no account.',
            style: context.t.bodySmall?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: T.s32),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 22,
                color: c.inkFaint,
              ),
              const SizedBox(height: T.s8),
              Text(
                'DocuScan Pro',
                style: context.t.titleSmall?.copyWith(color: c.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(color: context.c.hairline, height: 1);
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(T.rMd),
        border: Border.all(color: c.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(T.rMd),
        child: child,
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s16, vertical: T.s14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: c.ink),
            const SizedBox(width: T.s12),
            Expanded(child: Text(label, style: context.t.bodyLarge)),
            if (selected) Icon(Icons.check, size: 18, color: c.accent),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s16, vertical: T.s14),
      child: Row(
        children: [
          Icon(icon, size: 19, color: c.inkMuted),
          const SizedBox(width: T.s12),
          Expanded(child: Text(label, style: context.t.bodyLarge)),
          Text(value, style: context.t.titleSmall?.copyWith(color: c.inkMuted)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  final bool last;

  const _Step({
    required this.n,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : T.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.solid, shape: BoxShape.circle),
            child: Text(
              n,
              style: context.t.labelMedium?.copyWith(
                color: c.onSolid,
                fontSize: 10.5,
              ),
            ),
          ),
          const SizedBox(width: T.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: context.t.bodySmall?.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
