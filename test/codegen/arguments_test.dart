import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
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
          generator.generate(program, definitions: [target]).sections,
          isNotEmpty,
        );
        expect(entry.parameters, isEmpty);
        expect(target.parameterTypes, isEmpty);
        expect(
          () => generator.generate(
            program,
            definitions: [target],
            exports: {
              target: NativeExport('generic', NativeSignature(Int64, [])),
            },
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      '${generator.target} rejects unresolved compound type instantiation',
      () {
        final parameter = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final target = FunctionTarget(
          .parse('memory:type-arguments'),
          'nullable',
          .typeType,
          [],
          typeParameters: [parameter],
        );
        final entry = Block();
        entry.finish(Return(entry.emit(ReifyType(parameter.nullable))));
        final program = IrProgram([], [
          IrFunction(target, [entry]),
        ]);
        expect(
          () => generator.generate(program, definitions: [target]),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'missing instantiation',
              contains('requires runtime instantiation'),
            ),
          ),
        );
      },
    );
  }

  test(
    'incoming stack accesses reject offsets beyond their machine encoding',
    () {
      final generator = Arm64CodeGenerator(const Target(.linux, .arm64));
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
        if (count == 4102) {
          expect(
            generator
                .generate(program, definitions: [target])
                .sections
                .single
                .bytes,
            isNotEmpty,
          );
        } else {
          expect(
            () => generator.generate(program, definitions: [target]),
            throwsRangeError,
          );
        }
      }
    },
  );
}
