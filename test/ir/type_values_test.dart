import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  TypeParameterType parameter(String name) =>
      TypeParameterType(name)..initializeBound(ValueType.object.nullable);
  test('nullable structure retains its parameter before flow narrowing', () {
    final t = parameter('T');
    expect(t.nullable.nullableBase, same(t));
    expect(t.nullable.nonNullable, t.nonNullable);
    expect(ValueType.nullType.nullableBase, isNull);
    expect(ValueType.futureOr(ValueType.integer.nullable).nullableBase, isNull);
  });

  test(
    'runtime normalization retains static binders and callable metadata',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.never)
        ..initializeDefaultType(ValueType.never);
      final u = TypeParameterType('U')..initializeBound(ValueType.never);
      final original = FunctionType(t.nullable, [t], typeParameters: [t]);
      final expected = FunctionType(.nullType, [.never], typeParameters: [u]);
      final normalized = original.normalize() as FunctionType;
      expect(original, isNot(expected));
      expect(normalized, expected);
      expect(normalized.hashCode, expected.hashCode);
      expect(normalized.normalize(), normalized);
      expect(normalized.typeParameters.single, isNot(same(t)));
      expect(normalized.typeParameters.single.defaultType, ValueType.never);
      expect(
        normalized.instantiate([ValueType.never]).result,
        ValueType.nullType,
      );
      expect(original.result, t.nullable);
      expect(original.parameters.single, same(t));
      expect(
        TypeConstant(original).structuralKey,
        TypeConstant(expected).structuralKey,
      );
    },
  );

  test(
    'normalization follows dependent bounds through nested function scopes',
    () {
      final t = TypeParameterType('T'), u = TypeParameterType('U');
      t.initializeBound(u);
      u.initializeBound(ValueType.never);
      final v = TypeParameterType('V')..initializeBound(t);
      final source = FunctionType(
        t,
        [
          FunctionType(
            v.nullable,
            [ValueType.futureOr(t)],
            typeParameters: [v],
          ),
        ],
        typeParameters: [t, u],
      );
      final a = TypeParameterType('A')..initializeBound(ValueType.never);
      final b = TypeParameterType('B')..initializeBound(ValueType.never);
      final c = TypeParameterType('C')..initializeBound(ValueType.never);
      final expected = FunctionType(
        .never,
        [
          FunctionType(
            .nullType,
            [
              ValueType.future.instantiate([ValueType.never]),
            ],
            typeParameters: [c],
          ),
        ],
        typeParameters: [a, b],
      );
      expect(source.normalize(), expected);
      expect(source.normalize().hashCode, expected.hashCode);
    },
  );

  test(
    'normalization preserves free identities, recursive bounds and named slots',
    () {
      final free = parameter('Free');
      final t = TypeParameterType('T');
      t.initializeBound(CoreTypes.listOf(t));
      t.initializeDefaultType(CoreTypes.listOf(free));
      final source = FunctionType(
        free,
        [t, free],
        typeParameters: [t],
        namedParameters: {'z': true, 'a': false},
      );
      final normalized = source.normalize() as FunctionType;
      final fresh = normalized.typeParameters.single;
      expect(normalized, source);
      expect(normalized.hashCode, source.hashCode);
      expect(normalized.result, same(free));
      expect(fresh.bound, CoreTypes.listOf(fresh));
      expect(fresh.defaultType, CoreTypes.listOf(free));
      expect(normalized.named, source.named);
      expect(normalized.normalize(), normalized);
      for (final type in <ValueType>[
        .dynamicType,
        .voidType,
        .object.nullable,
      ]) {
        expect(type.normalize(), type);
      }
      expect(() => CellType(.integer).normalize(), throwsArgumentError);
    },
  );

  test('constant identity normalizes values, container types and tear-off arguments', () {
    final t = TypeParameterType('T')..initializeBound(ValueType.never);
    final u = TypeParameterType('U')..initializeBound(ValueType.never);
    final a = FunctionType(t, [t], typeParameters: [t]);
    final b = FunctionType(.never, [.never], typeParameters: [u]);
    final p = parameter('P');
    final box = ClassType(Uri.parse('memory:type'), 'Box', typeParameters: [p]);
    final field = InstanceField(box, 'type', .typeType, isFinal: true);
    final target = FunctionTarget(
      Uri.parse('memory:type'),
      'identity',
      p,
      [p],
      typeParameters: [p],
    );
    final constructor = FunctionTarget(
      box.library,
      'Box',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    List<Constant> values(ValueType type) => [
      TypeConstant(type),
      SequenceConstant(CoreTypes.listOf(type), []),
      SequenceConstant(CoreTypes.setOf(type), []),
      MapConstant(CoreTypes.mapOf(.integer, type), []),
      ObjectConstant(box.instantiate([type]), {field: TypeConstant(type)}),
      FunctionConstant(target, typeArguments: [type]),
      FunctionConstant(constructor, ownerType: box.instantiate([type])),
      RecordConstant(RecordType([CoreTypes.listOf(type)]), [
        SequenceConstant(CoreTypes.listOf(type), []),
      ]),
    ];
    final left = values(a),
        right = values(b),
        other = values(ValueType.integer);
    for (var i = 0; i < left.length; i++) {
      expect(left[i].structuralKey, right[i].structuralKey, reason: '$i');
      expect(
        left[i].structuralKey.hashCode,
        right[i].structuralKey.hashCode,
        reason: '$i',
      );
      expect(
        left[i].structuralKey,
        isNot(other[i].structuralKey),
        reason: '$i',
      );
    }
  });

  test(
    'normalization removes redundant intersections and retains refinements',
    () {
      final t = parameter('T');
      final n = TypeParameterType('N')..initializeBound(ValueType.integer);
      for (final (type, expected) in <(ValueType, ValueType)>[
        (PromotedTypeParameterType(t, .object), t.nonNullable),
        (PromotedTypeParameterType(t, .dynamicType), t),
        (PromotedTypeParameterType(t, .nullType, isNonNullable: true), .never),
        (PromotedTypeParameterType(n, .number, isNonNullable: true), n),
        (n.nonNullable, n),
        (
          PromotedTypeParameterType(t, .integer),
          PromotedTypeParameterType(t, .integer),
        ),
      ]) {
        expect(type.normalize(), expected);
        expect(type.normalize().normalize(), expected);
      }
    },
  );

  test('type constants require closed source types including nested slots', () {
    final t = parameter('T');
    for (final type in <ValueType>[
      t,
      CoreTypes.listOf(t),
      CellType(ValueType.integer),
    ]) {
      expect(() => TypeConstant(type), throwsArgumentError);
    }
    final generic = FunctionType(t, [t], typeParameters: [t]);
    expect(TypeConstant(generic).type, ValueType.typeType);
    expect(
      TypeConstant(ValueType.voidType).representedType,
      ValueType.voidType,
    );
    expect(
      TypeConstant(ValueType.integer).structuralKey,
      TypeConstant(ValueType.integer).structuralKey,
    );
    expect(
      TypeConstant(ValueType.dynamicType).structuralKey,
      isNot(TypeConstant(ValueType.object.nullable).structuralKey),
    );
  });
  test('reification is pure and verifier checks lexical template scope', () {
    final t = parameter('T');
    final op = ReifyType(CoreTypes.listOf(t));
    expect(op.inputs, isEmpty);
    expect(op.mayThrow, isFalse);
    final block = Block();
    block.emit(op);
    block.finish(Return(op));
    expect(
      () => IrFunction(
        FunctionTarget(Uri.parse('memory:type'), 'bad', ValueType.typeType, []),
        [block],
      ),
      throwsStateError,
    );
    final good = Block();
    final result = good.emit(ReifyType(CoreTypes.listOf(t)));
    good.finish(Return(result));
    expect(
      () => IrFunction(
        FunctionTarget(
          Uri.parse('memory:type'),
          'good',
          ValueType.typeType,
          [],
          typeParameters: [t],
        ),
        [good],
      ),
      returnsNormally,
    );
    expect(() => ReifyType(CellType(ValueType.integer)), throwsArgumentError);
  });
}
