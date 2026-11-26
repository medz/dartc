// What C does after objects of the program are gone.
import 'collector.dart';
import 'machine.dart';

// Where a call of C has its first word, its function and the bytes of the
// stack.
const _word = 0, _target = 136, _stackBytes = 144;

// Where the results of a call are, which one that was made can still have.
const _results = 160;

/// Calls the functions of C of the entries whose values are gone.
void finalizeNative() {
  final block = callBlock(), results = block + _results;
  // A collection can come while the results of a call are being taken. They
  // are kept without allocating.
  final a = load64(results), b = load64(results + 8);
  final c = load64(results + 16), d = load64(results + 24);
  final e = load64(results + 32), f = load64(results + 40);
  for (var entry = firstEntry(); entry != 0; entry = nextEntry(entry)) {
    final place = entryFunction(entry), function = load64(place);
    if (function == 0) continue;
    store64(place, 0);
    store64(block + _word, load64(entryArgument(entry)));
    store64(block + _target, function);
    store64(block + _stackBytes, 0);
    callNative(block);
  }
  store64(results, a);
  store64(results + 8, b);
  store64(results + 16, c);
  store64(results + 24, d);
  store64(results + 32, e);
  store64(results + 40, f);
}
