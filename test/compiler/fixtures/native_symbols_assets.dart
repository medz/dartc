import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

final nativeSymbols = {
  'native-symbols': {
    for (final name in [
      'integer',
      'floating',
      'pointer',
      'pair',
      'boolean',
      'read_only',
      'add',
    ])
      name: name,
  },
};

ObjectModule nativeSymbolsProvider(Target target) {
  final code = target.architecture == .arm64
      ? (arm.Assembler()
              ..addImmediate(.x0, .x0, 3)
              ..ret())
            .finish()
      : (x64.Assembler()
              ..move(.rax, .rdi)
              ..addImmediate(.rax, 3)
              ..ret())
            .finish();
  return ObjectModule(
    target,
    [
      Section.code(code),
      Section.zeroFill(48, alignment: 8),
      Section.readOnlyData([42, 0, 0, 0, 0, 0, 0, 0], alignment: 8),
    ],
    [
      Symbol(target.nativeSymbol('add'), 0, 0, code.length, exported: true),
      for (final (name, offset, size) in [
        ('integer', 0, 8),
        ('floating', 8, 8),
        ('pointer', 16, 8),
        ('pair', 24, 16),
        ('boolean', 40, 8),
      ])
        Symbol(
          target.nativeSymbol(name),
          1,
          offset,
          size,
          kind: .data,
          exported: true,
        ),
      Symbol(
        target.nativeSymbol('read_only'),
        2,
        0,
        8,
        kind: .data,
        exported: true,
      ),
    ],
  );
}
