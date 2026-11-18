import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

Iterable<Instruction> operations(IrFunction function) sync* {
  for (final block in function.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  final word = NativeScalarType(Int64);
  late FunctionTarget failure;
  setUpAll(() async {
    await prepareRuntime();
    failure = heapRuntime.primitives.entries
        .singleWhere((entry) => entry.value == .fail)
        .key;
  });
  final pair = NativeCompoundType('Pair', [NativeField('value', word)]);
  final pairType = ClassType(null, 'Pair', nativeType: pair);
  final pointerType = FfiTypes.int64Pointer;

  test('raw calls require C carriers and explicit compound output storage', () {
    final signature = NativeSignature.types(pair, [pair, .of(Pointer<Int64>)]);
    final args = <Value>[const Constant.integer(1), const Constant.integer(2)];
    final call = RawNativeCall(
      const Constant.integer(3),
      signature,
      args,
      resultStorage: const Constant.integer(4),
    );
    args.clear();
    expect(call.arguments, hasLength(2));
    expect(call.type, ValueType.voidType);
    expect(call.inputs, hasLength(4));
    expect(
      call.effects,
      containsAll([
        Effect.readsStorage,
        Effect.writesStorage,
        Effect.callsUserCode,
      ]),
    );
    expect(call.mapInputs((value) => value).inputs, call.inputs);
    expect(
      () => RawNativeCall(const Constant.integer(3), signature, call.arguments),
      throwsArgumentError,
    );
    expect(
      () => RawNativeCall(
        const Constant.integer(3),
        NativeSignature(Int64, []),
        [],
        resultStorage: const Constant.integer(4),
      ),
      throwsArgumentError,
    );
    expect(
      () => RawNativeCall(const Constant.integer(3), signature, [
        const Constant.integer(1),
        PointerFromAddress(const Constant.integer(2), pointerType),
      ], resultStorage: const Constant.integer(4)),
      throwsArgumentError,
    );
  });

  for (final compound in [false, true]) {
    for (final isLeaf in [false, true]) {
      test(
        '${compound ? 'aggregate' : 'pointer'} ${isLeaf ? 'leaf' : 'reentrant'} calls keep converted owners in the source caller',
        () {
          final type = compound ? pairType : pointerType;
          final native = compound ? pair : NativePointerType(word);
          final signature = NativeSignature.types(native, [native]);
          final target = FunctionTarget(null, 'source', type, [type]);
          final entry = Block(target.parameterTypes);
          final symbol = entry.emit(
            NativeSymbolAddress(
              NativeReference(
                'fixture',
                'probe',
                NativeFunctionType(signature),
                isLeaf: isLeaf,
              ),
            ),
          );
          final call = entry.emit(
            NativeCall.symbol(
              symbol,
              FunctionType(type, [type]),
              entry.parameters,
            ),
          );
          entry.finish(Return(call));
          final managedContext = NativeData(
            List.filled(RuntimeContext.size, 0),
            alignment: 8,
          );
          final pass = NativeCallLowering(
            managedContext: managedContext,
            failure: failure,
          );
          final source = IrProgram(
            [if (compound) IrClass(pairType, [])],
            [
              IrFunction(target, [entry]),
            ],
            externals: [
              heapRuntime.program.implementationOf(failure) as IrExternal,
            ],
          );
          final lowered = pass.lower(source);
          expect(pass.lower(lowered), same(lowered));
          final caller = lowered.implementationOf(target) as IrFunction;
          final ops = operations(caller).toList();
          expect(ops.whereType<NativeCall>(), isEmpty);
          expect(ops.whereType<FrameValue>(), isEmpty);
          final Instruction boundary = isLeaf
              ? ops.whereType<RawNativeCall>().single
              : ops.whereType<DirectCall>().single;
          final live = ValueLiveness.source(
            caller,
            calls: {boundary},
          ).acrossCalls[boundary]!;
          expect(live, contains(caller.entry.parameters.single));
          if (compound) {
            final output = ops.whereType<NativeView>().single;
            expect(live, contains(output));
            expect(ops.indexOf(output), lessThan(ops.indexOf(boundary)));
          } else {
            expect(
              ops.indexOf(ops.whereType<PointerFromAddress>().single),
              greaterThan(ops.indexOf(boundary)),
            );
          }
          if (isLeaf) {
            expect(lowered.functions, hasLength(1));
            expect((boundary as RawNativeCall).isLeaf, isTrue);
          } else {
            final bridge = lowered.implementationOf(
              (boundary as DirectCall).target,
            ) as IrFunction;
            expect(bridge.observesCallerFrame, isTrue);
            expect(
              bridge.target.parameterTypes.every(
                (type) => type == ValueType.integer,
              ),
              isTrue,
            );
            final body = operations(bridge).toList();
            expect(body.whereType<NativeView>(), isEmpty);
            expect(body.whereType<PointerFromAddress>(), isEmpty);
            expect(body.whereType<ReadNativeContext>(), isEmpty);
            expect(
              body.whereType<NativeDataAddress>().single.declaration,
              same(managedContext),
            );
            expect(body.whereType<LoadNative>(), hasLength(1));
            expect(body.whereType<StoreNative>(), hasLength(2));
            expect(body.whereType<FrameValue>().map((value) => value.kind), [
              FrameValueKind.callerStackPointer,
              FrameValueKind.returnAddress,
            ]);
            final raw = body.whereType<RawNativeCall>().single;
            expect(
              body.indexOf(body.whereType<StoreNative>().last),
              lessThan(body.indexOf(raw)),
            );
          }
        },
      );
    }
  }

  test('publication uses its owned context despite opaque ABI binding', () {
    final native = FunctionTarget(null, 'foreign', .integer, [.integer]);
    final bridgeTarget = FunctionTarget(null, 'bridge', .integer, [.integer]);
    final managedContext = NativeData(
      List.filled(RuntimeContext.size, 0),
      alignment: 8,
    );
    final bridge = NativeCallLowering.importBridge(
      bridgeTarget,
      native,
      managedContext: managedContext,
      failure: failure,
    );
    final recordType = NativeArrayType(
      .of(Int64),
      RuntimeContext.entrySize ~/ 8,
    );
    final root = FunctionTarget(null, 'root', .integer, []);
    final entry = Block();
    final context = entry.emit(NativeDataAddress(managedContext));
    final record = entry.emit(
      NativeLocalStorage(recordType, zeroInitialize: true),
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
    entry.emit(BindNativeContext(const Constant.integer(0)));
    entry.finish(
      Return(entry.emit(DirectCall(bridgeTarget, [const Constant.integer(7)]))),
    );
    final program = IrProgram(
      [],
      [
        IrFunction(root, [entry]),
        bridge,
      ],
      externals: [
        IrExternal(native),
        heapRuntime.program.implementationOf(failure) as IrExternal,
      ],
    );
    final facts = ProgramFlow(
      program,
      [(target: root, arguments: [])],
      memoryLayout: ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      ),
    ).facts;
    final lookup = operations(bridge).whereType<LoadNative>().single;
    expect(facts.valueOf(lookup).addresses, facts.valueOf(record).addresses);
    final writes = operations(bridge).whereType<StoreNative>();
    for (final store in writes) {
      expect(facts.effectsOf(store), contains(Effect.writesStorage));
    }
    final rewritten = const DirectCallInlining(maxCalleeCost: 10000).run(facts);
    expect(rewritten.implementationOf(bridgeTarget), isA<IrFunction>());
    expect(
      (rewritten.implementationOf(root) as IrFunction).callees,
      contains(bridgeTarget),
    );
    for (final os in OperatingSystem.values) {
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(Target(os, .arm64)),
        X64CodeGenerator(Target(os, .x64)),
      ]) {
        final module = generator.generate(
          Compiler(generator.target).prepare(
            program,
            roots: [root],
            runtime: heapRuntime,
            imports: {
              native: NativeImport('foreign', NativeSignature(Int64, [Int64])),
            },
          ),
        );
        expect(module.imports, {generator.target.nativeSymbol('foreign')});
        expect(module.symbols.any((symbol) => symbol.name == 'bridge'), isTrue);
      }
    }
  });

  test('aggregate ABI adapters preserve the observed raw call without new semantic dependencies', () {
    final signature = NativeSignature.types(word, [pair]);
    for (final isLeaf in [false, true]) {
      final target = FunctionTarget(null, 'rawAggregate', .integer, [
        .integer,
        .integer,
      ]);
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            RawNativeCall(entry.parameters.first, signature, [
              entry.parameters.last,
            ], isLeaf: isLeaf),
          ),
        ),
      );
      final program = IrProgram([], [
        IrFunction(target, [entry]),
      ]);
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.linux, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        final prepared = Compiler(generator.target)
            .prepare(program, roots: [target]);
        expect(generator.generate(prepared).imports, isEmpty);
      }
    }
  });

  test('preparation rejects a changed native no-reentry promise', () {
    final target = FunctionTarget(null, 'leaf', .integer, []);
    final signature = NativeSignature(Int64, []);
    final source = IrProgram([], [], externals: [IrExternal(target)]);
    final boundaries = NativeBoundaries(
      source,
      roots: [target],
      imports: {target: signature},
      leafImports: [target],
    );
    expect(
      () => ProgramPreparation(
        const Target(.linux, .arm64),
        source,
        boundaries: boundaries,
        imports: {target: NativeImport('leaf', signature)},
      ),
      throwsArgumentError,
    );
  });

  test('import lifecycle bridges respect the real leaf promise', () async {
    await prepareRuntime();
    final signature = NativeSignature(Int64, [Int64]);
    final leaf = FunctionTarget(null, 'leaf', .integer, [.integer]);
    final reentrant = FunctionTarget(null, 'reentrant', .integer, [.integer]);
    final root = FunctionTarget(null, 'root', .integer, [.integer]);
    final entry = Block(root.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          DirectCall(reentrant, [
            entry.emit(DirectCall(leaf, entry.parameters)),
          ]),
        ),
      ),
    );
    final original = NativeBoundaries(
      IrProgram(
        [],
        [
          IrFunction(root, [entry]),
        ],
        externals: [IrExternal(leaf), IrExternal(reentrant)],
      ),
      roots: [root],
      imports: {leaf: signature, reentrant: signature},
      leafImports: [leaf],
      exports: {root: NativeExport('root', signature)},
    );
    final boundaries = NativeBoundaries.withLifecycle(original, heapRuntime);
    expect(boundaries.imports.containsKey(leaf), isTrue);
    expect(boundaries.program.implementationOf(leaf), isA<IrExternal>());
    expect(boundaries.imports.containsKey(reentrant), isFalse);
    final bridge = boundaries.program.implementationOf(reentrant) as IrFunction;
    final terminal = boundaries.imports.entries
        .singleWhere((entry) => entry.value.source == reentrant)
        .key;
    expect(bridge.callees, {terminal, boundaries.publicationFailure});
    expect(operations(bridge).whereType<StoreNative>(), hasLength(2));
    expect(bridge.observesCallerFrame, isTrue);
  });
}
