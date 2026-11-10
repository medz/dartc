import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final platform = Target(os, arch);
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
