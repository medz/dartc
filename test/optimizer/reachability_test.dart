import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('memory:reachability');
const _one = Constant.integer(1);

void main() {
  test('reachability follows instantiated entries without compiling abstract declarations', () {
    final face = ClassType(_uri, 'Face');
    final first = ClassType(_uri, 'First', interfaces: [face]);
    final second = ClassType(_uri, 'Second', interfaces: [face]);
    final unused = ClassType(_uri, 'Unused', interfaces: [face]);
    FunctionTarget read(ClassType owner, {bool abstract = false}) =>
        FunctionTarget(
          _uri,
          'read',
          .integer,
          [],
          owner: owner,
          kind: .method,
          isAbstract: abstract,
        );
    FunctionTarget constructor(ClassType owner) => FunctionTarget(
      _uri,
      'new',
      .voidType,
      [],
      owner: owner,
      kind: .initializer,
    );
    final declaration = read(face, abstract: true);
    final readFirst = read(first),
        readSecond = read(second),
        readUnused = read(unused);
    final newFirst = constructor(first), newSecond = constructor(second);
    IrFunction constructAndCall(FunctionTarget target, FunctionTarget ctor) {
      final entry = Block(target.parameterTypes);
      final instance = entry.emit(Construct(ctor, []));
      entry.finish(Return(entry.emit(InstanceCall(declaration, instance, []))));
      return IrFunction(target, [entry]);
    }

    final root = constructAndCall(
      FunctionTarget(_uri, 'entry', .integer, []),
      newFirst,
    );
    final factory = FunctionTarget(
      _uri,
      'create',
      face,
      [],
      owner: face,
      kind: .factory,
      redirect: newSecond,
    );
    final tearOff = FunctionConstant(factory);
    final reference = IrFunction(
      FunctionTarget(_uri, 'constructor', tearOff.type, []),
      [Block()..finish(Return(tearOff))],
    );
    final constantEntry = Block();
    constantEntry.finish(
      Return(
        constantEntry.emit(
          InstanceCall(
            declaration,
            constantEntry.emit(TypeView(ObjectConstant(second, {}), face)),
            [],
          ),
        ),
      ),
    );
    final constantRoot = IrFunction(
      FunctionTarget(_uri, 'constant', .integer, []),
      [constantEntry],
    );
    final input = Block([face]);
    input.finish(
      Return(
        input.emit(InstanceCall(declaration, input.parameters.single, [])),
      ),
    );
    final supplied = IrFunction(
      FunctionTarget(_uri, 'supplied', .integer, [face]),
      [input],
    );
    final program = IrProgram(
      [
        IrClass(face, [], members: [declaration], constructors: [factory]),
        IrClass(first, [], members: [readFirst], constructors: [newFirst]),
        IrClass(second, [], members: [readSecond], constructors: [newSecond]),
        IrClass(unused, [], members: [readUnused]),
      ],
      [
        root,
        reference,
        constantRoot,
        supplied,
        constructAndCall(readFirst, newSecond),
        IrFunction(readSecond, [
          Block(readSecond.parameterTypes)..finish(const Return(_one)),
        ]),
        for (final ctor in [newFirst, newSecond])
          IrFunction(ctor, [
            Block(ctor.parameterTypes)..finish(const Return()),
          ]),
      ],
      externals: [IrExternal(readUnused)],
    );
    expect(root.callees, {newFirst});
    expect(root.virtualMembers, {(receiver: first, target: declaration)});
    expect(root.instantiatedClasses, {first, ValueType.integer});
    expect(reference.instantiatedClasses, {second});
    expect(reference.functionConstants.single.target, same(factory));
    expect(reachableDefinitions(program, [root.target]), {
      root.target,
      newFirst,
      newSecond,
      readFirst,
      readSecond,
    });
    expect(reachableDefinitions(program, [reference.target]), {
      reference.target,
      newSecond,
    });
    expect(reachableDefinitions(program, [constantRoot.target]), {
      constantRoot.target,
      readSecond,
    });
    expect(
      reachableDefinitions(
        program,
        [constantRoot.target],
        instantiatedTypes: [unused],
      ),
      {constantRoot.target, readSecond},
    );
    expect(reachableDefinitions(program, [supplied.target]), {supplied.target});
    expect(
      reachableDefinitions(
        program,
        [supplied.target],
        instantiatedTypes: [first],
      ),
      {supplied.target, readFirst, newSecond, readSecond},
    );
  });
}
