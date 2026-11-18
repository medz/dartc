import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/integer_range.dart';
import 'package:test/test.dart';

void main() {
  test('external unknown provenance survives checks, aliases and joins', () {
    expect(
      FlowValue.unknown(.integer).asExternal().externalUnknownTypes,
      isEmpty,
    );
    expect(
      FlowValue.unknown(.boolean, external: true).externalUnknownTypes,
      isEmpty,
    );
    expect(
      FlowValue.unknown(
        .object,
        external: true,
      ).check(.integer).value.externalUnknownTypes,
      isEmpty,
    );
    final box = ClassType(null, 'Box');
    final subtype = ClassType(null, 'Subtype', superclass: box);
    final parameter = Block([box]).parameters.single;
    final value = FlowValue.unknown(box)
        .asExternal()
        .withSource(parameter, Object());
    expect(value.withSources(const []).externalUnknownTypes, {box});
    expect(value.check(subtype).value.externalUnknownTypes, {subtype});
    expect(value.check(box, runtimeTypes: true).value.externalUnknownTypes, {
      box,
    });
    expect(value.join(FlowValue.unknown(.integer)).externalUnknownTypes, {box});
    expect(value.join(FlowValue.unknown(box)).externalUnknownTypes, isEmpty);
    final raw = FlowValue.unknown(.integer).withReferences([value]);
    expect(raw.references.externalUnknownTypes, {box});
    expect(raw.asExternal().references, raw.references);
    expect(value.mapObjects((object) => object), value);
  });

  test('constant rebinding preserves facts and updates native references', () {
    final owner = ClassType(null, 'Value');
    final initializer = FunctionTarget(
      null,
      'new',
      .voidType,
      [],
      owner: owner,
      kind: .initializer,
    );
    final original = FunctionConstant(initializer);
    final entry = FunctionTarget(null, 'entry', owner, []);
    final replacement = original.withInvocationEntry(entry);
    final parameter = Block([.integer]).parameters.single;
    final activation = Object();
    final input = FlowValue.address(FlowAddress(original, 8))
        .join(FlowValue.constant(const Constant.integer(11)))
        .withSource(parameter, activation);
    final rebound = input.rebindConstants(
      (value) => identical(value, original) ? replacement : value,
    );
    expect(rebound, input);
    expect(rebound, isNot(same(input)));
    expect(rebound.addresses.single.base, same(replacement));
    expect(rebound.addresses.single.offset, 8);
    expect(rebound.references.constants.single, same(replacement));
    expect(rebound.sources, input.sources);
    expect(rebound.rebindConstants((value) => value), same(rebound));
    expect(
      () =>
          FlowValue.constant(const Constant.integer(11))
              .rebindConstants((_) => const Constant.integer(12)),
      throwsArgumentError,
    );
  });

  test('runtime checks reify nominal arguments but retain scalar and record proofs', () {
    final proof = PromotedType(ValueType.object, ValueType.integer);
    final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
    final owner = ClassType(null, 'Box', typeParameters: [parameter]);
    final type = owner.instantiate([proof]);
    final object = FlowObject(
      NewPayload(type, const Constant.integer(0)),
      Object(),
    );
    final value = FlowValue.object(object);
    expect(
      value.check(owner.instantiate([ValueType.integer])).mayFail,
      isFalse,
    );
    expect(
      value
          .check(owner.instantiate([ValueType.integer]), runtimeTypes: true)
          .value
          .isBottom,
      isTrue,
    );
    expect(
      value
          .check(owner.instantiate([ValueType.object]), runtimeTypes: true)
          .value
          .objects,
      {object},
    );
    expect(
      FlowValue.unknown(proof).check(.integer, runtimeTypes: true).mayFail,
      isFalse,
    );
    expect(
      FlowValue.unknown(RecordType([proof], const {}))
          .check(RecordType([ValueType.integer], const {}), runtimeTypes: true)
          .mayFail,
      isFalse,
    );
  });

  test('bulk alternatives agree with incremental joins and shared aliases', () {
    final parameter = Block([.integer]).parameters.single;
    final activation = Object();
    final values = [
      const FlowValue.bottom(),
      for (final number in [2, 5, 9])
        FlowValue.constant(Constant.integer(number))
            .withSource(parameter, activation),
    ];
    final joined = FlowValue.joined(values);
    expect(joined, values.reduce((left, right) => left.join(right)));
    expect(joined.integers, FlowIntegerRange(2, 9));
    expect(joined.sources, {FlowSource(parameter, activation)});
    expect(
      FlowValue.joined([...values, FlowValue.unknown(.integer)]).sources,
      isEmpty,
    );
  });

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
        .join(FlowValue.constant(const Constant.integer(2)), widen: true);
    expect(joined.constant, isNull);
    expect(joined.unknownTypes, {ValueType.integer});
    expect(joined.constants, isEmpty);
    expect(joined.integers, FlowIntegerRange(1, FlowIntegerRange.maximum));
    expect(joined.join(FlowValue.constant(const Constant.integer(3))), joined);
  });

  test(
    'integer alternatives keep bounds and path filtering keeps equivalence',
    () {
      final block = Block([ValueType.integer]);
      final activation = Object();
      final joined = FlowValue.constant(const Constant.integer(1))
          .join(FlowValue.constant(const Constant.integer(3)))
          .withSource(block.parameters.single, activation);
      expect(
        joined.integers,
        FlowIntegerRange(1, 3, strideBits: 1, residue: 1),
      );
      expect(joined.check(.integer).value, joined);
      final narrowed = joined.restrictIntegers(FlowIntegerRange(3, 8));
      expect(
        narrowed.constant?.structuralKey,
        const Constant.integer(3).structuralKey,
      );
      expect(narrowed.sources, joined.sources);
      expect(joined.restrictIntegers(FlowIntegerRange(-2, 0)).isBottom, isTrue);
      expect(
        joined.join(FlowValue.unknown(.integer)).integers,
        FlowIntegerRange.full,
      );
      expect(joined.join(FlowValue.unknown(.string)).integers, isNull);
      expect(
        FlowValue.integerRange(FlowIntegerRange.full),
        FlowValue.unknown(.integer),
      );
    },
  );

  test('open generic type checks still reject unrelated nominal receivers', () {
    final uri = Uri.parse('memory:generic-receiver');
    final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
    final left = ClassType(uri, 'Left', typeParameters: [parameter]);
    final right = ClassType(uri, 'Right', typeParameters: [parameter]);
    final value = FlowValue.constant(
      ObjectConstant(left.instantiate([.integer]), {}),
    );
    expect(value.check(right).value.isBottom, isTrue);
    expect(value.check(right).mayFail, isTrue);
    expect(value.check(right, negated: true).value, value);
    expect(value.check(right, negated: true).mayFail, isFalse);
    expect(value.check(left).value.isBottom, isFalse);
  });

  test(
    'type filtering preserves allocation identities and unknown scalars',
    () {
      final left = ClassType(null, 'Left'), right = ClassType(null, 'Right');
      final instances = [
        for (var index = 0; index < 256; index++)
          FlowObject(
            NewPayload(index.isEven ? left : right, const Constant.integer(0)),
            Object(),
          ),
      ];
      final value = FlowValue.joined(instances.map(FlowValue.object));
      expect(
        value.check(left).value.objects,
        instances.where((object) => object.type == left),
      );
      expect(
        value.check(left, negated: true).value.objects,
        instances.where((object) => object.type == right),
      );
      expect(value.check(left).mayFail, isTrue);
      final scalar = FlowValue.constant(const Constant.integer(7))
          .join(FlowValue.unknown(.object));
      final checked = scalar.check(.integer).value;
      expect(checked.constants, isEmpty);
      expect(checked.unknownTypes, {ValueType.integer});
    },
  );

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

  test('non-null bounds reject Null without closing unrelated interfaces', () {
    final parameter = TypeParameterType('T')..initializeBound(.object);
    final left = ClassType(null, 'Left'), right = ClassType(null, 'Right');
    for (final bound in <ValueType>[
      .object,
      .integer,
      .stackTrace,
      left,
      parameter,
    ]) {
      final input = FlowValue.unknown(bound);
      final yes = input.check(.nullType),
          no = input.check(.nullType, negated: true);
      expect(yes.value.isBottom, isTrue);
      expect(yes.mayFail, isTrue);
      expect(no.value, input);
      expect(no.mayFail, isFalse);
    }
    for (final bound in <ValueType>[
      .object.nullable,
      .dynamicType,
      left.nullable,
    ]) {
      final input = FlowValue.unknown(bound);
      expect(input.check(.nullType).value.isBottom, isFalse);
      expect(input.check(.nullType).mayFail, isTrue);
      expect(input.check(.nullType, negated: true).value.isBottom, isFalse);
      expect(input.check(.nullType, negated: true).mayFail, isTrue);
    }
    for (final negated in [false, true]) {
      final check = FlowValue.unknown(left).check(right, negated: negated);
      expect(check.value.isBottom, isFalse);
      expect(check.mayFail, isTrue);
    }
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
      expect(joined.addresses, {
        FlowAddress.ranged(base, FlowIntegerRange(0, 4, strideBits: 2)),
      });
      final widened = joined.join(
        FlowValue.address(FlowAddress(base, 8)),
        widen: true,
      );
      expect(
        widened.addresses.single.offsets,
        FlowIntegerRange(0, FlowIntegerRange.maximum, strideBits: 2),
      );
      expect(widened.join(FlowValue.address(FlowAddress(base, 16))), widened);
      expect(
        joined.join(FlowValue.address(FlowAddress(base, null))).addresses,
        {FlowAddress(base, null)},
      );
      expect(joined.join(FlowValue.unknown(.integer)).unknownTypes, {
        ValueType.integer,
      });
      expect(first.check(.integer).value.addresses, first.addresses);
      expect(first.check(.string).value.isBottom, isTrue);
      final replacement = FlowObject(site, Object());
      final rebased = joined.mapObjects((_) => replacement);
      expect(rebased.addresses, {
        FlowAddress.ranged(replacement, FlowIntegerRange(0, 4, strideBits: 2)),
      });
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
