import 'dart:ffi';

import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
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
    isOutOfMemory: heapRuntime.isOutOfMemory,
    release: heapRuntime.release,
    runEvents: heapRuntime.runEvents,
    processExitCode: processStatus?.target,
    copyBytes: heapRuntime.copyBytes,
    captureStackTrace: heapRuntime.captureStackTrace,
    recordError: heapRuntime.recordError,
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
        release: heapRuntime.release,
        runEvents: heapRuntime.runEvents,
        copyBytes: heapRuntime.copyBytes,
        captureStackTrace: heapRuntime.captureStackTrace,
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
        release: heapRuntime.release,
        runEvents: heapRuntime.runEvents,
        copyBytes: heapRuntime.copyBytes,
        captureStackTrace: heapRuntime.captureStackTrace,
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
        release: heapRuntime.release,
        runEvents: heapRuntime.runEvents,
        copyBytes: heapRuntime.copyBytes,
        captureStackTrace: heapRuntime.captureStackTrace,
        recordError: heapRuntime.recordError,
        primitives: {
          for (final entry in heapRuntime.primitives.entries)
            if (entry.value != .captureStackTrace) entry.key: entry.value,
        },
        nonAllocating: [],
      ),
      throwsArgumentError,
    );
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
  test('an unmanaged process still calls its final status provider', () {
    final status = FunctionTarget(uri, 'processStatus', .integer, []);
    final block = Block()..finish(Return(const Constant.integer(43)));
    final module = generator.generate(
      Compiler(generator.target).prepare(
        IrProgram([], [mainBody(false)]),
        roots: const [],
        runtime: withCritical(
          status,
          processStatus: IrFunction(status, [block]),
        ),
        entryPoint: (function: entry, symbol: 'start'),
      ),
    );
    final index = module.symbols.indexWhere(
      (symbol) => symbol.name == status.name,
    );
    final start = module.symbols.singleWhere(
      (symbol) => symbol.name == 'start',
    );
    expect(
      module.relocations.where(
        (relocation) =>
            relocation.symbol == index &&
            relocation.offset >= start.offset &&
            relocation.offset < start.offset + start.size!,
      ),
      hasLength(1),
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
        final program = IrProgram([], [mainBody(managed)]);
        final prepared = Compiler(generator.target)
            .prepare(program, roots: [entry], runtime: heapRuntime);
        final module = generator.generate(prepared);
        expect(prepared.definitions, isNot(contains(eventLoopRun)));
        for (final target in [heapRuntime.allocate, heapRuntime.release]) {
          expect(module.symbols.any((s) => s.name == target.name), managed);
        }
        expect(
          module.symbols.any((s) => s.name == heapRuntime.runEvents.name),
          managed,
        );
        expect(module.imports, isNot(contains('.dartc.clock')));
        expect(module.imports, isNot(contains('.dartc.sleep')));
        if (managed) {
          expect(
            () => generator.generate(
              Compiler(generator.target).prepare(program, roots: [entry]),
            ),
            throwsArgumentError,
          );
        }
      }
    },
  );

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
    final capture = heapRuntime.primitives.entries
        .singleWhere(
          (entry) => entry.value == MemoryPrimitive.captureStackTrace,
        )
        .key;
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
