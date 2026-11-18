import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/frame_description.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

Iterable<Instruction> operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  test('ordinary execution bodies retain the language member frame', () {
    final uri = Uri.parse('memory:member-frames');
    final type = ClassType(uri, 'Receiver');
    final member = FunctionTarget(
      uri,
      'read',
      .integer,
      [],
      owner: type,
      kind: .method,
    );
    final method = Block(member.parameterTypes)
      ..finish(const Return(Constant.integer(42)));
    final root = FunctionTarget(uri, 'invoke', .integer, [type]);
    final entry = Block(root.parameterTypes);
    entry.finish(
      Return(
        entry.emit(InstanceCall(member, entry.parameters.single, const [])),
      ),
    );
    final source = IrProgram(
      [
        IrClass(type, [], members: [member]),
      ],
      [
        IrFunction(member, [method]),
        IrFunction(root, [entry]),
      ],
    );
    final bound = MemberEntryLowering(TypeImplementations())
        .run(ProgramFlow(source, const [], openEntries: [root]).facts);
    final ordinary = bound.functions.singleWhere(
      (f) => f.target.executionSource == member,
    );
    expect(frameDescription(ordinary.target), 'Receiver.read');
    final adapter = bound.functions.singleWhere(
      (f) => f.callees.contains(ordinary.target),
    );
    expect(frameDescription(adapter.target), isNull);
  });
  test(
    'ordinary member entries retain named order and actual source defaults',
    () {
      final type = ClassType(null, 'Receiver');
      final member = FunctionTarget(
        null,
        'combine',
        .integer,
        [.integer, .integer, .integer],
        owner: type,
        kind: .method,
        namedParameters: {'z': false, 'a': false},
      );
      final entry = Block(member.parameterTypes);
      final z = entry.emit(
        IntBinary(.multiply, entry.parameters[2], const Constant.integer(10)),
      );
      final a = entry.emit(
        IntBinary(.multiply, entry.parameters[3], const Constant.integer(100)),
      );
      entry.finish(
        Return(
          entry.emit(
            IntBinary(
              .add,
              entry.parameters[1],
              entry.emit(IntBinary(.add, z, a)),
            ),
          ),
        ),
      );
      final method = IrFunction(
        member,
        [entry],
        defaults: {1: const Constant.integer(9), 2: const Constant.integer(2)},
      );
      for (final supplied in [false, true]) {
        final root = FunctionTarget(null, 'invoke', .integer, [type, .integer]);
        final block = Block(root.parameterTypes);
        block.finish(
          Return(
            block.emit(
              InstanceCall(
                member,
                block.parameters.first,
                [block.parameters.last],
                {
                  'z': const Constant.integer(3),
                  if (supplied) 'a': const Constant.integer(4),
                },
              ),
            ),
          ),
        );
        final program = IrProgram(
          [
            IrClass(type, [], members: [member]),
          ],
          [
            method,
            IrFunction(root, [block]),
          ],
        );
        final bound = MemberEntryLowering(TypeImplementations())
            .run(ProgramFlow(program, const [], openEntries: [root]).facts);
        final binding = operations(bound.implementationOf(root) as IrFunction)
            .whereType<InstanceCall>()
            .single
            .entryBinding!;
        expect(binding.names, supplied ? ['a', 'z'] : ['z']);
        final invoke = Block();
        invoke.finish(
          Return(
            invoke.emit(
              DirectCall(root, [
                ObjectConstant(type, {}),
                const Constant.integer(1),
              ]),
            ),
          ),
        );
        expect(
          IrInterpreter(bound, {}).run(
            IrFunction(FunctionTarget(null, 'fixture', .integer, []), [invoke]),
            [],
          ),
          supplied ? 431 : 231,
        );
      }
    },
  );

  test('equal physical arguments do not share different named bindings', () {
    final type = ClassType(null, 'Receiver');
    final member = FunctionTarget(
      null,
      'subtract',
      .integer,
      [.integer, .integer],
      owner: type,
      kind: .method,
      namedParameters: {'left': false, 'right': false},
    );
    final body = Block(member.parameterTypes);
    body.finish(
      Return(
        body.emit(IntBinary(.subtract, body.parameters[1], body.parameters[2])),
      ),
    );
    final root = FunctionTarget(null, 'invoke', .integer, [type, .integer]);
    final entry = Block(root.parameterTypes);
    final left = entry.emit(
      InstanceCall(member, entry.parameters.first, [], {
        'left': entry.parameters.last,
      }),
    );
    final right = entry.emit(
      InstanceCall(member, entry.parameters.first, [], {
        'right': entry.parameters.last,
      }),
    );
    entry.finish(Return(entry.emit(IntBinary(.subtract, left, right))));
    final source = IrProgram(
      [
        IrClass(type, [], members: [member]),
      ],
      [
        IrFunction(
          member,
          [body],
          defaults: {
            0: const Constant.integer(0),
            1: const Constant.integer(0),
          },
        ),
        IrFunction(root, [entry]),
      ],
    );
    final bound = MemberEntryLowering(TypeImplementations())
        .run(ProgramFlow(source, const [], openEntries: [root]).facts);
    final invoke = Block();
    invoke.finish(
      Return(
        invoke.emit(
          DirectCall(root, [
            ObjectConstant(type, {}),
            const Constant.integer(13),
          ]),
        ),
      ),
    );
    expect(
      IrInterpreter(bound, {}).run(
        IrFunction(FunctionTarget(null, 'fixture', .integer, []), [invoke]),
        [],
      ),
      26,
    );
  });

  test(
    'a widened scalar operand retains its payload proof inside an entry',
    () {
      final type = ClassType(null, 'Receiver');
      final member = FunctionTarget(
        null,
        'read',
        .integer,
        [.object],
        owner: type,
        kind: .method,
      );
      final method = Block(member.parameterTypes)
        ..finish(const Return(Constant.integer(9)));
      final root = FunctionTarget(null, 'invoke', .integer, [type, .integer]);
      final entry = Block(root.parameterTypes);
      final view = entry.emit(TypeView(entry.parameters.last, .object));
      entry.finish(
        Return(
          entry.emit(InstanceCall(member, entry.parameters.first, [view])),
        ),
      );
      final source = IrProgram(
        [
          IrClass(type, [], members: [member]),
        ],
        [
          IrFunction(member, [method]),
          IrFunction(root, [entry]),
        ],
      );
      final bound = MemberEntryLowering(TypeImplementations())
          .run(ProgramFlow(source, const [], openEntries: [root]).facts);
      final call = operations(bound.implementationOf(root) as IrFunction)
          .whereType<InstanceCall>()
          .single;
      expect(call.positional.single.type, ValueType.integer);
      final adapter = bound.implementationOf(
        call.entryBinding!.entries[member]!,
      ) as IrFunction;
      final allocation = operations(adapter)
          .whereType<MaterializeValue>()
          .single;
      expect(allocation.value.type, ValueType.integer);
      final normalized = RepresentationLowering().lower(
        bound,
        bound.functions.map((f) => f.target),
      );
      for (final body in normalized.functions) {
        normalized.executionShapes!.verify(body);
      }
    },
  );

  test(
    'entry allocation failure reaches the original handler with actual writes',
    () {
      final type = ClassType(null, 'Receiver');
      final state = GlobalVariable(
        Uri.parse('memory:member-failure'),
        'state',
        .integer,
        isLate: true,
      );
      final member = FunctionTarget(
        null,
        'read',
        .integer,
        [.integer],
        owner: type,
        kind: .method,
      );
      final method = Block(member.parameterTypes)
        ..finish(Return(const Constant.integer(42)));
      final failure = FunctionTarget(null, 'allocationFailure', .never, []);
      final fail = Block();
      fail.emit(StoreGlobal(state, const Constant.integer(9)));
      fail.finish(Throw(const Constant.integer(73)));
      final root = FunctionTarget(null, 'invoke', .integer, [type, .integer]);
      final entry = Block(root.parameterTypes),
          success = Block([ValueType.integer]),
          caught = Block();
      entry.emit(StoreGlobal(state, const Constant.integer(1)));
      final call = InstanceCall(member, entry.parameters.first, [
        entry.parameters.last,
      ]);
      entry.finish(
        Invoke(call, onReturn: Jump(success, [call]), onThrow: Jump(caught)),
      );
      success.finish(Return(success.parameters.single));
      caught.finish(Return(caught.emit(LoadGlobal(state))));
      final source = IrProgram(
        [
          IrClass(type, [], members: [member]),
        ],
        [
          IrFunction(member, [method]),
          IrFunction(failure, [fail]),
          IrFunction(root, [entry, success, caught]),
        ],
        globals: [state],
        executionShapes: ExecutionShapes(
          entries: {
            member: ExecutionSignature([
              ExecutionShape.reference,
              ExecutionShape.reference,
            ], ExecutionShape.word),
          },
        ),
      );
      final before = ProgramFlow(
        source,
        const [],
        openEntries: [root],
        allocationFailure: failure,
      ).facts;
      final bound = MemberEntryLowering(TypeImplementations()).run(before);
      final facts = ProgramFlow(
        bound,
        const [],
        openEntries: [root],
        allocationFailure: failure,
      ).facts;
      final body = bound.implementationOf(root) as IrFunction;
      final read = operations(body).whereType<LoadGlobal>().single;
      expect(facts.valueOf(read).constant, const Constant.integer(9));
      expect(facts.definitions, contains(failure));
      expect(facts.returnedBy(root).integers, FlowIntegerRange(9, 42));
    },
  );

  test(
    'actual member adapter exposes physical demand before devirtualization',
    () {
      final type = ClassType(null, 'Receiver');
      final member = FunctionTarget(
        null,
        'read',
        .integer,
        [.integer],
        owner: type,
        kind: .method,
      );
      final method = Block(member.parameterTypes)
        ..finish(const Return(Constant.integer(9)));
      final root = FunctionTarget(null, 'invoke', .integer, [type, .integer]);
      final entry = Block(root.parameterTypes);
      final call = entry.emit(
        InstanceCall(member, entry.parameters.first, [entry.parameters.last]),
      );
      entry.finish(Return(call));
      final shapes = ExecutionShapes(
        entries: {
          member: ExecutionSignature([
            ExecutionShape.reference,
            ExecutionShape.reference,
          ], ExecutionShape.word),
        },
      );
      final source = IrProgram(
        [
          IrClass(type, [], members: [member]),
        ],
        [
          IrFunction(member, [method]),
          IrFunction(root, [entry]),
        ],
        executionShapes: shapes,
      );
      final inputs = [
        (
          target: root,
          arguments: [
            FlowValue.unknown(type),
            FlowValue.unknown(ValueType.integer),
          ],
        ),
      ];
      final facts = ProgramFlow(source, inputs).facts;
      expect(facts.pendingExecutionCalls[call], {member});
      final bound = MemberEntryLowering(TypeImplementations()).run(facts);
      final current = bound.implementationOf(root) as IrFunction;
      final binding = operations(current)
          .whereType<InstanceCall>()
          .single
          .entryBinding!;
      final adapter =
          bound.implementationOf(binding.entries[member]!) as IrFunction;
      expect(operations(adapter).whereType<MaterializeValue>(), hasLength(1));
      expect(operations(current).whereType<MaterializeValue>(), isEmpty);
      final normalized = RepresentationLowering().lower(
        bound,
        bound.functions.map((f) => f.target),
      );
      final resolved = ProgramFlow(normalized, inputs).facts;
      expect(resolved.pendingExecutionCalls, isEmpty);
      expect(
        resolved.hasUnknownCall(
          operations(normalized.implementationOf(root) as IrFunction)
              .whereType<InstanceCall>()
              .single,
        ),
        isFalse,
      );
      final optimized = ProgramOptimizer([
        const ProgramCallSpecialization(),
        MemberEntryLowering(TypeImplementations()),
        RepresentationLowering(),
      ]).run(source, inputs);
      expect(optimized.returnedBy(root).constant, const Constant.integer(9));
      expect(optimized.pendingExecutionCalls, isEmpty);
      final invoke = Block();
      invoke.finish(
        Return(
          invoke.emit(
            DirectCall(root, [
              ObjectConstant(type, {}),
              const Constant.integer(42),
            ]),
          ),
        ),
      );
      expect(
        IrInterpreter(optimized.program, {}).run(
          IrFunction(FunctionTarget(null, 'fixture', .integer, []), [invoke]),
          [],
        ),
        9,
      );
    },
  );

  test(
    'fresh owner extends a retained member call with a second actual target',
    () {
      final base = ClassType(null, 'Base', isAbstract: true);
      final a = ClassType(null, 'A', superclass: base);
      final b = ClassType(null, 'B', superclass: base);
      FunctionTarget method(ClassType owner, {bool abstract = false}) =>
          FunctionTarget(
            null,
            'read',
            .integer,
            [.integer],
            owner: owner,
            kind: .method,
            isAbstract: abstract,
          );
      final declaration = method(base, abstract: true),
          first = method(a),
          second = method(b);
      IrFunction implementation(FunctionTarget target, int delta) {
        final entry = Block(target.parameterTypes);
        entry.finish(
          Return(
            entry.emit(
              IntBinary(.add, entry.parameters.last, Constant.integer(delta)),
            ),
          ),
        );
        return IrFunction(target, [entry]);
      }

      final root = FunctionTarget(null, 'read', .integer, [base, .integer]);
      final entry = Block(root.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            InstanceCall(declaration, entry.parameters.first, [
              entry.parameters.last,
            ]),
          ),
        ),
      );
      final source = IrProgram(
        [
          IrClass(base, [], members: [declaration]),
          IrClass(a, [], members: [first]),
          IrClass(b, [], members: [second]),
        ],
        [
          implementation(first, 1),
          implementation(second, 2),
          IrFunction(root, [entry]),
        ],
      );
      final partial = MemberEntryLowering(TypeImplementations()).run(
        ProgramFlow(source, [
          (
            target: root,
            arguments: [
              FlowValue.constant(ObjectConstant(a, {})),
              FlowValue.unknown(ValueType.integer),
            ],
          ),
        ]).facts,
      );
      final partialCall = operations(
        partial.implementationOf(root) as IrFunction,
      ).whereType<InstanceCall>().single;
      final firstEntry = partialCall.entryBinding!.entries[first];
      final broad = ProgramFlow(partial, const [], openEntries: [root]).facts;
      expect(broad.pendingExecutionCalls[partialCall], {second});
      expect(broad.sourceTargetsOf(partialCall), {first, second});
      final complete = MemberEntryLowering(TypeImplementations()).run(broad);
      final call = operations(complete.implementationOf(root) as IrFunction)
          .whereType<InstanceCall>()
          .single;
      expect(call.entryBinding!.entries[first], same(firstEntry));
      expect(call.entryBinding!.entries.keys.toSet(), {first, second});
      expect(
        ProgramFlow(
          complete,
          const [],
          openEntries: [root],
        ).facts.pendingExecutionCalls,
        isEmpty,
      );
      expect(
        MemberEntryLowering(TypeImplementations())
            .run(ProgramFlow(complete, const [], openEntries: [root]).facts),
        same(complete),
      );
    },
  );

  test('member entry checks covariance before source side effects', () {
    final base = ClassType(null, 'Base', isAbstract: true);
    final derived = ClassType(null, 'Derived', superclass: base);
    final declaration = FunctionTarget(
      null,
      'put',
      .integer,
      [.object],
      owner: base,
      kind: .method,
      isAbstract: true,
    );
    final member = FunctionTarget(
      null,
      'put',
      .integer,
      [.integer],
      owner: derived,
      kind: .method,
      covariantParameters: {0},
    );
    final state = GlobalVariable(
      Uri.parse('memory:member-entry'),
      'state',
      .integer,
      isLate: true,
    );
    final method = Block(member.parameterTypes);
    method.emit(StoreGlobal(state, const Constant.integer(73)));
    method.finish(Return(method.parameters.last));
    final root = FunctionTarget(null, 'invoke', .integer, [base, .object]);
    final entry = Block(root.parameterTypes),
        returned = Block([ValueType.integer]),
        caught = Block();
    entry.emit(StoreGlobal(state, const Constant.integer(9)));
    final call = InstanceCall(declaration, entry.parameters.first, [
      entry.parameters.last,
    ]);
    entry.finish(
      Invoke(call, onReturn: Jump(returned, [call]), onThrow: Jump(caught)),
    );
    returned.finish(Return(returned.parameters.single));
    caught.finish(Return(caught.emit(LoadGlobal(state))));
    final source = IrProgram(
      [
        IrClass(base, [], members: [declaration]),
        IrClass(derived, [], members: [member]),
      ],
      [
        IrFunction(member, [method]),
        IrFunction(root, [entry, returned, caught]),
      ],
      globals: [state],
    );
    final inputs = [
      (
        target: root,
        arguments: [
          FlowValue.constant(ObjectConstant(derived, {})),
          FlowValue.constant(Constant.string('wrong')),
        ],
      ),
    ];
    final bound = MemberEntryLowering(TypeImplementations())
        .run(ProgramFlow(source, inputs).facts);
    final facts = ProgramFlow(bound, inputs).facts;
    expect(facts.returnedBy(root).constant, const Constant.integer(9));
    expect(facts.definitions, isNot(contains(member)));
    expect(facts.pendingExecutionCalls, isEmpty);
  });
}
