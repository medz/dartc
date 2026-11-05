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
}
