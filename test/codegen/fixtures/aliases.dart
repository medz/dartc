import 'dart:ffi';

import 'package:dartc/object.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

IrProgram arithmetic() {
  final functions = <IrFunction>[];
  for (final op in [IntOperator.add, IntOperator.subtract]) {
    final target = FunctionTarget(
      .parse('memory:arithmetic'),
      op == .add ? 'alias_add' : 'alias_subtract',
      .integer,
      [.integer, .integer],
    );
    final block = Block(target.parameterTypes);
    final result = block.emit(
      IntBinary(op, block.parameters[0], block.parameters[1]),
    );
    block.finish(Return(result));
    functions.add(.new(target, [block]));
  }
  return .new([], functions);
}

ObjectModule aliases(Target target) {
  final CodeGenerator generator = switch (target.architecture) {
    .arm64 => Arm64CodeGenerator(target),
    .x64 => X64CodeGenerator(target),
  };
  final program = arithmetic();
  return generator.generate(
    program,
    heapCapacity: heapCapacity,
    definitions: program.functions.map((f) => f.target),
    exports: {
      for (final f in program.functions)
        f.target: NativeExport(
          f.target.name,
          NativeSignature(
            Int64,
            List.filled(f.target.parameterTypes.length, Int64),
          ),
        ),
    },
  );
}
