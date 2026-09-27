import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'ocr_result.dart';

/// Real on-device OCR backed by Google ML Kit. Compiled only into the
/// Android build (selected by conditional import from `ocr.dart`).
class OcrEngine {
  OcrEngine._();

  /// `dart.library.io` is also true on desktop and in unit tests, but the
  /// ML Kit plugin only ships Android and iOS implementations — so gate on
  /// the actual platform rather than assuming.
  static bool get isSupported {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  static const String platformNote =
      'Text is recognised on-device with Google ML Kit. Nothing is '
      'uploaded.';

  static TextRecognizer? _recognizer;

  static TextRecognizer get _engine =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Recognise text in a JPEG page.
  ///
  /// ML Kit's byte-buffer API needs exact rotation/format metadata, which
  /// is easy to get wrong after our own processing pipeline. Writing a
  /// temp file and using `fromFilePath` lets ML Kit decode the image
  /// itself, which is both simpler and more reliable.
  static Future<OcrResult> recognise(Uint8List jpegBytes) async {
    if (!isSupported) {
      return const OcrResult.unavailable(
        'On-device text recognition is only available on Android and iOS.',
      );
    }
    File? temp;
    try {
      // Page dimensions are needed to normalise the bounding boxes.
      final decoded = img.decodeImage(jpegBytes);
      final pageW = (decoded?.width ?? 0).toDouble();
      final pageH = (decoded?.height ?? 0).toDouble();

      final dir = await getTemporaryDirectory();
      temp = File(
        '${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await temp.writeAsBytes(jpegBytes, flush: true);

      final input = InputImage.fromFilePath(temp.path);
      final recognised = await _engine.processImage(input);

      double nx(num v) => pageW <= 0 ? 0 : (v / pageW).clamp(0.0, 1.0);
      double ny(num v) => pageH <= 0 ? 0 : (v / pageH).clamp(0.0, 1.0);

      final blocks = <OcrBlock>[];
      for (final b in recognised.blocks) {
        final lines = <OcrLine>[];
        for (final l in b.lines) {
          final r = l.boundingBox;
          lines.add(OcrLine(
            text: l.text,
            left: nx(r.left),
            top: ny(r.top),
            right: nx(r.right),
            bottom: ny(r.bottom),
          ));
        }
        blocks.add(OcrBlock(text: b.text, lines: lines));
      }

      return OcrResult(
        text: recognised.text,
        blocks: blocks,
        recognised: true,
      );
    } catch (e) {
      debugPrint('ML Kit OCR failed: $e');
      return OcrResult.unavailable(
        'Text recognition could not run on this page ($e).',
      );
    } finally {
      // Never leave scan data lying around in the temp directory.
      try {
        if (temp != null && await temp.exists()) {
          await temp.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
