import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

const ioSymbols = {
  'dartc:posix': {
    'dartc_posix_write': 'dartc_posix_write',
    'dartc_posix_errno': 'dartc_posix_errno',
  },
  'io:test': {'state': 'io_state_address'},
};

ObjectModule ioStorage(Target target) {
  final List<int> code;
  final List<Fixup> fixups;
  if (target.architecture == .arm64) {
    final assembler = arm.Assembler();
    fixups = [assembler.pageAddress(.x0), assembler.addPageOffset(.x0, .x0)];
    assembler.ret();
    code = assembler.finish();
  } else {
    final assembler = x64.Assembler();
    fixups = [assembler.address(.rax)];
    assembler.ret();
    code = assembler.finish();
  }
  return ObjectModule(
    target,
    [Section.code(code), Section.zeroFill(256, alignment: 8)],
    [
      Symbol(target.nativeSymbol('io_state_address'), 0, 0, code.length),
      Symbol(
        target.nativeSymbol('io_bytes'),
        1,
        0,
        128,
        kind: .data,
        exported: true,
      ),
      Symbol(
        target.nativeSymbol('io_state'),
        1,
        128,
        64,
        kind: .data,
        exported: true,
      ),
    ],
    relocations: [
      for (final fixup in fixups)
        Relocation(0, fixup.offset, fixup.encoding, 2),
    ],
  );
}
