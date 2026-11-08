import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'symbol.dart';
import 'relocation.dart';

/// An immutable relocatable code section with scoped function definitions.
///
/// Direct calls may refer to defined symbols or named imports. Data sections
/// and references other than direct calls are not represented yet.
final class ObjectModule(
  final Target target,
  List<int> code,
  Iterable<Symbol> symbols, {
  Iterable<String> imports = const [],
  Iterable<Relocation> relocations = const [],
}) {
  /// An immutable copy of the machine code.
  final Uint8List code = Uint8List.fromList(code).asUnmodifiableView();

  /// Function ranges sorted by code offset.
  final List<Symbol> symbols = .unmodifiable(symbols);

  /// Undefined global symbols, indexed after [symbols].
  final List<String> imports = .unmodifiable(imports);

  /// Instruction references that a linker must resolve.
  final List<Relocation> relocations = .unmodifiable(relocations);

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
    for (final name in this.imports) {
      if (name.isEmpty || name.contains('\u0000') || !names.add(name)) {
        throw ArgumentError('Invalid or duplicate import: $name');
      }
    }
    final sites = this.relocations.toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    var previousEnd = 0;
    final data = ByteData.sublistView(this.code);
    for (final reference in sites) {
      final offset = reference.offset;
      final arm = reference.kind == .arm64Call26;
      if (arm != (target.architecture == .arm64) ||
          offset < previousEnd ||
          offset > code.length - 4 ||
          reference.symbol < 0 ||
          reference.symbol >= this.symbols.length + this.imports.length ||
          (arm
              ? offset % 4 != 0 || data.getUint32(offset, .little) != 0x94000000
              : offset == 0 ||
                    code[offset - 1] != 0xe8 ||
                    data.getInt32(offset, .little) != 0)) {
        throw ArgumentError('Invalid call relocation at $offset.');
      }
      previousEnd = offset + 4;
    }
  }
}
