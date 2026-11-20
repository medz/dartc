import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/callable_implementations.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:unknown-call-state');

void main() {
  for (final emptyGlobal in [false, true]) {
    test(
      'an external callee cannot publish a private callable alternative (empty global=$emptyGlobal)',
      () {
        final signature = FunctionType(.voidType, [.integer]);
        final root = FunctionTarget(_uri, 'select', .integer, [
          .boolean,
          signature,
        ]);
        final cell = CellType(.integer);
        final write = FunctionTarget(
          _uri,
          'write',
          .voidType,
          [.integer],
          kind: .closure,
          enclosing: root,
          sourceOffset: 1,
          captures: [cell],
        );
        final body = Block(write.parameterTypes);
        body.emit(WriteCell(body.parameters[1], body.parameters[2]));
        body.finish(const Return());
        final entry = Block(root.parameterTypes);
        final storage = entry.emit(NewCell(cell, const Constant.integer(42)));
        final local = entry.emit(MakeClosure(write, [storage]));
        final invoke = Block([signature]);
        entry.finish(
          Branch(
            entry.parameters.first,
            Jump(invoke, [local]),
            Jump(invoke, [entry.parameters[1]]),
          ),
        );
        final call = invoke.emit(
          FunctionCall(invoke.parameters.single, [const Constant.integer(42)]),
        );
        invoke.finish(Return(invoke.emit(ReadCell(storage))));
        final program = IrProgram(
          [],
          [
            IrFunction(root, [entry, invoke]),
            IrFunction(write, [body]),
          ],
          globals: [
            if (emptyGlobal) GlobalVariable(_uri, 'empty', signature.nullable),
          ],
        );
        final facts = ProgramFlow(program, [
          (
            target: root,
            arguments: [
              FlowValue.unknown(.boolean),
              FlowValue.unknown(signature, external: true),
            ],
          ),
        ]).facts;
        expect(facts.hasUnknownCall(call), isTrue);
        expect(facts.targetsOf(call), contains(write));
        expect(facts.activationsOf(write), hasLength(1));
        expect(
          facts.returnedBy(root).constant?.structuralKey,
          const Constant.integer(42).structuralKey,
        );
      },
    );
  }

  for (final lowered in [false, true]) {
    for (final raw in [false, true]) {
      for (final route in ['private', 'argument', 'retained']) {
        test('outside writes and returns an available value '
            '(lowered=$lowered, raw=$raw, route=$route)', () {
          final item = ClassType(_uri, 'Item');
          final valueType = (raw ? ValueType.integer : item).nullable;
          final signature = FunctionType(valueType, [valueType]);
          final root = FunctionTarget(_uri, 'root', valueType, [signature]);
          final saved = GlobalVariable(_uri, 'saved', valueType);
          final stash = FunctionTarget(_uri, 'stash', .voidType, [valueType]);
          final entry = Block(root.parameterTypes);
          final offered = entry.emit(
            NewPayload(item, const Constant.integer(8)),
          );
          entry.emit(NewPayload(item, const Constant.integer(8)));
          final ability = raw ? entry.emit(ReferenceAddress(offered)) : offered;
          if (route == 'retained') entry.emit(DirectCall(stash, [ability]));
          entry.emit(
            FunctionCall(entry.parameters.single, [
              route == 'argument' ? ability : const Constant.nullValue(),
            ]),
          );
          entry.finish(Return(entry.emit(LoadGlobal(saved))));
          final source = IrProgram(
            [IrClass(item, [])],
            [
              IrFunction(root, [entry]),
            ],
            globals: [saved],
            externals: [IrExternal(stash, effects: const {})],
          );
          final program = lowered
              ? GlobalLowering().lower(
                  source,
                  source.functions.map((f) => f.target),
                )
              : source;
          final facts = ProgramFlow(program, [
            (
              target: root,
              arguments: [FlowValue.unknown(signature, external: true)],
            ),
          ]).facts;
          final instructions = (program.implementationOf(root) as IrFunction)
              .blocks
              .expand((b) => b.instructions);
          final bodies = instructions
              .whereType<NewPayload>()
              .map((i) => facts.valueOf(i).objects.single)
              .toList();
          final call = instructions.whereType<FunctionCall>().single;
          for (final value in [facts.valueOf(call), facts.returnedBy(root)]) {
            if (!raw) expect(value.externalUnknownTypes, contains(valueType));
            final possible = raw
                ? {
                    ...value.references.objects,
                    ...value.addresses.map((a) => a.base),
                  }
                : value.objects;
            expect(possible.contains(bodies.first), route != 'private');
            expect(possible, isNot(contains(bodies.last)));
          }
        });
      }
    }
  }

  for (final offer in [false, true]) {
    test(
      'reentry can supply a published local as its argument (offer=$offer)',
      () {
        final targetType = FunctionType(.voidType, [.integer]);
        final observer = FunctionTarget(_uri, 'observe', .voidType, [
          targetType,
        ]);
        final observerBody = Block(observer.parameterTypes);
        final invoke = observerBody.emit(
          FunctionCall(observerBody.parameters.single, [
            const Constant.integer(71),
          ]),
        );
        observerBody.finish(const Return());
        final root = FunctionTarget(_uri, 'root', .integer, []);
        final cellType = CellType(.integer);
        final writer = FunctionTarget(
          _uri,
          'write',
          .voidType,
          [.integer],
          kind: .closure,
          enclosing: root,
          sourceOffset: 1,
          captures: [cellType],
        );
        final writerBody = Block(writer.parameterTypes);
        writerBody.emit(
          WriteCell(writerBody.parameters[1], writerBody.parameters[2]),
        );
        writerBody.finish(const Return());
        final host = FunctionTarget(_uri, 'host', .voidType, [
          observer.signature,
          targetType.nullable,
        ]);
        final entry = Block();
        final cell = entry.emit(NewCell(cellType, const Constant.integer(42)));
        final local = entry.emit(MakeClosure(writer, [cell]));
        entry.emit(
          DirectCall(host, [
            FunctionConstant(observer),
            offer ? local : const Constant.nullValue(),
          ]),
        );
        entry.finish(Return(entry.emit(ReadCell(cell))));
        final facts = ProgramFlow(
          IrProgram(
            [],
            [
              IrFunction(root, [entry]),
              IrFunction(observer, [observerBody]),
              IrFunction(writer, [writerBody]),
            ],
            externals: [IrExternal(host)],
          ),
          [(target: root, arguments: [])],
        ).facts;
        expect(facts.definitions, contains(observer));
        expect(facts.targetsOf(invoke).contains(writer), offer);
        expect(facts.returnedBy(root).integers?.contains(71), offer);
      },
    );
  }

  test('a noncapturing external can return the private object it receives', () {
    final type = ClassType(_uri, 'Returned');
    final root = FunctionTarget(_uri, 'root', type, []);
    final outside = FunctionTarget(_uri, 'pass', type, [type]);
    final block = Block();
    final offered = block.emit(NewPayload(type, const Constant.integer(8)));
    final private = block.emit(NewPayload(type, const Constant.integer(8)));
    final result = block.emit(DirectCall(outside, [offered]));
    block.finish(Return(result));
    final facts = ProgramFlow(
      IrProgram(
        [IrClass(type, [])],
        [
          IrFunction(root, [block]),
        ],
        externals: [
          IrExternal(outside, effects: const {}, capturesArguments: false),
        ],
      ),
      [(target: root, arguments: [])],
    ).facts;
    final returned = facts.returnedBy(root);
    expect(returned.externalUnknownTypes, contains(type));
    expect(returned.objects, contains(facts.valueOf(offered).objects.single));
    expect(
      returned.objects,
      isNot(contains(facts.valueOf(private).objects.single)),
    );
  });

  for (final lowered in [false, true]) {
    for (final throwing in [false, true]) {
      for (final unknown in [false, true]) {
        test(
          'callback summaries preserve program writes (lowered=$lowered, throw=$throwing, unknown=$unknown)',
          () {
            final fixture = _callback(throwing: throwing);
            final source = fixture.program;
            final program = lowered
                ? GlobalLowering().lower(
                    source,
                    source.functions.map((f) => f.target),
                  )
                : source;
            if (lowered) expect(program.globals, isEmpty);
            final facts = ProgramFlow(program, [
              (
                target: fixture.root,
                arguments: [
                  unknown
                      ? FlowValue.unknown(fixture.holder)
                      : FlowValue.constant(fixture.argument),
                ],
              ),
            ]).facts;
            final expected = throwing ? 109 : 9;
            expect(facts.hasUnknownCall(fixture.call), unknown);
            expect(
              facts.returnedBy(fixture.root).integers!.contains(expected),
              isTrue,
            );
            if (!unknown) {
              expect(
                facts.returnedBy(fixture.root).constant?.structuralKey,
                Constant.integer(expected).structuralKey,
              );
            }
            for (final graph in [
              program,
              const ProgramSimplification().run(facts),
            ]) {
              expect(
                IrInterpreter(
                  graph,
                  {},
                ).run(graph.implementationOf(fixture.oracle) as IrFunction, []),
                expected,
              );
            }
          },
        );
      }
    }

    for (final physical in [false, true]) {
      for (final throwing in [false, true]) {
        test(
          'unknown callbacks can invoke a closure stored in program state (lowered=$lowered, throw=$throwing, physical=$physical)',
          () {
            final fixture = _globalCapture(
              throwing: throwing,
              physical: physical,
            );
            final source = fixture.program;
            final program = lowered
                ? GlobalLowering().lower(
                    source,
                    source.functions.map((f) => f.target),
                  )
                : source;
            final facts = ProgramFlow(program, [
              (target: fixture.root, arguments: <FlowValue>[]),
            ]).facts;
            final expected = throwing ? 109 : 9;
            final call = (program.implementationOf(fixture.root) as IrFunction)
                .blocks
                .map((block) => block.end)
                .whereType<Invoke>()
                .map((end) => end.operation)
                .whereType<FunctionCall>()
                .single;
            expect(facts.hasUnknownCall(call), isTrue);
            expect(facts.definitions, contains(fixture.registered));
            expect(
              facts.returnedBy(fixture.root).integers!.contains(expected),
              isTrue,
            );
            for (final graph in [
              program,
              const ProgramSimplification().run(facts),
            ]) {
              late IrInterpreter interpreter;
              interpreter = IrInterpreter(
                graph,
                {},
                externalCalls: {
                  fixture.factory: (_) => interpreter.run(
                    graph.implementationOf(fixture.maker) as IrFunction,
                    [],
                  ),
                },
              );
              expect(
                interpreter.run(
                  graph.implementationOf(fixture.root) as IrFunction,
                  [],
                ),
                expected,
              );
            }
          },
        );
      }
    }
    test(
      'a declared external leaf keeps its bounded state contract (lowered=$lowered)',
      () {
        final fixture = _callback(throwing: false, externalLeaf: true);
        final source = fixture.program;
        final program = lowered
            ? GlobalLowering().lower(
                source,
                source.functions.map((f) => f.target),
              )
            : source;
        final facts = ProgramFlow(program, [
          (
            target: fixture.root,
            arguments: [FlowValue.unknown(fixture.holder)],
          ),
        ]).facts;
        expect(facts.hasUnknownCall(fixture.call), isFalse);
        expect(
          facts.returnedBy(fixture.root).constant,
          const Constant.integer(1),
        );
        for (final graph in [
          program,
          const ProgramSimplification().run(facts),
        ]) {
          expect(
            IrInterpreter(
              graph,
              {},
              externalCalls: {fixture.leaf: (_) => null},
            ).run(graph.implementationOf(fixture.oracle) as IrFunction, []),
            1,
          );
        }
      },
    );
  }

  for (final context in [false, true]) {
    for (final throwing in [false, true]) {
      test(
        'unknown callbacks can write implicit native storage (context=$context, throw=$throwing)',
        () {
          final data = NativeData([1, 0, 0, 0, 0, 0, 0, 0], alignment: 8);
          final storage = NativeScalarType(Int64);
          final writer = FunctionTarget(_uri, 'nativeWriter', .voidType, []);
          final write = Block();
          write.emit(
            StoreNative(
              write.emit(
                context ? ReadNativeContext() : NativeDataAddress(data),
              ),
              storage,
              const Constant.integer(9),
            ),
          );
          write.finish(
            throwing ? Throw(const Constant.integer(7)) : const Return(),
          );
          final root = FunctionTarget(_uri, 'nativeRoot', .integer, [
            writer.signature,
          ]);
          final entry = Block(root.parameterTypes),
              done = Block(),
              caught = Block();
          final location = entry.emit(
            context
                ? NativeLocalStorage(storage, zeroInitialize: true)
                : NativeDataAddress(data),
          );
          if (context) entry.emit(BindNativeContext(location));
          final call = FunctionCall(entry.parameters.single, const []);
          entry.finish(
            Invoke(call, onReturn: Jump(done), onThrow: Jump(caught)),
          );
          done.finish(Return(done.emit(LoadNative(location, storage))));
          caught.finish(
            Return(
              caught.emit(
                IntBinary(
                  .add,
                  const Constant.integer(100),
                  caught.emit(LoadNative(location, storage)),
                ),
              ),
            ),
          );
          final program = IrProgram([], [
            IrFunction(root, [entry, done, caught]),
            IrFunction(writer, [write]),
          ]);
          final layout = ProgramLayout(
            program.classes,
            nativeLayout: NativeLayout(const Target(.linux, .arm64)),
          );
          final facts = ProgramFlow(program, [
            (target: root, arguments: [FlowValue.unknown(writer.signature)]),
          ], memoryLayout: layout).facts;
          final expected = throwing ? 109 : 9;
          expect(facts.hasUnknownCall(call), isTrue);
          expect(facts.returnedBy(root).integers!.contains(expected), isTrue);
          final known = ProgramFlow(program, [
            (
              target: root,
              arguments: [FlowValue.constant(FunctionConstant(writer))],
            ),
          ], memoryLayout: layout).facts;
          expect(known.hasUnknownCall(call), isFalse);
          expect(
            known.returnedBy(root).constant?.structuralKey,
            Constant.integer(expected).structuralKey,
          );
        },
      );
    }
  }
}

