import 'dart:typed_data';

import 'ocr_result.dart';

/// Fallback used on platforms without an on-device OCR engine
/// (notably Flutter web). Selected via conditional import, so the
/// ML Kit plugin is never referenced in a web build.
class OcrEngine {
  OcrEngine._();

  static bool get isSupported => false;

  static const String platformNote =
      'Character recognition needs the on-device ML Kit model, which is '
      'only bundled in the Android build. Layout analysis below is '
      'measured from the scan itself and works everywhere.';

  static Future<OcrResult> recognise(Uint8List jpegBytes) async {
    return const OcrResult.unavailable(platformNote);
  }

  static Future<void> dispose() async {}
}
