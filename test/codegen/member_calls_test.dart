import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:test/test.dart';

void main() {
  test('source call facts constrain typed and dynamic member candidates', () {
    final uri = Uri.parse('memory:dispatch-flow');
    final base = ClassType(uri, 'Base');
    final classes = [
      ClassType(uri, 'Used', superclass: base),
      ClassType(uri, 'Other', superclass: base),
    ];
    final methods = [
      for (final type in classes)
        FunctionTarget(uri, 'value', .integer, [], owner: type, kind: .method),
    ];
    final forward = FunctionTarget(uri, 'forward', .dynamicType, [base]);
    final body = Block(forward.parameterTypes);
    final call = body.emit(
      DynamicDispatch(body.parameters.single, methods.first.selector, []),
    );
    body.finish(Return(call));
    final entry = Block();
    entry.finish(
      Return(
        entry.emit(DirectCall(forward, [ObjectConstant(classes.first, {})])),
      ),
    );
    final root = IrFunction(FunctionTarget(uri, 'root', .dynamicType, []), [
      entry,
    ]);
    final program = IrProgram(
      [
        IrClass(base, []),
        for (final (i, type) in classes.indexed)
          IrClass(type, [], members: [methods[i]]),
      ],
      [
        root,
        IrFunction(forward, [body]),
        for (final method in methods)
          IrFunction(method, [
            Block(method.parameterTypes)
              ..finish(const Return(Constant.integer(1))),
          ]),
      ],
    );
    final facts = CallTypeFlow(program, [
      root.target,
    ], instantiatedTypes: classes);
    final calls = MemberCalls(
      program,
      facts.definitions,
      instantiatedTypes: classes,
      callTypes: facts,
    );
    expect(calls.dynamicTargets(call), {classes.first: methods.first});
    expect(
      calls.targetsFor(
        base,
        methods.first.selector,
        receiverValue: body.parameters.single,
      ),
      {classes.first: methods.first},
    );
    expect(calls.targetsFor(base, methods.first.selector), {
      for (final (i, type) in classes.indexed) type: methods[i],
    });
    final generated = Block([base]).parameters.single;
    expect(
      calls.targetsFor(base, methods.first.selector, receiverValue: generated),
      calls.targetsFor(base, methods.first.selector),
    );
  });

  test('reachability and dispatch respect closed generic receiver bounds', () {
    final element = TypeParameterType('E')..initializeBound(.object.nullable);
    final classes = [
      for (final type in [ValueType.integer, ValueType.floating, element])
        ClassType(
          null,
          'Items${type.dartName}',
          typeParameters: type == element ? [element] : [],
          interfaces: [CoreTypes.listOf(type)],
        ),
    ];
    final reads = [
      for (final owner in classes)
        FunctionTarget(
          null,
          '[]',
          owner.interfaces.single.typeArguments.single,
          [.integer],
          owner: owner,
          kind: .method,
        ),
    ];
    final parameter = TypeParameterType('L')
      ..initializeBound(CoreTypes.listOf(.integer));
    final root = FunctionTarget(
      null,
      'read',
      .integer,
      [parameter],
      typeParameters: [parameter],
    );
    final entry = Block(root.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          CollectionGet(entry.parameters.single, const Constant.integer(0)),
        ),
      ),
    );
    final program = IrProgram(
      [
        for (final (i, type) in classes.indexed)
          IrClass(type, [], members: [reads[i]]),
      ],
      [
        IrFunction(root, [entry]),
      ],
      externals: [for (final read in reads) IrExternal(read)],
    );
    final calls = MemberCalls(
      program,
      reads.toSet(),
      instantiatedTypes: classes,
    );
    expect(calls.targetsFor(parameter, reads.first.selector), {
      classes[0]: reads[0],
      classes[2]: reads[2],
    });
    expect(program.reachableFrom([root], instantiatedTypes: classes), {
      root,
      reads[0],
      reads[2],
    });
    expect(
      MemberCalls(
        program,
        {},
        instantiatedTypes: classes,
      ).targetsFor(parameter, reads.first.selector),
      calls.targetsFor(parameter, reads.first.selector),
    );
    expect(
      () => MemberCalls(
        IrProgram(program.classes, []),
        {},
        instantiatedTypes: [classes.first],
      ).targetsFor(parameter, reads.first.selector),
      throwsArgumentError,
    );
  });

  test('generic collection calls exclude unrelated constructed classes', () {
    final list = ClassType(
      null,
      'Items',
      interfaces: [CoreTypes.listOf(.integer)],
    );
    final unrelated = ClassType(null, 'Unrelated');
    final write = FunctionTarget(
      null,
      '[]=',
      .voidType,
      [.integer, .integer],
      owner: list,
      kind: .method,
    );
    final body = IrFunction(write, [
      Block(write.parameterTypes)..finish(const Return()),
    ]);
    final element = TypeParameterType('E')..initializeBound(.number);
    final parameter = TypeParameterType('L')
      ..initializeBound(CoreTypes.listOf(element));
    final program = IrProgram(
      [
        IrClass(list, [], members: [write]),
        IrClass(unrelated, []),
      ],
      [body],
    );
    final calls = MemberCalls(
      program,
      {write},
      instantiatedTypes: [list, unrelated],
    );
    expect(calls.targetsFor(parameter, write.selector), {list: write});
    expect(calls.targetsFor(parameter.nonNullable, write.selector), {
      list: write,
    });
  });
}
