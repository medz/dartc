import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
      test('$target preserves symbol order within each binding', () {
        final symbols = [
          for (var i = 0; i < 80; i++)
            Symbol(
              'symbol$i',
              0,
              i * 8,
              8,
              kind: .data,
              binding: i.isEven ? .global : .local,
            ),
        ];
        final module = ObjectModule(target, [
          Section.data(Uint8List(640)),
        ], symbols);
        final bytes = format.encodeObject(module);
        final decoded = format.decodeObject(bytes);
        expect(decoded.symbols.map((s) => s.name), [
          for (final binding in SymbolBinding.values)
            for (final symbol in symbols)
              if (symbol.binding == binding) symbol.name,
        ]);
        expect(format.encodeObject(decoded), bytes);
      });
    }
  }
}
