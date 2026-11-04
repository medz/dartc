import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('memory:generics');
  TypeParameterType parameter(String name, [ValueType? bound]) =>
      TypeParameterType(name)
        ..initializeBound(bound ?? ValueType.object.nullable);

  test(
    'type variables preserve identity and do not accept bound inhabitants',
    () {
      final t = parameter('T');
      final other = parameter('T');
      expect(t, isNot(other));
      expect(t.accepts(ValueType.integer), isFalse);
      expect(t.accepts(ValueType.nullType), isFalse);
      expect(t.mayBeNull, isTrue);
      expect(t.nullable.accepts(t), isTrue);
      final sub = parameter('U', t);
      expect(t.accepts(sub.nonNullable), isTrue);
      expect(t.nonNullable.accepts(sub.nonNullable), isTrue);
      expect(t.nonNullable.mayBeNull, isFalse);
      expect(t.nullable.nonNullable.mayBeNull, isFalse);
      expect(
        substituteType(t.nullable, {t: ValueType.integer}),
        ValueType.integer.nullable,
      );
      expect(ValueType.object.nullable.accepts(t), isTrue);
      expect(t.accepts(t.nonNullable), isTrue);
      expect(
        substituteType(t.nonNullable, {t: ValueType.integer.nullable}),
        ValueType.integer,
      );
      expect(() => t.initializeBound(ValueType.object), throwsStateError);
    },
  );

  test(
    'applied identity, covariance and inherited substitution retain arguments',
    () {
      final t = parameter('T');
      final base = ClassType(library, 'Base', typeParameters: [t]);
      final u = parameter('U');
      final child = ClassType(
        library,
        'Child',
        typeParameters: [u],
        superclass: base.instantiate([
          RecordType([u]),
        ]),
      );
      final ints = child.instantiate([ValueType.integer]);
      expect(
        ints.asInstanceOf(base),
        base.instantiate([
          RecordType([ValueType.integer]),
        ]),
      );
      expect(child.instantiate([ValueType.number]).accepts(ints), isTrue);
      expect(ints.accepts(child.instantiate([ValueType.string])), isFalse);
      expect(ints, child.instantiate([ValueType.integer]));
      expect(ints.hashCode, child.instantiate([ValueType.integer]).hashCode);
      expect(() => child.instantiate([]), throwsArgumentError);
      expect(ints.dartName, 'Child<int>');
    },
  );

  test('two phase declarations support self-referential bounds and hierarchy arguments', () {
    final t = TypeParameterType('T');
    final node = ClassType.declare(library, 'Node', typeParameters: [t]);
    t.initializeBound(node.instantiate([t]));
    node.initializeHierarchy();
    expect(t.bound, node);
    expect(node.instantiate([ValueType.integer]).superclass, ValueType.object);
    expect(() => node.initializeHierarchy(), throwsStateError);
  });

  test('graphs reject type variables outside their lexical owner', () {
    final t = parameter('T');
    final fn = FunctionTarget(library, 'foreign', t, [t]);
    final entry = Block([t]);
    entry.finish(Return(entry.parameters.single));
    expect(() => IrFunction(fn, [entry]), throwsStateError);
  });

  test('bounds are checked simultaneously at allocation', () {
    final t = parameter('T', ValueType.number);
    final box = ClassType(library, 'NumericBox', typeParameters: [t]);
    final ctor = FunctionTarget(
      library,
      '',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    expect(
      () => Construct(
        ctor,
        [],
        instantiatedType: box.instantiate([ValueType.string]),
      ),
      throwsArgumentError,
    );
    expect(
      Construct(
        ctor,
        [],
        instantiatedType: box.instantiate([ValueType.integer]),
      ).type.dartName,
      'NumericBox<int>',
    );
  });

  test(
    'member views share identities while signatures and allocation are applied',
    () {
      final t = parameter('T');
      final box = ClassType(library, 'Box', typeParameters: [t]);
      final ints = box.instantiate([ValueType.integer]);
      final field = InstanceField(box, 'value', t);
      final member = FunctionTarget(
        library,
        'replace',
        t,
        [t],
        owner: box,
        kind: .method,
      );
      final ctor = FunctionTarget(
        library,
        '',
        .voidType,
        [t],
        owner: box,
        kind: .initializer,
      );
      final receiver = Block([ints]).parameters.single;
      expect(LoadField(field, receiver).type, ValueType.integer);
      expect(
        InstanceCall(member, receiver, [const Constant.integer(1)]).type,
        ValueType.integer,
      );
      expect(
        () => InstanceCall(member, receiver, [const Constant.string('x')]),
        throwsArgumentError,
      );
      expect((BindMethod(member, receiver).type as FunctionType).parameters, [
        ValueType.integer,
      ]);
      final broad = box.instantiate([ValueType.number]);
      final upcast = TypeView(receiver, broad);
      expect(upcast.mayThrow, isFalse);
      expect(
        InstanceCall(member, upcast, [const Constant.floating(1.5)]).type,
        ValueType.number,
      );
      expect(
        () => TypeView(receiver, box.instantiate([ValueType.string])),
        throwsArgumentError,
      );
      expect(
        InstanceCall(
          member,
          receiver,
          [const Constant.floating(1.5)],
          const {},
          broad,
        ).type,
        ValueType.number,
      );
      expect(
        (BindMethod(member, receiver, ownerType: broad).type as FunctionType)
            .result,
        ValueType.number,
      );
      expect(member.covariantParameters, {0});
      final consumes = FunctionTarget(
        library,
        'consumes',
        .voidType,
        [
          FunctionType(.voidType, [t]),
        ],
        owner: box,
        kind: .method,
      );
      final produces = FunctionTarget(
        library,
        'produces',
        .voidType,
        [FunctionType(t, [])],
        owner: box,
        kind: .method,
      );
      expect(consumes.covariantParameters, isEmpty);
      expect(produces.covariantParameters, {0});
      expect(member.reifiedSignature.parameters, [ValueType.object.nullable]);
      expect(
        Construct(ctor, [
          const Constant.integer(1),
        ], instantiatedType: ints).type,
        ints,
      );
      expect(
        (FunctionConstant(ctor, ownerType: ints).type as FunctionType).result,
        ints,
      );
      expect(
        DirectCall(member, [
          receiver,
          const Constant.integer(1),
        ], ownerType: ints).type,
        ValueType.integer,
      );
    },
  );
}
