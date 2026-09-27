import 'package:flutter/material.dart';

/// Design tokens for DocuScan Pro — "Editorial Minimal".
/// The paper is the hero; the chrome disappears.
class T {
  T._();

  // ── Spacing (4pt grid) ───────────────────────────────
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  // ── Radii ────────────────────────────────────────────
  static const double rSm = 8;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rXl = 28;
  static const double rPill = 999;

  // ── Motion ───────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration med = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve emphasis = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// Semantic palette, resolved per brightness.
class AppColors extends ThemeExtension<AppColors> {
  final Color canvas; // page background
  final Color surface; // cards
  final Color surfaceAlt; // subtle fills
  final Color ink; // primary text
  final Color inkMuted; // secondary text
  final Color inkFaint; // tertiary / meta
  final Color hairline; // 1px dividers & borders
  final Color accent; // amber highlight
  final Color accentSoft; // amber tint fill
  final Color solid; // solid button bg (near-black / near-white)
  final Color onSolid; // text on solid
  final Color success;
  final Color danger;
  final Color scrim;

  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.hairline,
    required this.accent,
    required this.accentSoft,
    required this.solid,
    required this.onSolid,
    required this.success,
    required this.danger,
    required this.scrim,
  });

  static const light = AppColors(
    canvas: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF2F2EE),
    ink: Color(0xFF111214),
    inkMuted: Color(0xFF62666D),
    inkFaint: Color(0xFF9AA0A6),
    hairline: Color(0xFFE5E4DF),
    accent: Color(0xFFCE8A2B),
    accentSoft: Color(0xFFFBF1DF),
    solid: Color(0xFF121316),
    onSolid: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D5B),
    danger: Color(0xFFC0392B),
    scrim: Color(0x99000000),
  );

  static const dark = AppColors(
    canvas: Color(0xFF0E0F11),
    surface: Color(0xFF17181B),
    surfaceAlt: Color(0xFF1F2125),
    ink: Color(0xFFF3F3F1),
    inkMuted: Color(0xFF9BA1A8),
    inkFaint: Color(0xFF6C7278),
    hairline: Color(0xFF272A2F),
    accent: Color(0xFFF0B354),
    accentSoft: Color(0xFF2A2318),
    solid: Color(0xFFF3F3F1),
    onSolid: Color(0xFF101114),
    success: Color(0xFF4CAF88),
    danger: Color(0xFFE1685A),
    scrim: Color(0xB3000000),
  );

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? hairline,
    Color? accent,
    Color? accentSoft,
    Color? solid,
    Color? onSolid,
    Color? success,
    Color? danger,
    Color? scrim,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      hairline: hairline ?? this.hairline,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      solid: solid ?? this.solid,
      onSolid: onSolid ?? this.onSolid,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      solid: Color.lerp(solid, other.solid, t)!,
      onSolid: Color.lerp(onSolid, other.onSolid, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>() ?? AppColors.light;
  TextTheme get t => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static ThemeData build(Brightness b) {
    final c = b == Brightness.dark ? AppColors.dark : AppColors.light;

    TextStyle base(
      double size,
      FontWeight w, {
      double? ls,
      double? h,
      Color? col,
    }) {
      return TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: w,
        letterSpacing: ls,
        height: h,
        color: col ?? c.ink,
      );
    }

    final text = TextTheme(
      // Display / big numbers
      displaySmall: base(34, FontWeight.w700, ls: -1.0, h: 1.08),
      headlineLarge: base(28, FontWeight.w700, ls: -0.7, h: 1.14),
      headlineMedium: base(23, FontWeight.w600, ls: -0.5, h: 1.2),
      titleLarge: base(18, FontWeight.w600, ls: -0.3, h: 1.25),
      titleMedium: base(15.5, FontWeight.w600, ls: -0.15, h: 1.3),
      titleSmall: base(14, FontWeight.w600, ls: -0.1, h: 1.3),
      bodyLarge: base(15.5, FontWeight.w400, h: 1.45),
      bodyMedium: base(14, FontWeight.w400, h: 1.45, col: c.inkMuted),
      bodySmall: base(12.5, FontWeight.w400, h: 1.4, col: c.inkFaint),
      labelLarge: base(14.5, FontWeight.w600, ls: 0.0),
      labelMedium: base(12.5, FontWeight.w600, ls: 0.2),
      // Micro uppercase eyebrow
      labelSmall: base(10.5, FontWeight.w600, ls: 1.4, col: c.inkFaint),
    );

    final scheme = ColorScheme(
      brightness: b,
      primary: c.ink,
      onPrimary: c.canvas,
      secondary: c.accent,
      onSecondary: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      error: c.danger,
      onError: Colors.white,
      surfaceContainerHighest: c.surfaceAlt,
      outline: c.hairline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      colorScheme: scheme,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: c.ink, size: 22),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rMd),
          side: BorderSide(color: c.hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rLg),
          side: BorderSide(color: c.hairline),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge?.copyWith(color: c.inkMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(T.rXl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.solid,
        contentTextStyle: text.bodyLarge?.copyWith(color: c.onSolid),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(T.rMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: text.bodyLarge?.copyWith(color: c.inkFaint),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: T.s16,
          vertical: T.s12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rMd),
          borderSide: BorderSide(color: c.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rMd),
          borderSide: BorderSide(color: c.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rMd),
          borderSide: BorderSide(color: c.accent, width: 1.4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.25),
        selectionHandleColor: c.accent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.ink,
        inactiveTrackColor: c.hairline,
        thumbColor: c.ink,
        overlayColor: c.ink.withValues(alpha: 0.08),
        trackHeight: 2,
      ),
      switchTheme: SwitchThemeData(
        // The OFF thumb must contrast against the OFF track, otherwise the
        // control reads as a blank pill on a near-white surface.
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onSolid : c.inkFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.solid : c.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.solid : c.hairline,
        ),
      ),
      iconTheme: IconThemeData(color: c.ink, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        textColor: c.ink,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
      ),
      extensions: <ThemeExtension<dynamic>>[c],
    );
  }
}
