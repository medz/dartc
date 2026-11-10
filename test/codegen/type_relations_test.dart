import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/type_relations.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('type argument equality compares every element and list length', () {
    final values = TypeValues();
    final cases = <(List<ValueType>, List<ValueType>, bool)>[
      ([], [], true),
      ([.integer], [.integer], true),
      ([.integer], [.number], false),
      ([], [.integer], false),
      ([.integer], [], false),
      ([.integer, .number], [.integer], false),
    ];
    final functions = <IrFunction>[];
    for (final (a, b, _) in cases) {
      final target = FunctionTarget(
        Uri.parse('memory:arguments'),
        'compare${functions.length}',
        .boolean,
        [],
      );
      final entry = Block();
      entry.finish(
        Return(
          entry.emit(
            DirectCall(values.argumentEquality, [
              values.argumentConstants(a),
              values.argumentConstants(b),
            ]),
          ),
        ),
      );
      functions.add(IrFunction(target, [entry]));
    }
    final interpreter = IrInterpreter(
      IrProgram(values.classes, [...functions, ...values.functions]),
      {},
    );
    for (final (i, (_, _, expected)) in cases.indexed) {
      expect(interpreter.run(functions[i], []), expected);
    }
  });
  test(
    'class projection substitutes reordered and nested actual arguments',
    () {
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
      final v = parameter('V');
      final expected = base.instantiate([
        ValueType.boolean.nullable,
        FunctionType(.integer, [v], typeParameters: [v]),
      ]);
      final values = TypeValues();
      final projection = TypeRelations(values, [base, child]);
      final target = FunctionTarget(uri, 'project', .boolean, []);
      final entry = Block();
      final view = entry.emit(
        DirectCall(projection.viewOf(base), [
          values.constant(child.instantiate([.integer, .boolean])),
        ]),
      );
      entry.finish(
        Return(
          entry.emit(
            DirectCall(values.equality, [
              entry.emit(NullCheck(view)),
              values.constant(expected),
            ]),
          ),
        ),
      );
      final function = IrFunction(target, [entry]);
      final projected = projection.functions.toList();
      final program = IrProgram(
        [...values.classes, ...projection.classes],
        [function, ...projected, ...values.functions],
      );
      expect(IrInterpreter(program, {}).run(function, []), isTrue);
    },
  );
  test(
    'runtime subtype rules preserve unions, variance and lexical bounds',
    () {
      final uri = Uri.parse('memory:subtypes');
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final box = ClassType(uri, 'Box', typeParameters: [t]);
      final p = TypeParameterType('P')
        ..initializeBound(ValueType.object.nullable);
      final projected = ClassType(
        uri,
        'Projected',
        typeParameters: [p],
        superclass: box.instantiate([p.nullable]),
      );
      final q = TypeParameterType('Q')
        ..initializeBound(ValueType.object.nullable);
      final u = TypeParameterType('U')
        ..initializeBound(ValueType.object.nullable);
      final shaped = ClassType(
        uri,
        'Shaped',
        typeParameters: [q],
        superclass: box.instantiate([
          FunctionType(q, [u], typeParameters: [u]),
        ]),
      );
      FunctionType generic(
        ValueType Function(TypeParameterType) bound,
        ValueType Function(TypeParameterType) result,
      ) {
        final x = TypeParameterType('X');
        x.initializeBound(bound(x));
        return FunctionType(result(x), [], typeParameters: [x]);
      }

      final cases = <ValueType>[
        .dynamicType,
        .voidType,
        .object.nullable,
        .object,
        .never,
        .nullType,
        .integer,
        .number,
        .floating,
        .boolean,
        ValueType.integer.nullable,
        ValueType.futureOr(.integer),
        ValueType.futureOr(ValueType.integer.nullable),
        ValueType.future.instantiate([.integer]),
        .function,
        .record,
        box.instantiate([.integer]),
        box.instantiate([.number]),
        box.instantiate([ValueType.integer.nullable]),
        projected.instantiate([.integer]),
        RecordType([.integer], {'flag': .boolean}),
        RecordType([.number], {'flag': .object}),
        RecordType([.integer], {'other': .boolean}),
        FunctionType(.integer, [.number]),
        FunctionType(.number, [.integer]),
        FunctionType(.integer, [.number, .boolean], optionalPositional: 1),
        FunctionType(.integer, [.number], namedParameters: {'value': false}),
        FunctionType(.number, [.integer], namedParameters: {'value': true}),
        FunctionType(
          .integer,
          [.number, .boolean],
          namedParameters: {'value': false, 'flag': false},
        ),
        generic((_) => .number, (x) => x),
        generic((_) => .number, (_) => .number),
        generic((_) => .number, (_) => .integer),
        generic((x) => ValueType.futureOr(x), (x) => x),
        generic((x) => ValueType.futureOr(x), (_) => .object),
        generic((x) => ValueType.futureOr(x), (_) => ValueType.object.nullable),
        generic(
          (_) => ValueType.object.nullable,
          (x) => shaped.instantiate([x]),
        ),
        generic((_) => ValueType.object.nullable, (x) {
          final y = TypeParameterType('Y')
            ..initializeBound(ValueType.object.nullable);
          return box.instantiate([
            FunctionType(x, [y], typeParameters: [y]),
          ]);
        }),
      ];
      final values = TypeValues();
      final relations = TypeRelations(values, [box, projected, shaped]);
      final functions = <IrFunction>[];
      for (final source in cases) {
        for (final target in cases) {
          final declaration = FunctionTarget(
            uri,
            'check${functions.length}',
            .boolean,
            [],
          );
          final body = Block();
          body.finish(
            Return(
              body.emit(
                DirectCall(relations.test, [
                  values.constant(source),
                  values.constant(target),
                ]),
              ),
            ),
          );
          functions.add(IrFunction(declaration, [body]));
        }
      }
      final rules = relations.functions.toList();
      final program = IrProgram(
        [...values.classes, ...relations.classes],
        [...functions, ...rules, ...values.functions],
      );
      final interpreter = IrInterpreter(program, {});
      var index = 0;
      for (final source in cases) {
        for (final target in cases) {
          expect(
            interpreter.run(functions[index++], []),
            target.accepts(source),
            reason: '${source.dartName} <: ${target.dartName}',
          );
        }
      }
    },
  );
}
