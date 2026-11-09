import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

List<ObjectModule> dataModules(Target target) {
  Uint8List words(List<int> values) {
    final data = ByteData(values.length * 8);
    for (final (i, value) in values.indexed) {
      data.setInt64(i * 8, value, .little);
    }
    return data.buffer.asUint8List();
  }

  final storage = ObjectModule(
    target,
    [
      Section.readOnlyData(words([111, 37]), alignment: 32),
      Section.data(words([0, 5]), alignment: 64),
      Section.zeroFill(0x20020, alignment: 32),
    ],
    [
      Symbol('private_data', 0, 0, 8, kind: .data, binding: .local),
      Symbol(target.nativeSymbol('constant'), 0, 8, 8, kind: .data),
      Symbol(
        target.nativeSymbol('state'),
        1,
        8,
        8,
        kind: .data,
        exported: true,
      ),
      Symbol(
        target.nativeSymbol('counter'),
        2,
        0x10008,
        8,
        kind: .data,
        exported: true,
      ),
    ],
  );
  final code = <int>[], symbols = <Symbol>[], references = <Relocation>[];
  for (final (name, symbol, write) in [
    ('read_constant', 5, false),
    ('update_state', 6, true),
    ('update_counter', 7, true),
    ('read_local', 4, false),
  ]) {
    final List<Fixup> fixups;
    final List<int> body;
    if (target.architecture == .arm64) {
      final assembler = arm.Assembler();
      fixups = [assembler.pageAddress(.x9), assembler.addPageOffset(.x9, .x9)];
      assembler.load(.x10, .x9, 0);
      if (write) {
        assembler
          ..add(.x0, .x10, .x0)
          ..store(.x0, .x9, 0);
      } else {
        assembler.move(.x0, .x10);
      }
      assembler.ret();
      body = assembler.finish();
    } else {
      final assembler = x64.Assembler();
      fixups = [assembler.address(.r10)];
      assembler.load(.rax, .r10, 0);
      if (write) {
        assembler
          ..add(.rax, .rdi)
          ..store(.rax, .r10, 0);
      }
      assembler.ret();
      body = assembler.finish();
    }
    for (final fixup in fixups) {
      references.add(
        Relocation.instruction(
          0,
          code.length + fixup.offset,
          fixup.encoding,
          symbol,
        ),
      );
    }
    symbols.add(
      Symbol(
        target.nativeSymbol(name),
        0,
        code.length,
        body.length,
        exported: true,
      ),
    );
    code.addAll(body);
  }
  symbols.add(
    const Symbol('private_data', 1, 0, 8, kind: .data, binding: .local),
  );
  return [
    storage,
    ObjectModule(
      target,
      [
        Section.code(code),
        Section.readOnlyData(words([17]), alignment: 8),
      ],
      symbols,
      imports: [
        for (final name in ['constant', 'state', 'counter'])
          target.nativeSymbol(name),
      ],
      relocations: references,
    ),
  ];
}
