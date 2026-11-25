// What C does after objects of the program are gone.
import 'collector.dart';
import 'machine.dart';

// Where a call of C has its first word, its function and the bytes of the
// stack.
const _word = 0, _target = 136, _stackBytes = 144;

/// Calls the functions of C of the entries whose values are gone.
void finalizeNative() {
  final block = callBlock();
  for (var entry = firstEntry(); entry != 0; entry = nextEntry(entry)) {
    final place = entryFunction(entry), function = load64(place);
    if (function == 0) continue;
    store64(place, 0);
    store64(block + _word, load64(entryArgument(entry)));
    store64(block + _target, function);
    store64(block + _stackBytes, 0);
    callNative(block);
  }
}
