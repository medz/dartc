import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Each owner writes a separate externally allocated marker on actual unload.
List<ObjectModule> finalizerModules(Target target) => [
  for (var owner = 0; owner < 2; owner++) _owner(target, owner),
];

ObjectModule _owner(Target target, int owner) {
  final List<int> body;
  final List<Fixup> fixups;
  if (target.architecture == .arm64) {
    final a = arm.Assembler();
    fixups = [a.pageAddress(.x9), a.addPageOffset(.x9, .x9)];
    a
      ..load(.x9, .x9, 0)
      ..load(.x10, .x9, 0)
      ..loadImmediate(.x11, 10)
      ..multiply(.x10, .x10, .x11)
      ..addImmediate(.x10, .x10, owner + 1)
      ..store(.x10, .x9, 0)
      ..ret();
    body = a.finish();
  } else {
    final a = x64.Assembler();
    fixups = [a.address(.r10)];
    a
      ..load(.r10, .r10, 0)
      ..load(.rax, .r10, 0)
      ..loadImmediate(.r11, 10)
      ..multiply(.rax, .r11)
      ..addImmediate(.rax, owner + 1)
      ..store(.rax, .r10, 0)
      ..ret();
    body = a.finish();
  }
  return ObjectModule(
    target,
    [
      Section.code(body),
      Section.zeroFill(8, alignment: 8),
      Section.finalizers(Uint8List(8)),
    ],
    [
      Symbol('cleanup', 0, 0, body.length, binding: .local),
      Symbol(
        target.nativeSymbol('marker_$owner'),
        1,
        0,
        8,
        kind: .data,
        exported: true,
      ),
    ],
    relocations: [
      for (final fixup in fixups)
        Relocation.instruction(0, fixup.offset, fixup.encoding, 1),
      const Relocation.address(2, 0, 0),
    ],
  );
}
