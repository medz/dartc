import 'dart:ffi';

import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test(
      '${generator.target} keeps reified arguments out of source and FFI signatures',
      () {
        final parameter = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final target = FunctionTarget(
          .parse('memory:type-arguments'),
          'generic',
          .integer,
          [],
          typeParameters: [parameter],
        );
        final entry = Block()..emit(ReifyType(parameter));
        entry.finish(Return(const Constant.integer(1)));
        final program = IrProgram([], [
          IrFunction(target, [entry]),
        ]);
        expect(
          generator
              .generate(
                Compiler(generator.target)
                    .prepare(program, runtime: heapRuntime, roots: [target]),
              )
              .sections,
          isNotEmpty,
        );
        expect(entry.parameters, isEmpty);
        expect(target.parameterTypes, isEmpty);
        expect(
          () => generator.generate(
            Compiler(generator.target).prepare(
              program,
              runtime: heapRuntime,
              roots: [target],
              exports: {
                target: NativeExport('generic', NativeSignature(Int64, [])),
              },
            ),
          ),
          throwsArgumentError,
        );
      },
    );
  }

  test(
    'incoming stack accesses expand offsets beyond one load instruction',
    () {
      final generator = Arm64CodeGenerator(const Target(.linux, .arm64));
      final sizes = <int>[];
      for (final count in [4102, 4103]) {
        final target = FunctionTarget(
          .parse('memory:stack-limit'),
          'last',
          .integer,
          List.filled(count, .integer),
        );
        final entry = Block(target.parameterTypes);
        entry.finish(Return(entry.parameters.last));
        final program = IrProgram([], [
          IrFunction(target, [entry]),
        ]);
        sizes.add(
          generator
              .generate(
                Compiler(generator.target)
                    .prepare(program, runtime: heapRuntime, roots: [target]),
              )
              .sections
              .single
              .bytes
              .length,
        );
      }
      expect(sizes.first, isPositive);
      expect(sizes.last, greaterThan(sizes.first));
    },
  );
}
