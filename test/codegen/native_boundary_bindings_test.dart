import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

Iterable<Instruction> _operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  setUpAll(prepareRuntime);
  for (final kind in ['export', 'process', 'callback']) {
    test('current $kind bindings execute arguments, results and lifecycle', () {
      final input = _Input(kind);
      final first = input.bind(input.program);
      final second = input.bind(first.program);
      final direct = NativeBoundaries.withLifecycle(
        second,
        heapRuntime,
        processEntry: second.processEntry,
      );
      expect(direct.runtimeContext, same(second.runtimeContext));
      expect(direct.exports, second.exports);
      expect(direct.imports, second.imports);
      expect(direct.callbacks, second.callbacks);
      expect(direct.processEntry, same(second.processEntry));
      expect(second.runtimeContext, same(first.runtimeContext));
      expect(
        second.program.nativeBoundaries!.imports,
        first.program.nativeBoundaries!.imports,
      );
      expect(
        second.program.nativeBoundaries!.exports,
        first.program.nativeBoundaries!.exports,
      );
      expect(
        second.program.nativeBoundaries!.callbacks,
        first.program.nativeBoundaries!.callbacks,
      );
      expect(second.processEntry, same(first.processEntry));
      final entry = kind == 'callback'
          ? second.callbacks.values.single.target
          : kind == 'process'
          ? second.processEntry!
          : second.exports.keys.single;
      _withHostStorage(second.program, (program, address) {
        final context = address(second.runtimeContext!);
        final events = <String>[];
        final arguments = <int>[];
        var nativeCalls = 0;
        final active = Pointer<Int64>.fromAddress(
          context + RuntimeContext.active,
        );
        final interpreter = IrInterpreter(
          program,
          {},
          externalCalls: {
            heapRuntime.linkEntry: (args) {
              expect(args.first, context);
              final record = Pointer<Int64>.fromAddress(args[1] as int);
              record.value = active.value;
              active.value = record.address;
              events.add('link');
              return null;
            },
            heapRuntime.unlinkEntry: (args) {
              expect(args.first, context);
              expect(active.value, args[1]);
              active.value = Pointer<Int64>.fromAddress(args[1] as int).value;
              events.add('unlink');
              return null;
            },
            heapRuntime.runEvents: (args) {
              expect(args.first, context);
              expect(active.value, isNonZero);
              events.add('drain');
              return null;
            },
            heapRuntime.release: (args) {
              expect(args.single, context);
              events.add('release');
              return null;
            },
            if (heapRuntime.processExitCode case final status?)
              status: (_) => 77,
            second.imports.keys.single: (args) {
              expect(active.value, isNonZero);
              arguments.add(args.single as int);
              events.add('native');
              nativeCalls++;
              if (args.single == -1) throw StateError('callback failure');
              return (args.single as int) * 2 + nativeCalls;
            },
            second.publicationFailure!: (_) =>
                throw StateError('invalid entry'),
          },
        );
        final body = program.implementationOf(entry) as IrFunction;
        expect(
          interpreter.run(body, kind == 'process' ? [20, 1] : [21]),
          kind == 'process' ? 0 : 43,
        );
        expect(
          interpreter.run(body, kind == 'process' ? [21, 1] : [22]),
          kind == 'process' ? 0 : 46,
        );
        expect(arguments, [21, 22]);
        expect(active.value, 0);
        expect(events, [
          for (var i = 0; i < 2; i++) ...[
            'link',
            'native',
            'drain',
            if (kind == 'process') 'release',
            'unlink',
          ],
        ]);
        if (kind == 'callback') {
          expect(interpreter.run(body, [-1]), -7);
          expect(events.sublist(events.length - 4), [
            'link',
            'native',
            'drain',
            'unlink',
          ]);
          expect(active.value, 0);
        }
      });
    });
  }

  test('incremental export and import retain the current owner and bodies', () {
    final input = _Input('export');
    final first = input.bind(input.program);
    final added = FunctionTarget(null, 'additional', .integer, [.integer]);
    final foreign = FunctionTarget(null, 'additionalForeign', .integer, [
      .integer,
    ]);
    final block = Block(added.parameterTypes);
    block.finish(Return(block.emit(DirectCall(foreign, block.parameters))));
    final oldEntry = first.exports.keys.single;
    final current = IrProgram(
      [],
      [
        ...first.program.functions.where((body) => body.target != oldEntry),
        // Current graph bodies are authoritative, even after semantic rewrites.
        IrFunction(oldEntry, [
          Block(oldEntry.parameterTypes)
            ..finish(const Return(Constant.integer(91))),
        ]),
        IrFunction(added, [block]),
      ],
      externals: [...first.program.externals, IrExternal(foreign)],
      nativeBoundaries: first.program.nativeBoundaries,
    );
    final next = NativeBoundaries.withLifecycle(
      NativeBoundaries(
        current,
        roots: [input.root, added],
        imports: {input.foreign: input.signature, foreign: input.signature},
        exports: {
          input.root: NativeExport('oldSymbolRenamed', input.signature),
          added: NativeExport('additional', input.signature),
        },
      ),
      heapRuntime,
    );
    expect(next.runtimeContext, same(first.runtimeContext));
    expect(next.exports[oldEntry]!.symbol, 'oldSymbolRenamed');
    expect(
      next.program.implementationOf(oldEntry),
      same(current.implementationOf(oldEntry)),
    );
    expect(next.cleanup, same(first.cleanup));
    expect(next.imports, hasLength(2));
    expect(next.program.nativeBoundaries!.exports, hasLength(2));
    final second = next.program.nativeBoundaries!.exports[added]!.entry;
    expect(second, isNot(same(oldEntry)));
    for (final target in [second, foreign]) {
      final body = next.program.implementationOf(target) as IrFunction;
      expect(
        _operations(body)
            .whereType<NativeDataAddress>()
            .any((op) => identical(op.declaration, first.runtimeContext)),
        isTrue,
      );
    }
  });

  test('current bindings reject lost ownership and incompatible promises', () {
    final input = _Input('export');
    final first = input.bind(input.program);
    final lost = IrProgram(
      first.program.classes,
      first.program.functions,
      externals: first.program.externals,
    );
    expect(() => input.bind(lost), throwsArgumentError);
    expect(
      () => NativeBoundaries(
        first.program,
        roots: [input.root],
        imports: {first.imports.keys.single: input.signature},
      ),
      throwsArgumentError,
    );
    expect(
      () => NativeBoundaries(
        first.program,
        roots: [input.root],
        imports: {input.foreign: input.signature},
        leafImports: [input.foreign],
      ),
      throwsArgumentError,
    );
    expect(
      () => IrProgram(
        first.program.classes,
        first.program.functions.where(
          (body) => body.target != first.exports.keys.single,
        ),
        externals: first.program.externals,
        nativeBoundaries: first.program.nativeBoundaries,
      ),
      throwsArgumentError,
    );
  });

  test(
    'ordinary native data and ABI binding do not imply lifecycle ownership',
    () {
      final root = FunctionTarget(null, 'plain', .integer, []);
      final block = Block();
      block.emit(
        BindNativeContext(
          block.emit(
            NativeDataAddress(
              NativeData(List.filled(RuntimeContext.size, 0), alignment: 8),
            ),
          ),
        ),
      );
      block.finish(const Return(Constant.integer(42)));
      final program = IrProgram([], [
        IrFunction(root, [block]),
      ]);
      final boundaries = NativeBoundaries(program, roots: [root]);
      expect(boundaries.program, same(program));
      expect(boundaries.runtimeContext, isNull);
      expect(boundaries.hasLifecycle, isFalse);
    },
  );
}

