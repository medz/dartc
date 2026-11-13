import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/type_relations.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  test('implicit metadata instances retain their source method bodies', () {
    final target = FunctionTarget(
      Uri.parse('memory:type-check'),
      'check',
      .boolean,
      [TypeMetadata.type, TypeMetadata.type],
    );
    final block = Block(target.parameterTypes);
    block.finish(
      Return(
        block.emit(
          DirectCall(heapRuntime.types!.entry(.typeSubtype), block.parameters),
        ),
      ),
    );
    final source = heapRuntime.program;
    final program = IrProgram(
      source.classes,
      [
        ...source.functions,
        IrFunction(target, [block]),
      ],
      globals: source.globals,
      externals: source.externals,
    );
    final module = Arm64CodeGenerator(const Target(.linux, .arm64)).generate(
      program,
      definitions: program.reachableFrom([target]),
      runtime: heapRuntime,
    );
    expect(module.symbols.map((symbol) => symbol.name), contains('_isSubtype'));
  });

  test('type operations bind to the checked Dart bodies and constructors', () {
    final runtime = heapRuntime.types!;
    final values = TypeValues(runtime);
    final relations = TypeRelations(values, const []);
    expect(relations.test, same(runtime.entry(.typeSubtype)));
    expect(values.equality, same(runtime.entry(.typeEquals)));
    expect(values.hash, same(runtime.entry(.typeHash)));
    expect(values.argumentEquality, same(runtime.entry(.typeArgumentsEqual)));
    expect(values.argumentHash, same(runtime.entry(.typeArgumentsHash)));
    for (final entry in runtime.entries) {
      expect(runtime.program.implementationOf(entry), isA<IrFunction>());
    }
    final block = Block();
    final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
    final type = values.build(block, ValueType.futureOr(parameter), {
      parameter: values.constant(.integer),
    });
    expect((type as DirectCall).target, same(values.entry(.typeFutureOr)));
    expect(values.functions, isEmpty);
    expect(relations.functions, isEmpty);
  });

  test('nominal projections use source normalization and lexical shifting', () {
    final uri = Uri.parse('memory:projection');
    TypeParameterType parameter(String name) =>
        TypeParameterType(name)..initializeBound(ValueType.object.nullable);
    final a = parameter('A'), b = parameter('B');
    final base = ClassType(uri, 'Base', typeParameters: [a, b]);
    final t = parameter('T'), u = parameter('U'), w = parameter('W');
    final child = ClassType(
      uri,
      'Child',
      typeParameters: [t, w],
      superclass: base.instantiate([
        w.nullable,
        FunctionType(t, [u], typeParameters: [u]),
      ]),
    );
    final values = TypeValues(heapRuntime.types);
    final relations = TypeRelations(values, [base, child]);
    relations.viewOf(base);
    final projection = relations.supertypes;
    final calls = projection.blocks
        .expand((b) => b.instructions)
        .whereType<DirectCall>()
        .map((call) => call.target)
        .toSet();
    expect(
      calls,
      containsAll([
        values.entry(.typeAt),
        values.entry(.typeNullable),
        values.entry(.typeShift),
      ]),
    );
    expect(projection.target, same(heapRuntime.types!.supertypes));
    expect(
      projection.blocks
          .expand((b) => b.instructions)
          .whereType<Construct>()
          .map((call) => call.initializer),
      everyElement(
        isIn([
          heapRuntime.types!.initializer(TypeMetadata.type),
          heapRuntime.types!.initializer(TypeMetadata.list),
        ]),
      ),
    );
  });
}
