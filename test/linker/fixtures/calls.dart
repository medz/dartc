import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';
import 'package:dartc/assembler/x64.dart' as x64;

List<ObjectModule> callModules(Target target) => [
  for (final first in [true, false]) _module(target, first),
];

ObjectModule _module(Target target, bool first) {
  final List<int> wrapper, local;
  final Fixup fixup;
  if (target.architecture == .arm64) {
    final assembler = arm.Assembler(), abi = Arm64Abi(assembler);
    abi.enterFrame(0);
    fixup = assembler.call();
    abi.leaveFrame(0);
    abi.returnValue(.x0);
    wrapper = assembler.finish();
    final localAssembler = arm.Assembler()
      ..loadImmediate(.x0, first ? 99 : 42)
      ..ret();
    local = localAssembler.finish();
  } else {
    final assembler = x64.Assembler(), abi = X64Abi(assembler);
    abi.enterFrame(0);
    fixup = assembler.call();
    abi.leaveFrame(0);
    abi.returnValue(.rax);
    wrapper = assembler.finish();
    final localAssembler = x64.Assembler()
      ..loadImmediate(.rax, first ? 99 : 42)
      ..ret();
    local = localAssembler.finish();
  }
  return ObjectModule(
    target,
    [...wrapper, ...local],
    [
      Symbol(
        target.nativeSymbol(first ? 'forward' : 'helper'),
        0,
        wrapper.length,
        exported: first,
      ),
      Symbol('local', wrapper.length, local.length, binding: .local),
    ],
    imports: [if (first) target.nativeSymbol('helper')],
    relocations: [Relocation(fixup.offset, fixup.encoding, first ? 2 : 1)],
  );
}
