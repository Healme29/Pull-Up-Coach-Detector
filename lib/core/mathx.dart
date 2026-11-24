/// The handful of NumPy primitives the rep pipeline depends on, reproduced
/// exactly so the app and `python main.py` agree on every number.
///
/// Each one mirrors NumPy's default behaviour, including the edge cases the
/// pipeline relies on: edge padding, linear percentile interpolation, and
/// one-sided gradients at the ends.
library;

import 'dart:math' as math;

const double nan = double.nan;

bool isFinite(double v) => !v.isNaN && !v.isInfinite;

/// `np.median`, with NaNs already filtered out by the caller.
double median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return nan;
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
}

/// `np.percentile(..., method="linear")`.
double percentile(List<double> values, double q) {
  if (values.isEmpty) return nan;
  final sorted = [...values]..sort();
  if (sorted.length == 1) return sorted.first;
  final position = (sorted.length - 1) * q / 100.0;
  final lo = position.floor();
  final hi = position.ceil();
  if (lo == hi) return sorted[lo];
  final frac = position - lo;
  return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
}

/// `np.pad(x, pad, mode="edge")`.
List<double> _padEdge(List<double> x, int pad) {
  if (x.isEmpty) return <double>[];
  if (pad <= 0) return [...x];
  final first = x.first;
  final last = x.last;
  return [
    for (var i = 0; i < pad; i++) first,
    ...x,
    for (var i = 0; i < pad; i++) last,
  ];
}

/// `np.gradient(x)`, edge order 1.
List<double> gradient(List<double> x) {
  final n = x.length;
  if (n < 2) return n == 1 ? [0.0] : <double>[];
  final out = List<double>.filled(n, 0);
  out[0] = x[1] - x[0];
  out[n - 1] = x[n - 1] - x[n - 2];
  for (var i = 1; i < n - 1; i++) {
    out[i] = (x[i + 1] - x[i - 1]) / 2.0;
  }
  return out;
}

/// `np.interp` over the implicit index 0..n-1, clamping at both ends.
List<double> interpGaps(List<double> x, List<int> validIndices) {
  final n = x.length;
  final out = List<double>.filled(n, 0);
  if (validIndices.isEmpty) return out;
  final first = validIndices.first;
  final last = validIndices.last;
  for (var i = 0; i < n; i++) {
    if (i <= first) {
      out[i] = x[first];
    } else if (i >= last) {
      out[i] = x[last];
    } else {
      // Advance the bracket until validIndices[k] <= i < validIndices[k + 1].
      var lo = 0;
      var hi = validIndices.length - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (validIndices[mid] <= i) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final a = validIndices[lo];
      final b = validIndices[lo + 1];
      final t = (i - a) / (b - a);
      out[i] = x[a] + (x[b] - x[a]) * t;
    }
  }
  return out;
}

List<double> medianFilter(List<double> x, int k) {
  if (k < 3) return [...x];
  final width = k + (k + 1) % 2;
  final half = width ~/ 2;
  final padded = _padEdge(x, half);
  return [
    for (var i = 0; i < x.length; i++)
      median(padded.sublist(i, i + width)),
  ];
}

List<double> boxFilter(List<double> x, int k) {
  if (k < 2) return [...x];
  final width = k + (k + 1) % 2;
  final half = width ~/ 2;
  final padded = _padEdge(x, half);
  return [
    for (var i = 0; i < x.length; i++)
      padded.sublist(i, i + width).reduce((a, b) => a + b) / width,
  ];
}

List<double> fillGaps(List<double> x) {
  final valid = <int>[
    for (var i = 0; i < x.length; i++)
      if (isFinite(x[i])) i,
  ];
  if (valid.length == x.length) return [...x];
  if (valid.isEmpty) return List<double>.filled(x.length, 0);
  return interpGaps(x, valid);
}

double mean(Iterable<double> values) {
  var sum = 0.0;
  var n = 0;
  for (final v in values) {
    sum += v;
    n++;
  }
  return n == 0 ? nan : sum / n;
}

/// The interior angle at `b`, in degrees, between `b->a` and `b->c`.
double interiorAngle(math.Point<double> a, math.Point<double> b,
    math.Point<double> c) {
  final ux = a.x - b.x, uy = a.y - b.y;
  final vx = c.x - b.x, vy = c.y - b.y;
  final nu = math.sqrt(ux * ux + uy * uy);
  final nv = math.sqrt(vx * vx + vy * vy);
  if (nu < 1e-9 || nv < 1e-9) return nan;
  final cosine = ((ux * vx + uy * vy) / (nu * nv)).clamp(-1.0, 1.0);
  return math.acos(cosine) * 180.0 / math.pi;
}
