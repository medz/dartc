import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native context bindings lower through ordinary callees on all targets',
    () {
      final reader = FunctionTarget(null, 'readContext', .integer, []);
      final readBody = Block();
      readBody.finish(Return(readBody.emit(ReadNativeContext())));
      final inner = FunctionTarget(null, 'innerContext', .integer, [.integer]);
      final innerBody = Block(inner.parameterTypes);
      innerBody.emit(BindNativeContext(innerBody.parameters.single));
      innerBody.finish(Return(innerBody.emit(DirectCall(reader, []))));
      final outer = FunctionTarget(null, 'outerContext', .integer, [
        .integer,
        .integer,
      ]);
      final outerBody = Block(outer.parameterTypes);
      outerBody.emit(BindNativeContext(outerBody.parameters.first));
      final returned = outerBody.emit(
        DirectCall(inner, [outerBody.parameters.last]),
      );
      final current = outerBody.emit(ReadNativeContext());
      outerBody.finish(
        Return(outerBody.emit(IntBinary(.add, returned, current))),
      );
      final program = IrProgram([], [
        IrFunction(reader, [readBody]),
        IrFunction(inner, [innerBody]),
        IrFunction(outer, [outerBody]),
      ]);
      for (final os in OperatingSystem.values) {
        for (final CodeGenerator generator in [
          Arm64CodeGenerator(Target(os, .arm64)),
          X64CodeGenerator(Target(os, .x64)),
        ]) {
          final module = generator.generate(
            Compiler(generator.target).prepare(program, roots: [outer]),
          );
          expect(module.imports, isEmpty);
          expect(
            module.symbols.map((symbol) => symbol.name),
            containsAll(['outerContext', 'innerContext']),
          );
        }
      }
    },
  );
}
