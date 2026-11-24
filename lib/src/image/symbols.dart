import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// A symbol of a file: its name, the number of the section it is in, or 0 if it
/// is in none, and its address.
typedef MachoSymbol = ({
  String name,
  int section,
  int address,
  bool isExternal,
});

const symbolBytes = 16;

/// The table of [symbols], and that of their names.
({Uint8List symbols, Uint8List names}) encodeSymbols(
  List<MachoSymbol> symbols,
) {
  final out = ByteWriter(.little);
  final names = ByteWriter(.little)..u8(0x20);
  names.u8(0);
  for (final (:name, :section, :address, :isExternal) in symbols) {
    final inSection = section == 0 ? 0 : 0xe;
    out
      ..u32(names.length)
      ..u8(inSection | (isExternal ? 1 : 0))
      ..u8(section)
      ..u16(0)
      ..u64(address);
    names
      ..bytes(utf8.encode(name))
      ..u8(0);
  }
  names.align(8);
  return (symbols: out.finish(), names: names.finish());
}
