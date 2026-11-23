import 'machine.dart';

/// The word for the call returning to [offset] in [table], or 0 if it has none.
///
/// A table is the number of its entries and, sorted, where a call returns to
/// and the word for it. All are 32 bits.
int findReturn(int table, int offset) {
  var low = 0, high = load32(table);
  while (low < high) {
    final middle = (low + high) >> 1, entry = table + 4 + middle * 8;
    final found = load32(entry);
    if (found == offset) return load32(entry + 4);
    if (found < offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return 0;
}
