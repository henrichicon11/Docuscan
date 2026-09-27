import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Low-level computer-vision helpers written in pure Dart so they run
/// identically on Android and on the web preview.
///
/// Everything here operates on a simple planar grayscale buffer to keep the
/// hot loops free of object allocation.
class Gray {
  final int w;
  final int h;
  final Uint8List data;

  Gray(this.w, this.h) : data = Uint8List(w * h);
  Gray.of(this.w, this.h, this.data);

  int at(int x, int y) => data[y * w + x];
  void set(int x, int y, int v) => data[y * w + x] = v;
}

class Cv {
  Cv._();

  // ── Box blur (separable, O(1) per pixel) ────────────────────────────
  static Gray boxBlur(Gray src, int radius) {
    if (radius < 1) return src;
    final tmp = Gray(src.w, src.h);
    final out = Gray(src.w, src.h);
    final win = radius * 2 + 1;

    // Horizontal
    for (int y = 0; y < src.h; y++) {
      final row = y * src.w;
      int sum = 0;
      for (int i = -radius; i <= radius; i++) {
        sum += src.data[row + i.clamp(0, src.w - 1)];
      }
      for (int x = 0; x < src.w; x++) {
        tmp.data[row + x] = sum ~/ win;
        final add = (x + radius + 1).clamp(0, src.w - 1);
        final rem = (x - radius).clamp(0, src.w - 1);
        sum += src.data[row + add] - src.data[row + rem];
      }
    }
    // Vertical
    for (int x = 0; x < src.w; x++) {
      int sum = 0;
      for (int i = -radius; i <= radius; i++) {
        sum += tmp.data[i.clamp(0, src.h - 1) * src.w + x];
      }
      for (int y = 0; y < src.h; y++) {
        out.data[y * src.w + x] = sum ~/ win;
        final add = (y + radius + 1).clamp(0, src.h - 1);
        final rem = (y - radius).clamp(0, src.h - 1);
        sum += tmp.data[add * src.w + x] - tmp.data[rem * src.w + x];
      }
    }
    return out;
  }

  /// Downscale by nearest-area averaging to a target width.
  static Gray resize(Gray src, int tw) {
    if (tw >= src.w) return src;
    final th = math.max(1, (src.h * tw / src.w).round());
    final out = Gray(tw, th);
    final sx = src.w / tw;
    final sy = src.h / th;
    for (int y = 0; y < th; y++) {
      final y0 = (y * sy).floor();
      final y1 = math.min(src.h, ((y + 1) * sy).ceil());
      for (int x = 0; x < tw; x++) {
        final x0 = (x * sx).floor();
        final x1 = math.min(src.w, ((x + 1) * sx).ceil());
        int sum = 0, n = 0;
        for (int yy = y0; yy < y1; yy++) {
          final row = yy * src.w;
          for (int xx = x0; xx < x1; xx++) {
            sum += src.data[row + xx];
            n++;
          }
        }
        out.data[y * tw + x] = n == 0 ? 0 : sum ~/ n;
      }
    }
    return out;
  }

  /// Sobel gradient magnitude, normalised to 0..255.
  static Gray sobel(Gray src) {
    final out = Gray(src.w, src.h);
    final w = src.w, h = src.h;
    int maxMag = 1;
    final mags = Int32List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final tl = src.data[i - w - 1],
            t = src.data[i - w],
            tr = src.data[i - w + 1];
        final l = src.data[i - 1], r = src.data[i + 1];
        final bl = src.data[i + w - 1],
            b = src.data[i + w],
            br = src.data[i + w + 1];
        final gx = (tr + 2 * r + br) - (tl + 2 * l + bl);
        final gy = (bl + 2 * b + br) - (tl + 2 * t + tr);
        final m = math.sqrt((gx * gx + gy * gy).toDouble()).round();
        mags[i] = m;
        if (m > maxMag) maxMag = m;
      }
    }
    for (int i = 0; i < mags.length; i++) {
      out.data[i] = (mags[i] * 255 ~/ maxMag).clamp(0, 255);
    }
    return out;
  }

  // ── Integral image for adaptive threshold ───────────────────────────
  static Int64List integral(Gray src) {
    final w = src.w, h = src.h;
    final ii = Int64List((w + 1) * (h + 1));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += src.data[y * w + x];
        ii[(y + 1) * (w + 1) + (x + 1)] = ii[y * (w + 1) + (x + 1)] + rowSum;
      }
    }
    return ii;
  }

  /// Bradley–Roth adaptive threshold — the technique that makes
  /// scanner "B&W" mode legible under uneven lighting.
  static Gray adaptiveThreshold(
    Gray src, {
    double windowFrac = 0.10,
    double t = 0.15,
  }) {
    final w = src.w, h = src.h;
    final ii = integral(src);
    final out = Gray(w, h);
    final r = math.max(3, (w * windowFrac / 2).round());
    for (int y = 0; y < h; y++) {
      final y1 = (y - r).clamp(0, h - 1);
      final y2 = (y + r).clamp(0, h - 1);
      for (int x = 0; x < w; x++) {
        final x1 = (x - r).clamp(0, w - 1);
        final x2 = (x + r).clamp(0, w - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);
        final sum =
            ii[(y2 + 1) * (w + 1) + (x2 + 1)] -
            ii[y1 * (w + 1) + (x2 + 1)] -
            ii[(y2 + 1) * (w + 1) + x1] +
            ii[y1 * (w + 1) + x1];
        final mean = sum / count;
        out.data[y * w + x] = src.data[y * w + x] < mean * (1.0 - t) ? 0 : 255;
      }
    }
    return out;
  }

  /// Otsu global threshold: the intensity that maximises between-class
  /// variance.
  ///
  /// Convention: the returned value is the **inclusive upper bound of the
  /// dark class**, so callers should treat `value <= t` as background and
  /// `value > t` as foreground.
  static int otsu(Gray src) {
    final hist = Int32List(256);
    for (final v in src.data) {
      hist[v]++;
    }
    final total = src.data.length;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    double sumB = 0, wB = 0, best = -1;
    int thr = 128;
    for (int i = 0; i < 256; i++) {
      wB += hist[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * hist[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        thr = i;
      }
    }
    return thr;
  }
}

