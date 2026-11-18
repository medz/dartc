import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/cell_initialization.dart';
import 'package:dartc/src/codegen/cell_lowering.dart';
import 'package:dartc/src/codegen/callable_implementations.dart';
import 'package:dartc/src/codegen/callable_lowering.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:cell-initialization');
  final cell = CellType(.integer);

  for (final before in [false, true]) {
    test('a reader capture ${before ? 'after' : 'before'} assignment', () {
      final root = FunctionTarget(uri, 'root', .integer, []);
      final reader = FunctionTarget(
        uri,
        'reader',
        .integer,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 1,
        captures: [cell],
      );
      final body = Block(reader.parameterTypes);
      body.finish(Return(body.emit(ReadCell(body.parameters[1]))));
      final entry = Block();
      final local = entry.emit(NewCell(cell, null));
      if (before) entry.emit(WriteCell(local, const Constant.integer(42)));
      final closure = entry.emit(MakeClosure(reader, [local]));
      if (!before) entry.emit(WriteCell(local, const Constant.integer(42)));
      entry.finish(Return(entry.emit(FunctionCall(closure, []))));
      final program = IrProgram([], [
        IrFunction(root, [entry]),
        IrFunction(reader, [body]),
      ]);
      if (!before) {
        expect(
          () => cellInitializationRequirements(program),
          throwsUnsupportedError,
        );
      } else {
        expect(cellInitializationRequirements(program)[reader], {(1, null)});
        expect(IrInterpreter(program, {}).run(program.functions.first, []), 42);
        final facts = ProgramFlow(program, [
          (target: root, arguments: <FlowValue>[]),
        ]).facts;
        final lowered = CellLowering().run(facts);
        final requirements = cellInitializationRequirements(lowered);
        expect(requirements[root], isEmpty);
        expect(IrInterpreter(lowered, {}).run(lowered.functions.first, []), 42);
      }
    });
  }

  for (final readAfterWrite in [false, true]) {
    test(
      'unbound capture permits ${readAfterWrite ? 'write then read' : 'write only'}',
      () {
        final root = FunctionTarget(uri, 'root', .integer, []);
        final writer = FunctionTarget(
          uri,
          'writer',
          .integer,
          [],
          kind: .closure,
          enclosing: root,
          sourceOffset: 2,
          captures: [cell],
        );
        final body = Block(writer.parameterTypes);
        body.emit(WriteCell(body.parameters[1], const Constant.integer(9)));
        body.finish(
          Return(
            readAfterWrite
                ? body.emit(ReadCell(body.parameters[1]))
                : const Constant.integer(9),
          ),
        );
        final entry = Block();
        final local = entry.emit(NewCell(cell, null));
        final closure = entry.emit(MakeClosure(writer, [local]));
        entry.finish(Return(entry.emit(FunctionCall(closure, []))));
        final program = IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(writer, [body]),
        ]);
        expect(cellInitializationRequirements(program)[writer], isEmpty);
        final entries = [(target: root, arguments: <FlowValue>[])];
        final lowered = CellLowering().run(ProgramFlow(program, entries).facts);
        cellInitializationRequirements(lowered);
        expect(IrInterpreter(lowered, {}).run(lowered.functions.first, []), 9);
      },
    );
  }

  test('partial branch writes cannot discharge a capture obligation', () {
    final root = FunctionTarget(uri, 'root', .integer, [.boolean]);
    final reader = FunctionTarget(
      uri,
      'reader',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 3,
      captures: [cell],
    );
    final body = Block(reader.parameterTypes);
    body.finish(Return(body.emit(ReadCell(body.parameters[1]))));
    final entry = Block(root.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block();
    final local = entry.emit(NewCell(cell, null));
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    yes.emit(WriteCell(local, const Constant.integer(7)));
    yes.finish(Jump(join));
    no.finish(Jump(join));
    final closure = join.emit(MakeClosure(reader, [local]));
    join.finish(Return(join.emit(FunctionCall(closure, []))));
    final program = IrProgram([], [
      IrFunction(root, [entry, yes, no, join]),
      IrFunction(reader, [body]),
    ]);
    expect(
      () => cellInitializationRequirements(program),
      throwsUnsupportedError,
    );
  });

  test(
    'an actual write before throw satisfies a capture created in its handler',
    () {
      final root = FunctionTarget(uri, 'root', .integer, []);
      final reader = FunctionTarget(
        uri,
        'reader',
        .integer,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 4,
        captures: [cell],
      );
      final body = Block(reader.parameterTypes);
      body.finish(Return(body.emit(ReadCell(body.parameters[1]))));
      final entry = Block(), caught = Block();
      final local = entry.emit(NewCell(cell, null));
      entry.emit(WriteCell(local, const Constant.integer(73)));
      entry.finish(Throw(const Constant.integer(7), onThrow: Jump(caught)));
      final closure = caught.emit(MakeClosure(reader, [local]));
      caught.finish(Return(caught.emit(FunctionCall(closure, []))));
      final program = IrProgram([], [
        IrFunction(root, [entry, caught]),
        IrFunction(reader, [body]),
      ]);
      expect(cellInitializationRequirements(program)[reader], {(1, null)});
      final lowered = CellLowering().run(
        ProgramFlow(program, [(target: root, arguments: <FlowValue>[])]).facts,
      );
      cellInitializationRequirements(lowered);
      expect(IrInterpreter(lowered, {}).run(lowered.functions.first, []), 73);
    },
  );

  test('a nested actual callee propagates its capture precondition', () {
    final root = FunctionTarget(uri, 'root', .integer, []);
    final outer = FunctionTarget(
      uri,
      'outer',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 5,
      captures: [cell],
    );
    final inner = FunctionTarget(
      uri,
      'inner',
      .integer,
      [],
      kind: .closure,
      enclosing: outer,
      sourceOffset: 6,
      captures: [cell],
    );
    final read = Block(inner.parameterTypes);
    read.finish(Return(read.emit(ReadCell(read.parameters[1]))));
    final middle = Block(outer.parameterTypes);
    final nested = middle.emit(MakeClosure(inner, [middle.parameters[1]]));
    middle.finish(Return(middle.emit(FunctionCall(nested, []))));
    final entry = Block();
    final local = entry.emit(NewCell(cell, null));
    final closure = entry.emit(MakeClosure(outer, [local]));
    entry.finish(Return(entry.emit(FunctionCall(closure, []))));
    final program = IrProgram([], [
      IrFunction(root, [entry]),
      IrFunction(outer, [middle]),
      IrFunction(inner, [read]),
    ]);
    expect(
      () => cellInitializationRequirements(program),
      throwsUnsupportedError,
    );
  });

  test('an opaque entry does not grant definite assignment', () {
    final root = FunctionTarget(uri, 'root', .integer, []);
    final target = FunctionTarget(
      uri,
      'reader',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 7,
      captures: [cell],
    );
    final entry = Block(target.parameterTypes);
    entry.finish(Return(entry.emit(ReadCell(entry.parameters[1]))));
    final body = IrFunction(target, [entry]);
    expect(() => checkCellInitialization(body), throwsUnsupportedError);
    expect(
      cellInitializationRequirements(
        IrProgram([], [
          IrFunction(root, [
            Block()..finish(const Return(Constant.integer(0))),
          ]),
          body,
        ]),
      )[target],
      {(1, null)},
    );
    final malformed = Block();
    malformed.emit(ReadCell(malformed.emit(NewCell(cell, null))));
    malformed.finish(const Return(Constant.integer(0)));
    expect(
      () => cellInitializationRequirements(
        IrProgram([], [
          IrFunction(root, [malformed]),
        ]),
      ),
      throwsUnsupportedError,
    );
  });
  test('physical captures follow actual initializer fields, not argument positions', () {
    final root = FunctionTarget(uri, 'root', .integer, []);
    final reader = FunctionTarget(
      uri,
      'reader',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 8,
      captures: [cell, cell],
    );
    final body = Block(reader.parameterTypes);
    body.finish(Return(body.emit(ReadCell(body.parameters[1]))));
    final entry = Block();
    final assigned = entry.emit(NewCell(cell, const Constant.integer(42)));
    final unbound = entry.emit(NewCell(cell, null));
    final closure = entry.emit(MakeClosure(reader, [assigned, unbound]));
    entry.finish(Return(entry.emit(FunctionCall(closure, []))));
    final original = IrProgram([], [
      IrFunction(root, [entry]),
      IrFunction(reader, [body]),
    ]);
    final owner = CallableImplementations();
    final lowered = CallableLowering(owner).run(
      ProgramFlow(original, [(target: root, arguments: <FlowValue>[])]).facts,
    );
    cellInitializationRequirements(lowered);
    final storage = lowered.classes
        .map((c) => c.callableStorage)
        .whereType<CallableStorage>()
        .singleWhere((storage) => storage.source == reader);
    final initializer =
        lowered.implementationOf(storage.initializer!)! as IrFunction;
    final fieldStore = initializer.entry.instructions
        .whereType<StoreField>()
        .singleWhere((store) => store.field == storage.captures.first);
    final otherStore = initializer.entry.instructions
        .whereType<StoreField>()
        .singleWhere((store) => store.field == storage.captures.last);
    final forged = FunctionRewrite(
      initializer,
      operations: {
        fieldStore: StoreField(
          fieldStore.field,
          fieldStore.receiver,
          otherStore.value,
        ),
      },
    ).run();
    final changed = IrProgram(lowered.classes, [
      for (final function in lowered.functions)
        identical(function, initializer) ? forged : function,
    ], executionShapes: lowered.executionShapes);
    expect(
      () => cellInitializationRequirements(changed),
      throwsUnsupportedError,
    );
    final oldProof = CellInitialization(lowered);
    expect(() => oldProof.check(forged), throwsArgumentError);
  });
}
