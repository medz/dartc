// Lists of integers.
int flips(int n) {
  final order = [for (var i = 0; i < n; i++) i], work = List.filled(n, 0);
  final counts = List.filled(n, 0);
  var most = 0, r = n;
  while (true) {
    while (r != 1) {
      counts[r - 1] = r;
      r--;
    }
    for (var i = 0; i < n; i++) {
      work[i] = order[i];
    }
    var made = 0;
    for (var first = work[0]; first != 0; first = work[0]) {
      for (var i = 0, j = first; i < j; i++, j--) {
        final kept = work[i];
        work[i] = work[j];
        work[j] = kept;
      }
      made++;
    }
    if (made > most) most = made;
    while (true) {
      if (r == n) return most;
      final first = order[0];
      for (var i = 0; i < r; i++) {
        order[i] = order[i + 1];
      }
      order[r] = first;
      if (--counts[r] > 0) break;
      r++;
    }
  }
}

void main() => print(flips(10));
