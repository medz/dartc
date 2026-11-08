import 'package:dartc/abi.dart';
import 'package:dartc/arm64.dart' as arm;
import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart' as x64;

List<ObjectModule> callModules(Target target) => [
  for (final first in [true, false]) _module(target, first),
];

ObjectModule _module(Target target, bool first) {
  final List<int> wrapper, local;
  final int offset;
  if (target.architecture == .arm64) {
    final assembler = arm.Assembler(), abi = Arm64Abi(assembler);
    abi.enterFrame(0);
    offset = assembler.length;
    assembler.call(0);
    abi.leaveFrame(0);
    abi.returnValue(.x0);
    wrapper = assembler.takeBytes();
    assembler
      ..loadImmediate(.x0, first ? 99 : 42)
      ..ret();
    local = assembler.takeBytes();
  } else {
    final assembler = x64.Assembler(), abi = X64Abi(assembler);
    abi.enterFrame(0);
    offset = assembler.length + 1;
    assembler.call(0);
    abi.leaveFrame(0);
    abi.returnValue(.rax);
    wrapper = assembler.takeBytes();
    assembler
      ..loadImmediate(.rax, first ? 99 : 42)
      ..ret();
    local = assembler.takeBytes();
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
    relocations: [
      Relocation(
        offset,
        target.architecture == .arm64 ? .arm64Call26 : .x64Call32,
        first ? 2 : 1,
      ),
    ],
  );
}