final class _Input(final String kind) {
  final signature = NativeSignature(Int64, [Int64]);
  final root = FunctionTarget(
    null,
    'body',
    .integer,
    List.filled(kind == 'process' ? 2 : 1, ValueType.integer),
  );
  final foreign = FunctionTarget(null, 'foreign', .integer, [.integer]);
  late final NativeCallbackTarget callback;
  late final IrProgram program;

  this {
    final body = Block(root.parameterTypes);
    final argument = kind == 'process'
        ? body.emit(IntBinary(.add, body.parameters[0], body.parameters[1]))
        : body.parameters.single;
    body.finish(Return(body.emit(DirectCall(foreign, [argument]))));
    callback = StaticCallbackTarget(
      root,
      FunctionType(
        FfiTypes.int64,
        List.filled(root.parameterTypes.length, FfiTypes.int64),
      ),
      exceptionalReturn: const Constant.integer(-7),
    );
    final address = Block();
    address.finish(Return(address.emit(NativeCallbackAddress(callback))));
    program = IrProgram(
      [],
      [
        IrFunction(root, [body]),
        if (kind == 'callback') IrFunction(addressRoot, [address]),
      ],
      externals: [IrExternal(foreign)],
    );
  }

  final addressRoot = FunctionTarget(null, 'callbackAddressRoot', .integer, []);

  NativeBoundaries bind(IrProgram program) => NativeBoundaries.withLifecycle(
    NativeBoundaries(
      program,
      roots: [kind == 'callback' ? addressRoot : root],
      imports: {foreign: signature},
      exports: {if (kind == 'export') root: NativeExport('body', signature)},
    ),
    heapRuntime,
    processEntry: kind == 'process' ? root : null,
  );
}

// Supplies actual host addresses for address/frame primitives only. Entry,
// publication, return, exception and memory operations execute as ordinary IR;
// lifecycle callees below are explicit models, not a native GC test.
void _withHostStorage(
  IrProgram source,
  void Function(IrProgram, int Function(Object)) run,
) {
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
      final replacements = <Value, Value>{}, discarded = <Instruction>{};
      for (final op in _operations(function)) {
        switch (op) {
          case NativeDataAddress(:final declaration):
            replacements[op] = Constant.integer(
              address(declaration, declaration.bytes.length, declaration.bytes),
            );
          case NativeLocalStorage():
            replacements[op] = Constant.integer(
              address(
                op.declaration,
                NativeLayout(Target.host()).of(op.storage).size,
              ),
            );
          case FrameValue(:final kind):
            replacements[op] = Constant.integer(
              kind == .returnAddress ? 0x1234 : 0x3210,
            );
          case BindNativeContext():
            discarded.add(op);
          case StackMapAddress() || ModuleRootsAddress():
            replacements[op] = const Constant.integer(0);
          default:
            continue;
        }
        discarded.add(op);
      }
      bodies.add(
        FunctionRewrite(
          function,
          replacements: replacements,
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
      (key) => storage[key]!.address,
    );
  } finally {
    for (final pointer in storage.values) {
      free(pointer);
    }
  }
}
