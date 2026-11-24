import 'dart:typed_data';

import 'bytes.dart';

/// What the last segment has for loaders and linkers, one after the other.
final class LinkTables(
  final Uint8List fixups,
  final Uint8List exports,
  final ({Uint8List symbols, Uint8List names}) symbolTable,
  final int symbolCount,
) {
  /// Where each is.
  int get exportsOffset => fixups.length;
  int get symbolsOffset => exportsOffset + exports.length;
  int get namesOffset => symbolsOffset + symbolTable.symbols.length;

  late final Uint8List bytes = () {
    final out = ByteWriter(.little)
      ..bytes(fixups)
      ..bytes(exports);
    if (symbolCount > 0) {
      out
        ..bytes(symbolTable.symbols)
        ..bytes(symbolTable.names);
    }
    return out.finish();
  }();
}
