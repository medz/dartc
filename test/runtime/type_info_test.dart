import 'package:dartc/runtime/contracts.dart';
import 'package:test/test.dart';

import '../../sdk/runtime/type_info.dart';

void main() {
  final integer = TypeInfo(TypeKind.nominal.index, 1, false, null, null, 'int');
  final number = TypeInfo(TypeKind.nominal.index, 2, false, null, null, 'num');
  TypeArguments? arguments(List<TypeInfo> values) =>
      values.reversed.fold(null, (tail, head) => TypeArguments(head, tail));

  test('argument equality checks every element and list length', () {
    for (final (left, right, expected) in [
      (<TypeInfo>[], <TypeInfo>[], true),
      ([integer], [integer], true),
      ([integer], [number], false),
      (<TypeInfo>[], [integer], false),
      ([integer], <TypeInfo>[], false),
      ([integer, number], [integer], false),
    ]) {
      final a = arguments(left), b = arguments(right);
      expect(TypeArguments.equal(a, b), expected);
      if (expected) expect(TypeArguments.hash(a), TypeArguments.hash(b));
    }
  });

  test('equal type keys have matching hashes across distinct allocations', () {
    TypeInfo box() => TypeInfo(
      TypeKind.nominal.index,
      3,
      false,
      arguments([integer, number]),
      null,
      'Box',
    );
    final first = box(), second = box();
    expect(identical(first, second), isFalse);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(<Type, int>{first: 42}[second], 42);
    expect(TypeInfo.equal(first, null), isFalse);
    expect(first == integer, isFalse);
  });

  test(
    'shifting nested functions retains local binders and moves captures',
    () {
      TypeInfo parameter(int slot) => TypeInfo(
        TypeKind.parameter.index,
        slot,
        false,
        null,
        null,
        'parameter',
      );
      final function = TypeInfo(
        TypeKind.function.index,
        4,
        false,
        arguments([number, parameter(1), parameter(0)]),
        FunctionInfo(1, 1, 1, null),
        'Closure',
      );
      final shifted = function.shift(2, 0);
      expect(TypeArguments.at(shifted.parts, 1).shape, 3);
      expect(TypeArguments.at(shifted.parts, 2).shape, 0);
      expect(shifted.shift(0, 0), shifted);
    },
  );
}
