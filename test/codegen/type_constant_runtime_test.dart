import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  test('actual Dart subtype bodies consume source type constants through one shared representation', () {
    final runtime = heapRuntime.types!;
    final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
    final box = ClassType(null, 'Box', typeParameters: [parameter]);
    final declarations = [...runtime.program.classes, IrClass(box, [])];
    final owner = TypeImplementations(runtime: runtime);
    final layouts = ProgramLayout(
      declarations,
      nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      typeImplementations: owner,
    );
    final projection = owner.relations.projection;
    final cases = <(ValueType, ValueType, bool)>[
      (ValueType.integer, ValueType.number, true),
      (ValueType.number, ValueType.integer, false),
      (
        box.instantiate([ValueType.integer]),
        box.instantiate([ValueType.number]),
        true,
      ),
      (
        box.instantiate([ValueType.number]),
        box.instantiate([ValueType.integer]),
        false,
      ),
    ];
    final roots = <IrFunction>[];
    for (final (index, (left, right, _)) in cases.indexed) {
      final block = Block();
      final source = block.emit(
        UncheckedCast(TypeConstant(left), TypeMetadata.type),
      );
      final target = block.emit(
        UncheckedCast(TypeConstant(right), TypeMetadata.type),
      );
      block.finish(
        Return(
          block.emit(DirectCall(runtime.entry(.typeSubtype), [source, target])),
        ),
      );
      roots.add(
        IrFunction(FunctionTarget(null, 'check.$index', .boolean, []), [block]),
      );
    }
    final program = IrProgram(
      declarations,
      [...runtime.program.functions, ...owner.functions, ...roots],
      globals: runtime.program.globals,
      externals: runtime.program.externals.where(
        (body) => body.target != projection.target,
      ),
    );
    final interpreter = IrInterpreter(program, {}, typeLayout: layouts);
    for (final (index, (_, _, expected)) in cases.indexed) {
      expect(interpreter.run(roots[index], []), expected);
    }
  });
}
