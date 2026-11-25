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

/// Where the record is for the call returning to [offset] in the stack maps
/// [table], or 0 if it has none. The compiler tells how they are encoded.
int findStackMap(int table, int offset) {
  final pages = load32(table), page = offset >> 12, starts = table + 4;
  if (offset < 0 || page >= pages) return 0;
  final index = starts + pages * 4 + 4, wanted = offset & 0xfff;
  var low = load32(starts + page * 4), high = load32(starts + page * 4 + 4);
  while (low < high) {
    final middle = (low + high) >> 1, word = load32(index + middle * 4);
    final found = word >> 20;
    if (found == wanted) {
      final records = index + load32(starts + pages * 4) * 4;
      return records + (word & 0xfffff) * 4;
    }
    if (found < wanted) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return 0;
}
