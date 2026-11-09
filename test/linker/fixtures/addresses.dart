import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import 'calls.dart';
import 'functions.dart';

List<ObjectModule> addressModules(Target target) {
  final function = functions(target, {'dartc_address_function': 42});
  final provider = ObjectModule(
    target,
    [
      ...function.sections,
      Section.readOnlyData([37, 0, 0, 0, 0, 0, 0, 0], alignment: 8),
      Section.data([7, 0, 0, 0, 0, 0, 0, 0], alignment: 8),
      Section.zeroFill(0x10008, alignment: 16),
    ],
    [
      ...function.symbols,
      for (final (i, name) in ['constant', 'state', 'zero'].indexed)
        Symbol(
          target.nativeSymbol('dartc_address_$name'),
          i + 1,
          i == 2 ? 0x10000 : 0,
          8,
          kind: .data,
          exported: true,
        ),
    ],
  );
  final code = <int>[], symbols = <Symbol>[], references = <Relocation>[];
  const operations = [
    ('address_function', 0),
    ('address_constant', 1),
    ('address_state', 2),
    ('address_zero', 3),
    ('address_local', -1),
    ('read_state', 2),
    ('write_state', 2),
  ];
  for (final (name, symbol) in operations) {
    final List<Fixup> fixups;
    final List<int> body;
    if (target.architecture == .arm64) {
      final assembler = arm.Assembler();
      fixups = [assembler.pageAddress(.x9), assembler.loadPageOffset(.x9, .x9)];
      if (name == 'write_state') assembler.store(.x0, .x9, 0);
      if (name == 'read_state' || name == 'write_state') {
        assembler.load(.x0, .x9, 0);
      } else {
        assembler.move(.x0, .x9);
      }
      assembler.ret();
      body = assembler.finish();
    } else {
      final assembler = x64.Assembler();
      fixups = [assembler.loadAddress(.r10)];
      if (name == 'write_state') assembler.store(.rdi, .r10, 0);
      if (name == 'read_state' || name == 'write_state') {
        assembler.load(.rax, .r10, 0);
      } else {
        assembler.move(.rax, .r10);
      }
      assembler.ret();
      body = assembler.finish();
    }
    for (final fixup in fixups) {
      references.add(
        Relocation(
          0,
          code.length + fixup.offset,
          fixup.encoding,
          operations.length + 1 + symbol,
          indirect: true,
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
  symbols.add(const Symbol('local', 1, 0, 8, kind: .data, binding: .local));
  final caller = callModules(target).first;
  return [
    provider,
    ObjectModule(
      target,
      [
        Section.code(code),
        Section.data([17, 0, 0, 0, 0, 0, 0, 0], alignment: 8),
      ],
      symbols,
      imports: [
        for (final name in ['function', 'constant', 'state', 'zero'])
          target.nativeSymbol('dartc_address_$name'),
      ],
      relocations: references,
    ),
    ObjectModule(
      target,
      caller.sections,
      caller.symbols,
      imports: [function.symbols.single.name],
      relocations: caller.relocations,
    ),
  ];
}
