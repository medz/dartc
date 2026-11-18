import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final proof = PromotedType(ValueType.object, ValueType.integer);
  final target = FunctionTarget(null, 'proved', proof, []);
  final body = IrFunction(target, [
    Block()..finish(const Return(Constant.integer(42))),
  ]);
  final constant = FunctionConstant(target);
  final actual = FunctionType(ValueType.object, []);
  final integerFunction = FunctionType(ValueType.integer, []);

  test('static views, entry bounds, cells and record fields retain the callable execution proof', () {
    final block = Block();
    final view = block.emit(TypeView(constant, constant.type));
    final call = block.emit(FunctionCall(view, []));
    block.finish(Return(call));
    final root = IrFunction(FunctionTarget(null, 'root', .integer, []), [
      block,
    ]);

    final record = RecordConstant(RecordType([constant.type]), [constant]);
    final recordBlock = Block();
    final recordView = recordBlock.emit(TypeView(record, record.type));
    final field = recordBlock.emit(RecordGet(recordView, 0));
    final recordCall = recordBlock.emit(FunctionCall(field, []));
    recordBlock.finish(Return(recordCall));
    final recordRoot = IrFunction(
      FunctionTarget(null, 'record', .integer, []),
      [recordBlock],
    );

    final cellBlock = Block();
    final cell = cellBlock.emit(NewCell(CellType(constant.type), constant));
    cellBlock.finish(
      Return(cellBlock.emit(FunctionCall(cellBlock.emit(ReadCell(cell)), []))),
    );
    final cellRoot = IrFunction(FunctionTarget(null, 'cell', .integer, []), [
      cellBlock,
    ]);

    final entryTarget = FunctionTarget(null, 'entry', .integer, [
      constant.type,
    ]);
    final entryBlock = Block(entryTarget.parameterTypes);
    entryBlock.finish(
      Return(entryBlock.emit(FunctionCall(entryBlock.parameters.single, []))),
    );
    final entryRoot = IrFunction(entryTarget, [entryBlock]);
    final program = IrProgram([], [
      body,
      root,
      recordRoot,
      cellRoot,
      entryRoot,
    ]);
    final facts = ProgramFlow(
      program,
      [
        (target: entryTarget, arguments: [FlowValue.constant(constant)]),
      ],
      openEntries: [root.target, recordRoot.target, cellRoot.target],
    ).facts;
    expect(facts.valueOf(view).constant, same(constant));
    expect((facts.valueOf(call).constant as ScalarConstant).value, 42);
    expect((facts.valueOf(recordCall).constant as ScalarConstant).value, 42);
    expect(FlowValue.constant(constant).types, [constant.type]);
    expect(FlowValue.constant(constant).runtimeTypes, [actual]);
    expect(FlowValue.constant(record).types, [
      RecordType([constant.type]),
    ]);
    expect(FlowValue.constant(record).runtimeTypes, [
      RecordType([actual]),
    ]);
    final rewritten = const ProgramSimplification().run(facts);
    for (final current in [program, rewritten]) {
      final interpreter = IrInterpreter(current, {});
      for (final target in [root.target, recordRoot.target, cellRoot.target]) {
        expect(
          interpreter.run(current.implementationOf(target) as IrFunction, []),
          42,
        );
      }
    }
  });

  test('runtime tests still observe reified signatures before and after simplification', () {
    final roots = <IrFunction>[];
    for (final (name, tested) in [
      ('integer', integerFunction),
      ('object', actual),
    ]) {
      final block = Block();
      block.finish(Return(block.emit(TypeTest(constant, tested))));
      roots.add(IrFunction(FunctionTarget(null, name, .boolean, []), [block]));
    }
    final block = Block();
    block.finish(
      Return(
        block.emit(
          Equals(
            block.emit(ObjectRuntimeType(constant, direct: true)),
            TypeConstant(actual),
          ),
        ),
      ),
    );
    roots.add(
      IrFunction(FunctionTarget(null, 'runtimeType', .boolean, []), [block]),
    );
    final program = IrProgram([], [body, ...roots]);
    final facts = ProgramFlow(
      program,
      [],
      openEntries: roots.map((f) => f.target),
    ).facts;
    final rewritten = const ProgramSimplification().run(facts);
    for (final current in [program, rewritten]) {
      final interpreter = IrInterpreter(current, {});
      for (final (index, root) in roots.indexed) {
        expect(
          interpreter.run(
            current.implementationOf(root.target) as IrFunction,
            [],
          ),
          index != 0,
        );
      }
    }
    expect(FlowValue.constant(constant).check(constant.type).mayFail, isFalse);
    expect(
      FlowValue.constant(constant)
          .check(integerFunction, runtimeTypes: true)
          .value
          .isBottom,
      isTrue,
    );
  });

  test('inlining retains a real covariant runtime check despite a static callable proof', () {
    final owner = ClassType(null, 'Receiver');
    final initialize = FunctionTarget(
      null,
      'new',
      .voidType,
      [],
      owner: owner,
      kind: .initializer,
    );
    final initializer = IrFunction(initialize, [
      Block(initialize.parameterTypes)..finish(const Return()),
    ]);
    final method = FunctionTarget(
      null,
      'accept',
      .integer,
      [integerFunction],
      owner: owner,
      kind: .method,
      covariantParameters: {0},
    );
    final methodBody = IrFunction(method, [
      Block(method.parameterTypes)..finish(const Return(Constant.integer(7))),
    ]);
    final entry = Block(), normal = Block(), caught = Block();
    final receiver = entry.emit(Construct(initialize, []));
    entry.finish(
      Invoke(
        DirectCall(method, [receiver, constant]),
        onReturn: Jump(normal),
        onThrow: Jump(caught),
      ),
    );
    normal.finish(const Return(Constant.integer(7)));
    caught.finish(const Return(Constant.integer(42)));
    final root = IrFunction(FunctionTarget(null, 'covariant', .integer, []), [
      entry,
      normal,
      caught,
    ]);
    final program = IrProgram(
      [
        IrClass(owner, [], constructors: [initialize], members: [method]),
      ],
      [body, initializer, methodBody, root],
    );
    final facts = ProgramFlow(program, [], openEntries: [root.target]).facts;
    final inlined = const DirectCallInlining().run(facts);
    for (final current in [program, inlined]) {
      expect(
        IrInterpreter(
          current,
          {},
        ).run(current.implementationOf(root.target) as IrFunction, []),
        42,
      );
    }
  });

  test(
    'type-test branch specialization uses runtime signatures on each edge',
    () {
      final integerTarget = FunctionTarget(null, 'integerResult', .integer, []);
      final integerBody = IrFunction(integerTarget, [
        Block()..finish(const Return(Constant.integer(42))),
      ]);
      final entry = Block([ValueType.boolean]),
          header = Block([ValueType.function]);
      final yes = Block()..finish(const Return(Constant.integer(1)));
      final no = Block()..finish(const Return(Constant.integer(0)));
      entry.finish(
        Branch(
          entry.parameters.single,
          Jump(header, [FunctionConstant(integerTarget)]),
          Jump(header, [constant]),
        ),
      );
      header.finish(
        Branch(
          header.emit(TypeTest(header.parameters.single, integerFunction)),
          Jump(yes),
          Jump(no),
        ),
      );
      final root = IrFunction(
        FunctionTarget(null, 'branch', .integer, [.boolean]),
        [entry, header, yes, no],
      );
      final program = IrProgram([], [body, integerBody, root]);
      ProgramFlowFacts facts(IrProgram current) =>
          ProgramFlow(current, [], openEntries: [root.target]).facts;
      final specialized = const ProgramBranchSpecialization().run(
        facts(program),
      );
      final simplified = const ProgramSimplification().run(facts(specialized));
      for (final current in [program, specialized, simplified]) {
        final interpreter = IrInterpreter(current, {});
        final function = current.implementationOf(root.target) as IrFunction;
        expect(interpreter.run(function, [true]), 1);
        expect(interpreter.run(function, [false]), 0);
      }
    },
  );

  test('a generic field read enforces its actual covariant result check', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final holder = ClassType(null, 'Holder', typeParameters: [t]);
    final field = InstanceField(
      holder,
      'value',
      FunctionType(ValueType.voidType, [t]),
    );
    expect(field.requiresReadCheck, isTrue);
    final consumer = FunctionTarget(null, 'consumeInt', .voidType, [.integer]);
    final consumerBody = IrFunction(consumer, [
      Block(consumer.parameterTypes)..finish(const Return()),
    ]);
    final value = FunctionConstant(consumer);
    final init = FunctionTarget(
      null,
      'new',
      .voidType,
      [field.type],
      owner: holder,
      kind: .initializer,
    );
    final initialize = Block(init.parameterTypes);
    initialize.emit(
      StoreField(
        field,
        initialize.parameters.first,
        initialize.parameters.last,
      ),
    );
    initialize.finish(const Return());
    final entry = Block(), normal = Block(), caught = Block();
    final object = entry.emit(
      Construct(init, [
        value,
      ], instantiatedType: holder.instantiate([ValueType.integer])),
    );
    final view = entry.emit(TypeView(object, holder.instantiate([proof])));
    final read = LoadField(field, view);
    entry.finish(Invoke(read, onReturn: Jump(normal), onThrow: Jump(caught)));
    normal.finish(const Return(Constant.integer(7)));
    caught.finish(const Return(Constant.integer(42)));
    final root = IrFunction(
      FunctionTarget(null, 'checkedField', .integer, []),
      [entry, normal, caught],
    );
    final program = IrProgram(
      [
        IrClass(holder, [field], constructors: [init]),
      ],
      [
        consumerBody,
        IrFunction(init, [initialize]),
        root,
      ],
    );
    final facts = ProgramFlow(program, [], openEntries: [root.target]).facts;
    expect(facts.valueOf(read).isBottom, isTrue);
    final rewritten = const ProgramSimplification().run(facts);
    for (final current in [program, rewritten]) {
      expect(
        IrInterpreter(
          current,
          {},
        ).run(current.implementationOf(root.target) as IrFunction, []),
        42,
      );
    }
  });
}
