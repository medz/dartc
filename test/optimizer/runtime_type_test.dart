import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:runtime-type-flow');

void main() {
  for (final throws in [false, true]) {
    test('user Type equality preserves writes and exceptions ($throws)', () {
      final user = ClassType(
        _uri,
        'UserType',
        interfaces: [ValueType.typeType],
      );
      final observed = GlobalVariable(_uri, 'observed', .integer, isLate: true);
      final equality = FunctionTarget(
        _uri,
        '==',
        .boolean,
        [.object],
        owner: user,
        kind: .method,
      );
      final equalBody = Block(equality.parameterTypes);
      equalBody.emit(StoreGlobal(observed, const Constant.integer(9)));
      equalBody.finish(
        throws
            ? Throw(const Constant.string('equality failed'))
            : const Return(Constant.boolean(true)),
      );
      final helper = FunctionTarget(_uri, 'compare', .voidType, [.typeType]);
      final compare = Block(helper.parameterTypes);
      compare.emit(Equals(compare.parameters.single, TypeConstant(.integer)));
      compare.finish(const Return());
      final root = FunctionTarget(_uri, 'root', .integer, []);
      final entry = Block(), normal = Block(), exceptional = Block();
      entry.emit(StoreGlobal(observed, const Constant.integer(1)));
      final call = DirectCall(helper, [ObjectConstant(user, {})]);
      entry.finish(
        Invoke(call, onReturn: Jump(normal), onThrow: Jump(exceptional)),
      );
      normal.finish(Return(normal.emit(LoadGlobal(observed))));
      exceptional.finish(
        Return(
          exceptional.emit(
            IntBinary(
              .add,
              exceptional.emit(LoadGlobal(observed)),
              const Constant.integer(100),
            ),
          ),
        ),
      );
      final program = IrProgram(
        [
          IrClass(user, [], members: [equality]),
        ],
        [
          IrFunction(root, [entry, normal, exceptional]),
          IrFunction(helper, [compare]),
          IrFunction(equality, [equalBody]),
        ],
        globals: [observed],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: <FlowValue>[]),
      ]).facts;
      final expected = throws ? 109 : 9;
      expect(
        facts.returnedBy(root).constant?.structuralKey,
        Constant.integer(expected).structuralKey,
      );
      expect(facts.activationsOf(equality), isNotEmpty);
      final simplified = ProgramOptimizer(const [ProgramSimplification()])
          .run(program, [(target: root, arguments: [])])
          .program;
      for (final graph in [program, simplified]) {
        expect(
          IrInterpreter(
            graph,
            {},
          ).run(graph.implementationOf(root) as IrFunction, []),
          expected,
        );
      }
    });
  }

  test('constant runtime metadata follows actual nested value types', () {
    final record = RecordConstant(
      RecordType([ValueType.object], {'named': ValueType.object}),
      [TypeConstant(.integer), const Constant.integer(7)],
    );
    for (final value in <Constant>[
      const Constant.integer(7),
      const Constant.floating(1.5),
      const Constant.boolean(true),
      const Constant.nullValue(),
      const Constant.string('value'),
      TypeConstant(.integer),
      record,
    ]) {
      final result = _input(value.type, FlowValue.constant(value));
      expect(_type(result), value.runtimeValueType.reify());
    }
    expect(
      record.runtimeValueType,
      RecordType([TypeMetadata.type], {'named': ValueType.integer}),
    );
  });

  test('closed scalar bounds retain each possible runtime descriptor', () {
    final bounds = <ValueType, Set<ValueType>>{
      ValueType.integer: {ValueType.integer},
      ValueType.floating: {ValueType.floating},
      ValueType.boolean: {ValueType.boolean},
      ValueType.number: {ValueType.integer, ValueType.floating},
    };
    for (final MapEntry(:key, :value) in bounds.entries) {
      for (final type in [key, key.nullable]) {
        final actual = _input(type, FlowValue.unknown(type));
        expect(actual.unknownTypes, isEmpty, reason: type.dartName);
        expect(
          actual.constants
              .map((c) => (c as TypeConstant).representedType)
              .toSet(),
          {...value, if (type != key) ValueType.nullType},
          reason: type.dartName,
        );
      }
    }
    expect(
      _type(_input(ValueType.nullType, FlowValue.unknown(ValueType.nullType))),
      ValueType.nullType,
    );
  });

  test(
    'unknown nominal, generic and record bounds do not become exact types',
    () {
      final box = ClassType(_uri, 'Box');
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final record = RecordType([ValueType.object], const {});
      for (final type in <ValueType>[
        ValueType.object,
        box,
        t,
        record,
        box.nullable,
        ValueType.string,
      ]) {
        final result = _input(
          type,
          FlowValue.unknown(type),
          parameters: type == t ? [t] : [],
        );
        expect(result.constant, isNull, reason: '$type');
        expect(result.unknownTypes, {TypeMetadata.type});
      }
    },
  );

  test(
    'allocation metadata uses exact classes and keeps open arguments unknown',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final element = TypeParameterType('E')..initializeBound(.object.nullable);
      final box = ClassType(_uri, 'Box', typeParameters: [element]);
      for (final argument in <ValueType>[ValueType.integer, t]) {
        final actual = box.instantiate([argument]);
        final root = FunctionTarget(
          _uri,
          'root',
          .typeType,
          [],
          typeParameters: [t],
        );
        final body = Block();
        final object = body.emit(
          AllocatedObject(
            const Constant.integer(4096),
            actual,
            const Constant.integer(0),
          ),
        );
        body.finish(Return(body.emit(ObjectRuntimeType(object, direct: true))));
        final facts = ProgramFlow(
          IrProgram(
            [IrClass(box, [])],
            [
              IrFunction(root, [body]),
            ],
          ),
          [(target: root, arguments: <FlowValue>[])],
        ).facts;
        final result = facts.returnedBy(root);
        if (argument == t) {
          expect(result.constant, isNull);
          expect(result.unknownTypes, {TypeMetadata.type});
        } else {
          expect(_type(result), actual);
        }
      }
    },
  );

  test('a fresh record does not make its static field bounds exact', () {
    final root = FunctionTarget(_uri, 'root', .typeType, [.object]);
    final body = Block(root.parameterTypes);
    final record = body.emit(
      MakeRecord(RecordType([ValueType.object]), [body.parameters.single]),
    );
    body.finish(Return(body.emit(ObjectRuntimeType(record, direct: true))));
    final facts = ProgramFlow(
      IrProgram([], [
        IrFunction(root, [body]),
      ]),
      [
        (target: root, arguments: [FlowValue.unknown(.object)]),
      ],
    ).facts;
    expect(facts.returnedBy(root).constant, isNull);
    expect(facts.returnedBy(root).unknownTypes, {TypeMetadata.type});
  });

  test('direct metadata does not replace a user runtimeType override', () {
    final owner = ClassType(_uri, 'Custom');
    final getter = FunctionTarget(
      _uri,
      'runtimeType',
      .typeType,
      [],
      owner: owner,
      kind: .getter,
    );
    final getterBody = Block(getter.parameterTypes)
      ..finish(Return(TypeConstant(.string)));
    for (final direct in [false, true]) {
      final root = FunctionTarget(_uri, 'root', .typeType, []);
      final body = Block();
      final object = body.emit(NewPayload(owner, const Constant.integer(0)));
      body.finish(Return(body.emit(ObjectRuntimeType(object, direct: direct))));
      final program = IrProgram(
        [
          IrClass(owner, [], members: [getter]),
        ],
        [
          IrFunction(root, [body]),
          IrFunction(getter, [getterBody]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: <FlowValue>[]),
      ]).facts;
      expect(_type(facts.returnedBy(root)), direct ? owner : ValueType.string);
      expect(facts.activationsOf(getter).isNotEmpty, !direct);
    }
  });
}

FlowValue _input(
  ValueType type,
  FlowValue value, {
  List<TypeParameterType> parameters = const [],
}) {
  final root = FunctionTarget(_uri, 'root', .typeType, [
    type,
  ], typeParameters: parameters);
  final body = Block(root.parameterTypes);
  body.finish(
    Return(body.emit(ObjectRuntimeType(body.parameters.single, direct: true))),
  );
  return ProgramFlow(
    IrProgram([], [
      IrFunction(root, [body]),
    ]),
    [
      (target: root, arguments: [value]),
    ],
  ).facts.returnedBy(root);
}

ValueType? _type(FlowValue value) => switch (value.constant) {
  TypeConstant(:final representedType) => representedType,
  _ => null,
};
