import 'package:dartc/compiler.dart';
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
      Compiler(const Target(.linux, .arm64))
          .prepare(program, roots: [target], runtime: heapRuntime),
    );
    expect(module.symbols.map((symbol) => symbol.name), contains('_isSubtype'));
  });

  test('type operations bind to the checked Dart bodies and constructors', () {
    final runtime = heapRuntime.types!;
    final values = TypeValues(runtime);
    for (final entry in runtime.entries) {
      expect(runtime.program.implementationOf(entry), isA<IrFunction>());
    }
    final block = Block();
    final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
    final type = values.build(block, ValueType.futureOr(parameter), {
      parameter: values.constant(.integer),
    });
    expect((type as DirectCall).target, same(values.entry(.typeFutureOr)));
  });

  test('inherited argument reads reuse metadata without allocation', () {
    final uri = Uri.parse('memory:argument-projection');
    final a = TypeParameterType('A')..initializeBound(.object.nullable);
    final b = TypeParameterType('B')..initializeBound(.object.nullable);
    final base = ClassType(uri, 'Base', typeParameters: [a, b]);
    final x = TypeParameterType('X')..initializeBound(.object.nullable);
    final y = TypeParameterType('Y')..initializeBound(.object.nullable);
    final child = ClassType(
      uri,
      'Child',
      typeParameters: [x, y],
      superclass: base.instantiate([y, x]),
    );
    final relations = TypeRelations(TypeValues(), [child]);
    final target = relations.argumentOf(base, 0);
    final body = relations.functions.singleWhere(
      (body) => body.target == target,
    );
    expect(
      body.blocks.expand((block) => block.instructions).whereType<Construct>(),
      isEmpty,
    );
    expect(body.callees, isEmpty);
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
    final target = relations.viewOf(base);
    final projection = relations.projection;
    final view = relations.functions.singleWhere(
      (body) => body.target == target,
    );
    final calls = view.blocks
        .expand((b) => b.instructions)
        .whereType<DirectCall>()
        .map((call) => call.target)
        .toSet();
    expect(
      calls,
      containsAll([values.entry(.typeNullable), values.entry(.typeShift)]),
    );
    expect(projection.target, same(heapRuntime.types!.projection));
    expect(
      view.blocks
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
