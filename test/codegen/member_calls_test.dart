import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:test/test.dart';

void main() {
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
