import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/cell_lowering.dart';
import 'package:dartc/src/codegen/cell_initialization.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:cell-lowering');
  final failure = FunctionTarget(uri, 'bindingFailure', .never, [.string]);
  IrFunction fail() => IrFunction(failure, [
    Block(failure.parameterTypes)..finish(Throw(const Constant.integer(-1))),
  ]);

  void check(IrProgram source, FunctionTarget root, int expected) {
    final entries = [(target: root, arguments: <FlowValue>[])];
    final original = ProgramFlow(source, entries).facts;
    expect(
      IrInterpreter(
        source,
        {},
      ).run(source.implementationOf(root)! as IrFunction, []),
      expected,
    );
    final lowered = CellLowering(failure: failure).run(original);
    final facts = ProgramFlow(lowered, entries).facts;
    expect((facts.returnedBy(root).constant as ScalarConstant).value, expected);
    expect(
      IrInterpreter(
        lowered,
        {},
      ).run(lowered.implementationOf(root)! as IrFunction, []),
      expected,
    );
    final fresh = CellLowering(failure: failure).run(facts);
    expect(fresh, same(lowered));
    final optimized = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      ProgramBranchSpecialization(),
      ProgramLoopSpecialization(),
      DirectCallInlining(),
    ]).run(lowered, entries);
    cellInitializationRequirements(optimized.program);
    expect(
      (optimized.returnedBy(root).constant as ScalarConstant).value,
      expected,
    );
    expect(
      IrInterpreter(
        optimized.program,
        {},
      ).run(optimized.program.implementationOf(root)! as IrFunction, []),
      expected,
    );
  }

  test(
    'later implementation bodies normalize before their next semantic solve',
    () {
      final root = FunctionTarget(uri, 'lateSupport', .integer, [.integer]);
      final helper = FunctionTarget(uri, 'newSupport', .integer, [.integer]);
      final entry = Block(root.parameterTypes);
      final source = entry.emit(
        IntBinary(.add, entry.parameters.single, const Constant.integer(1)),
      );
      entry.finish(Return(source));
      final body = IrFunction(root, [entry]);
      final helperEntry = Block(helper.parameterTypes);
      final cell = helperEntry.emit(
        NewCell(CellType(.integer), helperEntry.parameters.single),
      );
      helperEntry.emit(
        WriteCell(
          cell,
          helperEntry.emit(
            IntBinary(
              .add,
              helperEntry.emit(ReadCell(cell)),
              const Constant.integer(1),
            ),
          ),
        ),
      );
      helperEntry.finish(Return(helperEntry.emit(ReadCell(cell))));
      final support = IrFunction(helper, [helperEntry]);
      final facts =
          ProgramOptimizer([
            CellLowering(),
            _InstallCellSupport(root, source, support),
            const ProgramSimplification(),
            const ProgramStoragePromotion(),
            const ProgramStorageElimination(),
            const DirectCallInlining(),
          ]).run(IrProgram([], [body]), [
            (target: root, arguments: [FlowValue.unknown(ValueType.integer)]),
          ]);
      for (final body in facts.program.functions) {
        expect(
          _operations(body).where(
            (op) =>
                op is NewCell ||
                op is ReadCell ||
                op is WriteCell ||
                op is CopyCell,
          ),
          isEmpty,
        );
      }
      cellInitializationRequirements(facts.program);
      expect(
        CellLowering().bind().normalize(facts.program),
        same(facts.program),
      );
      final runner = IrInterpreter(facts.program, {});
      final result = facts.program.implementationOf(root)! as IrFunction;
      expect(runner.run(result, [41]), 42);
      expect(runner.run(result, [-2]), -1);
    },
  );

  test(
    'physical cells retain shared capture writes and allocation identity',
    () {
      final cell = CellType(.integer);
      final root = FunctionTarget(uri, 'root', .integer, []);
      final closure = FunctionTarget(
        uri,
        'write',
        .voidType,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 1,
        captures: [cell],
      );
      final body = Block(closure.parameterTypes);
      body.emit(WriteCell(body.parameters[1], const Constant.integer(9)));
      body.finish(const Return());
      final entry = Block();
      final original = entry.emit(NewCell(cell, const Constant.integer(1)));
      final callable = entry.emit(MakeClosure(closure, [original]));
      entry.emit(FunctionCall(callable, []));
      entry.finish(Return(entry.emit(ReadCell(original))));
      check(
        IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(closure, [body]),
          fail(),
        ]),
        root,
        9,
      );
    },
  );

  test('copying unbound storage does not read it or alias later writes', () {
    final root = FunctionTarget(uri, 'copyUnbound', .integer, []);
    final entry = Block();
    final original = entry.emit(NewCell(CellType(.integer), null));
    final copied = entry.emit(CopyCell(original));
    entry.emit(WriteCell(original, const Constant.integer(9)));
    entry.emit(WriteCell(copied, const Constant.integer(7)));
    final left = entry.emit(
      IntBinary(
        .multiply,
        entry.emit(ReadCell(original)),
        const Constant.integer(10),
      ),
    );
    entry.finish(
      Return(entry.emit(IntBinary(.add, left, entry.emit(ReadCell(copied))))),
    );
    check(
      IrProgram([], [
        IrFunction(root, [entry]),
        fail(),
      ]),
      root,
      97,
    );
  });

  test(
    'an unbound copied capture cannot become a zero-valued callee input',
    () {
      final cellType = CellType(.integer);
      final root = FunctionTarget(uri, 'conditionalBinding', .integer, [
        .boolean,
      ]);
      final reader = FunctionTarget(
        uri,
        'readCapture',
        .integer,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 3,
        captures: [cellType],
      );
      final read = Block(reader.parameterTypes);
      read.finish(Return(read.emit(ReadCell(read.parameters[1]))));
      final entry = Block(root.parameterTypes),
          yes = Block(),
          no = Block(),
          invoke = Block(),
          returned = Block([ValueType.integer]),
          caught = Block();
      final original = entry.emit(NewCell(cellType, null));
      final copied = entry.emit(CopyCell(original));
      final closure = entry.emit(MakeClosure(reader, [copied]));
      entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
      yes.emit(WriteCell(copied, const Constant.integer(7)));
      yes.finish(Jump(invoke));
      no.finish(Jump(invoke));
      final call = FunctionCall(closure, []);
      invoke.finish(
        Invoke(call, onReturn: Jump(returned, [call]), onThrow: Jump(caught)),
      );
      returned.finish(Return(returned.parameters.single));
      caught.finish(const Return(Constant.integer(73)));
      final source = IrProgram([], [
        IrFunction(root, [entry, yes, no, invoke, returned, caught]),
        IrFunction(reader, [read]),
        fail(),
      ]);
      final sourceFacts = ProgramFlow(
        source,
        const [],
        openEntries: [root],
      ).facts;
      expect(
        () => CellLowering(failure: failure).run(sourceFacts),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'reason',
            contains('before initialization'),
          ),
        ),
      );
    },
  );

  for (final mode in ['final', 'throw', 'overwrite']) {
    test('late cell $mode preserves recursive writes and completion', () {
      final cellType = CellType(
        .integer,
        isLate: true,
        isFinal: mode == 'final',
      );
      final callback = GlobalVariable(
        uri,
        'callback$mode',
        FunctionType(.voidType, []),
        isLate: true,
      );
      final initializer = FunctionTarget(uri, 'initialize$mode', .integer, []);
      final lazy = Block();
      lazy.emit(FunctionCall(lazy.emit(LoadGlobal(callback)), []));
      lazy.finish(
        mode == 'throw'
            ? Throw(const Constant.integer(7))
            : const Return(Constant.integer(42)),
      );
      final root = FunctionTarget(uri, 'lateRoot$mode', .integer, []);
      final setter = FunctionTarget(
        uri,
        'set$mode',
        .voidType,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 2,
        captures: [cellType],
      );
      final write = Block(setter.parameterTypes);
      write.emit(WriteCell(write.parameters[1], const Constant.integer(9)));
      write.finish(const Return());
      final entry = Block(),
          normal = Block([ValueType.integer]),
          caught = Block();
      final cell = entry.emit(
        NewCell(cellType, null, initializer: FunctionConstant(initializer)),
      );
      entry.emit(
        StoreGlobal(callback, entry.emit(MakeClosure(setter, [cell]))),
      );
      final read = ReadCell(cell);
      entry.finish(
        Invoke(read, onReturn: Jump(normal, [read]), onThrow: Jump(caught)),
      );
      normal.finish(Return(normal.parameters.single));
      caught.finish(Return(caught.emit(ReadCell(cell))));
      check(
        IrProgram(
          [],
          [
            IrFunction(root, [entry, normal, caught]),
            IrFunction(setter, [write]),
            IrFunction(initializer, [lazy]),
            fail(),
          ],
          globals: [callback],
        ),
        root,
        mode == 'overwrite' ? 42 : 9,
      );
    });
  }

  test('copying an unbound late cell retains independent lazy bindings', () {
    final count = GlobalVariable(uri, 'count', .integer, isLate: true);
    final initializer = FunctionTarget(uri, 'lazyCounter', .integer, []);
    final lazy = Block();
    lazy.emit(
      StoreGlobal(
        count,
        lazy.emit(
          IntBinary(
            .add,
            lazy.emit(LoadGlobal(count)),
            const Constant.integer(1),
          ),
        ),
      ),
    );
    lazy.finish(const Return(Constant.integer(42)));
    final root = FunctionTarget(uri, 'copyLazy', .integer, []);
    final entry = Block();
    entry.emit(StoreGlobal(count, const Constant.integer(0)));
    final original = entry.emit(
      NewCell(
        CellType(.integer, isLate: true),
        null,
        initializer: FunctionConstant(initializer),
      ),
    );
    final copied = entry.emit(CopyCell(original));
    entry.emit(ReadCell(original));
    entry.emit(ReadCell(copied));
    entry.finish(Return(entry.emit(LoadGlobal(count))));
    check(
      IrProgram(
        [],
        [
          IrFunction(root, [entry]),
          IrFunction(initializer, [lazy]),
          fail(),
        ],
        globals: [count],
      ),
      root,
      2,
    );
  });

  test('two logical capture types share a fixed traced payload without a covariant store', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    IrFunction exchange(String name, ValueType type, {bool generic = false}) {
      final target = FunctionTarget(uri, name, type, [
        type,
        type,
      ], typeParameters: generic ? [t] : []);
      final entry = Block(target.parameterTypes);
      final cell = entry.emit(NewCell(CellType(type), entry.parameters.first));
      entry.emit(WriteCell(cell, entry.parameters.last));
      entry.finish(Return(entry.emit(ReadCell(cell))));
      return IrFunction(target, [entry]);
    }

    final program = CellLowering().bind().normalize(
      IrProgram([], [
        exchange('generic', t, generic: true),
        exchange('other', ValueType.string),
      ]),
    );
    final storage = program.classes.single.cellStorage!;
    expect(storage.type.typeParameters, isEmpty);
    expect(storage.value.type, ValueType.object.nullable);
    final stores = program.functions
        .expand(_operations)
        .whereType<StoreField>()
        .where((op) => op.field == storage.value)
        .toList();
    expect(stores.map((s) => s.storageView!.typeOf(s.field)).toSet(), {
      t,
      ValueType.string,
    });
    expect(stores.every((op) => !op.mayThrow), isTrue);
    final loads = program.functions
        .expand(_operations)
        .whereType<LoadField>()
        .where((op) => op.field == storage.value)
        .toList();
    expect(loads.map((op) => op.type).toSet(), {t, ValueType.string});
    final shape = program.executionShapes!;
    expect(shape.slotOf(storage.value), ExecutionShape.reference);
    for (final load in loads) {
      expect(shape.shapeOf(null, load), ExecutionShape.reference);
    }
  });

  test('inlining a generic cell preserves its reference slot', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final source = FunctionTarget(uri, 'generic', t, [t], typeParameters: [t]);
    final body = Block(source.parameterTypes);
    final cell = body.emit(NewCell(CellType(t), body.parameters.single));
    body.finish(Return(body.emit(ReadCell(cell))));
    final root = FunctionTarget(uri, 'genericRoot', .integer, []);
    final entry = Block();
    entry.finish(
      Return(
        entry.emit(
          DirectCall(
            source,
            [const Constant.integer(42)],
            typeArguments: [.integer],
          ),
        ),
      ),
    );
    check(
      IrProgram([], [
        IrFunction(root, [entry]),
        IrFunction(source, [body]),
        fail(),
      ]),
      root,
      42,
    );
  });
}

Iterable<Instruction> _operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

final class _InstallCellSupport(
  final FunctionTarget root,
  final IntBinary source,
  final IrFunction support,
) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    if (facts.program.implementationOf(support.target) != null) {
      return facts.program;
    }
    final body = facts.program.implementationOf(root)! as IrFunction;
    final rewritten = FunctionRewrite(
      body,
      operations: {
        source: DirectCall(support.target, [source.left]),
      },
    ).run();
    return IrProgram(facts.program.classes, [
      rewritten,
      support,
    ], executionShapes: facts.program.executionShapes);
  }
}
