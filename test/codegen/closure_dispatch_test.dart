import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final platform = Target(os, arch);
      test(
        '$platform preserves pointer references in wider function results',
        () {
          final uri = Uri.parse('memory:pointer-result');
          final pointer = FfiTypes.pointer.instantiate([FfiTypes.int64]);
          final source = FunctionTarget(uri, 'pointer', pointer, []);
          final sourceEntry = Block();
          sourceEntry.finish(
            Return(
              sourceEntry.emit(
                PointerFromAddress(const Constant.integer(16), pointer),
              ),
            ),
          );
          final caller = FunctionTarget(uri, 'widen', .object.nullable, []);
          final entry = Block();
          final view = entry.emit(
            TypeView(
              FunctionConstant(source),
              FunctionType(.object.nullable, []),
            ),
          );
          entry.finish(Return(entry.emit(FunctionCall(view, []))));
          final program = IrProgram([], [
            IrFunction(source, [sourceEntry]),
            IrFunction(caller, [entry]),
          ]);
          final CodeGenerator generator = arch == .arm64
              ? Arm64CodeGenerator(platform)
              : X64CodeGenerator(platform);
          expect(
            () => generator.generate(
              program,
              runtime: heapRuntime,
              definitions: program.reachableFrom([caller]),
            ),
            returnsNormally,
          );
        },
      );

      test(
        '$platform hashes function constants without managed allocation',
        () {
          final uri = Uri.parse('memory:function-hash');
          final function = FunctionTarget(uri, 'function', .integer, []);
          final hash = FunctionTarget(uri, 'hash', .integer, []);
          final entry = Block()..finish(const Return(Constant.integer(7)));
          final hashing = Block();
          hashing.finish(
            Return(hashing.emit(ObjectHashCode(FunctionConstant(function)))),
          );
          final program = IrProgram([], [
            IrFunction(function, [entry]),
            IrFunction(hash, [hashing]),
          ]);
          final CodeGenerator generator = arch == .arm64
              ? Arm64CodeGenerator(platform)
              : X64CodeGenerator(platform);
          expect(
            generator
                .generate(
                  program,
                  runtime: heapRuntime,
                  definitions: program.reachableFrom([hash]),
                )
                .sections,
            isNotEmpty,
          );
        },
      );
      test('$platform excludes unrelated open closure signatures', () {
        for (final genericView in [false, true]) {
          for (final unrelatedResult in [
            ValueType.voidType,
            ValueType.floating,
          ]) {
            final uri = Uri.parse('memory:closure-dispatch');
            final t = TypeParameterType('T')
              ..initializeBound(ValueType.object.nullable);
            final argument = genericView ? t : ValueType.integer;
            final outer = FunctionTarget(
              uri,
              'outer',
              .integer,
              [argument],
              typeParameters: [t],
            );
            final good = FunctionTarget(
              uri,
              'good',
              .integer,
              [argument],
              kind: .closure,
              enclosing: outer,
              sourceOffset: 0,
            );
            final unrelated = FunctionTarget(
              uri,
              'unrelated',
              unrelatedResult,
              [t],
              kind: .closure,
              enclosing: outer,
              sourceOffset: 1,
            );
            final entry = Block(outer.parameterTypes);
            final function = entry.emit(MakeClosure(good, []));
            entry.emit(MakeClosure(unrelated, []));
            entry.finish(
              Return(entry.emit(FunctionCall(function, entry.parameters))),
            );
            final goodEntry = Block(good.parameterTypes)
              ..finish(const Return(Constant.integer(7)));
            final otherEntry = Block(unrelated.parameterTypes)
              ..finish(
                unrelatedResult == .voidType
                    ? const Return()
                    : const Return(Constant.floating(1.5)),
              );
            final program = IrProgram([], [
              IrFunction(outer, [entry]),
              IrFunction(good, [goodEntry]),
              IrFunction(unrelated, [otherEntry]),
            ]);
            final CodeGenerator generator = arch == .arm64
                ? Arm64CodeGenerator(platform)
                : X64CodeGenerator(platform);
            expect(
              generator
                  .generate(
                    program,
                    runtime: heapRuntime,
                    definitions: program.reachableFrom([outer]),
                  )
                  .sections,
              isNotEmpty,
            );
          }
        }
      });
    }
  }
}
