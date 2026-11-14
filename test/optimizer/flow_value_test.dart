import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:test/test.dart';

void main() {
  test('an absent path contributes no value or unknown bound', () {
    final known = FlowValue.constant(const Constant.integer(7));
    expect(const FlowValue.bottom().join(known), same(known));
    expect(known.join(const FlowValue.bottom()), same(known));
    expect(
      known.constant?.structuralKey,
      const Constant.integer(7).structuralKey,
    );
  });

  test('different scalar loop values widen without an unbounded set', () {
    final joined = FlowValue.constant(const Constant.integer(1))
        .join(FlowValue.constant(const Constant.integer(2)));
    expect(joined.constant, isNull);
    expect(joined.unknownTypes, {ValueType.integer});
    expect(joined.constants, isEmpty);
    expect(joined.join(FlowValue.constant(const Constant.integer(3))), joined);
  });

  test('same-signature functions retain their declaration identity', () {
    final first = FunctionTarget(
      Uri.parse('memory:first'),
      'same',
      ValueType.integer,
      [ValueType.integer],
    );
    final second = FunctionTarget(
      Uri.parse('memory:second'),
      'same',
      ValueType.integer,
      [ValueType.integer],
    );
    final firstValue = FunctionConstant(first);
    final secondValue = FunctionConstant(second);
    final joined = FlowValue.constant(firstValue)
        .join(FlowValue.constant(secondValue));
    expect(
      joined.constants.map((value) => (value as FunctionConstant).target),
      {first, second},
    );
    expect(joined.unknownTypes, isEmpty);
    expect(
      FlowValue.constant(firstValue)
          .join(FlowValue.constant(FunctionConstant(first)))
          .constant,
      firstValue,
    );
  });

  test('unknown bounds do not discard known function provenance', () {
    final target = FunctionTarget(null, 'f', ValueType.integer, []);
    final function = FunctionConstant(target);
    final joined = FlowValue.unknown(function.type)
        .join(FlowValue.constant(function));
    expect(joined.constants.single, same(function));
    expect(joined.constant, isNull);
    expect(joined.unknownTypes, {function.type});
  });

  test('allocation identity separates activations of the same site', () {
    final site = NewCell(
      CellType(ValueType.integer),
      const Constant.integer(1),
    );
    final activation = Object();
    final first = FlowObject(site, activation);
    final sameAllocation = FlowObject(site, activation);
    final anotherActivation = FlowObject(site, Object());
    expect(first, sameAllocation);
    expect(first, isNot(anotherActivation));
    expect(
      FlowValue.object(first).join(FlowValue.object(anotherActivation)).objects,
      {first, anotherActivation},
    );
  });

  test(
    'equal unknown types do not make different SSA inputs interchangeable',
    () {
      final block = Block([ValueType.integer, ValueType.integer]);
      final activation = Object();
      final x = FlowValue.unknown(.integer)
          .withSource(block.parameters[0], activation);
      final y = FlowValue.unknown(.integer)
          .withSource(block.parameters[1], activation);
      expect(x.sources, {FlowSource(block.parameters[0], activation)});
      expect(x.join(y).sources, isEmpty);
      expect(x.join(x).sources, x.sources);
      expect(
        x.join(FlowValue.constant(const Constant.integer(7))).sources,
        isEmpty,
      );
      expect(x.check(.integer).value.sources, x.sources);
      expect(x.check(.integer).mayFail, isFalse);
    },
  );

  test(
    'receiver candidates distinguish exact allocations from unknown bounds',
    () {
      final base = ClassType(Uri.parse('memory:types'), 'Base');
      final child = ClassType(
        Uri.parse('memory:types'),
        'Child',
        superclass: base,
      );
      final allocation = Construct(
        FunctionTarget(
          null,
          'new',
          .voidType,
          [],
          owner: base,
          kind: .initializer,
        ),
        [],
      );
      final value = FlowValue.object(FlowObject(allocation, Object()));
      expect(value.mayHaveInstance(base), isTrue);
      expect(value.mayHaveInstance(child), isFalse);
      expect(FlowValue.unknown(base).mayHaveInstance(child), isTrue);
      expect(FlowValue.unknown(.integer).mayHaveInstance(base), isFalse);
      expect(
        FlowValue.constant(const Constant.nullValue())
            .mayHaveInstance(ValueType.nullClass),
        isTrue,
      );
      expect(
        value
            .withReferences([FlowValue.constant(ObjectConstant(child, {}))])
            .mayHaveInstance(child),
        isFalse,
      );
    },
  );

  test(
    'address alternatives preserve storage identity and bound loop offsets',
    () {
      final site = NewCell(CellType(.integer), const Constant.integer(7));
      final base = FlowObject(site, Object());
      final first = FlowValue.address(FlowAddress(base, 0));
      final second = FlowValue.address(FlowAddress(base, 4));
      final joined = first.join(second);
      expect(first.types, [ValueType.integer]);
      expect(first.unknownTypes, isEmpty);
      expect(first.objects, isEmpty);
      expect(first.references.objects, {base});
      expect(joined.addresses, {FlowAddress(base, null)});
      expect(joined.join(FlowValue.address(FlowAddress(base, 8))), joined);
      expect(joined.join(FlowValue.unknown(.integer)).unknownTypes, {
        ValueType.integer,
      });
      expect(first.check(.integer).value.addresses, first.addresses);
      expect(first.check(.string).value.isBottom, isTrue);
      final replacement = FlowObject(site, Object());
      final rebased = first.mapObjects((_) => replacement);
      expect(rebased.addresses, {FlowAddress(replacement, 0)});
      expect(rebased.references.objects, {replacement});
      expect(first.withSource(site, Object()).addresses, first.addresses);
      expect(first.withSources(const []).addresses, first.addresses);
      expect(first.constant, isNull);
    },
  );

  test(
    'address constants share canonical storage and validate address views',
    () {
      final first = FlowAddress(const Constant.string('same'), 0);
      final second = FlowAddress(const Constant.string('same'), 0);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        FlowValue.address(first).join(FlowValue.address(second)).addresses,
        {first},
      );
      expect(
        FlowValue.address(first).references.constants.single.structuralKey,
        const Constant.string('same').structuralKey,
      );
      expect(() => FlowAddress(Object(), 0), throwsArgumentError);
      expect(
        () => FlowAddress(const Constant.string('same'), 0, type: .string),
        throwsArgumentError,
      );
    },
  );

  test('address reachability does not change a scalar value type', () {
    final cell = NewCell(CellType(.integer), const Constant.integer(7));
    final object = FlowObject(cell, Object());
    final address = FlowValue.unknown(.integer)
        .withReferences([FlowValue.object(object)]);
    expect(address.types, [ValueType.integer]);
    expect(address.objects, isEmpty);
    expect(address.references.objects, {object});
    expect(address.join(FlowValue.unknown(.integer)).references.objects, {
      object,
    });
    final replacement = FlowObject(cell, Object());
    expect(address.mapObjects((_) => replacement).references.objects, {
      replacement,
    });
  });

  test('failed runtime checks do not admit the rejected value', () {
    final value = FlowValue.constant(const Constant.string('wrong'));
    expect(value.check(.integer).value.isBottom, isTrue);
    expect(value.check(.integer).mayFail, isTrue);
    final optional = value.join(FlowValue.constant(const Constant.integer(3)));
    expect(
      optional.check(.integer).value.constant?.structuralKey,
      const Constant.integer(3).structuralKey,
    );
    expect(optional.check(.integer).mayFail, isTrue);
  });

  test(
    'checked bounds retain non-null precision and generic null exclusions',
    () {
      final nullable = FlowValue.unknown(ValueType.integer.nullable);
      expect(nullable.check(.object).value.unknownTypes, {ValueType.integer});
      expect(nullable.check(.nullType, negated: true).value.unknownTypes, {
        ValueType.integer,
      });
      expect(
        nullable.check(.integer, negated: true).value.constant?.structuralKey,
        const Constant.nullValue().structuralKey,
      );
      final parameter = TypeParameterType('T')
        ..initializeBound(.object.nullable);
      final nullValue = FlowValue.constant(const Constant.nullValue());
      expect(nullValue.check(parameter.nonNullable).value.isBottom, isTrue);
      expect(
        nullValue.check(parameter.nonNullable, negated: true).value,
        nullValue,
      );
      expect(nullable.check(.never).value.isBottom, isTrue);
      expect(nullable.check(.never, negated: true).value, nullable);
    },
  );

  test('floating constants retain signed zero and stable NaN identity', () {
    final positive = FlowValue.constant(const Constant.floating(0.0));
    final negative = FlowValue.constant(const Constant.floating(-0.0));
    expect(positive, isNot(negative));
    expect(positive.join(negative).constant, isNull);
    final nan = FlowValue.constant(const Constant.floating(double.nan));
    expect(
      nan.join(FlowValue.constant(const Constant.floating(double.nan))),
      nan,
    );
  });
}
