import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('package:example/entry.dart');
  test('an abstract signature keeps its distinct inherited callable entry', () {
    final type = ClassType(library, 'C');
    final declaration = FunctionTarget(
      library,
      'f',
      .object.nullable,
      [.integer],
      owner: type,
      kind: .method,
      isAbstract: true,
    );
    final implementation = FunctionTarget(
      library,
      'f',
      .object.nullable,
      [.number],
      owner: type,
      kind: .method,
      covariantParameters: [0],
    );
    final entry = Block(implementation.parameterTypes);
    entry.finish(Return(entry.parameters[1]));
    final caller = FunctionTarget(library, 'call', .object.nullable, [type]);
    final call = Block(caller.parameterTypes);
    call.finish(
      Return(
        call.emit(
          InstanceCall(declaration, call.parameters[0], [
            const Constant.integer(3),
          ]),
        ),
      ),
    );
    final program = IrProgram(
      [
        IrClass(
          type,
          [],
          members: [declaration],
          implementations: [implementation],
        ),
      ],
      [
        IrFunction(implementation, [entry]),
        IrFunction(caller, [call]),
      ],
    );
    expect(
      program.lookupMember(type, declaration.selector).target,
      same(implementation),
    );
    expect(
      program.classes.single.members[declaration.selector],
      same(declaration),
    );
    final text = StringBuffer();
    program.writeTo(text);
    expect(text.toString(), contains('-> entry Object? Function(num)'));
  });

  test(
    'implementation bindings reject missing declarations and unsound results',
    () {
      final type = ClassType(library, 'C');
      final declaration = FunctionTarget(
        library,
        'f',
        .integer,
        [.integer],
        owner: type,
        kind: .method,
        isAbstract: true,
      );
      final body = FunctionTarget(
        library,
        'f',
        .string,
        [.number],
        owner: type,
        kind: .method,
      );
      expect(
        () => IrClass(type, [], implementations: [body]),
        throwsArgumentError,
      );
      expect(
        () =>
            IrClass(type, [], members: [declaration], implementations: [body]),
        throwsArgumentError,
      );
      expect(
        () => IrClass(
          type,
          [],
          members: [declaration],
          implementations: [declaration],
        ),
        throwsArgumentError,
      );
    },
  );
}
