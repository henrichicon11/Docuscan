import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Small uppercase section label.
class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: context.t.labelSmall);
}

/// The primary solid action button (near-black in light, near-white in dark).
class SolidButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final bool loading;
  final Color? color;
  final Color? textColor;

  const SolidButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.expand = false,
    this.loading = false,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = color ?? c.solid;
    final fg = textColor ?? c.onSolid;
    final enabled = onTap != null && !loading;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(T.rPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rPill),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap!.call();
                }
              : null,
          child: Container(
            height: 50,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: expand ? 0 : T.s24),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (icon != null)
                  Icon(icon, size: 19, color: fg),
                if (loading || icon != null) const SizedBox(width: T.s8),
                Text(label, style: context.t.labelLarge?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline-outlined secondary button.
class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final Color? tint;

  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.expand = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = tint ?? c.ink;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rPill),
          side: BorderSide(color: c.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rPill),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!.call();
                },
          child: Container(
            height: 50,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: expand ? 0 : T.s20),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, size: 19, color: fg),
                if (icon != null) const SizedBox(width: T.s8),
                Text(label, style: context.t.labelLarge?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular icon button with a hairline ring — used in toolbars.
class RingIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;
  final double size;

  const RingIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.active = false,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = Material(
      color: active ? c.solid : Colors.transparent,
      shape: CircleBorder(
        side: BorderSide(color: active ? c.solid : c.hairline),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!.call();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.45,
            color: active ? c.onSolid : c.ink,
          ),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Text-only filter tab with an animated underline.
class UnderlineTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  const UnderlineTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AnimatedDefaultTextStyle(
                  duration: T.fast,
                  style: (context.t.titleMedium ?? const TextStyle()).copyWith(
                    color: active ? c.ink : c.inkFaint,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                  child: Text(label),
                ),
                if (count != null) ...[
                  const SizedBox(width: T.s6),
                  Text(
                    '$count',
                    style: context.t.bodySmall?.copyWith(
                      color: active ? c.accent : c.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: T.s6),
            AnimatedContainer(
              duration: T.med,
              curve: T.ease,
              height: 2,
              width: active ? 100 : 0,
              constraints: const BoxConstraints(maxWidth: 100),
              decoration: BoxDecoration(
                color: c.ink,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a scanned page as convincing paper: white sheet, crisp corner
/// radius, layered soft shadow, hairline border.
class PaperThumb extends StatelessWidget {
  final Uint8List bytes;
  final double radius;
  final BoxFit fit;
  final bool shadow;
  final double? aspectRatio;

  const PaperThumb({
    super.key,
    required this.bytes,
    this.radius = T.rSm,
    this.fit = BoxFit.cover,
    this.shadow = true,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: context.isDark ? const Color(0xFF202226) : Colors.white,
        child: Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Container(
            color: c.surfaceAlt,
            child: Icon(
              Icons.broken_image_outlined,
              color: c.inkFaint,
              size: 22,
            ),
          ),
        ),
      ),
    );

    if (aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio!, child: image);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.hairline),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDark ? 0.45 : 0.07,
                  ),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDark ? 0.3 : 0.04,
                  ),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: image,
    );
  }
}

/// Tiny pill used for page counts and tags.
class MetaPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? bg;
  final Color? fg;

  const MetaPill({super.key, required this.text, this.icon, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.s8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? c.surfaceAlt,
        borderRadius: BorderRadius.circular(T.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg ?? c.inkMuted),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: context.t.labelMedium?.copyWith(
              color: fg ?? c.inkMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent empty state.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(T.s32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 27, color: c.inkFaint),
            ),
            const SizedBox(height: T.s20),
            Text(
              title,
              style: context.t.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: T.s8),
            Text(
              message,
              style: context.t.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: T.s24), action!],
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet grabber + title row.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        const SizedBox(height: T.s12),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: c.hairline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: T.s20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.t.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: context.t.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        const SizedBox(height: T.s16),
      ],
    );
  }
}

/// Row inside an options sheet.
class SheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? tint;
  final Widget? trailing;

  const SheetTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.tint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = tint ?? c.ink;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!.call();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s20, vertical: T.s12),
        child: Row(
          children: [
            SizedBox(width: 26, child: Icon(icon, size: 20, color: col)),
            const SizedBox(width: T.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.t.titleMedium?.copyWith(color: col),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!, style: context.t.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Full-screen blocking progress overlay.
class BusyOverlay extends StatelessWidget {
  final String label;
  final double? progress;
  const BusyOverlay({super.key, required this.label, this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: c.scrim,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: T.s24,
              vertical: T.s20,
            ),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(T.rLg),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: progress,
                    color: c.ink,
                    backgroundColor: c.hairline,
                  ),
                ),
                const SizedBox(height: T.s16),
                Text(
                  label,
                  style: context.t.titleSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide + fade entrance used for list items.
class Reveal extends StatefulWidget {
  final int index;
  final Widget child;
  const Reveal({super.key, required this.index, required this.child});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: T.slow,
  );

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 34 * widget.index.clamp(0, 10));
    Future.delayed(delay, () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _ctl, curve: T.ease);
    return AnimatedBuilder(
      animation: curve,
      builder: (_, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * 14),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

void toast(BuildContext context, String message, {IconData? icon}) {
  final c = Theme.of(context).extension<AppColors>() ?? AppColors.light;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2200),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: c.onSolid),
              const SizedBox(width: T.s8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
