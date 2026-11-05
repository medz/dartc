import 'package:dartc/ir.dart';
import 'package:dartc/src/ir/type.dart' show containsTypeParameter;
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

void main() {
  TypeParameterType parameter(String name, [ValueType? bound]) =>
      TypeParameterType(name)
        ..initializeBound(bound ?? ValueType.object.nullable);
  test('promotion retains lexical identity and both subtype proofs', () {
    final t = parameter('T');
    final p = PromotedTypeParameterType(t, ValueType.integer);
    expect(t.accepts(p), isTrue);
    expect(t.nonNullable.accepts(p), isTrue);
    expect(ValueType.number.accepts(p), isTrue);
    expect(ValueType.string.accepts(p), isFalse);
    expect(p.accepts(t), isFalse);
    expect(p.accepts(ValueType.integer), isFalse);
    expect(p.mayBeNull, isFalse);
    expect(PromotedTypeParameterType(t, ValueType.number).accepts(p), isTrue);
    expect(
      p.accepts(PromotedTypeParameterType(parameter('T'), ValueType.integer)),
      isFalse,
    );
  });
  test('promotion substitution renames binders but reification retains T', () {
    final t = parameter('T'), u = parameter('U');
    final p = PromotedTypeParameterType(t, CoreTypes.listOf(u));
    final fresh = parameter('Fresh');
    expect(
      substituteType(p, {t: fresh, u: ValueType.integer}),
      PromotedTypeParameterType(fresh, CoreTypes.listOf(ValueType.integer)),
    );
    expect(
      substituteType(p, {t: ValueType.object, u: ValueType.integer}),
      ValueType.object,
    );
    expect(typeParametersIn(p), [t, u]);
    expect(containsTypeParameter(p, {u}), isTrue);
    expect(containsCovariantTypeParameter(p, {u}), isTrue);
  });
  test('null assertion retains the promotion and an extra non-null fact', () {
    final t = parameter('T');
    final p = PromotedTypeParameterType(
      t,
      ValueType.futureOr(ValueType.integer.nullable),
    );
    expect(p.mayBeNull, isTrue);
    final nonNull = p.nonNullable as PromotedTypeParameterType;
    expect(nonNull.bound, p.bound);
    expect(nonNull.mayBeNull, isFalse);
    expect(ValueType.object.accepts(nonNull), isTrue);
    expect(t.accepts(nonNull), isTrue);
    expect(nonNull.accepts(p), isFalse);
    expect(nonNull, isNot(p));
  });
  test('generic function alpha equivalence includes promoted bounds', () {
    final t = parameter('T'), u = parameter('U');
    final a = FunctionType(
      PromotedTypeParameterType(t, ValueType.integer),
      [t],
      typeParameters: [t],
    );
    final b = FunctionType(
      PromotedTypeParameterType(u, ValueType.integer),
      [u],
      typeParameters: [u],
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
  test(
    'runtime casts and tests check both sides before reification erasure',
    () {
      final t = parameter('T');
      final intersection = PromotedTypeParameterType(t, ValueType.integer);
      for (final promoted in [
        intersection,
        intersection.nullable,
        ValueType.futureOr(intersection),
      ]) {
        for (final cast in [false, true]) {
          final target = FunctionTarget(
            Uri.parse('memory:promoted'),
            'check',
            cast ? ValueType.dynamicType : ValueType.boolean,
            [ValueType.dynamicType],
            typeParameters: [t],
          );
          final block = Block(target.parameterTypes);
          final result = block.emit(
            cast
                ? TypeCast(block.parameters.single, promoted)
                : TypeTest(block.parameters.single, promoted),
          );
          block.finish(Return(result));
          final function = IrFunction(target, [block]);
          final runner = FixtureRunner(IrProgram([], [function]), {});
          expect(
            runner.run(function, [3], {t: ValueType.object}),
            cast ? 3 : true,
          );
          if (cast) {
            expect(
              () => runner.run(function, ['bad'], {t: ValueType.object}),
              throwsA(isA<TypeError>()),
            );
            expect(
              () => runner.run(function, [3], {t: ValueType.string}),
              throwsA(isA<TypeError>()),
            );
          } else {
            expect(
              runner.run(function, ['bad'], {t: ValueType.object}),
              isFalse,
            );
            expect(runner.run(function, [3], {t: ValueType.string}), isFalse);
          }
        }
      }
    },
  );
  test(
    'T & Object rejects null even when reified T is dynamic or FutureOr',
    () {
      final t = parameter('T');
      final target = FunctionTarget(
        Uri.parse('memory:nonnull'),
        'check',
        ValueType.boolean,
        [ValueType.dynamicType],
        typeParameters: [t],
      );
      final block = Block(target.parameterTypes);
      block.finish(
        Return(block.emit(TypeTest(block.parameters.single, t.nonNullable))),
      );
      final function = IrFunction(target, [block]);
      final runner = FixtureRunner(IrProgram([], [function]), {});
      for (final actual in [
        ValueType.dynamicType,
        ValueType.futureOr(ValueType.integer.nullable),
      ]) {
        expect(runner.run(function, [null], {t: actual}), isFalse);
        expect(runner.run(function, [3], {t: actual}), isTrue);
      }
    },
  );
  test(
    'a non-null lexical bound removes null from a nullable promoted bound',
    () {
      final t = parameter('T', ValueType.object);
      final p = PromotedTypeParameterType(t, ValueType.integer.nullable);
      expect(p.mayBeNull, isFalse);
      expect(ValueType.integer.accepts(p), isTrue);
      expect(CoreTypes.view(p, ValueType.integer), ValueType.integer);
    },
  );
}