({
  IrProgram program,
  FunctionTarget root,
  FunctionTarget oracle,
  FunctionTarget leaf,
  ClassType holder,
  Constant argument,
  Instruction call,
})
_callback({required bool throwing, bool externalLeaf = false}) {
  final holder = ClassType(_uri, 'Holder');
  final field = InstanceField(
    holder,
    'callback',
    FunctionType(.voidType, []),
    isFinal: true,
  );
  final initializer = FunctionTarget(_uri, 'initial', .integer, []);
  final observed = GlobalVariable(
    _uri,
    'observed',
    .integer,
    initializer: initializer,
  );
  final writer = FunctionTarget(_uri, 'writeThenComplete', .voidType, []);
  final write = Block();
  write.emit(StoreGlobal(observed, const Constant.integer(9)));
  write.finish(throwing ? Throw(const Constant.integer(7)) : const Return());
  final leaf = FunctionTarget(_uri, 'boundedLeaf', .voidType, []);
  final helper = FunctionTarget(_uri, 'invoke', .voidType, [holder]);
  final invoke = Block(helper.parameterTypes);
  final Instruction call = externalLeaf
      ? DirectCall(leaf, [])
      : FunctionCall(
          invoke.emit(LoadField(field, invoke.parameters.single)),
          const [],
        );
  invoke.emit(call);
  invoke.finish(const Return());
  final root = FunctionTarget(_uri, 'consume', .integer, [holder]);
  final entry = Block(root.parameterTypes), normal = Block(), caught = Block();
  entry.emit(StoreGlobal(observed, const Constant.integer(1)));
  entry.finish(
    Invoke(
      DirectCall(helper, entry.parameters),
      onReturn: Jump(normal),
      onThrow: Jump(caught),
    ),
  );
  normal.finish(Return(normal.emit(LoadGlobal(observed))));
  caught.finish(
    Return(
      caught.emit(
        IntBinary(
          .add,
          const Constant.integer(100),
          caught.emit(LoadGlobal(observed)),
        ),
      ),
    ),
  );
  final argument = ObjectConstant(holder, {field: FunctionConstant(writer)});
  final oracle = FunctionTarget(_uri, 'oracle', .integer, []);
  final concrete = Block();
  concrete.finish(Return(concrete.emit(DirectCall(root, [argument]))));
  final program = IrProgram(
    [
      IrClass(holder, [field]),
    ],
    [
      IrFunction(root, [entry, normal, caught]),
      IrFunction(helper, [invoke]),
      IrFunction(writer, [write]),
      IrFunction(oracle, [concrete]),
      IrFunction(initializer, [
        Block()..finish(const Return(Constant.integer(0))),
      ]),
    ],
    globals: [observed],
    externals: [
      IrExternal(
        leaf,
        effects: const {Effect.writesStorage},
        capturesArguments: false,
      ),
    ],
  );
  return (
    program: program,
    root: root,
    oracle: oracle,
    leaf: leaf,
    holder: holder,
    argument: argument,
    call: call,
  );
}

