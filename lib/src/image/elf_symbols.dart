import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// Texts that others refer to by where they start.
final class ElfNames() {
  final _out = ByteWriter(.little)..u8(0);
  final _offsets = <String, int>{'': 0};

  int operator [](String name) => _offsets[name] ??= _add(name);

  int _add(String name) {
    final at = _out.length;
    _out
      ..bytes(utf8.encode(name))
      ..u8(0);
    return at;
  }

  Uint8List finish() => _out.finish();
}

/// What symbols are, as they have it.
enum ElfSymbolType(final int code) {
  none(0),
  object(1),
  function(2),
}

/// A symbol: the number of the section that it is in, or 0 if it is in none, and
/// where.
typedef ElfSymbol = ({
  String name,
  ElfSymbolType type,
  int section,
  int value,
  bool isGlobal,
});

const elfSymbolBytes = 24;

/// The table of [symbols], after the first one that all tables have.
Uint8List encodeElfSymbols(Iterable<ElfSymbol> symbols, ElfNames names) {
  final out = ByteWriter(.little)..zeros(elfSymbolBytes);
  for (final (:name, :type, :section, :value, :isGlobal) in symbols) {
    out
      ..u32(names[name])
      ..u8((isGlobal ? 1 : 0) << 4 | type.code)
      ..u8(0)
      ..u16(section)
      ..u64(value)
      ..u64(0);
  }
  return out.finish();
}

/// The table that finds the symbols called [names], from number 1 on.
Uint8List elfHashTable(List<String> names) {
  final buckets = List.filled(names.length + 1, 0);
  final chains = List.filled(names.length + 1, 0);
  for (final (i, name) in names.indexed) {
    final bucket = _hash(name) % buckets.length;
    chains[i + 1] = buckets[bucket];
    buckets[bucket] = i + 1;
  }
  final out = ByteWriter(.little)
    ..u32(buckets.length)
    ..u32(chains.length);
  [...buckets, ...chains].forEach(out.u32);
  return out.finish();
}

int _hash(String name) {
  var hash = 0;
  for (final byte in utf8.encode(name)) {
    hash = (hash << 4) + byte;
    final high = hash & 0xf0000000;
    hash = (hash ^ high >> 24) & 0xfffffff;
  }
  return hash;
}
