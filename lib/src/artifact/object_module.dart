import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'symbol.dart';

/// An immutable relocatable code section with scoped function definitions.
///
/// Code must be position independent and contain no unresolved references.
/// Data sections and relocations are not represented yet.
final class ObjectModule(
  final Target target,
  List<int> code,
  Iterable<Symbol> symbols,
) {
  /// An immutable copy of the machine code.
  final Uint8List code = Uint8List.fromList(code).asUnmodifiableView();

  /// Function ranges sorted by code offset.
  final List<Symbol> symbols = .unmodifiable(symbols);

  this {
    if (code.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Expected bytes in the range 0..255.');
    }
    if (target.architecture == .arm64 && code.length % 4 != 0) {
      throw ArgumentError('AArch64 code must contain whole instructions.');
    }
    final names = <String>{};
    var end = 0;
    for (final symbol in this.symbols) {
      if (symbol.name.isEmpty ||
          symbol.name.contains('\u0000') ||
          symbol.binding == .global && !names.add(symbol.name) ||
          symbol.exported && symbol.binding != .global ||
          symbol.offset < end ||
          symbol.size <= 0 ||
          symbol.offset > code.length - symbol.size ||
          target.architecture == .arm64 &&
              (symbol.offset % 4 != 0 || symbol.size % 4 != 0)) {
        throw ArgumentError('Invalid function symbol: ${symbol.name}');
      }
      end = symbol.offset + symbol.size;
    }
  }
}
