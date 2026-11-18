import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

Iterable<Instruction> ops(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  setUpAll(prepareRuntime);
  for (final opaque in [false, true]) {
    for (final pointer in [false, true]) {
      test(
        'publication stays independent of rebound ${opaque ? "Int64 storage" : "zero"}, ${pointer ? "pointer call" : "import"}',
        () {
          final signature = NativeSignature(Int64, []);
          final foreign = FunctionTarget(null, 'foreign', .integer, []);
          final root = FunctionTarget(null, 'root', .integer, []);
          final block = Block();
          final Value binding = opaque
              ? block.emit(
                  NativeLocalStorage(
                    NativeScalarType(Int64),
                    zeroInitialize: true,
                  ),
                )
              : const Constant.integer(0);
          final bind = block.emit(BindNativeContext(binding));
          final call = pointer
              ? block.emit(
                  NativeCall.symbol(
                    block.emit(
                      NativeSymbolAddress(
                        NativeReference(
                          'review',
                          'foreign',
                          NativeFunctionType(signature),
                        ),
                      ),
                    ),
                    FunctionType(.integer, []),
                    [],
                  ),
                )
              : block.emit(DirectCall(foreign, []));
          block.finish(Return(call));
          final original = NativeBoundaries(
            IrProgram(
              [],
              [
                IrFunction(root, [block]),
              ],
              externals: [if (!pointer) IrExternal(foreign)],
            ),
            roots: [root],
            imports: {if (!pointer) foreign: signature},
            exports: {root: NativeExport('root', signature)},
          );
          // This is Compiler.prepare's actual lifecycle constructor and exact
          // default managedContext owner, without a heavyweight whole-runtime run.
          final boundaries = NativeBoundaries.withLifecycle(
            original,
            heapRuntime,
          );
          expect(boundaries.hasLifecycle, isTrue);
          final lowered = NativeCallLowering(
            managedContext: boundaries.runtimeContext,
            failure: boundaries.publicationFailure,
          ).lower(boundaries.program);
          final source = lowered.implementationOf(root) as IrFunction;
          final sourceOps = ops(source).toList();
          final actualBind = sourceOps.whereType<BindNativeContext>().single;
          if (opaque) {
            expect(
              (actualBind.address as NativeLocalStorage).declaration,
              same((binding as NativeLocalStorage).declaration),
            );
          } else {
            expect((actualBind.address as ScalarConstant).value, 0);
          }
          expect(bind.address, same(binding));
          final bridgeCall = sourceOps.whereType<DirectCall>().single;
          expect(
            sourceOps.indexOf(actualBind),
            lessThan(sourceOps.indexOf(bridgeCall)),
          );
          final bridge =
              lowered.implementationOf(bridgeCall.target) as IrFunction;
          expect(bridge.entry.end, isA<Branch>());
          final body = ops(bridge).toList();
          expect(body.whereType<ReadNativeContext>(), isEmpty);
          final owned = body.whereType<NativeDataAddress>().single;
          expect(owned.declaration, same(boundaries.runtimeContext));
          final lookup = body.whereType<LoadNative>().single;
          final address = lookup.address as IntBinary;
          expect(address.left, same(owned));
          expect(
            (address.right as ScalarConstant).value,
            RuntimeContext.active,
          );
          expect(boundaries.runtimeContext!.bytes.length, RuntimeContext.size);
          final query =
              lowered.implementationOf(heapRuntime.context!) as IrFunction;
          expect(
            ops(query).whereType<NativeDataAddress>().single.declaration,
            same(boundaries.runtimeContext),
          );
          final stores = body.whereType<StoreNative>().toList();
          expect(stores, hasLength(2));
          for (final store in stores) {
            expect((store.address as IntBinary).left, same(lookup));
          }
          final externalCall = pointer
              ? body.whereType<RawNativeCall>().single
              : body.whereType<DirectCall>().singleWhere(
                  (call) => call.target != boundaries.publicationFailure,
                );
          expect(
            body.indexOf(stores.last),
            lessThan(body.indexOf(externalCall)),
          );
          expect(
            source.observesCallerFrame,
            isTrue,
          ); // Bind activation survives.
        },
      );
    }
  }

  test(
    'unlinked mixed source root fails before publication and native entry',
    () {
      final signature = NativeSignature(Int64, []);
      final plain = FunctionTarget(null, 'plain', .integer, []);
      final exported = FunctionTarget(null, 'exported', .integer, []);
      final native = FunctionTarget(null, 'foreign', .integer, []);
      final a = Block();
      a.finish(Return(a.emit(DirectCall(native, []))));
      final b = Block()..finish(const Return(Constant.integer(42)));
      final original = NativeBoundaries(
        IrProgram(
          [],
          [
            IrFunction(plain, [a]),
            IrFunction(exported, [b]),
          ],
          externals: [IrExternal(native)],
        ),
        roots: [plain],
        exports: {exported: NativeExport('exported', signature)},
        imports: {native: signature},
      );
      final boundaries = NativeBoundaries.withLifecycle(original, heapRuntime);
      final failure = boundaries.publicationFailure!;
      final program = IrProgram(
        boundaries.program.classes,
        boundaries.program.functions,
        externals: boundaries.program.externals,
      );
      expect(boundaries.roots, contains(plain));
      final source = program.implementationOf(plain) as IrFunction;
      expect(source.callees, {native});
      final bridge = program.implementationOf(native) as IrFunction;
      final facts = ProgramFlow(
        program,
        [(target: plain, arguments: [])],
        memoryLayout: ProgramLayout(
          [],
          nativeLayout: NativeLayout(Target.host()),
        ),
      ).facts;
      expect(facts.returnedBy(plain).isBottom, isTrue);
      expect(facts.definitions, contains(failure));
      final foreign = boundaries.imports.keys.single;
      expect(facts.definitions, isNot(contains(foreign)));
      for (final write in ops(bridge).whereType<StoreNative>()) {
        expect(facts.reachesOperation(write), isFalse);
      }
      final fail = ops(bridge)
          .whereType<DirectCall>()
          .singleWhere((call) => call.target == failure);
      expect(facts.reachesOperation(fail), isTrue);
    },
  );

  for (final throws in [false, true]) {
    test(
      'linked Dart root preserves ${throws ? "exception propagation" : "managed result"}',
      () {
        final signature = NativeSignature(Int64, []);
        final plain = FunctionTarget(null, 'plain', .object, [.object]);
        final exported = FunctionTarget(null, 'exported', .integer, []);
        final native = FunctionTarget(null, 'foreign', .integer, []);
        final a = Block(plain.parameterTypes);
        a.emit(BindNativeContext(const Constant.integer(0)));
        a.emit(DirectCall(native, []));
        a.finish(
          throws ? Throw(a.parameters.single) : Return(a.parameters.single),
        );
        final b = Block()..finish(const Return(Constant.integer(42)));
        final original = NativeBoundaries(
          IrProgram(
            [],
            [
              IrFunction(plain, [a]),
              IrFunction(exported, [b]),
            ],
            externals: [
              IrExternal(native, effects: const {}, terminates: true),
            ],
          ),
          roots: [plain],
          exports: {exported: NativeExport('exported', signature)},
          imports: {native: signature},
        );
        final boundaries = NativeBoundaries.withLifecycle(
          original,
          heapRuntime,
        );
        final root = FunctionTarget(null, 'caller', .object, []);
        final entry = Block(),
            returned = Block([ValueType.object]),
            caught = Block([ValueType.object]);
        final word = NativeScalarType(Int64);
        final context = entry.emit(
          NativeDataAddress(boundaries.runtimeContext!),
        );
        final record = entry.emit(
          NativeLocalStorage(
            NativeArrayType(word, RuntimeContext.entrySize ~/ 8),
            zeroInitialize: true,
          ),
        );
        entry.emit(
          StoreNative(
            entry.emit(
              IntBinary(
                .add,
                context,
                const Constant.integer(RuntimeContext.active),
              ),
            ),
            word,
            record,
          ),
        );
        final value = const Constant.string('same managed value');
        final call = DirectCall(plain, [value]);
        entry.finish(
          Invoke(
            call,
            onReturn: Jump(returned, [call]),
            onThrow: Jump(caught, [UnwindValue.exception]),
          ),
        );
        returned.finish(Return(returned.parameters.single));
        caught.finish(Return(caught.parameters.single));
        final program = IrProgram([], [
          ...boundaries.program.functions,
          IrFunction(root, [entry, returned, caught]),
        ], externals: boundaries.program.externals);
        final facts = ProgramFlow(
          program,
          [(target: root, arguments: [])],
          memoryLayout: ProgramLayout(
            [],
            nativeLayout: NativeLayout(Target.host()),
          ),
        ).facts;
        expect(facts.returnedBy(root).constant, value);
        expect(facts.definitions, contains(boundaries.imports.keys.single));

        final bridge = program.implementationOf(native) as IrFunction;
        for (final write in ops(bridge).whereType<StoreNative>()) {
          expect(facts.reachesOperation(write), isTrue);
        }
        expect(facts.reachesBlock(caught), throws);
        // Execute the real branches and stores with concrete host storage.
        // Only target address/frame primitives are supplied by this test model.
        _withHostStorage(program, (concrete) {
          var calls = 0;
          final interpreter = IrInterpreter(
            concrete,
            {},
            externalCalls: {
              boundaries.imports.keys.single: (_) {
                calls++;
                return 1;
              },
              boundaries.publicationFailure!: (_) =>
                  throw StateError('unlinked publication'),
            },
          );
          expect(
            interpreter.run(concrete.implementationOf(root) as IrFunction, []),
            'same managed value',
          );
          expect(calls, 1);
        });
      },
    );
  }

  test(
    'module context identity reaches every process and allocation consumer',
    () {
      final root = FunctionTarget(null, 'processBody', .integer, []);
      final block = Block()..finish(const Return(Constant.integer(0)));
      final source = NativeBoundaries(
        IrProgram([], [
          IrFunction(root, [block]),
        ]),
        roots: [root],
      );
      final first = NativeBoundaries.withLifecycle(
        source,
        heapRuntime,
        processEntry: root,
      );
      final second = NativeBoundaries.withLifecycle(
        source,
        heapRuntime,
        processEntry: root,
      );
      expect(first.runtimeContext, isNot(same(second.runtimeContext)));
      final entry =
          first.program.implementationOf(first.processEntry!) as IrFunction;
      final calls = ops(entry).whereType<DirectCall>().where(
        (call) => {
          heapRuntime.linkEntry,
          heapRuntime.unlinkEntry,
          heapRuntime.runEvents,
          heapRuntime.release,
        }.contains(call.target),
      );
      expect(
        calls.map((call) => call.target),
        containsAll([
          heapRuntime.linkEntry,
          heapRuntime.unlinkEntry,
          heapRuntime.runEvents,
          heapRuntime.release,
        ]),
      );
      for (final call in calls) {
        expect(
          (call.inputs.first as NativeDataAddress).declaration,
          same(first.runtimeContext),
        );
      }
      final type = ClassType(null, 'Retained');
      final allocation = HeapPlan(
        runtime: heapRuntime,
        managedContext: first.runtimeContext,
      ).payload(type);
      final call = ops(allocation)
          .whereType<DirectCall>()
          .singleWhere((call) => call.target == heapRuntime.allocate);
      expect(
        (call.inputs.first as NativeDataAddress).declaration,
        same(first.runtimeContext),
      );
      expect(ops(allocation).whereType<ReadNativeContext>(), isEmpty);
      expect(first.runtimeContext!.bytes.every((byte) => byte == 0), isTrue);
    },
  );
}

