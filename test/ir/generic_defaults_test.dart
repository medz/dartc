import 'package:dartc/ir.dart';
import 'package:test/test.dart';

TypeParameterType _parameter(
  String name, {
  ValueType? bound,
  ValueType? defaultType,
}) {
  final parameter = TypeParameterType(name)
    ..initializeBound(bound ?? ValueType.object.nullable);
  if (defaultType != null) parameter.initializeDefaultType(defaultType);
  return parameter;
}

IrFunction _emptyFunction(FunctionTarget target) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(const Return())]);

void main() {
  final library = Uri.parse('memory:generic-defaults');

  test('default metadata is optional and initialized independently once', () {
    final t = TypeParameterType('T');
    expect(t.defaultType, isNull);
    expect(
      () => t.initializeDefaultType(CellType(ValueType.integer)),
      throwsStateError,
    );
    expect(t.defaultType, isNull);
    t.initializeDefaultType(ValueType.string);
    expect(t.defaultType, ValueType.string);
    expect(() => t.bound, throwsStateError);
    t.initializeBound(ValueType.number);
    expect(() => t.initializeDefaultType(ValueType.number), throwsStateError);
    expect(t.defaultType, ValueType.string);
    final signature = FunctionType(t, [], typeParameters: [t]);
    expect(signature.defaultTypeArguments, [ValueType.string]);
    expect(signature.instantiateToBounds, throwsArgumentError);
    expect(
      signature.instantiate([ValueType.integer]).result,
      ValueType.integer,
    );
  });

  test('nongeneric signatures have no default arguments', () {
    final signature = FunctionType(ValueType.integer, [ValueType.string]);
    expect(signature.defaultTypeArguments, isEmpty);
    expect(signature.instantiateToBounds(), signature);
    expect(
      () => signature.defaultTypeArguments.add(ValueType.integer),
      throwsUnsupportedError,
    );
  });

  test(
    'recorded defaults distinguish dynamic from an explicit Object bound',
    () {
      final unbounded = _parameter('T', defaultType: ValueType.dynamicType);
      final explicit = _parameter('T', defaultType: ValueType.object.nullable);
      final numeric = _parameter(
        'N',
        bound: ValueType.number,
        defaultType: ValueType.number,
      );
      for (final (parameter, expected) in [
        (unbounded, ValueType.dynamicType),
        (explicit, ValueType.object.nullable),
        (numeric, ValueType.number),
      ]) {
        final signature = FunctionType(
          parameter,
          [parameter],
          typeParameters: [parameter],
        );
        expect(signature.defaultTypeArguments, [expected]);
        expect(
          signature.instantiateToBounds(),
          FunctionType(expected, [expected]),
        );
      }
      expect(unbounded.bound, explicit.bound);
    },
  );

  test('dependent and reordered defaults are exact recorded templates', () {
    final t = _parameter(
      'T',
      bound: ValueType.number,
      defaultType: ValueType.number,
    );
    final list = CoreTypes.listOf(ValueType.number);
    final u = _parameter('U', bound: CoreTypes.listOf(t), defaultType: list);
    for (final parameters in [
      <TypeParameterType>[t, u],
      [u, t],
    ]) {
      final signature = FunctionType(u, [t, u], typeParameters: parameters);
      expect(signature.defaultTypeArguments, [
        for (final parameter in parameters) parameter.defaultType,
      ]);
      expect(
        signature.instantiateToBounds(),
        FunctionType(list, [ValueType.number, list]),
      );
    }
  });

  test('recursive defaults are recorded before invocation bound checks', () {
    final t = TypeParameterType('T');
    final owner = ClassType(library, 'Bound', typeParameters: [t]);
    t.initializeBound(owner);
    final defaultType = owner.instantiate([ValueType.dynamicType]);
    t.initializeDefaultType(defaultType);
    final target = FunctionTarget(
      library,
      'recursive',
      .voidType,
      [],
      typeParameters: [t],
    );
    expect(() => _emptyFunction(target), returnsNormally);
    expect(target.signature.defaultTypeArguments, [defaultType]);
    expect(target.signature.instantiateToBounds, throwsArgumentError);
  });

  test('contravariant and mixed recursive defaults retain Never polarity', () {
    for (final mixed in [false, true]) {
      final t = TypeParameterType('T');
      t.initializeBound(FunctionType(mixed ? t : ValueType.voidType, [t]));
      final defaultType = FunctionType(
        mixed ? ValueType.dynamicType : ValueType.voidType,
        [ValueType.never],
      );
      t.initializeDefaultType(defaultType);
      final signature = FunctionType(.voidType, [], typeParameters: [t]);
      expect(signature.defaultTypeArguments, [defaultType]);
      expect(signature.instantiateToBounds, throwsArgumentError);
    }
  });

  test('missing metadata fails only on default demand', () {
    final t = _parameter('T', bound: ValueType.number);
    final target = FunctionTarget(
      library,
      'explicit',
      .voidType,
      [t],
      typeParameters: [t],
    );
    final signature = target.signature;
    expect(() => _emptyFunction(target), returnsNormally);
    expect(signature.instantiate([ValueType.integer]).parameters, [
      ValueType.integer,
    ]);
    expect(
      () => DirectCall(
        target,
        [const Constant.integer(1)],
        typeArguments: [ValueType.integer],
      ),
      returnsNormally,
    );
    expect(
      () => signature.defaultTypeArguments,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Missing default type metadata for T'),
        ),
      ),
    );
    expect(signature.instantiateToBounds, throwsStateError);
  });

  test(
    'defaults do not change binder identity, alpha equality or subtyping',
    () {
      final t = _parameter('T');
      final u = _parameter('U', defaultType: ValueType.object.nullable);
      final left = FunctionType(t, [t], typeParameters: [t]);
      final right = FunctionType(u, [u], typeParameters: [u]);
      final binderHash = t.hashCode;
      final functionHash = left.hashCode;
      final signatures = {left};
      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left.accepts(right), isTrue);
      expect(right.accepts(left), isTrue);
      t.initializeDefaultType(ValueType.dynamicType);
      expect(t.hashCode, binderHash);
      expect(t, isNot(u));
      expect(left.hashCode, functionHash);
      expect(signatures.contains(right), isTrue);
      expect(left, right);
      expect(left.accepts(right), isTrue);
      expect(right.accepts(left), isTrue);
      expect(left.defaultTypeArguments, isNot(right.defaultTypeArguments));
    },
  );

  test('default-only outer references trigger substitution and freshening', () {
    final outer = _parameter('Outer');
    final t = _parameter('T', defaultType: outer);
    final absent = _parameter('Missing');
    final source = FunctionType(.voidType, [], typeParameters: [t, absent]);
    expect(typeParametersIn(source), [outer]);
    final changed =
        substituteType(source, {outer: ValueType.integer}) as FunctionType;
    expect(changed, source);
    expect(changed.typeParameters[0], isNot(same(t)));
    expect(changed.typeParameters[0].defaultType, ValueType.integer);
    expect(changed.typeParameters[1], isNot(same(absent)));
    expect(changed.typeParameters[1].defaultType, isNull);
    expect(typeParametersIn(changed), isEmpty);
    expect(t.defaultType, same(outer));
    expect(substituteType(source, {t: ValueType.string}), same(source));
  });

  test('fresh defaults use the same scoped binder map as bounds', () {
    final outer = _parameter('Outer');
    final t = _parameter('T', bound: outer, defaultType: outer);
    final u = _parameter('U', bound: t, defaultType: t);
    final source = FunctionType(u, [t], typeParameters: [t, u]);
    final changed =
        substituteType(source, {outer: ValueType.number}) as FunctionType;
    final freshT = changed.typeParameters[0];
    final freshU = changed.typeParameters[1];
    expect(freshT.bound, ValueType.number);
    expect(freshT.defaultType, ValueType.number);
    expect(freshU.bound, same(freshT));
    expect(freshU.defaultType, same(freshT));
    expect(changed.defaultTypeArguments, [ValueType.number, freshT]);
    expect(changed.result, same(freshU));
    expect(changed.parameters, [freshT]);
    expect(u.defaultType, same(t));
  });

  test('default substitution cannot capture replacement variables', () {
    final outer = _parameter('T');
    final inner = _parameter('T');
    inner.initializeDefaultType(RecordType([outer, inner]));
    final source = FunctionType(.voidType, [], typeParameters: [inner]);
    final changed = substituteType(source, {outer: inner}) as FunctionType;
    final fresh = changed.typeParameters.single;
    final defaultType = fresh.defaultType as RecordType;
    expect(fresh, isNot(same(inner)));
    expect(defaultType.fields, [inner, fresh]);
    expect(typeParametersIn(changed), [inner]);
    expect((inner.defaultType as RecordType).fields, [outer, inner]);
  });

  test('verifier rejects free defaults but accepts own binders', () {
    final foreign = _parameter('Foreign');
    final invalid = _parameter('T', defaultType: foreign);
    final target = FunctionTarget(
      library,
      'invalid',
      .voidType,
      [],
      typeParameters: [invalid],
    );
    expect(() => _emptyFunction(target), throwsStateError);
    final t = _parameter('T');
    final u = _parameter('U', defaultType: t);
    t.initializeDefaultType(u);
    final own = FunctionTarget(
      library,
      'own',
      .voidType,
      [],
      typeParameters: [t, u],
    );
    expect(typeParametersIn(own.signature), isEmpty);
    expect(() => _emptyFunction(own), returnsNormally);
  });

  test('nested function metadata participates in lexical scope checks', () {
    final foreign = _parameter('Foreign');
    final inner = _parameter('Inner', defaultType: foreign);
    final callback = FunctionType(.voidType, [], typeParameters: [inner]);
    final invalid = FunctionTarget(library, 'nested', .voidType, [callback]);
    expect(() => _emptyFunction(invalid), throwsStateError);
    final valid = FunctionTarget(
      library,
      'nestedGeneric',
      .voidType,
      [callback],
      typeParameters: [foreign],
    );
    expect(() => _emptyFunction(valid), returnsNormally);
  });

  test(
    'receiver and captured defaults remain templates until substitution',
    () {
      final t = _parameter('T', defaultType: ValueType.dynamicType);
      final owner = ClassType(library, 'Owner', typeParameters: [t]);
      final u = _parameter('U', bound: t, defaultType: t);
      final member = FunctionTarget(
        library,
        'method',
        .voidType,
        [],
        owner: owner,
        kind: .method,
        typeParameters: [u],
      );
      expect(() => _emptyFunction(member), returnsNormally);
      final applied = member.signatureFor(owner.instantiate([.integer]));
      expect(applied.defaultTypeArguments, [ValueType.integer]);
      expect(applied.typeParameters.single.bound, ValueType.integer);
      expect(applied.instantiateToBounds().typeParameters, isEmpty);
      expect(u.defaultType, same(t));
      final v = _parameter('V', bound: u, defaultType: u);
      final local = FunctionTarget(
        library,
        'local',
        .voidType,
        [],
        kind: .closure,
        enclosing: member,
        sourceOffset: 1,
        typeParameters: [v],
      );
      expect(() => _emptyFunction(local), returnsNormally);
      final captured = substituteType(local.signature, {
        u: ValueType.integer,
      }) as FunctionType;
      expect(captured.defaultTypeArguments, [ValueType.integer]);
      expect(v.defaultType, same(u));
    },
  );

  test(
    'constructor aliases retain their own defaults instead of owner defaults',
    () {
      final t = _parameter(
        'T',
        bound: ValueType.number,
        defaultType: ValueType.number,
      );
      final owner = ClassType(library, 'Construct', typeParameters: [t]);
      final constructor = FunctionTarget(
        library,
        'new',
        .voidType,
        [t],
        owner: owner,
        kind: .initializer,
      );
      final u = _parameter(
        'U',
        bound: ValueType.integer,
        defaultType: ValueType.integer,
      );
      final alias = FunctionConstant(
        constructor,
        constructorSignature: FunctionType(
          owner.instantiate([u]),
          [u],
          typeParameters: [u],
        ),
        constructorAlias: (library, 'Alias'),
      );
      final signature = alias.type as FunctionType;
      expect(signature.typeParameters.single, same(u));
      expect(signature.defaultTypeArguments, [ValueType.integer]);
      expect(
        signature.instantiateToBounds().result,
        owner.instantiate([ValueType.integer]),
      );
      expect(constructor.tearOffSignature().defaultTypeArguments, [
        ValueType.number,
      ]);
    },
  );

  test(
    'core generic declarations and MapEntry constructors default to dynamic',
    () {
      for (final owner in [
        CoreTypes.iterable,
        CoreTypes.iterator,
        CoreTypes.list,
        CoreTypes.set,
        CoreTypes.map,
        CoreTypes.mapEntry,
      ]) {
        expect(
          owner.typeParameters.map((parameter) => parameter.defaultType),
          everyElement(ValueType.dynamicType),
        );
      }
      final constructor = FunctionTarget(
        Uri.parse('dart:core'),
        'new',
        .voidType,
        CoreTypes.mapEntry.typeParameters,
        owner: CoreTypes.mapEntry,
        kind: .initializer,
      );
      final signature = constructor.tearOffSignature();
      expect(signature.defaultTypeArguments, [
        ValueType.dynamicType,
        ValueType.dynamicType,
      ]);
      expect(
        signature.instantiateToBounds().result,
        CoreTypes.mapEntryOf(.dynamicType, .dynamicType),
      );
      expect(
        signature.instantiate([.string, .integer]).result,
        CoreTypes.mapEntryOf(.string, .integer),
      );
      expect(constructor.typeParameters, isEmpty);
    },
  );
}
