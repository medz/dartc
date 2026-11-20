import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:dispatch-storage');
  FunctionTarget getter(ClassType owner) =>
      FunctionTarget(uri, 'n', .integer, [], owner: owner, kind: .getter);

  test(
    'an interface implementer does not enter the implemented class getter',
    () {
      final base = ClassType(uri, 'Owner');
      final implementation = ClassType(uri, 'Implementer', interfaces: [base]);
      final child = ClassType(uri, 'Child', superclass: base);
      final field = InstanceField(base, 'n', .integer);
      final readBase = getter(base),
          readImplementation = getter(implementation);
      final baseBody = Block(readBase.parameterTypes);
      baseBody.finish(
        Return(baseBody.emit(LoadField(field, baseBody.parameters.single))),
      );
      final override = Block(readImplementation.parameterTypes)
        ..finish(const Return(Constant.integer(29)));

      final root = FunctionTarget(uri, 'root', .integer, [.boolean, .boolean]);
      final entry = Block(root.parameterTypes),
          choose = Block(),
          first = Block(),
          second = Block(),
          third = Block(),
          joined = Block([base]);
      entry.finish(Branch(entry.parameters[0], Jump(first), Jump(choose)));
      choose.finish(Branch(entry.parameters[1], Jump(second), Jump(third)));
      for (final (block, object) in [
        (
          first,
          ModuleObject(
            base,
            initialFields: {field: const Constant.integer(18)},
          ),
        ),
        (second, ModuleObject(implementation)),
        (
          third,
          ModuleObject(
            child,
            initialFields: {field: const Constant.integer(41)},
          ),
        ),
      ]) {
        block.finish(Jump(joined, [block.emit(ModuleObjectReference(object))]));
      }
      final call = joined.emit(
        InstanceCall(readBase, joined.parameters.single, []),
      );
      joined.finish(Return(call));
      final program = IrProgram(
        [
          IrClass(base, [field], members: [readBase]),
          IrClass(implementation, [], members: [readImplementation]),
          IrClass(child, []),
        ],
        [
          IrFunction(root, [entry, choose, first, second, third, joined]),
          IrFunction(readBase, [baseBody]),
          IrFunction(readImplementation, [override]),
        ],
      );
      ProgramFlowFacts analyze(FlowValue a, FlowValue b) =>
          ProgramFlow(program, [
            (target: root, arguments: [a, b]),
          ]).facts;
      final facts = analyze(
        FlowValue.unknown(.boolean),
        FlowValue.unknown(.boolean),
      );
      expect(facts.targetsOf(call), {readBase, readImplementation});
      final retained = {
        for (final activation in facts.activationsOf(readBase))
          ...facts
              .valueOf(baseBody.parameters.single, activation: activation)
              .objects
              .map((o) => o.type),
      };
      expect(retained, {base, child});
      for (final (a, b, expected) in [
        (true, true, 18),
        (false, true, 29),
        (false, false, 41),
      ]) {
        expect(
          analyze(
            FlowValue.constant(Constant.boolean(a)),
            FlowValue.constant(Constant.boolean(b)),
          ).returnedBy(root).integers?.constant,
          expected,
        );
      }
    },
  );

  test('one getter in distinct open generic environments keeps its matching allocations', () {
    final e = TypeParameterType('E')..initializeBound(.object.nullable);
    final base = ClassType(uri, 'Box', typeParameters: [e]);
    final field = InstanceField(base, 'n', .integer);
    final constructor = FunctionTarget(
      uri,
      '',
      .voidType,
      [.integer],
      owner: base,
      kind: .initializer,
    );
    final init = Block(constructor.parameterTypes);
    init.emit(StoreField(field, init.parameters.first, init.parameters.last));
    init.finish(const Return());
    final target = getter(base);
    final body = Block(target.parameterTypes);
    body.finish(Return(body.emit(LoadField(field, body.parameters.single))));
    final a = TypeParameterType('T')..initializeBound(.object.nullable),
        b = TypeParameterType('T')..initializeBound(.object.nullable);
    final left = base.instantiate([a]), right = base.instantiate([b]);
    final root = FunctionTarget(
      uri,
      'read',
      .integer,
      [.boolean],
      typeParameters: [a, b],
    );
    final entry = Block(root.parameterTypes),
        first = Block(),
        second = Block(),
        joined = Block([
          base.instantiate([ValueType.object.nullable]),
        ]);
    entry.finish(Branch(entry.parameters.first, Jump(first), Jump(second)));
    for (final (block, type, n) in [(first, left, 13), (second, right, 43)]) {
      final box = block.emit(
        Construct(constructor, [Constant.integer(n)], instantiatedType: type),
      );
      block.finish(Jump(joined, [box]));
    }
    final call = joined.emit(InstanceCall(target, joined.parameters.first, []));
    joined.finish(Return(call));
    final program = IrProgram(
      [
        IrClass(base, [field], constructors: [constructor], members: [target]),
      ],
      [
        IrFunction(constructor, [init]),
        IrFunction(target, [body]),
        IrFunction(root, [entry, first, second, joined]),
      ],
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: [FlowValue.unknown(.boolean)]),
    ]).facts;
    expect(facts.targetsOf(call), {target});
    final receivers = [
      for (final activation in facts.activationsOf(target))
        facts
            .valueOf(body.parameters.single, activation: activation)
            .objects
            .map((o) => o.type)
            .toSet(),
    ];
    expect(
      receivers,
      unorderedEquals([
        {left},
        {right},
      ]),
    );
    expect(facts.returnedBy(root).integers?.lower, 13);
    expect(facts.returnedBy(root).integers?.upper, 43);
  });

  test('unknown abstract receivers keep matching implementations and external provenance', () {
    final interface = ClassType(uri, 'Interface', isAbstract: true);
    final parent = ClassType(uri, 'Parent', interfaces: [interface]);
    final child = ClassType(uri, 'Child', superclass: parent);
    final other = ClassType(uri, 'Other');
    final value = FlowValue.unknown(
      interface,
      external: true,
    ).join(FlowValue.unknown(other));
    expect(value.receiverFor(parent).externalUnknownTypes, {parent});
    expect(value.receiverFor(child).externalUnknownTypes, {child});
    expect(value.receiverFor(other).externalUnknownTypes, isEmpty);
    final overlap = value.join(FlowValue.unknown(child));
    expect(overlap.receiverFor(child).unknownTypes, {child});
    expect(overlap.receiverFor(child).externalUnknownTypes, isEmpty);
  });
  test('Null dispatch requires an actual nullable alternative', () {
    final owner = ClassType(uri, 'NonNullOwner');
    for (final value in [
      const FlowValue.bottom(),
      FlowValue.unknown(owner),
      FlowValue.constant(const Constant.integer(0)),
    ]) {
      expect(value.receiverFor(ValueType.nullClass).isBottom, isTrue);
    }
    final source = Block([owner.nullable]).parameters.single;
    for (final value in [
      FlowValue.constant(const Constant.nullValue()),
      FlowValue.unknown(owner.nullable),
      FlowValue.unknown(.nullType),
    ]) {
      final incoming = value.withSource(source, owner);
      final selected = incoming.receiverFor(ValueType.nullClass);
      expect(selected.constant, const Constant.nullValue());
      expect(selected.sources, incoming.sources);
      expect(selected.unknownTypes, isEmpty);
    }
  });

  test(
    'Function dispatch retains unknown signatures and concrete tear-offs',
    () {
      final owner = ClassType(uri, 'Callable');
      final method = FunctionTarget(
        uri,
        'call',
        .integer,
        [],
        owner: owner,
        kind: .method,
      );
      final object = FlowObject(
        NewPayload(owner, const Constant.integer(0)),
        owner,
      );
      final tearOff = FlowObject(BindMethod(method, object.site), owner);
      final top = FunctionConstant(FunctionTarget(uri, 'top', .integer, []));
      final bound = FunctionType(.integer, [.string]);
      final incoming = FlowValue.unknown(bound, external: true)
          .join(FlowValue.constant(top))
          .join(FlowValue.object(tearOff))
          .join(FlowValue.object(object));
      final functions = incoming.receiverFor(ValueType.function);
      expect(functions.constants, [top]);
      expect(functions.objects, {tearOff});
      expect(functions.unknownTypes, {bound});
      expect(functions.externalUnknownTypes, {bound});
      final nominal = incoming.receiverFor(owner);
      expect(nominal.objects, {object});
      expect(nominal.unknownTypes, isEmpty);
      expect(nominal.constants, isEmpty);
    },
  );
}
