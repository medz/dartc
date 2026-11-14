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
