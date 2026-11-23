import 'dart:typed_data';

import 'package:dartc/emit.dart';

/// Code that cannot become an executable: always a compiler bug.
final class ImageError(final String message) implements Exception {
  @override
  String toString() => 'ImageError: $message';
}

/// Fills in the symbol addresses of [text], which will be loaded at [address].
///
/// [symbols] gives each symbol's final address.
void relocate(
  Uint8List text,
  int address,
  Iterable<Relocation> relocations,
  Map<String, int> symbols,
) {
  final words = ByteData.sublistView(text);
  for (final Relocation(:offset, :kind, :symbol) in relocations) {
    final target = symbols[symbol] ?? (throw ImageError('No symbol $symbol.'));
    final at = address + offset;
    final bits = switch (kind) {
      .call26 => _signed((target - at) >> 2, 26, symbol),
      .page21 => pageField(at, target, symbol),
      .pageOffset12 => (target & 0xfff) << 10,
    };
    final word = words.getUint32(offset, .little);
    words.setUint32(offset, word | bits, .little);
  }
}

/// Writes the distance from table [name] to each function, at [offset].
void fillTable(
  Uint8List bytes,
  int offset,
  String name,
  List<String> functions,
  Map<String, int> symbols,
) {
  final words = ByteData.sublistView(bytes);
  for (final (i, function) in functions.indexed) {
    final target =
        symbols[function] ?? (throw ImageError('No symbol $function.'));
    final distance = _signed(target - symbols[name]!, 32, function);
    words.setUint32(offset + i * 4, distance, .little);
  }
}

/// The `adrp` immediate reaching [target]'s page from an instruction at [at].
int pageField(int at, int target, String symbol) {
  final field = _signed((target >> 12) - (at >> 12), 21, symbol);
  return (field & 3) << 29 | (field >> 2) << 5;
}

int _signed(int value, int bits, String symbol) {
  final limit = 1 << (bits - 1);
  if (value < -limit || value >= limit) {
    throw ImageError('$symbol is out of reach.');
  }
  return value & ((1 << bits) - 1);
}
