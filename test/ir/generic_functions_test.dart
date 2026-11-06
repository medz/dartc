import 'package:dartc/ir.dart';
import 'package:test/test.dart';

TypeParameterType parameter(String name, [ValueType? bound]) =>
    TypeParameterType(name)
      ..initializeBound(bound ?? ValueType.object.nullable);

void main() {
  final library = Uri.parse('memory:generic-functions');
  test('call sites use the same type arguments they retain', () {
    final t = parameter('T');
    final function = FunctionTarget(library, 'f', t, [], typeParameters: [t]);
    final value = FunctionConstant(function);
    final owner = ClassType(library, 'C');
    final receiver = Block([owner]).parameters.single;
    final method = FunctionTarget(
      library,
      'm',
      t,
      [],
      kind: .method,
      owner: owner,
      typeParameters: [t],
    );
    for (final build in <Value Function(Iterable<ValueType>)>[
      (a) => FunctionCall(value, [], {}, a),
      (a) => DirectCall(function, [], typeArguments: a),
      (a) => InstanceCall(method, receiver, [], {}, null, a),
      (a) => InstantiateFunction(value, a),
      (a) => FunctionConstant(function, typeArguments: a),
    ]) {
      var reads = 0;
      Iterable<ValueType> arguments() sync* {
        yield ++reads == 1 ? ValueType.integer : ValueType.string;
      }

      final call = build(arguments());
      final result = call.type;
      expect(
        result is FunctionType ? result.result : result,
        ValueType.integer,
      );
      expect(reads, 1);
    }
  });

  test('callable kinds validate the binders retained by their signature', () {
    final t = parameter('T');
    var reads = 0;
    Iterable<TypeParameterType> binders() sync* {
      if (++reads == 1) yield t;
    }

    expect(
      () => FunctionTarget(
        library,
        'getValue',
        t,
        [],
        kind: .staticGetter,
        typeParameters: binders(),
      ),
      throwsArgumentError,
    );
    expect(reads, 1);
  });

  test('generic equality and hashing are alpha equivalent', () {
    final t = parameter('T');
    final u = parameter('U');
    final a = FunctionType(t, [t], typeParameters: [t]);
    final b = FunctionType(u, [u], typeParameters: [u]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a, b}, hasLength(1));
    expect(a.accepts(b), isTrue);
    expect(a.accepts(FunctionType(.integer, [.integer])), isFalse);
    final n = parameter('N', .number);
    expect(a.accepts(FunctionType(n, [n], typeParameters: [n])), isFalse);
    expect(a.instantiate([.integer]), FunctionType(.integer, [.integer]));
    expect(() => a.instantiate([]), throwsArgumentError);
    expect(
      () => FunctionType(n, [n], typeParameters: [n]).instantiate([.string]),
      throwsArgumentError,
    );
  });

  test('nested binders and their bounds preserve alpha equivalence', () {
    FunctionType nested(String outerName, String innerName) {
      final outer = parameter(outerName);
      final inner = parameter(innerName, outer);
      return FunctionType(
        FunctionType(inner, [outer, inner], typeParameters: [inner]),
        [outer],
        typeParameters: [outer],
      );
    }

    final a = nested('T', 'T');
    final b = nested('U', 'V');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.accepts(b), isTrue);
    final free = parameter('T');
    final otherFree = parameter('T');
    expect(FunctionType(free, []), isNot(FunctionType(otherFree, [])));
  });

  test(
    'substitution changes outer bounds without changing original binders',
    () {
      final outer = parameter('T');
      final inner = parameter('U', outer);
      final source = FunctionType(
        inner,
        [outer, inner],
        typeParameters: [inner],
      );
      final changed =
          substituteType(source, {outer: ValueType.number}) as FunctionType;
      expect(inner.bound, same(outer));
      expect(changed.typeParameters.single.bound, ValueType.number);
      expect(changed.parameters.first, ValueType.number);
      expect(changed.parameters.last, same(changed.typeParameters.single));
      expect(
        changed.instantiate([ValueType.integer]).result,
        ValueType.integer,
      );
      expect(
        () => changed.instantiate([ValueType.string]),
        throwsArgumentError,
      );
      expect(substituteType(source, {inner: ValueType.integer}), same(source));
    },
  );

  test('simultaneous substitution avoids capturing replacement variables', () {
    final outer = parameter('T');
    final inner = parameter('T');
    final source = FunctionType(outer, [inner], typeParameters: [inner]);
    final changed = substituteType(source, {outer: inner}) as FunctionType;
    expect(changed.result, same(inner));
    expect(changed.typeParameters.single, isNot(same(inner)));
    expect(changed.parameters.single, same(changed.typeParameters.single));
  });

  test('dependent bounds are checked after simultaneous substitution', () {
    final t = parameter('T', .number);
    final u = parameter('U', t);
    final source = FunctionType(u, [t, u], typeParameters: [t, u]);
    expect(source.instantiate([.number, .integer]).result, ValueType.integer);
    expect(() => source.instantiate([.integer, .number]), throwsArgumentError);
  });

  test('generic calls and instantiations preserve declaration identity', () {
    final t = parameter('T');
    final target = FunctionTarget(library, 'id', t, [t], typeParameters: [t]);
    final one = const Constant.integer(1);
    final call = DirectCall(target, [one], typeArguments: [ValueType.integer]);
    expect(call.target, same(target));
    expect(call.type, ValueType.integer);
    expect(() => DirectCall(target, [one]), throwsArgumentError);
    final generic = FunctionConstant(target);
    final applied = InstantiateFunction(generic, [ValueType.integer]);
    expect(FunctionCall(applied, [one]).type, ValueType.integer);
    expect(
      FunctionCall(generic, [one], {}, [ValueType.integer]).type,
      ValueType.integer,
    );
    expect(() => FunctionCall(generic, [one]), throwsArgumentError);
    expect(
      FunctionConstant(target, typeArguments: [ValueType.integer]).type,
      applied.type,
    );
  });

  test('class and function type arguments remain independent', () {
    final t = parameter('T', .number);
    final owner = ClassType(library, 'Box', typeParameters: [t]);
    final u = parameter('U', t);
    final member = FunctionTarget(
      library,
      'pick',
      u,
      [u],
      owner: owner,
      kind: .method,
      typeParameters: [u],
    );
    final receiver = Block([
      owner.instantiate([ValueType.number]),
    ]).parameters.single;
    final call = InstanceCall(
      member,
      receiver,
      [const Constant.integer(2)],
      {},
      null,
      [ValueType.integer],
    );
    expect(call.type, ValueType.integer);
    expect(
      () => InstanceCall(
        member,
        receiver,
        [const Constant.string('x')],
        {},
        null,
        [ValueType.string],
      ),
      throwsArgumentError,
    );
    expect(member.typeParameters.single.bound, same(t));
    final ctor = FunctionTarget(
      library,
      'new',
      .voidType,
      [t],
      owner: owner,
      kind: .initializer,
    );
    final generic = FunctionConstant(ctor);
    expect((generic.type as FunctionType).typeParameters, [t]);
    expect(ctor.typeParameters, isEmpty);
    final applied = InstantiateFunction(generic, [ValueType.integer]);
    expect(
      (applied.type as FunctionType).result,
      owner.instantiate([ValueType.integer]),
    );
    expect(
      (FunctionConstant(
                ctor,
                ownerType: owner.instantiate([ValueType.integer]),
              ).type
              as FunctionType)
          .typeParameters,
      isEmpty,
    );
  });

  test(
    'verifier accepts own and nested binders but rejects free call arguments',
    () {
      final t = parameter('T');
      final identity = FunctionTarget(
        library,
        'id',
        t,
        [t],
        typeParameters: [t],
      );
      final entry = Block(identity.parameterTypes);
      entry.finish(Return(entry.parameters.single));
      expect(() => IrFunction(identity, [entry]), returnsNormally);
      final foreign = parameter('Foreign');
      final callee = FunctionTarget(
        library,
        'ignore',
        .voidType,
        [],
        typeParameters: [t],
      );
      final root = FunctionTarget(library, 'root', .voidType, []);
      final bad = Block([]);
      bad.emit(DirectCall(callee, [], typeArguments: [foreign]));
      bad.finish(Return(null));
      expect(() => IrFunction(root, [bad]), throwsStateError);
      final good = Block([]);
      good.finish(Return(null));
      expect(() => IrFunction(root, [good]), returnsNormally);
    },
  );

  test(
    'phantom type arguments in nested constants and defaults cannot escape',
    () {
      final t = parameter('T');
      final foreign = parameter('T');
      final phantom = FunctionTarget(
        library,
        'phantom',
        .integer,
        [],
        typeParameters: [t],
      );
      final illegal = FunctionConstant(phantom, typeArguments: [foreign]);
      final recordType = RecordType([illegal.type]);
      final root = FunctionTarget(library, 'returnRecord', recordType, []);
      final entry = Block([])
        ..finish(Return(RecordConstant(recordType, [illegal])));
      expect(() => IrFunction(root, [entry]), throwsStateError);
      final defaultTarget = FunctionTarget(library, 'withDefault', .voidType, [
        illegal.type,
      ], optionalPositional: 1);
      final body = Block(defaultTarget.parameterTypes)..finish(const Return());
      expect(
        () => IrFunction(defaultTarget, [body], defaults: {0: illegal}),
        throwsStateError,
      );
      final generic = FunctionConstant(phantom);
      final goodTarget = FunctionTarget(
        library,
        'returnGeneric',
        generic.type,
        [],
      );
      final good = Block([])..finish(Return(generic));
      expect(() => IrFunction(goodTarget, [good]), returnsNormally);
    },
  );

  test('function bounds and static class scope are checked separately', () {
    final outer = parameter('T');
    final owner = ClassType(library, 'Owner', typeParameters: [outer]);
    final static = FunctionTarget(library, 'invalidStatic', outer, [
      outer,
    ], owner: owner);
    final entry = Block(static.parameterTypes)..finish(Return(null));
    expect(() => IrFunction(static, [entry]), throwsStateError);
    final u = parameter('U', outer);
    final top = FunctionTarget(
      library,
      'invalidBound',
      .voidType,
      [],
      typeParameters: [u],
    );
    final body = Block([])..finish(const Return());
    expect(() => IrFunction(top, [body]), throwsStateError);
  });

  test(
    'format includes generic binders and phantom instantiation arguments',
    () {
      final t = parameter('T');
      final callee = FunctionTarget(
        library,
        'phantom',
        .integer,
        [],
        typeParameters: [t],
      );
      final root = FunctionTarget(library, 'entry', .integer, []);
      final entry = Block([]);
      final instantiation = entry.emit(
        InstantiateFunction(FunctionConstant(callee), [ValueType.integer]),
      );
      entry.emit(DirectCall(callee, [], typeArguments: [ValueType.string]));
      entry.emit(
        FunctionCall(FunctionConstant(callee), [], {}, [ValueType.boolean]),
      );
      entry.finish(Return(entry.emit(FunctionCall(instantiation, []))));
      final output = StringBuffer();
      IrFunction(root, [entry]).writeTo(output);
      expect(
        output.toString(),
        contains('instantiate tearoff memory:generic-functions::phantom<int>'),
      );
      expect(output.toString(), contains('phantom<String>()'));
      expect(output.toString(), contains('phantom<bool>()'));
      final genericEntry = Block(callee.parameterTypes)
        ..finish(const Return(Constant.integer(1)));
      final genericOutput = StringBuffer();
      IrFunction(callee, [genericEntry]).writeTo(genericOutput);
      expect(genericOutput.toString(), contains('phantom<T extends Object?>'));
    },
  );

  test('constructor alias callable views preserve reordered fixed and repeated arguments', () {
    final a = parameter('A');
    final b = parameter('B');
    final pair = ClassType(library, 'Pair', typeParameters: [a, b]);
    final ctor = FunctionTarget(
      library,
      'new',
      .voidType,
      [a, b],
      owner: pair,
      kind: .initializer,
    );
    final x = parameter('X');
    final y = parameter('Y');
    FunctionType view(
      List<TypeParameterType> binders,
      List<ValueType> arguments,
    ) => FunctionType(
      pair.instantiate(arguments),
      arguments,
      typeParameters: binders,
    );
    final flip = FunctionConstant(
      ctor,
      constructorSignature: view([x, y], [y, x]),
      constructorAlias: (library, 'Flip'),
    );
    final fixed = FunctionConstant(
      ctor,
      constructorSignature: view([x], [ValueType.integer, x]),
      constructorAlias: (library, 'Fixed'),
    );
    final same = FunctionConstant(
      ctor,
      constructorSignature: view([x], [x, x]),
      constructorAlias: (library, 'Same'),
    );
    expect(
      (InstantiateFunction(flip, [ValueType.integer, ValueType.string]).type
              as FunctionType)
          .result,
      pair.instantiate([ValueType.string, ValueType.integer]),
    );
    expect(
      (InstantiateFunction(fixed, [ValueType.string]).type as FunctionType)
          .parameters,
      [ValueType.integer, ValueType.string],
    );
    expect(
      (InstantiateFunction(same, [ValueType.string]).type as FunctionType)
          .result,
      pair.instantiate([ValueType.string, ValueType.string]),
    );
    expect(
      (FunctionConstant(
                ctor,
                constructorSignature: flip.constructorSignature,
                constructorAlias: flip.constructorAlias,
                typeArguments: [ValueType.integer, ValueType.string],
              ).type
              as FunctionType)
          .result,
      pair.instantiate([ValueType.string, ValueType.integer]),
    );
    final root = FunctionTarget(library, 'alias', flip.type, []);
    final entry = Block([])..finish(Return(flip));
    final output = StringBuffer();
    IrFunction(root, [entry]).writeTo(output);
    expect(output.toString(), contains('::Flip.new'));
    expect(output.toString(), contains('Pair<Y, X>'));
    expect(ctor.typeParameters, isEmpty);
  });

  test('constructor callable view rejects forged signature and missing alias binders', () {
    final t = parameter('T');
    final owner = ClassType(library, 'Box', typeParameters: [t]);
    final ctor = FunctionTarget(
      library,
      'new',
      .voidType,
      [t],
      owner: owner,
      kind: .initializer,
    );
    final u = parameter('U');
    expect(
      () => FunctionConstant(ctor, constructorAlias: (library, 'Invalid')),
      throwsArgumentError,
    );
    expect(
      () => FunctionConstant(
        ctor,
        constructorSignature: FunctionType(
          owner.instantiate([u]),
          [ValueType.integer],
          typeParameters: [u],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => FunctionConstant(
        ctor,
        constructorSignature: FunctionType(
          ValueType.integer,
          [u],
          typeParameters: [u],
        ),
      ),
      throwsArgumentError,
    );
    final signature = FunctionType(
      owner.instantiate([u]),
      [u],
      typeParameters: [u],
    );
    expect(
      () => FunctionConstant(
        ctor,
        ownerType: owner.instantiate([ValueType.integer]),
        constructorSignature: signature,
      ),
      throwsArgumentError,
    );
    final foreign = parameter('Foreign');
    final phantom = parameter('Phantom', foreign);
    final hidden = FunctionType(
      owner.instantiate([ValueType.integer]),
      [ValueType.integer],
      typeParameters: [phantom],
    );
    final constant = FunctionConstant(
      ctor,
      constructorSignature: hidden,
      constructorAlias: (library, 'Hidden'),
    );
    final root = FunctionTarget(library, 'badAlias', constant.type, []);
    final body = Block([])..finish(Return(constant));
    expect(() => IrFunction(root, [body]), throwsStateError);
  });

  test(
    'generic function bounds trigger covariance at every surrounding polarity',
    () {
      final t = parameter('T');
      final owner = ClassType(library, 'BoundOwner', typeParameters: [t]);
      final u = parameter('U', t);
      final callback = FunctionType(
        ValueType.voidType,
        [u],
        typeParameters: [u],
      );
      final callbackResult = FunctionType(u, [u], typeParameters: [u]);
      final shapes = <ValueType>[
        callback,
        FunctionType(callbackResult, []),
        FunctionType(ValueType.voidType, [callback]),
        FunctionType(ValueType.voidType, [
          FunctionType(ValueType.voidType, [callback]),
        ]),
        RecordType([callback]),
        CoreTypes.list.instantiate([callback]),
      ];
      final member = FunctionTarget(
        library,
        'takes',
        ValueType.voidType,
        shapes,
        owner: owner,
        kind: .method,
      );
      expect(member.covariantParameters, {0, 1, 2, 3, 4, 5});
      expect(
        member.reifiedSignature.parameters,
        List<ValueType>.filled(shapes.length, ValueType.object.nullable),
      );
      final receiver = Block([
        owner.instantiate([ValueType.integer]),
      ]).parameters.single;
      final tearoff = BindMethod(member, receiver);
      expect(tearoff.mayThrow, isTrue);
      final staticSignature = tearoff.type as FunctionType;
      final runtimeSignature = member.tearOffSignature(
        ownerType: owner.instantiate([ValueType.integer]),
        reified: true,
      );
      expect(staticSignature.accepts(runtimeSignature), isTrue);
      expect(member.signature.parameters.first, same(callback));
    },
  );

  test(
    'covariance excludes shadowed binders and ordinary negative occurrences',
    () {
      final t = parameter('T');
      final owner = ClassType(library, 'ShadowOwner', typeParameters: [t]);
      final shadow = parameter('T');
      final u = parameter('U', shadow);
      final selfBound = FunctionType(
        ValueType.voidType,
        [u],
        typeParameters: [shadow, u],
      );
      final negative = FunctionType(ValueType.voidType, [t]);
      final positive = FunctionType(t, []);
      final member = FunctionTarget(
        library,
        'takes',
        ValueType.voidType,
        [selfBound, negative, positive],
        owner: owner,
        kind: .method,
      );
      expect(member.covariantParameters, {2});
      expect(member.reifiedSignature.parameters[0], selfBound);
      expect(member.reifiedSignature.parameters[1], negative);
      expect(member.reifiedSignature.parameters[2], ValueType.object.nullable);
      final own = parameter('T', ValueType.number);
      final generic = FunctionTarget(
        library,
        'generic',
        own,
        [own],
        owner: owner,
        kind: .method,
        typeParameters: [own],
      );
      expect(generic.covariantParameters, isEmpty);
    },
  );
}
