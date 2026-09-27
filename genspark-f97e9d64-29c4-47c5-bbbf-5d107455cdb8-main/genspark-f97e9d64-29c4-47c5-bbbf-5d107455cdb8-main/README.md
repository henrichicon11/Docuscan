# DocuScan Pro

A professional document scanner and PDF toolkit built with Flutter. Everything
(edge detection, perspective correction, enhancement, OCR, PDF export) runs
**on-device** — nothing is uploaded and there is no account.

## Features

- **Capture & import** – camera, multi-image gallery import, or file picker (JPG/PNG/WEBP/BMP).
- **Automatic edge detection** – Sobel + Hough-transform line detection finds the page quad.
- **Perspective correction** – homography solved from the corners, bilinear resampling.
- **Enhancement filters** – Original, Magic Color, Lighten, Grayscale, B&W (Bradley adaptive threshold), Ink Boost; plus brightness / contrast / sharpen and rotation.
- **Manual crop editor** with draggable corners and magnifier loupe.
- **Signatures & stamps** – draw a signature and place/scale it on a page.
- **OCR** – Google ML Kit on Android/iOS (searchable from the library); layout analysis fallback on web.
- **Library** – folders, favourites, search (title + OCR text), sort, list/grid view, multi-select.
- **Document tools** – merge, split, duplicate, reorder / duplicate / delete pages, apply a filter to all pages.
- **Export** – PDF with page size (Auto/A4/Letter/Legal/A5), quality, watermark and page numbers; print, share PDF or share page images.
- Light / dark / system themes, persisted preferences (Hive — files on Android, IndexedDB on web).

## Project structure

```
lib/
  main.dart               App entry, theming, provider
  models/doc.dart         ScanDoc, ScanPage, Folder, enums
  state/app_state.dart    ChangeNotifier with all library / page operations
  services/
    capture.dart          Camera / gallery / file import
    cv.dart               Edge detection, Hough lines, homography
    image_pipeline.dart   Crop, warp, filters, adjustments, synthetic demo pages
    pdf_service.dart      PDF build / print / share
    storage.dart          Hive persistence
    text_analysis.dart    Layout analysis (works everywhere)
    ocr/                  Conditional import: ML Kit (mobile) / stub (web)
  screens/                Shell, library, doc detail, page editor/viewer,
                          signature, tools, settings, export sheet
  widgets/                Design kit, crop editor, signature pad
  theme/tokens.dart       Design tokens and ThemeData
test/                     Unit tests for CV, pipeline, text analysis and PDF
```

## Getting started

Requires Flutter 3.35.x (Dart ^3.9.2).

```bash
flutter pub get
flutter analyze
flutter test

# Android
flutter run            # or: flutter build apk --release

# Web preview
flutter build web --release
python3 serve.py       # serves build/web on http://localhost:5060
```

> `google_mlkit_text_recognition` is pinned to 0.16.0, the newest release that
> supports Flutter 3.35.x. On web the OCR plugin is never linked (conditional
> import), so character recognition is Android/iOS only.

## Release signing

`android/app/build.gradle.kts` currently signs release builds with the debug
key so `flutter run --release` works. Add your own signing config before
publishing to the Play Store.
