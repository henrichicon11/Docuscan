/// Shared OCR data types used by both the real (Android/ML Kit) and the
/// stub (web) implementations.

/// One recognised line of text with its position on the page.
class OcrLine {
  final String text;

  /// Bounding box in normalised page coordinates (0..1).
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
}

/// One recognised block (paragraph) of text.
class OcrBlock {
  final String text;
  final List<OcrLine> lines;

  const OcrBlock({required this.text, required this.lines});
}

/// Full recognition result for a single page.
class OcrResult {
  /// Complete recognised text, blocks separated by blank lines.
  final String text;
  final List<OcrBlock> blocks;

  /// True when genuine character recognition ran. False means the
  /// platform has no OCR engine and only layout metrics are available.
  final bool recognised;

  /// Present when [recognised] is false, explaining why.
  final String? unavailableReason;

  const OcrResult({
    required this.text,
    required this.blocks,
    required this.recognised,
    this.unavailableReason,
  });

  const OcrResult.unavailable(String reason)
      : text = '',
        blocks = const [],
        recognised = false,
        unavailableReason = reason;

  bool get isEmpty => text.trim().isEmpty;

  int get lineCount =>
      blocks.fold<int>(0, (sum, b) => sum + b.lines.length);

  int get wordCount => text
      .split(RegExp(r'\s+'))
      .where((w) => w.trim().isNotEmpty)
      .length;

  int get charCount => text.replaceAll(RegExp(r'\s'), '').length;

  /// Rough reading time at 220 wpm.
  String get readingTime {
    final mins = wordCount / 220.0;
    if (wordCount == 0) return '—';
    if (mins < 1) return 'under a minute';
    return '${mins.ceil()} min read';
  }
}
