import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final mode in ['pure', 'read', 'write', 'capture']) {
    test('closed $mode leaf preserves its actual heap contract', () {
      final box = ClassType(null, 'Box');
      final field = InstanceField(box, 'value', .integer);
      final leaf = FunctionTarget(null, 'leaf', .voidType, [box]);
      final later = FunctionTarget(null, 'later', .voidType, []);
      final helper = FunctionTarget(null, 'helper', .integer, [box]);
      final body = Block(helper.parameterTypes);
      body.emit(DirectCall(leaf, body.parameters));
      body.finish(Return(body.emit(LoadField(field, body.parameters.single))));
      final make = FunctionTarget(null, 'make', box, []);
      final makeBody = Block();
      final made = makeBody.emit(NewPayload(box, const Constant.integer(0)));
      makeBody.emit(StoreField(field, made, const Constant.integer(7)));
      makeBody.finish(Return(made));
      final root = FunctionTarget(null, 'root', .integer, []);
      final entry = Block();
      final owners = <Value>[];
      for (var i = 0; i < 2; i++) {
        final owner = entry.emit(DirectCall(make, const []));
        owners.add(owner);
        entry.emit(DirectCall(helper, [owner]));
      }
      entry.emit(DirectCall(later, const []));
      entry.finish(Return(entry.emit(LoadField(field, owners.first))));
      final rootBody = IrFunction(root, [entry]);
      final program = IrProgram(
        [
          IrClass(box, [field]),
        ],
        [
          rootBody,
          IrFunction(helper, [body]),
          IrFunction(make, [makeBody]),
        ],
        externals: [
          IrExternal(
            leaf,
            effects: {
              if (mode == 'read') Effect.readsStorage,
              if (mode == 'write') Effect.writesStorage,
            },
            capturesArguments: mode == 'capture',
            memory: mode == 'write'
                ? const ExternalMemory.arbitrary()
                : const ExternalMemory.unchanged(),
            terminates: true,
          ),
          IrExternal(
            later,
            effects: {Effect.writesStorage},
            capturesArguments: false,
            terminates: true,
          ),
        ],
      );
      final facts = ProgramFlow(program, [(target: root, arguments: [])]).facts;
      expect(facts.activationsOf(helper), hasLength(mode == 'pure' ? 1 : 2));
      final value = facts.returnedBy(root);
      if (mode == 'capture' || mode == 'write') {
        expect(value.constant, isNull);
        expect(value.integers!.contains(7), isTrue);
      } else {
        expect((value.constant as ScalarConstant).value, 7);
      }
      expect(
        IrInterpreter(
          program,
          {},
          externalCalls: {leaf: (_) => null, later: (_) => null},
        ).run(rootBody, []),
        7,
      );
    });
  }

  test('member call projection includes its actual entry guard', () {
    final receiver = ClassType(null, 'Receiver');
    final member = FunctionTarget(
      null,
      'read',
      .integer,
      [],
      owner: receiver,
      kind: .method,
    );
    final source = Block(member.parameterTypes)
      ..finish(const Return(Constant.integer(9)));
    final flag = GlobalVariable(
      Uri.parse('memory:entry'),
      'ready',
      ValueType.boolean.nullable,
    );
    final entryTarget = FunctionTarget(null, 'entry', .integer, [receiver]);
    final guard = Block(entryTarget.parameterTypes);
    final ready = Block()..finish(const Return(Constant.integer(9)));
    final failed = Block()..finish(Throw(const Constant.string('not ready')));
    guard.finish(
      Branch(
        guard.emit(
          Equals(guard.emit(LoadGlobal(flag)), const Constant.boolean(true)),
        ),
        Jump(ready),
        Jump(failed),
      ),
    );
    final shapes = ExecutionShapes();
    final binding = MemberEntryBinding(
      entryTarget.signature,
      shapes.entryOf(entryTarget),
      0,
      const [],
      0,
      {member: entryTarget},
      executionShapes: shapes,
    );
    final helper = FunctionTarget(null, 'helper', .integer, [receiver]);
    final body = Block(helper.parameterTypes);
    body.finish(
      Return(
        body.emit(
          InstanceCall(
            member,
            body.parameters.single,
            const [],
            const {},
            null,
            const [],
            binding,
          ),
        ),
      ),
    );
    final root = FunctionTarget(null, 'root', .integer, []);
    final block = Block();
    block.emit(StoreGlobal(flag, const Constant.boolean(true)));
    block.finish(
      Return(block.emit(DirectCall(helper, [ObjectConstant(receiver, {})]))),
    );
    final program = IrProgram(
      [
        IrClass(receiver, [], members: [member]),
      ],
      [
        IrFunction(member, [source]),
        IrFunction(entryTarget, [guard, ready, failed]),
        IrFunction(helper, [body]),
        IrFunction(root, [block]),
      ],
      globals: [flag],
      executionShapes: shapes,
    );
    final facts = ProgramFlow(program, [(target: root, arguments: [])]).facts;
    expect((facts.returnedBy(root).constant as ScalarConstant).value, 9);
    expect(facts.thrownBy(root).exception.isBottom, isTrue);
  });

  test('an address-only call is independent of pointee content changes', () {
    final box = ClassType(null, 'Addressed');
    final field = InstanceField(box, 'value', .integer);
    final address = FunctionTarget(null, 'address', .integer, [box]);
    final body = Block(address.parameterTypes);
    body.finish(Return(body.emit(ReferenceAddress(body.parameters.single))));
    final root = FunctionTarget(null, 'root', .integer, []);
    final entry = Block();
    final object = entry.emit(NewPayload(box, const Constant.integer(0)));
    entry.emit(StoreField(field, object, const Constant.integer(1)));
    entry.emit(DirectCall(address, [object]));
    entry.emit(StoreField(field, object, const Constant.integer(2)));
    final pointer = entry.emit(DirectCall(address, [object]));
    final returned = entry.emit(ReferenceFromAddress(pointer, box));
    entry.finish(Return(entry.emit(LoadField(field, returned))));
    final program = IrProgram(
      [
        IrClass(box, [field]),
      ],
      [
        IrFunction(address, [body]),
        IrFunction(root, [entry]),
      ],
    );
    final facts = ProgramFlow(program, [(target: root, arguments: [])]).facts;
    expect(facts.activationsOf(address), hasLength(1));
    expect((facts.returnedBy(root).constant as ScalarConstant).value, 2);
  });
}