/// A straight line in normal form: x·cosθ + y·sinθ = ρ
class HLine {
  final double theta;
  final double rho;
  final int votes;
  const HLine(this.theta, this.rho, this.votes);

  /// Intersection with another line, or null if near-parallel.
  Offset? intersect(HLine o) {
    final det =
        math.cos(theta) * math.sin(o.theta) -
        math.sin(theta) * math.cos(o.theta);
    if (det.abs() < 1e-6) return null;
    final x = (rho * math.sin(o.theta) - math.sin(theta) * o.rho) / det;
    final y = (math.cos(theta) * o.rho - rho * math.cos(o.theta)) / det;
    return Offset(x, y);
  }
}

/// Document boundary detector: Hough transform restricted to the
/// near-horizontal / near-vertical families, then border selection.
class EdgeDetector {
  /// Returns normalised corners (tl, tr, br, bl) in 0..1 space,
  /// or null when no convincing document boundary is present.
  static List<Offset>? detect(Gray full) {
    // 1. Work small — detection accuracy does not need full resolution.
    final g = Cv.resize(full, 320);
    final blurred = Cv.boxBlur(g, 2);
    final edges = Cv.sobel(blurred);

    // 2. Keep only strong edge pixels.
    final thr = math.max(40, Cv.otsu(edges));
    final w = edges.w, h = edges.h;

    // 3. Hough accumulator.
    const thetaSteps = 180; // 1° resolution over 180°
    final diag = math.sqrt((w * w + h * h).toDouble());
    final rhoMax = diag.ceil();
    final rhoSteps = rhoMax * 2 + 1;
    final acc = Int32List(thetaSteps * rhoSteps);
    final cosT = Float64List(thetaSteps);
    final sinT = Float64List(thetaSteps);
    for (int t = 0; t < thetaSteps; t++) {
      final a = t * math.pi / thetaSteps;
      cosT[t] = math.cos(a);
      sinT[t] = math.sin(a);
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // `thr` is the inclusive top of the weak class, so keep `> thr`.
        if (edges.data[y * w + x] <= thr) continue;
        for (int t = 0; t < thetaSteps; t++) {
          final rho = (x * cosT[t] + y * sinT[t]).round() + rhoMax;
          acc[t * rhoSteps + rho]++;
        }
      }
    }

    // 4. Harvest peaks with non-maximum suppression.
    final peaks = <HLine>[];
    final minVotes = math.max(28, (math.min(w, h) * 0.22).round());
    for (int t = 0; t < thetaSteps; t++) {
      for (int r = 1; r < rhoSteps - 1; r++) {
        final v = acc[t * rhoSteps + r];
        if (v < minVotes) continue;
        bool isMax = true;
        for (int dt = -2; dt <= 2 && isMax; dt++) {
          final tt = (t + dt + thetaSteps) % thetaSteps;
          for (int dr = -4; dr <= 4; dr++) {
            final rr = r + dr;
            if (rr < 0 || rr >= rhoSteps) continue;
            if (acc[tt * rhoSteps + rr] > v) {
              isMax = false;
              break;
            }
          }
        }
        if (isMax) {
          peaks.add(
            HLine(t * math.pi / thetaSteps, (r - rhoMax).toDouble(), v),
          );
        }
      }
    }
    if (peaks.length < 4) return null;

    // 5. Split into near-vertical (θ≈0 or π) and near-horizontal (θ≈π/2).
    const tol = 35 * math.pi / 180;
    final verticals = <HLine>[];
    final horizontals = <HLine>[];
    for (final p in peaks) {
      final a = p.theta;
      if (a < tol || a > math.pi - tol) {
        verticals.add(p);
      } else if ((a - math.pi / 2).abs() < tol) {
        horizontals.add(p);
      }
    }
    if (verticals.length < 2 || horizontals.length < 2) return null;

