import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'cv.dart';
import 'image_pipeline.dart';

/// One detected line of text, in normalised page coordinates.
class TextLine {
  final double top;
  final double bottom;
  final double left;
  final double right;
  final int wordCount;

  const TextLine({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.wordCount,
  });

  double get height => bottom - top;
}

class TextLayout {
  final List<TextLine> lines;
  final double inkCoverage; // fraction of page that is ink
  final double skewDegrees; // estimated page skew
  final int blockCount;

  const TextLayout({
    required this.lines,
    required this.inkCoverage,
    required this.skewDegrees,
    required this.blockCount,
  });

  int get lineCount => lines.length;
  int get wordEstimate => lines.fold<int>(0, (s, l) => s + l.wordCount);

  /// Very rough reading-time estimate at 220 wpm.
  String get readingTime {
    final mins = wordEstimate / 220.0;
    if (mins < 1) return 'under a minute';
    return '${mins.ceil()} min read';
  }

  bool get isEmpty => lines.isEmpty;
}

/// Document layout analysis: binarise, find text rows by horizontal
/// projection profile, then split each row into words by gaps.
///
/// This is real measurement of the page — not character recognition.
class TextAnalysis {
  TextAnalysis._();

  static TextLayout analyze(Uint8List jpegBytes) {
    final im = ImagePipeline.decode(jpegBytes);
    if (im == null) {
      return const TextLayout(
        lines: [],
        inkCoverage: 0,
        skewDegrees: 0,
        blockCount: 0,
      );
    }

    // Work at a modest width — enough to resolve text rows.
    final small = img.copyResize(
      im,
      width: math.min(900, im.width),
      interpolation: img.Interpolation.average,
    );
    final gray = ImagePipeline.toGray(small);
    final bin = Cv.adaptiveThreshold(gray, windowFrac: 0.08, t: 0.16);
    final w = bin.w, h = bin.h;

    // Ink coverage
    int inkPixels = 0;
    for (final v in bin.data) {
      if (v == 0) inkPixels++;
    }
    final coverage = inkPixels / (w * h);

    // Horizontal projection: count ink pixels per row.
    final proj = Int32List(h);
    for (int y = 0; y < h; y++) {
      int c = 0;
      final row = y * w;
      for (int x = 0; x < w; x++) {
        if (bin.data[row + x] == 0) c++;
      }
      proj[y] = c;
    }

    // Adaptive row threshold: a fraction of the median non-zero row.
    final nonZero = proj.where((v) => v > 0).toList()..sort();
    if (nonZero.isEmpty) {
      return TextLayout(
        lines: const [],
        inkCoverage: coverage,
        skewDegrees: 0,
        blockCount: 0,
      );
    }
    final median = nonZero[nonZero.length ~/ 2];
    final rowThr = math.max(2, (median * 0.28).round());

    // Group consecutive rows above threshold into bands.
    final bands = <List<int>>[];
    int? start;
    for (int y = 0; y < h; y++) {
      final on = proj[y] >= rowThr;
      if (on && start == null) {
        start = y;
      } else if (!on && start != null) {
        if (y - start >= 3) bands.add([start, y - 1]);
        start = null;
      }
    }
    if (start != null && h - start >= 3) bands.add([start, h - 1]);

    // For each band, measure extent and split into words by vertical gaps.
    final lines = <TextLine>[];
    for (final b in bands) {
      final y0 = b[0], y1 = b[1];
      final colHas = List<bool>.filled(w, false);
      for (int y = y0; y <= y1; y++) {
        final row = y * w;
        for (int x = 0; x < w; x++) {
          if (bin.data[row + x] == 0) colHas[x] = true;
        }
      }
      int left = -1, right = -1;
      for (int x = 0; x < w; x++) {
        if (colHas[x]) {
          left = x;
          break;
        }
      }
      for (int x = w - 1; x >= 0; x--) {
        if (colHas[x]) {
          right = x;
          break;
        }
      }
      if (left < 0 || right <= left) continue;

      // Word segmentation: a gap wider than ~55% of band height splits words.
      final bandH = (y1 - y0 + 1);
      final gapThr = math.max(3, (bandH * 0.55).round());
      int words = 0;
      int gap = 0;
      bool inWord = false;
      for (int x = left; x <= right; x++) {
        if (colHas[x]) {
          if (!inWord) {
            words++;
            inWord = true;
          }
          gap = 0;
        } else {
          gap++;
          if (gap >= gapThr) inWord = false;
        }
      }

      // Reject bands that are almost certainly rules/borders or noise.
      final widthFrac = (right - left) / w;
      if (bandH <= 2 && widthFrac > 0.5) continue; // horizontal rule
      if (words == 0) continue;

      lines.add(
        TextLine(
          top: y0 / h,
          bottom: y1 / h,
          left: left / w,
          right: right / w,
          wordCount: words,
        ),
      );
    }

    // Block count: consecutive lines with small vertical spacing = one block.
    int blocks = 0;
    double? prevBottom;
    double avgH = lines.isEmpty
        ? 0
        : lines.map((l) => l.height).reduce((a, b) => a + b) / lines.length;
    for (final l in lines) {
      if (prevBottom == null || (l.top - prevBottom) > avgH * 1.9) {
        blocks++;
      }
      prevBottom = l.bottom;
    }

    // Skew estimate from the dominant near-horizontal Hough line.
    final skew = _estimateSkew(gray);

    return TextLayout(
      lines: lines,
      inkCoverage: coverage,
      skewDegrees: skew,
      blockCount: blocks,
    );
  }

  /// Estimate page skew in degrees by testing shear angles and picking the
  /// one that maximises projection-profile variance (classic technique).
  static double _estimateSkew(Gray gray) {
    final small = Cv.resize(gray, 300);
    final bin = Cv.adaptiveThreshold(small, windowFrac: 0.12, t: 0.16);
    final w = bin.w, h = bin.h;
    double bestScore = -1;
    double bestAngle = 0;

    for (double a = -6; a <= 6.01; a += 0.5) {
      final rad = a * math.pi / 180;
      final tan = math.tan(rad);
      final proj = Int32List(h);
      for (int y = 0; y < h; y++) {
        final row = y * w;
        for (int x = 0; x < w; x++) {
          if (bin.data[row + x] != 0) continue;
          final ny = (y + (x - w / 2) * tan).round();
          if (ny >= 0 && ny < h) proj[ny]++;
        }
      }
      // Variance of the profile — sharper rows => higher variance.
      double mean = 0;
      for (final v in proj) {
        mean += v;
      }
      mean /= h;
      double varSum = 0;
      for (final v in proj) {
        final d = v - mean;
        varSum += d * d;
      }
      if (varSum > bestScore) {
        bestScore = varSum;
        bestAngle = a;
      }
    }
    return bestAngle;
  }

  /// Human-readable summary used in the analysis sheet.
  static String summarize(TextLayout l) {
    if (l.isEmpty) return 'No text structure detected on this page.';
    final b = StringBuffer();
    b.writeln(
      '${l.lineCount} text lines across ${l.blockCount} '
      'block${l.blockCount == 1 ? '' : 's'}.',
    );
    b.writeln('~${l.wordEstimate} words · ${l.readingTime}.');
    b.writeln('Ink coverage ${(l.inkCoverage * 100).toStringAsFixed(1)}%.');
    final s = l.skewDegrees;
    if (s.abs() < 0.4) {
      b.writeln('Page is square to the frame (no skew correction needed).');
    } else {
      b.writeln(
        'Estimated skew ${s.toStringAsFixed(1)}° — '
        'use Auto-straighten to correct.',
      );
    }
    return b.toString().trim();
  }
}
