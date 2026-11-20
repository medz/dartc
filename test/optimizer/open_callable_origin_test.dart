import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

TypeParameterType variable(String name) => TypeParameterType(name)
  ..initializeBound(ValueType.object.nullable)
  ..initializeDefaultType(ValueType.dynamicType);

void main() {
  for (final hasCall in [false, true]) {
    test('an ordinary object fails an open function cast (call=$hasCall)', () {
      final parameter = variable('T');
      final root = FunctionTarget(
        null,
        'invoke',
        .object.nullable,
        [],
        typeParameters: [parameter],
      );
      final error = FunctionTarget(null, 'exhausted', .never, []);
      final reported = const Constant.string('allocation failed');
      final failed = Block()..finish(Throw(reported));
      final plain = ClassType(null, 'Plain');
      final method = FunctionTarget(
        null,
        'call',
        .integer,
        [],
        owner: plain,
        kind: .method,
      );
      final body = Block(method.parameterTypes)
        ..finish(const Return(Constant.integer(7)));
      final entry = Block();
      final object = entry.emit(NewPayload(plain, const Constant.integer(0)));
      final checked = entry.emit(TypeCast(object, FunctionType(parameter, [])));
      final action = entry.emit(FunctionCall(checked, []));
      entry.finish(Return(action));
      final program = IrProgram(
        [
          IrClass(plain, [], members: [if (hasCall) method]),
        ],
        [
          IrFunction(root, [entry]),
          IrFunction(error, [failed]),
          if (hasCall) IrFunction(method, [body]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: []),
      ], allocationFailure: error).facts;
      expect(facts.valueOf(checked).isBottom, isTrue);
      expect(
        facts.failureOf(checked).exception.unknownTypes,
        contains(ValueType.typeError),
      );
      expect(facts.failureOf(object).exception.constants, contains(reported));
      expect(facts.returnedBy(root).isBottom, isTrue);
      expect(facts.targetsOf(action), isEmpty);
      expect(facts.hasUnknownCall(action), isFalse);
    });
  }

  test(
    'an external source retains known and unknown callable alternatives',
    () {
      final parameter = variable('E');
      final signature = FunctionType(.boolean, [parameter]);
      final root = FunctionTarget(
        null,
        'filter',
        .boolean,
        [parameter],
        typeParameters: [parameter],
      );
      final plain = ClassType(null, 'NonCallable');
      final predicate = FunctionTarget(
        null,
        'predicate',
        .boolean,
        [ValueType.object.nullable],
        kind: .closure,
        enclosing: root,
        sourceOffset: 1,
      );
      final implementation = Block(predicate.parameterTypes)
        ..finish(const Return(Constant.boolean(true)));
      final ext = FunctionTarget(null, 'select', .object.nullable, [
        .object,
        .object,
      ]);
      final entry = Block(root.parameterTypes);
      final object = entry.emit(NewPayload(plain, const Constant.integer(0)));
      final closure = entry.emit(MakeClosure(predicate, []));
      final selected = entry.emit(DirectCall(ext, [object, closure]));
      final cast = entry.emit(TypeCast(selected, signature));
      final call = entry.emit(FunctionCall(cast, [entry.parameters.single]));
      entry.finish(Return(call));
      final program = IrProgram(
        [IrClass(plain, [])],
        [
          IrFunction(root, [entry]),
          IrFunction(predicate, [implementation]),
        ],
        externals: [
          IrExternal(
            ext,
            effects: {},
            memory: const ExternalMemory.unchanged(),
            capturesArguments: false,
          ),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: [FlowValue.unknown(parameter)]),
      ]).facts;
      expect(
        facts.valueOf(selected).objects.map((o) => o.site),
        containsAll([object, closure]),
      );
      final callable = facts.valueOf(cast);
      expect(callable.objects.map((o) => o.site), orderedEquals([closure]));
      expect(callable.externalUnknownTypes, contains(signature));
      expect(
        facts.failureOf(cast).exception.unknownTypes,
        contains(ValueType.typeError),
      );
      expect(facts.targetsOf(call), contains(predicate));
      expect(facts.hasUnknownCall(call), isTrue);
    },
  );

  test(
    'a borrowed address and a generic nominal argument supply no function bits',
    () {
      final e = variable('E');
      final t = variable('T');
      final data = ClassType(null, 'Container', typeParameters: [t]);
      final nominal = data.instantiate([e]);
      final object = FlowObject(
        AllocatedObject(
          const Constant.integer(4096),
          nominal,
          const Constant.integer(0),
        ),
        Object(),
      );
      final address = FlowValue.address(FlowAddress(object, 0));
      final signature = FunctionType(.boolean, [e]);
      for (final value in [FlowValue.object(object), address]) {
        expect(value.externalValue(signature).objects, isEmpty);
        expect(
          value.externalValue(signature).externalUnknownTypes,
          contains(signature),
        );
      }
      expect(signature.mayHaveInstance(nominal), isFalse);
      expect(signature.mayHaveInstance(ValueType.function), isTrue);
      expect(
        FlowValue.unknown(signature).check(signature).value.unknownTypes,
        contains(signature),
      );
    },
  );
}