({
  IrProgram program,
  FunctionTarget root,
  FunctionTarget factory,
  FunctionTarget maker,
  FunctionTarget registered,
  Instruction call,
})
_globalCapture({required bool throwing, bool physical = false}) {
  final root = FunctionTarget(_uri, 'captureRoot', .integer, []);
  final cellType = CellType(.integer);
  final registered = FunctionTarget(
    _uri,
    'registered',
    .voidType,
    [.integer],
    kind: .closure,
    enclosing: root,
    sourceOffset: 1,
    captures: [cellType],
  );
  final initializer = FunctionTarget(
    _uri,
    'initialCallback',
    registered.signature.nullable,
    [],
  );
  final saved = GlobalVariable(
    _uri,
    'saved',
    registered.signature.nullable,
    initializer: initializer,
  );
  final writer = Block(registered.parameterTypes);
  writer.emit(WriteCell(writer.parameters[1], const Constant.integer(9)));
  writer.finish(throwing ? Throw(const Constant.integer(7)) : const Return());
  final attack = FunctionTarget(_uri, 'invokeRegistered', .voidType, []);
  final attacking = Block();
  attacking.emit(
    FunctionCall(attacking.emit(NullCheck(attacking.emit(LoadGlobal(saved)))), [
      const Constant.integer(4),
    ]),
  );
  attacking.finish(const Return());
  final maker = FunctionTarget(
    _uri,
    'makeRuntimeCallback',
    attack.signature,
    [],
  );
  final factory = FunctionTarget(_uri, 'opaqueFactory', attack.signature, []);
  final body = Block(), normal = Block(), caught = Block();
  final cell = body.emit(NewCell(cellType, const Constant.integer(1)));
  body.emit(StoreGlobal(saved, body.emit(MakeClosure(registered, [cell]))));
  final call = FunctionCall(body.emit(DirectCall(factory, [])), []);
  body.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(caught)));
  normal.finish(Return(normal.emit(ReadCell(cell))));
  caught.finish(
    Return(
      caught.emit(
        IntBinary(
          .add,
          const Constant.integer(100),
          caught.emit(ReadCell(cell)),
        ),
      ),
    ),
  );
  var program = IrProgram(
    [],
    [
      IrFunction(root, [body, normal, caught]),
      IrFunction(registered, [writer]),
      IrFunction(attack, [attacking]),
      IrFunction(maker, [Block()..finish(Return(FunctionConstant(attack)))]),
      IrFunction(initializer, [
        Block()..finish(const Return(Constant.nullValue())),
      ]),
    ],
    globals: [saved],
    externals: [
      IrExternal(factory, effects: const {}, capturesArguments: false),
    ],
  );
  if (physical) {
    final owner = CallableImplementations()..extend(program);
    final rootBody = program.implementationOf(root) as IrFunction;
    final rewritten = FunctionRewrite(
      rootBody,
      operations: {
        for (final block in rootBody.blocks)
          for (final operation in block.instructions.whereType<MakeClosure>())
            operation: owner.createClosure(operation),
      },
    ).run();
    program = IrProgram(
      [
        ...program.classes,
        ...owner.storage.classes,
        for (final entry in TypeMetadata.fields.entries)
          IrClass(entry.key, entry.value),
      ],
      [
        for (final body in program.functions)
          body.target == root ? rewritten : body,
        ...owner.constructionFunctions,
        ...owner.storage.functions,
      ],
      globals: program.globals,
      externals: program.externals,
    );
  }
  return (
    program: program,
    root: root,
    factory: factory,
    maker: maker,
    registered: registered,
    call: call,
  );
}
