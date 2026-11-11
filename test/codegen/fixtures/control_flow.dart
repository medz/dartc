import 'dart:ffi';

import 'package:dartc/object.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

IrProgram controlFlowGraphs() {
  final functions = <IrFunction>[];
  final uri = Uri.parse('memory:control_flow');
  final selection = FunctionTarget(uri, 'same_target', .integer, [
    .integer,
    .integer,
  ]);
  final entry = Block(selection.parameterTypes),
      join = Block([.integer, .integer]);
  final a = entry.parameters[0], b = entry.parameters[1];
  final condition = entry.emit(IntBinary(.lessThan, a, b));
  entry.finish(Branch(condition, Jump(join, [a, b]), Jump(join, [b, a])));
  join.finish(
    Return(
      join.emit(IntBinary(.subtract, join.parameters[0], join.parameters[1])),
    ),
  );
  functions.add(IrFunction(selection, [entry, join]));

  final scrambled = FunctionTarget(uri, 'scrambled', .integer, [.integer]);
  final start = Block(scrambled.parameterTypes),
      middle = Block(),
      left = Block(),
      right = Block(),
      end = Block();
  start.finish(Jump(middle));
  final value = middle.emit(
    IntBinary(.add, start.parameters.single, const Constant.integer(7)),
  );
  final positive = middle.emit(
    IntBinary(.greaterThan, value, const Constant.integer(0)),
  );
  middle.finish(Branch(positive, Jump(left), Jump(right)));
  left.finish(Jump(end));
  right.finish(Jump(end));
  end.finish(Return(end.emit(IntBinary(.add, value, start.parameters.single))));
  functions.add(IrFunction(scrambled, [start, end, right, left, middle]));

  final pressure = FunctionTarget(
    uri,
    'unused_result',
    .integer,
    List.filled(6, .integer),
  );
  final body = Block(pressure.parameterTypes);
  const constants = [
    Constant.integer(1),
    Constant.integer(2),
    Constant.integer(3),
  ];
  for (final constant in constants) {
    body.emit(IntBinary(.add, body.parameters.first, constant));
  }
  for (final parameter in body.parameters) {
    for (final constant in constants) {
      body.emit(IntBinary(.add, parameter, constant));
    }
  }
  body.finish(Return(body.parameters.first));
  functions.add(IrFunction(pressure, [body]));

  final dropped = FunctionTarget(uri, 'dropped_arguments', .integer, [
    .integer,
    .integer,
  ]);
  final from = Block(dropped.parameterTypes),
      to = Block([.integer, .object, .floating, .integer]);
  final pointer = from.emit(
    PointerFromAddress(
      from.parameters.first,
      FfiTypes.resolve(
        NativePointerType(NativeFunctionType(NativeSignature(Int64, [Int64]))),
      ),
    ),
  );
  final effect = from.emit(NativeCall(pointer, [from.parameters.last]));
  from.finish(
    Jump(to, [
      effect,
      const Constant.string('unused'),
      const Constant.floating(-0.0),
      from.parameters.last,
    ]),
  );
  to.finish(Return(to.parameters.last));
  functions.add(IrFunction(dropped, [from, to]));

  final forever = FunctionTarget(uri, 'forever', .integer, []);
  final initial = Block(), loop = Block();
  initial.finish(Jump(loop));
  loop.finish(Jump(loop));
  functions.add(IrFunction(forever, [initial, loop]));
  return IrProgram([], functions);
}

ObjectModule controlFlow(Target target) {
  final program = controlFlowGraphs();
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    runtime: heapRuntime,
    definitions: program.functions.map((f) => f.target),
    exports: {
      for (final function in program.functions)
        if (function.target.name != 'forever')
          function.target: NativeExport(
            function.target.name,
            NativeSignature(
              Int64,
              List.filled(function.target.parameterTypes.length, Int64),
            ),
          ),
    },
  );
}
