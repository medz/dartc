import 'dart:_heap/machine.dart' show load64, load8;
import 'dart:_heap/objects.dart' show arguments;

/// The arguments of the program.
List<String> _mainArguments() {
  final at = arguments();
  final count = load64(at) - 1;
  // The first one is the name of the program.
  final first = load64(at + 8) + 8;
  return [
    for (var i = 0; i < count; i++) _decode(load64(first + i * 8)),
  ].toList(growable: false);
}

/// The text of the bytes at [address], which a 0 ends.
String _decode(int address) {
  final bytes = <int>[];
  for (var at = address; load8(at) != 0; at++) {
    bytes.add(load8(at));
  }
  return utf8.decode(bytes, allowMalformed: true);
}
