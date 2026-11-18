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
