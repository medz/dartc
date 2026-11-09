import 'dart:typed_data';

import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Builds tail-call entries paired with loader-initialized pointer slots.
ObjectModule callStubs(Target target, List<String> names) {
  final code = BytesBuilder(copy: false), symbols = <Symbol>[];
  final relocations = <Relocation>[];
  for (final (i, name) in names.indexed) {
    final start = code.length, slot = symbols.length + 1;
    if (target.architecture == .arm64) {
      final assembler = arm.Assembler();
      for (final fixup in [
        assembler.pageAddress(.x16),
        assembler.addPageOffset(.x16, .x16),
      ]) {
        relocations.add(.new(0, start + fixup.offset, fixup.encoding, slot));
      }
      assembler
        ..load(.x16, .x16, 0)
        ..branchRegister(.x16);
      code.add(assembler.finish());
    } else {
      final assembler = x64.Assembler();
      final fixup = assembler.address(.r11);
      relocations.add(.new(0, start + fixup.offset, fixup.encoding, slot));
      assembler
        ..load(.r11, .r11, 0)
        ..jumpRegister(.r11);
      code.add(assembler.finish());
    }
    symbols.addAll([
      Symbol(name, 0, start, code.length - start),
      Symbol(name, 1, i * 8, 8, kind: .data, binding: .local),
    ]);
  }
  return ObjectModule(
    target,
    [
      Section.code(code.takeBytes()),
      Section.data(Uint8List(names.length * 8), alignment: 8),
    ],
    symbols,
    relocations: relocations,
  );
}
