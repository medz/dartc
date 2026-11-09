import 'dart:typed_data';

import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Builds pointer-slot definitions followed by tail-call entries using them.
ObjectModule linkageTable(Target target, int slots, Map<String, int> calls) {
  final code = BytesBuilder(copy: false);
  final symbols = [
    for (var i = 0; i < slots; i++)
      Symbol('slot$i', 1, i * 8, 8, kind: .data, binding: .local),
  ];
  final relocations = <Relocation>[];
  for (final MapEntry(key: name, value: slot) in calls.entries) {
    final start = code.length;
    if (target.architecture == .arm64) {
      final assembler = arm.Assembler();
      for (final fixup in [
        assembler.pageAddress(.x16),
        assembler.loadPageOffset(.x16, .x16),
      ]) {
        relocations.add(.new(0, start + fixup.offset, fixup.encoding, slot));
      }
      assembler.branchRegister(.x16);
      code.add(assembler.finish());
    } else {
      final assembler = x64.Assembler();
      final fixup = assembler.loadAddress(.r11);
      relocations.add(.new(0, start + fixup.offset, fixup.encoding, slot));
      assembler.jumpRegister(.r11);
      code.add(assembler.finish());
    }
    symbols.add(Symbol(name, 0, start, code.length - start));
  }
  return ObjectModule(
    target,
    [
      Section.code(code.takeBytes()),
      Section.data(Uint8List(slots * 8), alignment: 8),
    ],
    symbols,
    relocations: relocations,
  );
}