    // Position of each line along its perpendicular axis, measured at the
    // image centre — used to decide which side of the page it belongs to.
    double vx(HLine l) {
      // x where the line crosses the vertical centre of the image
      final yc = h / 2;
      if (l.theta.abs() < 1e-6) return l.rho;
      return (l.rho - yc * math.sin(l.theta)) / math.cos(l.theta);
    }

    double hy(HLine l) {
      final xc = w / 2;
      return (l.rho - xc * math.cos(l.theta)) / math.sin(l.theta);
    }

    // 6. Pick one border per side. The true page edge is the *strongest*
    //    accumulation on that side — choosing the most extreme line instead
    //    lets a slightly tilted stray line win and skews the quad.
    HLine? strongestWhere(List<HLine> pool, bool Function(HLine) inRegion) {
      HLine? best;
      for (final l in pool) {
        if (!inRegion(l)) continue;
        if (best == null || l.votes > best.votes) best = l;
      }
      return best;
    }

    final left = strongestWhere(verticals, (l) => vx(l) < w * 0.45);
    final right = strongestWhere(verticals, (l) => vx(l) > w * 0.55);
    final top = strongestWhere(horizontals, (l) => hy(l) < h * 0.45);
    final bottom = strongestWhere(horizontals, (l) => hy(l) > h * 0.55);

    if (left == null || right == null || top == null || bottom == null) {
      return null;
    }

    final tl = top.intersect(left);
    final tr = top.intersect(right);
    final br = bottom.intersect(right);
    final bl = bottom.intersect(left);
    if (tl == null || tr == null || br == null || bl == null) return null;

    final quad = [tl, tr, br, bl];

    // 7. Sanity: corners inside a small margin, convex, and covering
    //    a meaningful share of the frame.
    final mx = w * 0.06, my = h * 0.06;
    for (final p in quad) {
      if (p.dx < -mx || p.dx > w + mx || p.dy < -my || p.dy > h + my) {
        return null;
      }
    }
    final area = _polyArea(quad).abs();
    if (area < w * h * 0.18) return null;
    if (!_isConvex(quad)) return null;

    return quad
        .map(
          (p) => Offset((p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0)),
        )
        .toList();
  }

  static double _polyArea(List<Offset> p) {
    double a = 0;
    for (int i = 0; i < p.length; i++) {
      final q = p[(i + 1) % p.length];
      a += p[i].dx * q.dy - q.dx * p[i].dy;
    }
    return a / 2;
  }

  static bool _isConvex(List<Offset> p) {
    int sign = 0;
    for (int i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      final c = p[(i + 2) % p.length];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
      if (s == 0) continue;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }
}

/// 3×3 homography solved from four point correspondences.
class Homography {
  final Float64List m; // 9 entries, row-major, m[8] == 1

  Homography(this.m);

  /// Maps `dst` corners onto `src` corners (i.e. use it to pull pixels).
  static Homography? fromCorners(List<Offset> dst, List<Offset> src) {
    // Build 8×9 system and solve with Gaussian elimination.
    final a = List<Float64List>.generate(8, (_) => Float64List(9));
    for (int i = 0; i < 4; i++) {
      final x = dst[i].dx, y = dst[i].dy;
      final u = src[i].dx, v = src[i].dy;
      final r1 = a[i * 2];
      r1[0] = x;
      r1[1] = y;
      r1[2] = 1;
      r1[3] = 0;
      r1[4] = 0;
      r1[5] = 0;
      r1[6] = -u * x;
      r1[7] = -u * y;
      r1[8] = u;
      final r2 = a[i * 2 + 1];
      r2[0] = 0;
      r2[1] = 0;
      r2[2] = 0;
      r2[3] = x;
      r2[4] = y;
      r2[5] = 1;
      r2[6] = -v * x;
      r2[7] = -v * y;
      r2[8] = v;
    }

    // Gauss–Jordan with partial pivoting.
    for (int col = 0; col < 8; col++) {
      int piv = col;
      double best = a[col][col].abs();
      for (int r = col + 1; r < 8; r++) {
        final val = a[r][col].abs();
        if (val > best) {
          best = val;
          piv = r;
        }
      }
      if (best < 1e-12) return null;
      if (piv != col) {
        final tmp = a[col];
        a[col] = a[piv];
        a[piv] = tmp;
      }
      final pv = a[col][col];
      for (int k = col; k < 9; k++) {
        a[col][k] /= pv;
      }
      for (int r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col];
        if (f == 0) continue;
        for (int k = col; k < 9; k++) {
          a[r][k] -= f * a[col][k];
        }
      }
    }

    final m = Float64List(9);
    for (int i = 0; i < 8; i++) {
      m[i] = a[i][8];
    }
    m[8] = 1.0;
    return Homography(m);
  }

  /// Apply to a point.
  Offset map(double x, double y) {
    final d = m[6] * x + m[7] * y + m[8];
    if (d.abs() < 1e-12) return Offset.zero;
    return Offset(
      (m[0] * x + m[1] * y + m[2]) / d,
      (m[3] * x + m[4] * y + m[5]) / d,
    );
  }
}
