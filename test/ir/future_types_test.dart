import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final future = CoreTypes.futureOf;
  final either = ValueType.futureOr;
  TypeParameterType parameter(String name) =>
      TypeParameterType(name)..initializeBound(ValueType.object.nullable);

  test(
    'FutureOr normalizes special arguments but preserves union identity',
    () {
      for (final type in <ValueType>[
        .dynamicType,
        .voidType,
        .object,
        ValueType.object.nullable,
      ]) {
        expect(either(type), type);
        expect(either(type).hashCode, type.hashCode);
      }
      expect(either(.never), future(.never));
      expect(either(.nullType), future(.nullType).nullable);
      expect(either(ValueType.never.nullable), future(.nullType).nullable);
      final nested = either(future(.object));
      expect(nested, isNot(future(.object)));
      expect(nested.accepts(future(.object)), isTrue);
      expect(future(.object).accepts(nested), isTrue);
      expect(either(either(.integer)), isNot(either(.integer)));
      expect(either(either(.integer)).accepts(either(.integer)), isTrue);
      expect(either(.integer).accepts(either(either(.integer))), isFalse);
      expect(() => either(CellType(.integer)), throwsArgumentError);
      expect(CoreTypes.future.library, Uri.parse('dart:async'));
    },
  );

  test('outer nullability is distinct from a nullable value arm', () {
    final nullable = either(ValueType.integer.nullable);
    final outer = either(.integer).nullable;
    expect(nullable.mayBeNull, isTrue);
    expect(nullable.nullable, nullable);
    expect(nullable.nonNullable, nullable);
    expect(nullable, isNot(outer));
    expect(nullable.accepts(outer), isTrue);
    expect(outer.accepts(nullable), isFalse);
    expect(
      nullable.accepts(future(ValueType.integer.nullable).nullable),
      isTrue,
    );
    expect(
      nullable.nonNullable.accepts(future(ValueType.integer.nullable)),
      isTrue,
    );
    expect(outer.nonNullable, either(.integer));
    expect(either(.integer).mayBeNull, isFalse);
    expect(either(.integer).hasScalarEquality, isFalse);
    final t = parameter('T');
    expect(either(t).mayBeNull, isTrue);
    expect(either(t).accepts(.nullType), isFalse);
    expect(either(t).nullable, isNot(either(t)));
    expect(either(t.nullable).nullable, either(t.nullable));
    final value = Block([nullable]).parameters.single;
    final check = NullCheck(value);
    expect(check.type, nullable);
    expect(check.mayThrow, isTrue);
  });

  test(
    'substitution renormalizes unions and preserves nested Future arguments',
    () {
      final t = parameter('T');
      for (final type in <ValueType>[
        .never,
        .nullType,
        .object,
        .dynamicType,
        .voidType,
        ValueType.object.nullable,
        ValueType.integer.nullable,
        future(.integer),
      ]) {
        expect(substituteType(either(t), {t: type}), either(type));
        expect(
          substituteType(either(t).nullable, {t: type}),
          either(type).nullable,
        );
      }
      expect(
        substituteType(either(t).nonNullable, {t: ValueType.integer.nullable}),
        either(ValueType.integer.nullable),
      );
      expect(either(.number).accepts(either(.integer)), isTrue);
      expect(either(.integer).accepts(either(.number)), isFalse);
      expect(either(.integer).accepts(future(.integer)), isTrue);
      expect(either(.integer).accepts(future(.number)), isFalse);
      expect(ValueType.object.accepts(either(.integer)), isTrue);
      expect(
        ValueType.object.accepts(either(ValueType.integer.nullable)),
        isFalse,
      );
    },
  );

  test(
    'generic function equality, hashing and scope retain FutureOr binders',
    () {
      final a = parameter('A'), b = parameter('B');
      final left = FunctionType(either(a), [future(a)], typeParameters: [a]);
      final right = FunctionType(either(b), [future(b)], typeParameters: [b]);
      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left.accepts(right), isTrue);
      expect(
        left.instantiate([ValueType.nullType]).result,
        future(.nullType).nullable,
      );
      expect(typeParametersIn(either(a)), [a]);
      expect(typeParametersIn(left), isEmpty);
      expect(containsCovariantTypeParameter(either(a), {a}), isTrue);
      expect(
        containsCovariantTypeParameter(FunctionType(.voidType, [either(a)]), {
          a,
        }),
        isFalse,
      );
      expect(() => TypeConstant(either(a)), throwsArgumentError);
      final block = Block();
      block.finish(Return(block.emit(ReifyType(either(a)))));
      expect(
        () => IrFunction(
          FunctionTarget(
            Uri.parse('memory:future'),
            'bad',
            ValueType.typeType,
            [],
          ),
          [block],
        ),
        throwsStateError,
      );
      expect(TypeConstant(either(.integer)).representedType, either(.integer));
      final outer = parameter('Outer');
      final inner = TypeParameterType('Inner')..initializeBound(either(outer));
      final nested = FunctionType(
        either(inner),
        [future(outer)],
        typeParameters: [inner],
      );
      final rebound =
          substituteType(nested, {outer: ValueType.nullType}) as FunctionType;
      expect(rebound.typeParameters.single, isNot(same(inner)));
      expect(rebound.typeParameters.single.bound, future(.nullType).nullable);
      expect(rebound.result, either(rebound.typeParameters.single));
      expect(rebound.parameters, [future(.nullType)]);
      expect(typeParametersIn(rebound), isEmpty);
      expect(containsCovariantTypeParameter(nested, {outer}), isTrue);
    },
  );

  test(
    'recursive FutureOr bounds terminate without inventing subtype proofs',
    () {
      final x = TypeParameterType('X');
      x.initializeBound(either(x));
      expect(x.mayBeNull, isTrue);
      expect(ValueType.object.accepts(x), isFalse);
      expect(ValueType.object.nullable.accepts(x), isTrue);
      expect(either(.integer).accepts(x), isFalse);
      expect(x.bound.accepts(x), isTrue);
      expect(CoreTypes.view(x, CoreTypes.future), isNull);
      final u = TypeParameterType('U')..initializeBound(either(.integer));
      expect(either(.number).accepts(u), isTrue);
      expect(ValueType.object.accepts(u), isTrue);
      final v = TypeParameterType('V')
        ..initializeBound(either(.integer).nullable);
      expect(either(.integer).accepts(v.nonNullable), isTrue);
      expect(either(.integer).accepts(v), isFalse);
      final nullable = TypeParameterType('Nullable')
        ..initializeBound(either(ValueType.integer.nullable));
      expect(
        CoreTypes.view(nullable.nonNullable, ValueType.object),
        ValueType.object,
      );
      final member = FunctionTarget(
        Uri.parse('dart:core'),
        'hashCode',
        .integer,
        [],
        owner: ValueType.object,
        kind: .getter,
      );
      expect(
        InstanceCall(
          member,
          Block([nullable.nonNullable]).parameters.single,
          [],
        ).type,
        ValueType.integer,
      );
    },
  );

  test('a shared Future view does not change a FutureOr type identity', () {
    final type = either(future(.object));
    expect(CoreTypes.view(type, CoreTypes.future), future(.object));
    expect(CoreTypes.view(either(.integer), CoreTypes.future), isNull);
    final method = FunctionTarget(
      Uri.parse('dart:async'),
      'value',
      .object,
      [],
      owner: CoreTypes.future,
      kind: .getter,
    );
    expect(
      InstanceCall(method, Block([type]).parameters.single, []).type,
      ValueType.object,
    );
  });
}
