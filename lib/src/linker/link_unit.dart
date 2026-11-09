import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Merges definitions and resolves symbol identities for one library link.
final class LinkUnit(
  final Target target,
  Iterable<ObjectModule> input,
  final String name,
) {
  late final Uint8List code;
  final symbols = <Symbol>[];
  final _references = <(Fixup, int)>[];

  this {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name');
    }
    final objects = input.toList();
    if (objects.isEmpty || objects.any((object) => object.target != target)) {
      throw ArgumentError('Expected non-empty modules for $target.');
    }
    final bytes = BytesBuilder(copy: false);
    final bases = <int>[], globals = <String, int>{};
    for (final object in objects) {
      bytes.add(Uint8List((-bytes.length) & 15));
      final base = bytes.length;
      bases.add(base);
      for (final symbol in object.symbols) {
        if (symbol.binding == .global) {
          if (globals.containsKey(symbol.name)) {
            throw ArgumentError('Duplicate global: ${symbol.name}');
          }
          globals[symbol.name] = base + symbol.offset;
        }
        symbols.add(
          .new(
            symbol.name,
            base + symbol.offset,
            symbol.size,
            binding: symbol.binding,
            exported: symbol.exported,
          ),
        );
      }
      bytes.add(object.code);
    }
    code = bytes.takeBytes();
    for (final (i, object) in objects.indexed) {
      for (final name in object.imports) {
        if (!globals.containsKey(name)) {
          throw ArgumentError('Undefined symbol: $name');
        }
      }
      for (final reference in object.relocations) {
        final destination = reference.symbol < object.symbols.length
            ? bases[i] + object.symbols[reference.symbol].offset
            : globals[object.imports[reference.symbol -
                  object.symbols.length]]!;
        _references.add((
          Fixup(bases[i] + reference.offset, reference.encoding),
          destination,
        ));
      }
    }
  }

  /// Copies and relocates code directly into the final image's owned buffer.
  void writeCode(ByteData image, int fileOffset, {required int address}) {
    RangeError.checkValueInInterval(
      fileOffset,
      0,
      image.lengthInBytes - code.length,
      'fileOffset',
    );
    if (address < 0 ||
        target.architecture == .arm64 &&
            (fileOffset % 4 != 0 || address % 4 != 0)) {
      throw ArgumentError('Invalid linked code placement.');
    }
    image.buffer
        .asUint8List(image.offsetInBytes + fileOffset, code.length)
        .setAll(0, code);
    for (final (fixup, destination) in _references) {
      fixup.encoding.apply(
        image,
        fileOffset + fixup.offset,
        placeAddress: address + fixup.offset,
        targetAddress: address + destination,
      );
    }
  }
}
