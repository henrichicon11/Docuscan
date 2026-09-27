import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import '../models/doc.dart';
import 'cv.dart';

class ProcessRequest {
  final Uint8List bytes;
  final List<Offset>? corners;
  final ScanFilter filter;
  final int rotation;
  final double brightness;
  final double contrast;
  final double sharpen;
  final int maxEdge;

  const ProcessRequest({
    required this.bytes,
    this.corners,
    this.filter = ScanFilter.magic,
    this.rotation = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.sharpen = 0,
    this.maxEdge = 1800,
  });
}

class ImagePipeline {
  ImagePipeline._();

  // ── Decoding helpers ────────────────────────────────────────────────

  static img.Image? decode(Uint8List bytes) => img.decodeImage(bytes);

  static Gray toGray(img.Image src) {
    final g = Gray(src.width, src.height);
    int i = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        // Rec. 709 luma
        g.data[i++] = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
            .round()
            .clamp(0, 255);
      }
    }
    return g;
  }

  /// Detect page corners from encoded bytes. Returns normalised quad.
  static List<Offset>? detectCorners(Uint8List bytes) {
    final im = decode(bytes);
    if (im == null) return null;
    final small = img.copyResize(
      im,
      width: math.min(700, im.width),
      interpolation: img.Interpolation.average,
    );
    return EdgeDetector.detect(toGray(small));
  }

  // ── Geometry ────────────────────────────────────────────────────────

  /// Perspective-correct `src` using a normalised quad, bilinear sampled.
  static img.Image warp(img.Image src, List<Offset> normQuad) {
    final quad = normQuad
        .map((o) => Offset(o.dx * src.width, o.dy * src.height))
        .toList();
    final tl = quad[0], tr = quad[1], br = quad[2], bl = quad[3];

    double dist(Offset a, Offset b) =>
        math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));

    // Output size = average of opposite edge lengths (keeps aspect sane).
    int outW = ((dist(tl, tr) + dist(bl, br)) / 2).round();
    int outH = ((dist(tl, bl) + dist(tr, br)) / 2).round();
    outW = outW.clamp(64, 4200);
    outH = outH.clamp(64, 4200);

    final h = Homography.fromCorners([
      const Offset(0, 0),
      Offset(outW - 1, 0),
      Offset(outW - 1, outH - 1),
      Offset(0, outH - 1),
    ], quad);
    if (h == null) return src;

    final out = img.Image(width: outW, height: outH, numChannels: 3);
    final maxX = src.width - 1;
    final maxY = src.height - 1;

    for (int y = 0; y < outH; y++) {
      for (int x = 0; x < outW; x++) {
        final p = h.map(x.toDouble(), y.toDouble());
        final sx = p.dx.clamp(0.0, maxX.toDouble());
        final sy = p.dy.clamp(0.0, maxY.toDouble());
        final x0 = sx.floor(), y0 = sy.floor();
        final x1 = math.min(x0 + 1, maxX), y1 = math.min(y0 + 1, maxY);
        final fx = sx - x0, fy = sy - y0;

        final p00 = src.getPixel(x0, y0);
        final p10 = src.getPixel(x1, y0);
        final p01 = src.getPixel(x0, y1);
        final p11 = src.getPixel(x1, y1);

        double lerp(num a, num b, num c, num d) {
          final top = a + (b - a) * fx;
          final bot = c + (d - c) * fx;
          return top + (bot - top) * fy;
        }

        out.setPixelRgb(
          x,
          y,
          lerp(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
          lerp(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
          lerp(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
        );
      }
    }
    return out;
  }

  // ── Tone / enhancement ──────────────────────────────────────────────

  /// Divide the image by its own heavily-blurred luma to remove shadows
  /// and vignetting — the "flat white paper" trick.
  static img.Image flattenIllumination(img.Image src, {double strength = 1.0}) {
    final gray = toGray(src);
    final radius = math.max(
      8,
      (math.min(src.width, src.height) * 0.06).round(),
    );
    final bg = Cv.boxBlur(gray, radius);

    final out = img.Image(width: src.width, height: src.height, numChannels: 3);
    int i = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final b = bg.data[i++];
        final gain = b <= 4 ? 1.0 : 235.0 / b;
        final g = 1.0 + (gain - 1.0) * strength;
        final p = src.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          (p.r * g).round().clamp(0, 255),
          (p.g * g).round().clamp(0, 255),
          (p.b * g).round().clamp(0, 255),
        );
      }
    }
    return out;
  }

  /// Stretch the histogram so the paper reads pure white and ink reads black.
  static img.Image autoLevels(
    img.Image src, {
    double lowPct = 0.5,
    double highPct = 99.3,
    double sat = 1.0,
  }) {
    final hist = Int32List(256);
    final gray = toGray(src);
    for (final v in gray.data) {
      hist[v]++;
    }
    final total = gray.data.length;
    final loTarget = total * lowPct / 100;
    final hiTarget = total * highPct / 100;
    int lo = 0, hi = 255, acc = 0;
    for (int v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= loTarget) {
        lo = v;
        break;
      }
    }
    acc = 0;
    for (int v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= hiTarget) {
        hi = v;
        break;
      }
    }
    if (hi - lo < 12) {
      lo = 0;
      hi = 255;
    }
    final scale = 255.0 / (hi - lo);

    final lut = Uint8List(256);
    for (int v = 0; v < 256; v++) {
      lut[v] = ((v - lo) * scale).round().clamp(0, 255);
    }

    final out = img.Image(width: src.width, height: src.height, numChannels: 3);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        int r = lut[p.r.toInt().clamp(0, 255)];
        int g = lut[p.g.toInt().clamp(0, 255)];
        int b = lut[p.b.toInt().clamp(0, 255)];
        if (sat != 1.0) {
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          r = (l + (r - l) * sat).round().clamp(0, 255);
          g = (l + (g - l) * sat).round().clamp(0, 255);
          b = (l + (b - l) * sat).round().clamp(0, 255);
        }
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  static img.Image applyBrightnessContrast(
    img.Image src,
    double brightness,
    double contrast,
  ) {
    if (brightness == 0 && contrast == 0) return src;
    final b = brightness * 90; // -90..90
    final c = 1.0 + contrast * 0.85; // 0.15..1.85
    final lut = Uint8List(256);
    for (int v = 0; v < 256; v++) {
      final x = (v - 128) * c + 128 + b;
      lut[v] = x.round().clamp(0, 255);
    }
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        src.setPixelRgb(
          x,
          y,
          lut[p.r.toInt().clamp(0, 255)],
          lut[p.g.toInt().clamp(0, 255)],
          lut[p.b.toInt().clamp(0, 255)],
        );
      }
    }
    return src;
  }

  /// Unsharp mask driven by the blurred luma — cheap but effective.
  static img.Image unsharp(img.Image src, double amount) {
    if (amount <= 0.001) return src;
    final gray = toGray(src);
    final blur = Cv.boxBlur(gray, 2);
    final k = amount * 1.6;
    int i = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final d = (gray.data[i] - blur.data[i]) * k;
        i++;
        final p = src.getPixel(x, y);
        src.setPixelRgb(
          x,
          y,
          (p.r + d).round().clamp(0, 255),
          (p.g + d).round().clamp(0, 255),
          (p.b + d).round().clamp(0, 255),
        );
      }
    }
    return src;
  }

  static img.Image toBlackWhite(img.Image src) {
    final gray = toGray(src);
    final bw = Cv.adaptiveThreshold(gray, windowFrac: 0.09, t: 0.14);
    final out = img.Image(width: src.width, height: src.height, numChannels: 3);
    int i = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final v = bw.data[i++];
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  static img.Image toGrayscaleImage(img.Image src) {
    final gray = toGray(src);
    final out = img.Image(width: src.width, height: src.height, numChannels: 3);
    int i = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final v = gray.data[i++];
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  // ── Main entry point ────────────────────────────────────────────────

  /// Full pipeline: decode → warp → filter → adjust → encode JPEG.
  static Uint8List process(ProcessRequest r) {
    var im = decode(r.bytes);
    if (im == null) return r.bytes;

    // 1. Geometry first, so enhancement statistics only see the page.
    if (r.corners != null && r.corners!.length == 4) {
      im = warp(im, r.corners!);
    }

    // 2. Constrain working resolution (keeps web preview responsive).
    final longest = math.max(im.width, im.height);
    if (longest > r.maxEdge) {
      final scale = r.maxEdge / longest;
      im = img.copyResize(
        im,
        width: (im.width * scale).round(),
        height: (im.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }

    // 3. Rotation.
    final rot = r.rotation % 4;
    if (rot != 0) {
      im = img.copyRotate(im, angle: rot * 90);
    }

    // 4. Filter presets.
    switch (r.filter) {
      case ScanFilter.original:
        break;
      case ScanFilter.magic:
        im = flattenIllumination(im, strength: 1.0);
        im = autoLevels(im, lowPct: 1.0, highPct: 99.2, sat: 1.12);
        im = unsharp(im, 0.45);
        break;
      case ScanFilter.lighten:
        im = flattenIllumination(im, strength: 0.65);
        im = autoLevels(im, lowPct: 0.2, highPct: 99.7, sat: 1.0);
        break;
      case ScanFilter.grayscale:
        im = flattenIllumination(im, strength: 0.9);
        im = toGrayscaleImage(im);
        im = autoLevels(im, lowPct: 1.0, highPct: 99.4, sat: 0);
        break;
      case ScanFilter.bw:
        im = flattenIllumination(im, strength: 1.0);
        im = toBlackWhite(im);
        break;
      case ScanFilter.ink:
        im = flattenIllumination(im, strength: 1.0);
        im = autoLevels(im, lowPct: 3.0, highPct: 99.0, sat: 1.25);
        im = unsharp(im, 0.85);
        break;
    }

    // 5. Manual adjustments.
    im = applyBrightnessContrast(im, r.brightness, r.contrast);
    if (r.sharpen > 0) im = unsharp(im, r.sharpen);

    return Uint8List.fromList(img.encodeJpg(im, quality: 88));
  }

  /// Small thumbnail for list/grid rendering.
  static Uint8List thumbnail(Uint8List bytes, {int width = 320}) {
    final im = decode(bytes);
    if (im == null) return bytes;
    final t = img.copyResize(
      im,
      width: math.min(width, im.width),
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(t, quality: 80));
  }

  /// Re-encode at a target long edge for export.
  static Uint8List forExport(Uint8List bytes, int maxEdge, int quality) {
    final im = decode(bytes);
    if (im == null) return bytes;
    final longest = math.max(im.width, im.height);
    var out = im;
    if (longest > maxEdge) {
      final s = maxEdge / longest;
      out = img.copyResize(
        im,
        width: (im.width * s).round(),
        height: (im.height * s).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: quality));
  }

  /// Synthesise a believable scanned page — used to seed the demo library
  /// so the app never opens empty.
  static Uint8List syntheticPage({
    required int seed,
    required String kind,
    int width = 760,
  }) {
    final rnd = math.Random(seed);
    final h = (width * 1.414).round();
    final im = img.Image(width: width, height: h, numChannels: 3);

    // Paper with a faint warm tint and subtle grain.
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < width; x++) {
        final n = rnd.nextInt(6);
        im.setPixelRgb(x, y, 252 - n, 251 - n, 247 - n);
      }
    }

    final ink = img.ColorRgb8(28, 30, 34);
    final faint = img.ColorRgb8(120, 126, 134);
    final accent = img.ColorRgb8(190, 140, 60);

    void bar(int x, int y, int w, int hh, img.Color col) {
      img.fillRect(
        im,
        x1: x,
        y1: y,
        x2: (x + w).clamp(0, width - 1),
        y2: (y + hh).clamp(0, h - 1),
        color: col,
      );
    }

    // Header block
    bar(60, 70, 250, 16, ink);
    bar(60, 100, 150, 9, faint);
    bar(width - 190, 72, 130, 10, faint);
    bar(60, 132, width - 120, 2, img.ColorRgb8(225, 223, 216));

    int y = 170;
    if (kind == 'receipt') {
      for (int row = 0; row < 12; row++) {
        final wLeft = 120 + rnd.nextInt(220);
        bar(60, y, wLeft, 9, ink);
        bar(width - 150, y, 90, 9, faint);
        y += 34;
      }
      bar(60, y + 12, width - 120, 2, img.ColorRgb8(225, 223, 216));
      bar(60, y + 34, 120, 14, ink);
      bar(width - 180, y + 32, 120, 16, accent);
    } else if (kind == 'id') {
      // Photo placeholder + field lines
      bar(60, 170, 180, 220, img.ColorRgb8(228, 226, 219));
      bar(90, 210, 120, 120, img.ColorRgb8(200, 197, 190));
      int fy = 180;
      for (int row = 0; row < 6; row++) {
        bar(280, fy, 90, 8, faint);
        bar(280, fy + 16, 180 + rnd.nextInt(120), 11, ink);
        fy += 46;
      }
      bar(60, 430, width - 120, 2, img.ColorRgb8(225, 223, 216));
      for (int row = 0; row < 6; row++) {
        bar(60, 460 + row * 30, 300 + rnd.nextInt(280), 9, faint);
      }
    } else {
      // Contract / notes: paragraphs of ragged text lines
      for (int para = 0; para < 5; para++) {
        bar(60, y, 190, 12, ink);
        y += 30;
        final lines = 4 + rnd.nextInt(4);
        for (int l = 0; l < lines; l++) {
          final wl = (width - 130) - (l == lines - 1 ? rnd.nextInt(300) : 0);
          bar(60, y, wl, 8, faint);
          y += 22;
        }
        y += 22;
        if (y > h - 200) break;
      }
      // Signature squiggle
      final sy = h - 150;
      bar(60, sy, 200, 2, img.ColorRgb8(215, 213, 206));
      for (int i = 0; i < 170; i++) {
        final sx = 70 + i;
        final yy = sy - 14 + (math.sin(i / 12.0) * 11).round();
        for (int t = 0; t < 3; t++) {
          if (yy + t >= 0 && yy + t < h && sx < width) {
            im.setPixelRgb(sx, yy + t, 40, 55, 110);
          }
        }
      }
    }

    // Gentle page curl shading on the right edge for realism.
    for (int yy = 0; yy < h; yy++) {
      for (int xx = width - 40; xx < width; xx++) {
        final f = (width - xx) / 40.0;
        final p = im.getPixel(xx, yy);
        final k = 1.0 - (1.0 - f) * 0.10;
        im.setPixelRgb(
          xx,
          yy,
          (p.r * k).round(),
          (p.g * k).round(),
          (p.b * k).round(),
        );
      }
    }

    return Uint8List.fromList(img.encodeJpg(im, quality: 86));
  }
}
