/// Platform-dispatching OCR entry point.
///
/// `dart.library.io` is available on mobile/desktop but not on web, so the
/// web build compiles `ocr_stub.dart` and never links the ML Kit plugin.
/// Everything else gets the real Google ML Kit engine.
library;

export 'ocr_result.dart';
export 'ocr_stub.dart' if (dart.library.io) 'ocr_mlkit.dart';
