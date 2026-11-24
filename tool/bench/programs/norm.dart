// Lists of doubles.
import 'dart:math';

double entry(int i, int j) => 1 / ((i + j) * (i + j + 1) ~/ 2 + i + 1);

void times(List<double> from, List<double> to, bool isTransposed) {
  for (var i = 0; i < to.length; i++) {
    var sum = 0.0;
    for (var j = 0; j < from.length; j++) {
      sum += (isTransposed ? entry(j, i) : entry(i, j)) * from[j];
    }
    to[i] = sum;
  }
}

void main() {
  const n = 1200;
  final u = List.filled(n, 1.0), v = List.filled(n, 0.0);
  final w = List.filled(n, 0.0);
  for (var i = 0; i < 10; i++) {
    times(u, w, false);
    times(w, v, true);
    times(v, w, false);
    times(w, u, true);
  }
  var uv = 0.0, vv = 0.0;
  for (var i = 0; i < n; i++) {
    uv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  print(sqrt(uv / vv).toStringAsFixed(9));
}
