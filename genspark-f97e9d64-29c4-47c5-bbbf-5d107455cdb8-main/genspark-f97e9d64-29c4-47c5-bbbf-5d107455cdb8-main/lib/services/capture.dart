import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Thin wrapper around the platform image sources so the UI never has to
/// care which platform it is on.
class Capture {
  Capture._();

  static final ImagePicker _picker = ImagePicker();

  /// Single shot from the device camera. On web this opens the browser's
  /// camera/file dialog, which is the correct behaviour there.
  static Future<Uint8List?> fromCamera() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 96,
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (x == null) return null;
      return await x.readAsBytes();
    } catch (e) {
      debugPrint('camera capture failed: $e');
      return null;
    }
  }

  /// Pick one or many images from the gallery / file system.
  static Future<List<Uint8List>> fromGallery({bool multiple = true}) async {
    try {
      if (multiple) {
        final files = await _picker.pickMultiImage(imageQuality: 96);
        final out = <Uint8List>[];
        for (final f in files) {
          out.add(await f.readAsBytes());
        }
        return out;
      }
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 96,
      );
      if (x == null) return [];
      return [await x.readAsBytes()];
    } catch (e) {
      debugPrint('gallery pick failed, trying file picker: $e');
      return fromFiles();
    }
  }

  /// Generic file picker restricted to image types.
  static Future<List<Uint8List>> fromFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
        withData: true,
      );
      if (res == null) return [];
      final out = <Uint8List>[];
      for (final f in res.files) {
        final b = f.bytes;
        if (b != null) out.add(b);
      }
      return out;
    } catch (e) {
      debugPrint('file pick failed: $e');
      return [];
    }
  }
}
