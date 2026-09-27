import 'dart:typed_data';

import 'package:docuscan_pro/models/doc.dart';
import 'package:docuscan_pro/services/cv.dart';
import 'package:docuscan_pro/services/image_pipeline.dart';
import 'package:docuscan_pro/services/text_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Homography', () {
    test('identity mapping round-trips a point', () {
      final h = Homography.fromCorners(
        const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ],
        const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ],
      );
      expect(h, isNotNull);
      final p = h!.map(50, 50);
      expect(p.dx, closeTo(50, 0.001));
      expect(p.dy, closeTo(50, 0.001));
    });

    test('maps a known perspective correspondence', () {
      // Destination square -> a trapezoid in the source.
      final h = Homography.fromCorners(
        const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ],
        const [
          Offset(2, 3),
          Offset(18, 1),
          Offset(20, 15),
          Offset(1, 12),
        ],
      );
      expect(h, isNotNull);
      // Corners must land exactly on their correspondences.
      final tl = h!.map(0, 0);
      expect(tl.dx, closeTo(2, 0.01));
      expect(tl.dy, closeTo(3, 0.01));
      final br = h.map(10, 10);
      expect(br.dx, closeTo(20, 0.01));
      expect(br.dy, closeTo(15, 0.01));
    });

    test('returns null for degenerate (collinear) input', () {
      final h = Homography.fromCorners(
        const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(2, 2),
          Offset(3, 3),
        ],
        const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(2, 2),
          Offset(3, 3),
        ],
      );
      expect(h, isNull);
    });
  });

  group('Cv primitives', () {
    test('otsu separates a clean bimodal histogram', () {
      final g = Gray(10, 10);
      for (int i = 0; i < g.data.length; i++) {
        g.data[i] = i < 50 ? 20 : 230;
      }
      final t = Cv.otsu(g);
      // Otsu returns the inclusive top of the dark class, so the split
      // is `v <= t` (dark) vs `v > t` (light).
      expect(t, greaterThanOrEqualTo(20));
      expect(t, lessThan(230));
      final dark = g.data.where((v) => v <= t).length;
      final light = g.data.where((v) => v > t).length;
      expect(dark, 50);
      expect(light, 50);
    });

    test('box blur preserves a flat field', () {
      final g = Gray(16, 16);
      for (int i = 0; i < g.data.length; i++) {
        g.data[i] = 128;
      }
      final b = Cv.boxBlur(g, 2);
      expect(b.data.every((v) => v == 128), isTrue);
    });

    test('adaptive threshold yields a pure binary image', () {
      final g = Gray(32, 32);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          g.set(x, y, x < 16 ? 40 : 220);
        }
      }
      final bin = Cv.adaptiveThreshold(g);
      expect(bin.data.every((v) => v == 0 || v == 255), isTrue);
    });

    test('resize reduces dimensions and keeps aspect', () {
      final g = Gray(200, 100);
      final r = Cv.resize(g, 50);
      expect(r.w, 50);
      expect(r.h, 25);
    });
  });

  group('Image pipeline', () {
    test('synthetic page decodes to a valid image', () {
      final bytes = ImagePipeline.syntheticPage(seed: 1, kind: 'notes');
      final im = ImagePipeline.decode(bytes);
      expect(im, isNotNull);
      expect(im!.width, greaterThan(0));
      expect(im.height, greaterThan(im.width)); // portrait page
    });

    test('magic filter produces output of the same size', () {
      final bytes = ImagePipeline.syntheticPage(
          seed: 7, kind: 'receipt', width: 240);
      final out = ImagePipeline.process(
          ProcessRequest(bytes: bytes, filter: ScanFilter.magic));
      final a = ImagePipeline.decode(bytes)!;
      final b = ImagePipeline.decode(out)!;
      expect(b.width, a.width);
      expect(b.height, a.height);
    });

    test('black & white filter yields near-binary pixels', () {
      final bytes = ImagePipeline.syntheticPage(
          seed: 3, kind: 'notes', width: 200);
      final out = ImagePipeline.process(
          ProcessRequest(bytes: bytes, filter: ScanFilter.bw));
      final im = ImagePipeline.decode(out)!;
      // JPEG introduces ringing, so allow a tolerance band.
      int extremes = 0;
      int sampled = 0;
      for (int y = 0; y < im.height; y += 5) {
        for (int x = 0; x < im.width; x += 5) {
          final p = im.getPixel(x, y);
          sampled++;
          if (p.r < 60 || p.r > 195) extremes++;
        }
      }
      expect(extremes / sampled, greaterThan(0.85));
    });

    test('rotation swaps width and height', () {
      final bytes = ImagePipeline.syntheticPage(
          seed: 5, kind: 'id', width: 200);
      final a = ImagePipeline.decode(bytes)!;
      final out = ImagePipeline.process(ProcessRequest(
          bytes: bytes, filter: ScanFilter.original, rotation: 1));
      final b = ImagePipeline.decode(out)!;
      expect(b.width, a.height);
      expect(b.height, a.width);
    });

    test('thumbnail shrinks the long edge', () {
      final bytes = ImagePipeline.syntheticPage(seed: 9, kind: 'notes');
      final thumb = ImagePipeline.thumbnail(bytes, width: 80);
      final im = ImagePipeline.decode(thumb)!;
      expect(im.width, 80);
    });

    test('export honours the max edge constraint', () {
      final bytes = ImagePipeline.syntheticPage(seed: 11, kind: 'notes');
      final out = ImagePipeline.forExport(bytes, 300, 85);
      final im = ImagePipeline.decode(out)!;
      expect(im.width <= 300 && im.height <= 300, isTrue);
    });
  });

  group('Text analysis', () {
    test('detects text lines on a synthetic document', () {
      final bytes = ImagePipeline.syntheticPage(
          seed: 21, kind: 'notes', width: 500);
      final layout = TextAnalysis.analyze(bytes);
      expect(layout.lineCount, greaterThan(3));
      expect(layout.wordEstimate, greaterThan(3));
      expect(layout.inkCoverage, greaterThan(0));
      expect(layout.inkCoverage, lessThan(1));
    });

    test('summary is human readable and non-empty', () {
      final bytes = ImagePipeline.syntheticPage(
          seed: 22, kind: 'receipt', width: 400);
      final layout = TextAnalysis.analyze(bytes);
      final s = TextAnalysis.summarize(layout);
      expect(s, isNotEmpty);
    });

    test('blank page reports no text structure', () {
      // A pure white page has no ink to find.
      final blank = ImagePipeline.process(ProcessRequest(
        bytes: ImagePipeline.syntheticPage(
            seed: 31, kind: 'notes', width: 120),
        filter: ScanFilter.original,
      ));
      final layout = TextAnalysis.analyze(blank);
      expect(layout.lineCount, greaterThanOrEqualTo(0));
    });
  });

  group('Models', () {
    test('ScanDoc serialises and restores through a map', () {
      final page = ScanPage(
        id: 'p1',
        original: Uint8List.fromList([1, 2, 3]),
        processed: Uint8List.fromList([4, 5, 6]),
        filter: ScanFilter.bw,
        rotation: 2,
        brightness: 0.4,
        corners: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(1, 1),
          Offset(0, 1),
        ],
      );
      final doc = ScanDoc(
        id: 'd1',
        title: 'Test doc',
        pages: [page],
        favorite: true,
      );

      final restored = ScanDoc.fromMap(doc.toMap());
      expect(restored.id, 'd1');
      expect(restored.title, 'Test doc');
      expect(restored.favorite, isTrue);
      expect(restored.pageCount, 1);
      final rp = restored.pages.first;
      expect(rp.filter, ScanFilter.bw);
      expect(rp.rotation, 2);
      expect(rp.brightness, closeTo(0.4, 0.0001));
      expect(rp.corners, isNotNull);
      expect(rp.corners!.length, 4);
      expect(rp.processed, equals(Uint8List.fromList([4, 5, 6])));
    });

    test('size label scales with byte count', () {
      final doc = ScanDoc(
        id: 'd2',
        title: 'Sized',
        pages: [
          ScanPage(
            id: 'p',
            original: Uint8List(0),
            processed: Uint8List(2048),
          ),
        ],
      );
      expect(doc.sizeLabel, contains('KB'));
    });

    test('search blob includes title and ocr text', () {
      final doc = ScanDoc(
        id: 'd3',
        title: 'Invoice',
        pages: [
          ScanPage(
            id: 'p',
            original: Uint8List(0),
            processed: Uint8List(0),
            ocrText: 'ACME Corp',
          ),
        ],
      );
      expect(doc.searchBlob, contains('invoice'));
      expect(doc.searchBlob, contains('acme'));
    });

    test('page clone is a deep copy', () {
      final p = ScanPage(
        id: 'a',
        original: Uint8List.fromList([9, 9]),
        processed: Uint8List.fromList([8, 8]),
      );
      final c = p.clone('b');
      c.processed[0] = 1;
      expect(p.processed[0], 8); // original untouched
      expect(c.id, 'b');
    });
  });

  group('Edge detection', () {
    test('finds the border of a high-contrast page on a dark field', () {
      // Build a synthetic scene: dark background, bright page inset.
      final g = Gray(300, 400);
      for (int i = 0; i < g.data.length; i++) {
        g.data[i] = 30;
      }
      for (int y = 40; y < 360; y++) {
        for (int x = 30; x < 270; x++) {
          g.set(x, y, 240);
        }
      }
      final corners = EdgeDetector.detect(g);
      expect(corners, isNotNull);
      expect(corners!.length, 4);

      // Ground truth: x spans 30..269 of 300, y spans 40..359 of 400.
      const tol = 0.035;
      final tl = corners[0], tr = corners[1];
      final br = corners[2], bl = corners[3];

      expect(tl.dx, closeTo(30 / 300, tol));
      expect(tl.dy, closeTo(40 / 400, tol));
      expect(tr.dx, closeTo(270 / 300, tol));
      expect(tr.dy, closeTo(40 / 400, tol));
      expect(br.dx, closeTo(270 / 300, tol));
      expect(br.dy, closeTo(360 / 400, tol));
      expect(bl.dx, closeTo(30 / 300, tol));
      expect(bl.dy, closeTo(360 / 400, tol));
    });

    test('returns null on a featureless field', () {
      final g = Gray(120, 160);
      for (int i = 0; i < g.data.length; i++) {
        g.data[i] = 128;
      }
      expect(EdgeDetector.detect(g), isNull);
    });
  });
}
