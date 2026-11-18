import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

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
      p.substitute({t: fresh, u: ValueType.integer}),
      PromotedTypeParameterType(fresh, CoreTypes.listOf(ValueType.integer)),
    );
    expect(
      p.substitute({t: ValueType.object, u: ValueType.integer}),
      ValueType.object,
    );
    expect(p.freeTypeParameters, [t, u]);
    expect(p.freeTypeParameters, contains(u));
    expect(p.requiresCovariantCheck({u}), isTrue);
  });

  test('executable substitution retains unrelated concrete constraints', () {
    final uri = Uri.parse('memory:flow-intersection');
    final first = ClassType(uri, 'First', isAbstract: true);
    final second = ClassType(uri, 'Second', isAbstract: true);
    final both = ClassType(uri, 'Both', interfaces: [first, second]);
    final t = parameter('T');
    final source = PromotedTypeParameterType(t, second);
    final result = source.substituteForFlow({t: first}) as PromotedType;

    expect(result, isA<InstantiatedPromotionType>());
    expect(result.lexicalType, first);
    expect(result.bound, second);
    expect(first.accepts(result), isTrue);
    expect(second.accepts(result), isTrue);
    expect(result.accepts(both), isTrue);
    expect(result.accepts(first), isFalse);
    expect(result.accepts(second), isFalse);
    expect(result.mayHaveInstance(both), isTrue);
    expect(result.mayHaveInstance(first), isFalse);
    expect(CoreTypes.view(result, first), first);
    expect(CoreTypes.view(result, second), second);
    expect(result.freeTypeParameters, isEmpty);
    expect(result.referencedClasses.toSet(), {first, second});
    expect(result.normalize(), result);
    expect(result.reify(), first);
    expect(source.substitute({t: first}), first);
  });

  test('runtime observations separate reified arguments from value proofs', () {
    final t = parameter('T');
    final promoted = PromotedTypeParameterType(t, ValueType.integer);
    final concrete = promoted.substituteForFlow({t: ValueType.object});
    expect(promoted.reify(), same(t));
    expect(concrete.reify(), ValueType.object);
    expect(ValueType.integer.accepts(concrete.runtimeValueBound), isTrue);
    expect(concrete.runtimeCheckType.accepts(ValueType.string), isFalse);
    expect(
      CoreTypes.listOf(concrete).runtimeValueBound,
      CoreTypes.listOf(ValueType.object),
    );
    final record = RecordType([concrete], const {});
    expect(record.runtimeValueBound, record);
    expect(record.runtimeCheckType, RecordType([ValueType.object], const {}));
    expect(
      RecordType([
        ValueType.integer,
      ], const {}).accepts(record.runtimeValueBound),
      isTrue,
    );
    expect(
      FunctionType(concrete, [concrete]).runtimeValueBound,
      FunctionType(ValueType.object, [ValueType.object]),
    );
  });

  test(
    'flow substitution preserves nested constraints without binding capture',
    () {
      final t = parameter('T'), u = parameter('U'), inner = parameter('U');
      final promoted = PromotedTypeParameterType(t, CoreTypes.listOf(u));
      final signature = FunctionType(
        promoted,
        [inner, CoreTypes.listOf(promoted)],
        typeParameters: [inner],
      );
      final result = signature.substituteForFlow({
        t: ValueType.object,
        u: ValueType.integer,
      }) as FunctionType;
      final proof = result.result as PromotedType;
      expect(proof.lexicalType, ValueType.object);
      expect(proof.bound, CoreTypes.listOf(ValueType.integer));
      expect(result.parameters[1], CoreTypes.listOf(proof));
      expect(result.parameters.first, same(result.typeParameters.single));
      expect(result.typeParameters.single, isNot(same(inner)));
      expect(result.freeTypeParameters, isEmpty);
      expect(
        result.reify(),
        FunctionType(
          ValueType.object,
          [inner, CoreTypes.listOf(ValueType.object)],
          typeParameters: [inner],
        ).reify(),
      );
    },
  );

  test(
    'flow substitution preserves nullable and FutureOr promotion checks',
    () {
      final t = parameter('T');
      final promoted = PromotedTypeParameterType(t, ValueType.integer.nullable);
      final proof = promoted.substituteForFlow({t: ValueType.object.nullable});
      expect(proof.mayBeNull, isTrue);
      expect(proof.accepts(ValueType.nullType), isTrue);
      expect(proof.nonNullable.mayBeNull, isFalse);
      expect(ValueType.integer.accepts(proof.nonNullable), isTrue);
      final future = ValueType.futureOr(promoted)
          .substituteForFlow({t: ValueType.object.nullable});
      expect(future, isA<FutureOrType>());
      expect((future as FutureOrType).argument, proof);
      expect(
        promoted.nullable.substituteForFlow({t: ValueType.object}),
        PromotedType(ValueType.object, ValueType.integer.nullable).nullable,
      );
    },
  );
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
          final runner = IrInterpreter(IrProgram([], [function]), {});
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
      final runner = IrInterpreter(IrProgram([], [function]), {});
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
