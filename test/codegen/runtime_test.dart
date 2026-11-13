import 'dart:ffi';

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

  HeapRuntime withCritical(FunctionTarget function) => HeapRuntime(
    heapRuntime.program,
    types: heapRuntime.types,
    allocate: heapRuntime.allocate,
    isOutOfMemory: heapRuntime.isOutOfMemory,
    release: heapRuntime.release,
    runEvents: heapRuntime.runEvents,
    eventAccess: heapRuntime.eventAccess,
    copyBytes: heapRuntime.copyBytes,
    captureStackTrace: heapRuntime.captureStackTrace,
    recordError: heapRuntime.recordError,
    primitives: heapRuntime.primitives,
    nonAllocating: [...heapRuntime.nonAllocating, function],
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
        eventAccess: heapRuntime.eventAccess,
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
        eventAccess: heapRuntime.eventAccess,
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
        eventAccess: heapRuntime.eventAccess,
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
        IrProgram([changed], [mainBody(true)]),
        definitions: [entry],
        runtime: heapRuntime,
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
        expect(() => bindRuntime(result), throwsArgumentError);
      } else {
        final body =
            bindRuntime(result).program.implementationOf(target) as IrFunction;
        expect(body.blocks.single.instructions.single, isA<UncheckedCast>());
      }
    }
  });

  final generator = Arm64CodeGenerator(const Target(.linux, .arm64));
  test('unmanaged programs do not retain runtime allocation or scheduling', () {
    for (final managed in [false, true]) {
      final program = IrProgram([], [mainBody(managed)]);
      final module = generator.generate(
        program,
        definitions: [entry],
        runtime: heapRuntime,
      );
      for (final target in [heapRuntime.allocate, heapRuntime.release]) {
        expect(module.symbols.any((s) => s.name == target.name), managed);
      }
      expect(
        module.symbols.any((s) => s.name == heapRuntime.runEvents.name),
        isFalse,
      );
      expect(module.imports, isNot(contains('.dartc.clock')));
      if (managed) {
        expect(
          () => generator.generate(program, definitions: [entry]),
          throwsArgumentError,
        );
      }
    }
  });

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
          IrProgram([], [
            mainBody(true),
            IrFunction(caller, [call]),
            IrFunction(leaf, [body]),
          ]),
          definitions: [entry, caller, leaf],
          runtime: withCritical(caller),
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
    'critical calls reject foreign code even without managed allocation',
    () {
      for (final managed in [false, true]) {
        final foreign = FunctionTarget(uri, 'foreign', .integer, []);
        final critical = FunctionTarget(uri, 'critical', .integer, []);
        final block = Block();
        block.finish(Return(block.emit(DirectCall(foreign, []))));
        expect(
          () => generator.generate(
            IrProgram(
              [],
              [
                mainBody(managed),
                IrFunction(critical, [block]),
              ],
              externals: [IrExternal(foreign)],
            ),
            definitions: [entry, critical, foreign],
            imports: {
              foreign: NativeImport(
                'foreign',
                NativeSignature(Int64, []),
                isLeaf: true,
              ),
            },
            runtime: withCritical(critical),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'contract',
              contains('foreign'),
            ),
          ),
        );
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
          IrProgram(
            [],
            [
              IrFunction(critical, [block]),
            ],
            externals: [IrExternal(capture)],
          ),
          definitions: [critical, capture],
          runtime: withCritical(marked),
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
