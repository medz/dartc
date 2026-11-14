import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

List<ObjectModule> stackCalls(Target target) {
  final declaration = FunctionTarget(
    .parse('memory:stack-calls'),
    'stack_value',
    .integer,
    List.filled(10, .integer),
  );
  final entry = Block(declaration.parameterTypes);
  Value result = entry.parameters.first;
  for (final parameter in entry.parameters.skip(1)) {
    result = entry.emit(
      IntBinary(.add, entry.emit(IntBinary(.add, result, result)), parameter),
    );
  }
  entry.finish(Return(result));
  final program = IrProgram([], [
    IrFunction(declaration, [entry]),
  ]);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  final callee = generator.generate(
    Compiler(generator.target).prepare(
      program,
      roots: [declaration],
      exports: {
        declaration: NativeExport(
          'stack_value',
          .new(Int64, List.filled(10, Int64)),
        ),
      },
    ),
  );

  final List<int> code;
  final Fixup call;
  if (target.architecture == .arm64) {
    final abi = Arm64Abi(target), assembler = arm.Assembler();
    final layout = abi.classify(.new(Int64, List.filled(10, Int64)));
    final frame = abi.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: layout.stackBytes,
    );
    abi.emitPrologue(assembler, frame);
    for (final argument in layout.parameters.whereType<StackArgument>()) {
      assembler
        ..load(.x9, .sp, frame.incomingStackOffset + argument.offset)
        ..store(.x9, .sp, argument.offset);
    }
    call = assembler.call();
    abi.emitEpilogue(assembler, frame);
    code = assembler.finish();
  } else {
    final abi = X64Abi(target), assembler = x64.Assembler();
    final layout = abi.classify(.new(Int64, List.filled(10, Int64)));
    final frame = abi.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: layout.stackBytes,
    );
    abi.emitPrologue(assembler, frame);
    for (final argument in layout.parameters.whereType<StackArgument>()) {
      assembler
        ..load(.r10, .rsp, frame.incomingStackOffset + argument.offset)
        ..store(.r10, .rsp, argument.offset);
    }
    call = assembler.call();
    abi.emitEpilogue(assembler, frame);
    code = assembler.finish();
  }
  return [
    ObjectModule(
      target,
      [Section.code(code)],
      [
        Symbol(
          target.nativeSymbol('stack_forward'),
          0,
          0,
          code.length,
          exported: true,
        ),
      ],
      imports: [callee.symbols.single.name],
      relocations: [Relocation.instruction(0, call.offset, call.encoding, 1)],
    ),
    callee,
  ];
}
