import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/program_preparation.dart'
    show PreparedProgramEmission;
import 'package:dartc/runtime/contracts.dart';
import 'package:dartc/src/compiler/runtime.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  late LoweringResult lowered;
  setUpAll(() async => lowered = await prepareRuntime());
  final uri = Uri.parse('memory:runtime-contract');
  final entry = FunctionTarget(uri, 'entry', .integer, []);

  HeapRuntime withCritical(
    FunctionTarget function, {
    IrFunction? processStatus,
    FunctionTarget? linkEntry,
    FunctionTarget? unlinkEntry,
    Iterable<NativeReference> nativeContracts = const [],
  }) => HeapRuntime(
    processStatus == null
        ? heapRuntime.program
        : IrProgram(
            heapRuntime.program.classes,
            [...heapRuntime.program.functions, processStatus],
            globals: heapRuntime.program.globals,
            externals: heapRuntime.program.externals,
          ),
    types: heapRuntime.types,
    invocation: heapRuntime.invocation,
    dispatchFailure: heapRuntime.dispatchFailure,
    stackContext: heapRuntime.stackContext,
    allocate: heapRuntime.allocate,
    allocationFailure: heapRuntime.allocationFailure,
    isOutOfMemory: heapRuntime.isOutOfMemory,
    linkEntry: linkEntry ?? heapRuntime.linkEntry,
    unlinkEntry: unlinkEntry ?? heapRuntime.unlinkEntry,
    release: heapRuntime.release,
    runEvents: heapRuntime.runEvents,
    processExitCode: processStatus?.target,
    copyBytes: heapRuntime.copyBytes,
    captureStackTrace: heapRuntime.captureStackTrace,
    captureTrace: heapRuntime.captureTrace,
    recordError: heapRuntime.recordError,
    typeCheckFailure: heapRuntime.typeCheckFailure,
    primitives: heapRuntime.primitives,
    nonAllocating: [...heapRuntime.nonAllocating, function],
    nonAllocatingNatives: [
      ...heapRuntime.nonAllocatingNatives,
      ...nativeContracts,
    ],
  );

  IrFunction mainBody(bool managed) {
    final block = Block();
    block.finish(
      Return(
        managed
            ? block.emit(
                CollectionLength(
                  block.emit(NewCollection(CoreTypes.listOf(.integer))),
                ),
              )
            : const Constant.integer(42),
      ),
    );
    return IrFunction(entry, [block]);
  }

  test('runtime external effects reach the semantic program', () {
    for (final MapEntry(key: target, value: operation)
        in heapRuntime.primitives.entries) {
      final external =
          heapRuntime.program.implementationOf(target) as IrExternal;
      expect(external.effects, operation.effects, reason: target.name);
    }
    final readonly = heapRuntime.program.functions.singleWhere(
      (body) =>
          body.target.owner?.name == 'Memory' && body.target.name == 'context',
    );
    expect(
      readonly.blocks.expand((block) => block.instructions).single.effects,
      {Effect.readsStorage},
    );
    for (final entry in lowered.imports.entries) {
      if (lowered.program.implementationOf(entry.key) case IrExternal source) {
        final bound = heapRuntime.program.implementationOf(entry.key);
        if (bound is! IrExternal || heapRuntime.primitives.containsKey(entry.key)) {
          continue;
        }
        final critical = lowered.runtime.nonAllocating.contains(entry.key);
        expect(bound.effects, {
          ...source.effects,
        }..removeAll({
          if (critical || entry.value.isLeaf) Effect.callsUserCode,
          if (critical) ...[Effect.allocates, Effect.mayThrow],
        }), reason: entry.key.name);
      }
    }
  });

  test('leaf calling convention preserves declared failure and memory effects', () {
    final leaf = FunctionTarget(uri, 'readNative', .integer, []);
    final signature = NativeFunctionType(NativeSignature(Int64, []));
    final source = IrExternal(
      leaf,
      effects: {Effect.readsStorage, Effect.allocates, Effect.mayThrow, Effect.callsUserCode},
      memory: const .unchanged(),
      terminates: true,
      capturesArguments: false,
    );
    final bound = bindRuntime((
      program: IrProgram(
        lowered.program.classes,
        lowered.program.functions,
        globals: lowered.program.globals,
        externals: [...lowered.program.externals, source],
      ),
      entryPoint: lowered.entryPoint,
      exports: lowered.exports,
      imports: {...lowered.imports, leaf: NativeReference('asset', 'read', signature, isLeaf: true)},
      runtime: lowered.runtime,
    ), Target.host()).program.implementationOf(leaf) as IrExternal;
    expect(bound.effects, {Effect.readsStorage, Effect.allocates, Effect.mayThrow});
    expect(bound.memory, same(source.memory));
    expect(bound.terminates, isTrue);
    expect(bound.capturesArguments, isFalse);
  });

  test('runtime entries must implement their machine boundary signatures', () {
    for (final target in [
      ...lowered.runtime.entries.values,
      ...lowered.runtime.primitives.keys,
      ...lowered.runtime.nonAllocating,
    ]) {
      expect(lowered.program.implementationOf(target)?.target, same(target));
    }
    final context = lowered.runtime.stackContext;
    expect(context, isNotNull);
    expect(heapRuntime.stackContext, same(context));
    final record = heapRuntime.program.classes.singleWhere(
      (c) => c.type.name == 'FinalizationRecord',
    );
    expect(
      record.weakFields.map((f) => f.name),
      unorderedEquals(['target', 'detachKey', '_registryNext']),
    );
    expect(
      () => HeapRuntime(
        heapRuntime.program,
        allocate: heapRuntime.release,
        isOutOfMemory: heapRuntime.isOutOfMemory,
        linkEntry: heapRuntime.linkEntry,
        unlinkEntry: heapRuntime.unlinkEntry,
        release: heapRuntime.release,
        runEvents: heapRuntime.runEvents,
        copyBytes: heapRuntime.copyBytes,
        captureStackTrace: heapRuntime.captureStackTrace,
        captureTrace: heapRuntime.captureTrace,
        recordError: heapRuntime.recordError,
        primitives: heapRuntime.primitives,
        nonAllocating: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => HeapRuntime(
        heapRuntime.program,
        allocate: heapRuntime.allocate,
        isOutOfMemory: heapRuntime.isOutOfMemory,
        linkEntry: heapRuntime.linkEntry,
        unlinkEntry: heapRuntime.unlinkEntry,
        release: heapRuntime.release,
        runEvents: heapRuntime.runEvents,
        copyBytes: heapRuntime.copyBytes,
        captureStackTrace: heapRuntime.captureStackTrace,
        captureTrace: heapRuntime.captureTrace,
        recordError: heapRuntime.recordError,
        primitives: {
          ...heapRuntime.primitives,
          heapRuntime.primitives.entries
                  .singleWhere((entry) => entry.value == .map)
                  .key:
              .fail,
        },
        nonAllocating: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => HeapRuntime(
        heapRuntime.program,
        allocate: heapRuntime.allocate,
        isOutOfMemory: heapRuntime.isOutOfMemory,
        linkEntry: heapRuntime.linkEntry,
        unlinkEntry: heapRuntime.unlinkEntry,
        release: heapRuntime.release,
        runEvents: heapRuntime.runEvents,
        copyBytes: heapRuntime.copyBytes,
        captureStackTrace: heapRuntime.captureStackTrace,
        captureTrace: heapRuntime.captureStackTrace,
        recordError: heapRuntime.recordError,
        primitives: heapRuntime.primitives,
        nonAllocating: [],
      ),
      throwsArgumentError,
    );
  });

  test('entry protocols require their signatures and ordinary Dart bodies', () {
    expect(
      heapRuntime.linkEntry,
      same(lowered.runtime.entries[RuntimeRole.linkEntry]),
    );
    expect(
      heapRuntime.unlinkEntry,
      same(lowered.runtime.entries[RuntimeRole.unlinkEntry]),
    );
    for (final (link, unlink) in [
      (heapRuntime.unlinkEntry, heapRuntime.unlinkEntry),
      (heapRuntime.linkEntry, heapRuntime.release),
      (
        FunctionTarget(
          uri,
          'missingLink',
          .voidType,
          List.filled(4, ValueType.integer),
        ),
        heapRuntime.unlinkEntry,
      ),
      (
        heapRuntime.linkEntry,
        FunctionTarget(uri, 'missingUnlink', .voidType, [.integer, .integer]),
      ),
    ]) {
      expect(
        () => withCritical(
          heapRuntime.isOutOfMemory,
          linkEntry: link,
          unlinkEntry: unlink,
        ),
        throwsArgumentError,
      );
    }
  });

  test('runtime binding rejects a missing entry protocol', () {
    for (final missing in [RuntimeRole.linkEntry, RuntimeRole.unlinkEntry]) {
      final entries = {...lowered.runtime.entries}..remove(missing);
      final result = (
        program: lowered.program,
        entryPoint: lowered.entryPoint,
        exports: lowered.exports,
        imports: lowered.imports,
        runtime: RuntimeDeclarations(
          entries,
          lowered.runtime.primitives,
          lowered.runtime.nonAllocating,
          lowered.runtime.systemFunctions,
          aliases: lowered.runtime.aliases,
          stackContext: lowered.runtime.stackContext,
        ),
      );
      expect(() => bindRuntime(result, Target.host()), throwsArgumentError);
    }
  });

  test('runtime linking rejects conflicting instance storage', () {
    final declaration = heapRuntime.program.classes.firstWhere(
      (c) => c.fields.isNotEmpty,
    );
    final changed = IrClass(declaration.type, [
      InstanceField(declaration.type, 'foreign', .integer),
    ]);
    expect(
      () => Arm64CodeGenerator(const Target(.linux, .arm64)).generate(
        Compiler(const Target(.linux, .arm64)).prepare(
          IrProgram([changed], [mainBody(true)]),
          roots: [entry],
          runtime: heapRuntime,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('trusted cast entries validate signatures without Dart cast checks', () {
    final parameter = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    for (final (operation, input, valid)
        in <(MemoryOperation, ValueType, bool)>[
          (.uncheckedCast, .dynamicType, true),
          (.uncheckedCast, .integer, false),
          (.typeView, .typeType, true),
          (.typeView, .object, false),
        ]) {
      final typeView = operation == .typeView;
      final target = FunctionTarget(
        uri,
        'assertType',
        typeView ? TypeMetadata.type : parameter,
        [input],
        typeParameters: typeView ? [] : [parameter],
      );
      final result = (
        program: IrProgram(
          lowered.program.classes,
          lowered.program.functions,
          globals: lowered.program.globals,
          externals: [...lowered.program.externals, IrExternal(target)],
        ),
        entryPoint: lowered.entryPoint,
        exports: lowered.exports,
        imports: lowered.imports,
        runtime: RuntimeDeclarations(
          lowered.runtime.entries,
          {...lowered.runtime.primitives, target: operation},
          lowered.runtime.nonAllocating,
          lowered.runtime.systemFunctions,
        ),
      );
      if (!valid) {
        expect(() => bindRuntime(result, Target.host()), throwsArgumentError);
      } else {
        final body = bindRuntime(
          result,
          Target.host(),
        ).program.implementationOf(target) as IrFunction;
        expect(body.blocks.single.instructions.single, isA<UncheckedCast>());
      }
    }
  });

  test('ABI queries reject incompatible trusted declarations', () {
    final parameter = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    for (final target in [
      FunctionTarget(uri, 'withArgument', .integer, [.integer]),
      FunctionTarget(uri, 'wrongResult', .string, []),
      FunctionTarget(uri, 'generic', .integer, [], typeParameters: [parameter]),
    ]) {
      final result = (
        program: IrProgram(
          lowered.program.classes,
          lowered.program.functions,
          globals: lowered.program.globals,
          externals: [...lowered.program.externals, IrExternal(target)],
        ),
        entryPoint: lowered.entryPoint,
        exports: lowered.exports,
        imports: lowered.imports,
        runtime: RuntimeDeclarations(
          lowered.runtime.entries,
          {...lowered.runtime.primitives, target: .abi},
          lowered.runtime.nonAllocating,
          lowered.runtime.systemFunctions,
        ),
      );
      expect(() => bindRuntime(result, Target.host()), throwsArgumentError);
    }
  });

  final generator = Arm64CodeGenerator(const Target(.linux, .arm64));
  test(
    'root protocol transitions satisfy the selected no-allocation contract',
    () {
      const operations = {
        'link',
        'unlink',
        'publish',
        'stop',
        'resume',
        'close',
      };
      final targets = heapRuntime.program.functions
          .map((function) => function.target)
          .where(
            (target) =>
                target.owner?.name == 'NativeRoots' &&
                operations.contains(target.name),
          )
          .toList();
      expect(targets.map((target) => target.name), unorderedEquals(operations));
      expect(heapRuntime.nonAllocating, containsAll(targets));
      final prepared = Compiler(generator.target)
          .prepare(heapRuntime.program, roots: targets, runtime: heapRuntime);
      expect(prepared.definitions, containsAll(targets));
      expect(() => generator.generate(prepared), returnsNormally);
    },
  );

  test('standalone services preserve their required entry context', () {
    final clock = heapRuntime.primitives.entries
        .singleWhere((entry) => entry.value == MemoryPrimitive.clock)
        .key;
    final context = heapRuntime.program.functions.singleWhere(
      (body) =>
          body.target.owner?.name == 'Memory' && body.target.name == 'context',
    );
    expect(
      context.blocks
          .expand((block) => block.instructions)
          .whereType<ReadNativeContext>(),
      hasLength(1),
    );
    for (final target in [clock, context.target]) {
      final block = Block();
      block.finish(Return(block.emit(DirectCall(target, []))));
      final prepared = Compiler(generator.target).prepare(
        IrProgram([], [
          IrFunction(entry, [block]),
        ]),
        roots: [entry],
        runtime: heapRuntime,
      );
      final module = generator.generate(prepared);
      expect(module.symbols, isNotEmpty);
      // Ordinary source roots remain Dart callees; they cannot release their
      // caller's heap before returning a managed value or its context.
      expect(prepared.definitions, isNot(contains(heapRuntime.release)));
      if (target == context.target) {
        final caller = FunctionTarget(uri, 'contextCaller', .integer, []);
        final body = Block();
        body.emit(BindNativeContext(const Constant.integer(0x1234)));
        body.finish(Return(body.emit(DirectCall(entry, []))));
        final graph = prepared.program;
        final invoked = IrProgram(
          graph.classes,
          [
            ...graph.functions,
            IrFunction(caller, [body]),
          ],
          globals: graph.globals,
          externals: graph.externals,
        );
        final facts = ProgramFlow(invoked, [
          (target: caller, arguments: []),
        ]).facts;
        expect(
          (facts.returnedBy(caller).constant as ScalarConstant).value,
          0x1234,
        );
      }
    }
  });
  test('an unmanaged process still calls its final status provider', () {
    final status = FunctionTarget(uri, 'processStatus', .integer, []);
    final block = Block()..finish(Return(const Constant.integer(43)));
    final prepared = Compiler(generator.target).prepare(
      IrProgram([], [mainBody(false)]),
      roots: const [],
      runtime: withCritical(status, processStatus: IrFunction(status, [block])),
      entryPoint: (function: entry, symbol: 'start'),
    );
    final module = generator.generate(prepared);
    expect(module.symbols.any((symbol) => symbol.name == 'start'), isTrue);
    final facts = ProgramFlow(
      prepared.program,
      [(target: prepared.entryPoint!.function, arguments: [])],
      memoryLayout: ProgramLayout(
        prepared.program.classes,
        functions: prepared.program.functions,
        nativeLayout: NativeLayout(generator.target),
      ),
    ).facts;
    // The body returns 42, but process completion must use the provider's 43,
    // whether the actual call remains or its implementation has been inlined.
    expect(
      (facts.returnedBy(prepared.entryPoint!.function).constant
              as ScalarConstant)
          .value,
      43,
    );
  });
  test(
    'programs without scheduling retain only the managed lifecycle hook',
    () {
      final eventLoopRun = heapRuntime.program.functions
          .singleWhere(
            (body) =>
                body.target.owner?.name == 'EventLoop' &&
                body.target.name == 'run',
          )
          .target;
      for (final managed in [false, true]) {
        final resultType = managed
            ? CoreTypes.listOf(.integer)
            : ValueType.integer;
        final lifecycle = FunctionTarget(uri, 'lifecycle', resultType, []);
        final body = Block();
        body.finish(
          Return(
            managed
                ? body.emit(NewCollection(CoreTypes.listOf(.integer)))
                : const Constant.integer(42),
          ),
        );
        // Returning the fresh list keeps its allocation observable. Reading
        // only its empty length is a valid allocation-free compiler short path.
        final program = IrProgram([], [
          IrFunction(lifecycle, [body]),
        ]);
        final prepared = Compiler(generator.target)
            .prepare(program, roots: [lifecycle], runtime: heapRuntime);
        final module = generator.generate(prepared);
        expect(prepared.definitions, isNot(contains(eventLoopRun)));
        for (final target in [heapRuntime.allocate, heapRuntime.release]) {
          expect(module.symbols.any((s) => s.name == target.name), managed);
        }
        expect(
          module.symbols.any((s) => s.name == heapRuntime.runEvents.name),
          managed,
        );
        for (final binding in heapRuntime.primitives.entries) {
          if (binding.value == .clock || binding.value == .sleep) {
            expect(prepared.definitions, isNot(contains(binding.key)));
          }
        }
        if (managed) {
          expect(
            () => generator.generate(
              Compiler(generator.target).prepare(program, roots: [lifecycle]),
            ),
            throwsArgumentError,
          );
        }
      }
    },
  );

  test('an eliminated local collection needs no managed lifecycle', () {
    final prepared = Compiler(generator.target).prepare(
      IrProgram([], [mainBody(true)]),
      roots: [entry],
      runtime: heapRuntime,
    );
    final module = generator.generate(prepared);
    for (final target in [
      heapRuntime.allocate,
      heapRuntime.release,
      heapRuntime.runEvents,
    ]) {
      expect(
        module.symbols.any((symbol) => symbol.name == target.name),
        isFalse,
      );
    }
  });

  test(
    'ordinary pointer helpers cross branches and return in critical closures',
    () {
      final pointer = FfiTypes.int64Pointer;
      final helper = FunctionTarget(uri, 'choosePointer', pointer, [
        pointer,
        pointer,
        .boolean,
      ]);
      final begin = Block(helper.parameterTypes), done = Block([pointer]);
      begin.finish(
        Branch(
          begin.parameters[2],
          Jump(done, [begin.parameters[0]]),
          Jump(done, [begin.parameters[1]]),
        ),
      );
      done.finish(Return(done.parameters.single));
      final critical = FunctionTarget(uri, 'criticalPointer', .integer, [
        pointer,
        .boolean,
      ]);
      final block = Block(critical.parameterTypes);
      final offset = block.emit(
        PointerOffset(block.parameters[0], const Constant.integer(1)),
      );
      final result = block.emit(
        DirectCall(helper, [block.parameters[0], offset, block.parameters[1]]),
      );
      block.finish(
        Return(
          block.emit(
            LoadNative(
              block.emit(PointerAddress(result)),
              NativeScalarType(Int64),
            ),
          ),
        ),
      );
      final program = IrProgram([], [
        IrFunction(helper, [begin, done]),
        IrFunction(critical, [block]),
      ]);
      for (final runtime in [heapRuntime, withCritical(critical)]) {
        final module = generator.generate(
          Compiler(generator.target)
              .prepare(program, roots: [critical, helper], runtime: runtime),
        );
        expect(
          module.symbols.any((s) => s.name == heapRuntime.allocate.name),
          isFalse,
        );
      }
    },
  );

  test('critical calls reject transitive allocation and exceptions', () {
    for (final allocates in [true, false]) {
      final leaf = FunctionTarget(uri, 'leaf', .integer, [.integer]);
      final caller = FunctionTarget(uri, 'critical', .integer, [.integer]);
      final call = Block(caller.parameterTypes);
      call.finish(Return(call.emit(DirectCall(leaf, call.parameters))));
      final body = Block(leaf.parameterTypes);
      if (allocates) {
        final boxed = body.emit(TypeView(body.parameters.single, .object));
        body.finish(Return(body.emit(ObjectHashCode(boxed, direct: true))));
      } else {
        body.finish(Throw(Constant.string('failure')));
      }
      expect(
        () => generator.generate(
          Compiler(generator.target).prepare(
            IrProgram([], [
              mainBody(true),
              IrFunction(caller, [call]),
              IrFunction(leaf, [body]),
            ]),
            roots: [entry, caller, leaf],
            runtime: withCritical(caller),
          ),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'contract',
            contains('must not allocate'),
          ),
        ),
      );
    }
  });

  test(
    'foreign effects require an explicit contract independently of leaf calls',
    () {
      for (final managed in [false, true]) {
        for (final leaf in [false, true]) {
          for (final permitted in [false, true]) {
            final foreign = FunctionTarget(uri, 'foreign', .integer, []);
            final critical = FunctionTarget(uri, 'critical', .integer, []);
            final block = Block();
            block.finish(Return(block.emit(DirectCall(foreign, []))));
            Object generate() => generator.generate(
              Compiler(generator.target).prepare(
                IrProgram(
                  [],
                  [
                    mainBody(managed),
                    IrFunction(critical, [block]),
                  ],
                  externals: [IrExternal(foreign)],
                ),
                roots: [entry, critical, foreign],
                imports: {
                  foreign: NativeImport(
                    'foreign',
                    NativeSignature(Int64, []),
                    isLeaf: leaf,
                    isNonAllocating: permitted,
                  ),
                },
                runtime: withCritical(critical),
              ),
            );
            if (permitted) {
              expect(generate, returnsNormally);
            } else {
              expect(
                generate,
                throwsA(
                  isA<UnsupportedError>().having(
                    (e) => e.message,
                    'contract',
                    contains('foreign'),
                  ),
                ),
              );
            }
          }
        }
      }
    },
  );

  test('native address calls retain their declaration effect contract', () {
    for (final leaf in [false, true]) {
      for (final permitted in [false, true]) {
        final reference = NativeReference(
          'test',
          'native_effects',
          NativeFunctionType(NativeSignature(Int64, [])),
          isLeaf: leaf,
        );
        final critical = FunctionTarget(uri, 'nativeAddressCall', .integer, []);
        final block = Block();
        final address = block.emit(NativeSymbolAddress(reference));
        block.finish(
          Return(
            block.emit(
              NativeCall.symbol(address, FunctionType(.integer, []), []),
            ),
          ),
        );
        Object generate() => generator.generate(
          Compiler(generator.target).prepare(
            IrProgram([], [
              IrFunction(critical, [block]),
            ]),
            roots: [critical],
            nativeSymbols: {reference: 'native_effects'},
            runtime: withCritical(
              critical,
              nativeContracts: permitted ? [reference] : [],
            ),
          ),
        );
        if (permitted) {
          expect(generate, returnsNormally);
        } else {
          expect(
            generate,
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'contract',
                contains('unknown effects'),
              ),
            ),
          );
        }
      }
    }
  });

  test(
    'critical arithmetic keeps proven bounds and rejects possible errors',
    () {
      for (final bounded in [true, false]) {
        final critical = FunctionTarget(uri, 'shift', .integer, [.integer]);
        final block = Block(critical.parameterTypes);
        final count = bounded
            ? block.emit(
                IntBinary(
                  .bitAnd,
                  block.parameters.single,
                  const Constant.integer(63),
                ),
              )
            : block.parameters.single;
        block.finish(
          Return(
            block.emit(IntBinary(.shiftLeft, const Constant.integer(1), count)),
          ),
        );
        Object generate() => generator.generate(
          Compiler(generator.target).prepare(
            IrProgram([], [
              IrFunction(critical, [block]),
            ]),
            roots: [critical],
            runtime: withCritical(critical),
          ),
        );
        if (bounded) {
          expect(generate, returnsNormally);
        } else {
          expect(
            generate,
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'contract',
                contains('must not allocate'),
              ),
            ),
          );
        }
      }
    },
  );
  test('critical closures follow the allocating stack capture bridge', () {
    final capture = heapRuntime.captureTrace;
    final critical = FunctionTarget(uri, 'critical', .stackTrace, []);
    final block = Block();
    block.finish(Return(block.emit(DirectCall(capture, []))));
    for (final marked in [critical, capture]) {
      expect(
        () => generator.generate(
          Compiler(generator.target).prepare(
            IrProgram(
              [],
              [
                IrFunction(critical, [block]),
              ],
              externals: [IrExternal(capture)],
            ),
            roots: [critical, capture],
            runtime: withCritical(marked),
          ),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'contract',
            contains('must not allocate'),
          ),
        ),
      );
    }
  });
}