void _withHostStorage(IrProgram source, void Function(IrProgram) run) {
  final allocate = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Uint8> Function(Size, Size),
        Pointer<Uint8> Function(int, int)
      >('calloc');
  final free = DynamicLibrary.process()
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  final storage = <Object, Pointer<Uint8>>{};
  int address(Object key, int size, [List<int>? initial]) =>
      storage.putIfAbsent(key, () {
        final pointer = allocate(size, 1);
        if (pointer == nullptr) throw StateError('calloc failed');
        if (initial != null) pointer.asTypedList(size).setAll(0, initial);
        return pointer;
      }).address;
  try {
    final bodies = <IrFunction>[];
    for (final function in source.functions) {
      final replaced = <Value, Value>{}, discarded = <Instruction>{};
      for (final op in ops(function)) {
        switch (op) {
          case NativeDataAddress(:final declaration):
            replaced[op] = Constant.integer(
              address(declaration, declaration.bytes.length, declaration.bytes),
            );
          case NativeLocalStorage():
            replaced[op] = Constant.integer(
              address(
                op.declaration,
                NativeLayout(Target.host()).of(op.storage).size,
              ),
            );
          case FrameValue(:final kind):
            replaced[op] = Constant.integer(
              kind == .returnAddress ? 0x1234 : 0x3210,
            );
          case BindNativeContext():
            discarded.add(op);
          case StackMapAddress() || ModuleRootsAddress():
            replaced[op] = const Constant.integer(0);
          default:
            continue;
        }
        discarded.add(op);
      }
      bodies.add(
        FunctionRewrite(
          function,
          replacements: replaced,
          discardable: discarded,
        ).run(),
      );
    }
    run(
      IrProgram(
        source.classes,
        bodies,
        globals: source.globals,
        externals: source.externals,
      ),
    );
  } finally {
    for (final pointer in storage.values) {
      free(pointer);
    }
  }
}
