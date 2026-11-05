import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test('nongeneric instantiation preserves immutable signature and shape', () {
    final nested = FunctionType(.integer, [.string]);
    final named = FunctionType(
      nested,
      [.integer, .string],
      namedParameters: {'name': true},
    );
    final optional = FunctionType(.integer, [.integer], optionalPositional: 1);
    expect(named.instantiate([]), same(named));
    expect(named.instantiateToBounds(), same(named));
    expect(named.instantiate([]).result, same(nested));
    expect(named.instantiate([]).named, {'name': (slot: 1, required: true)});
    expect(named.instantiate([]).requiredPositional, 1);
    expect(optional.instantiate([]), same(optional));
    expect(optional.instantiate([]).requiredPositional, 0);
    expect(() => named.instantiate([ValueType.integer]), throwsArgumentError);
    expect(
      () => named.instantiate([CellType(ValueType.integer)]),
      throwsArgumentError,
    );
    expect(
      () => named.parameters.add(ValueType.integer),
      throwsUnsupportedError,
    );
    expect(() => named.named.clear(), throwsUnsupportedError);
  });

  test(
    'generic instantiation retains arity, internal type and bound checks',
    () {
      final t = TypeParameterType('T')..initializeBound(ValueType.number);
      final generic = FunctionType(t, [t], typeParameters: [t]);
      expect(() => generic.instantiate([]), throwsArgumentError);
      expect(
        () => generic.instantiate([CellType(ValueType.integer)]),
        throwsArgumentError,
      );
      expect(
        () => generic.instantiate([ValueType.string]),
        throwsArgumentError,
      );
      final applied = generic.instantiate([ValueType.integer]);
      expect(applied, isNot(same(generic)));
      expect(applied.result, ValueType.integer);
      expect(applied.parameters, [ValueType.integer]);
      expect(applied.typeParameters, isEmpty);
      expect(t.bound, ValueType.number);
    },
  );

  test('rebinding freshens even closed method binders and keeps defaults', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.number)
      ..initializeDefaultType(ValueType.integer);
    final source = FunctionType(t, [t], typeParameters: [t]);
    expect(substituteType(source, const {}), same(source));
    final rebound = rebindFunctionType(source, const {});
    final fresh = rebound.typeParameters.single;
    expect(fresh, isNot(same(t)));
    expect(fresh.bound, ValueType.number);
    expect(fresh.defaultType, ValueType.integer);
    expect(rebound.result, same(fresh));
    expect(rebound.parameters.single, same(fresh));
    expect(rebound.instantiateToBounds().result, ValueType.integer);
  });
  test('rebinding can override runtime defaults without changing bounds', () {
    final outer = TypeParameterType('T')..initializeBound(ValueType.number);
    final method = TypeParameterType('U')
      ..initializeBound(outer)
      ..initializeDefaultType(outer);
    final source = FunctionType(method, [method], typeParameters: [method]);
    final rebound = rebindFunctionType(
      source,
      {outer: ValueType.integer},
      defaultTemplates: [ValueType.number],
    );
    final fresh = rebound.typeParameters.single;
    expect(fresh.bound, ValueType.integer);
    expect(fresh.defaultType, ValueType.number);
    expect(method.bound, same(outer));
    expect(method.defaultType, same(outer));
    expect(rebound.instantiate([ValueType.integer]).result, ValueType.integer);
    expect(() => rebound.instantiateToBounds(), throwsArgumentError);
    expect(
      () => rebindFunctionType(source, const {}, defaultTemplates: []),
      throwsArgumentError,
    );
  });
}
