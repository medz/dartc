import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/entry_lifecycle.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  test('process entry drains, reads status, releases, then unlinks', () {
    final probe = _Probe(process: true);
    final facts = probe.analyze();
    expect(_number(facts.returnedBy(probe.root)), 42123645);
  });

  test('module entry retains the heap and unload does not drain events', () {
    final probe = _Probe(close: true);
    final facts = probe.analyze();
    expect(_number(facts.returnedBy(probe.root)), 131235145);
  });

  for (final failure in ['body', 'events', 'release']) {
    test(
      'escaping $failure failure cannot skip cleanup or return normally',
      () {
        final probe = _Probe(process: true, failure: failure);
        final facts = probe.analyze();
        expect(facts.returnedBy(probe.root).isBottom, isTrue);
        final expected = switch (failure) {
          'body' => 12745,
          'events' => 123745,
          _ => 123645,
        };
        expect(_number(facts.valueOf(probe.observedFailure)), expected);
        expect(facts.definitions, contains(probe.exit));
      },
    );
  }

  test(
    'callback body failure becomes its scalar result before event delivery',
    () {
      final probe = _Probe(callback: true, failure: 'body');
      final facts = probe.analyze();
      expect(_number(facts.returnedBy(probe.root)), 171235);
      expect(facts.definitions, isNot(contains(probe.exit)));
    },
  );
}

/// Models lifecycle callees to observe wrapper ordering; source implementations
/// have separate runtime tests and this does not claim native execution.
final class _Probe({
  bool process = false,
  bool close = false,
  bool callback = false,
  String? failure,
}) {
  static final word = NativeScalarType(Int64);
  final ledger = NativeData(List.filled(8, 0), alignment: 8);
  final root = FunctionTarget(null, 'probe', .integer, []);
  late final Instruction observedFailure;
  late final FunctionTarget exit;
  late final IrProgram program;

  this {
    final runtime = heapRuntime;
    final status = FunctionTarget(null, 'status', .integer, []);
    final statusBody = Block();
    _record(statusBody, 6);
    statusBody.finish(Return(const Constant.integer(42)));
    final contract = HeapRuntime(
      IrProgram(
        runtime.program.classes,
        [
          ...runtime.program.functions,
          IrFunction(status, [statusBody]),
        ],
        globals: runtime.program.globals,
        externals: runtime.program.externals,
      ),
      allocate: runtime.allocate,
      isOutOfMemory: runtime.isOutOfMemory,
      linkEntry: runtime.linkEntry,
      unlinkEntry: runtime.unlinkEntry,
      release: runtime.release,
      runEvents: runtime.runEvents,
      processExitCode: status,
      copyBytes: runtime.copyBytes,
      captureStackTrace: runtime.captureStackTrace,
      captureTrace: runtime.captureTrace,
      recordError: runtime.recordError,
      primitives: runtime.primitives,
      nonAllocating: [],
    );
    final lifecycle = EntryLifecycle(
      contract,
      globalRoots: (_) => const Constant.integer(0),
      context: process ? null : NativeData(List.filled(64, 0), alignment: 8),
    );
    final body = FunctionTarget(null, 'body', .integer, []);
    final bodyEntry = Block();
    _record(bodyEntry, 2);
    bodyEntry.finish(
      failure == 'body'
          ? Throw(const Constant.string('failure'))
          : Return(const Constant.integer(13)),
    );
    final wrapped = lifecycle.wrap(
      body,
      process: process,
      callback: callback
          ? StaticCallbackTarget(
              body,
              FunctionType(FfiTypes.scalarTypes[Int64]!, []),
              exceptionalReturn: const Constant.integer(17),
            )
          : null,
    );
    final entry = Block();
    final result = entry.emit(DirectCall(wrapped, []));
    if (close) entry.emit(DirectCall(lifecycle.close(), []));
    final total = entry.emit(
      LoadNative(entry.emit(NativeDataAddress(ledger)), word),
    );
    entry.finish(
      Return(
        entry.emit(
          IntBinary(
            .add,
            entry.emit(
              IntBinary(
                .multiply,
                result,
                Constant.integer(
                  close
                      ? 10000000
                      : process
                      ? 1000000
                      : 10000,
                ),
              ),
            ),
            total,
          ),
        ),
      ),
    );
    final functions = <IrFunction>[
      IrFunction(root, [entry]),
      IrFunction(body, [bodyEntry]),
      IrFunction(status, [statusBody]),
      ...lifecycle.functions,
    ];
    for (final (target, digit) in [
      (runtime.linkEntry, 1),
      (runtime.runEvents, 3),
      (runtime.release, 4),
      (runtime.unlinkEntry, 5),
      (runtime.isOutOfMemory, 7),
    ]) {
      final block = Block(target.parameterTypes);
      _record(block, digit);
      if (target == runtime.linkEntry) {
        // No enclosing entry exists in these tests.
        block.emit(
          StoreNative(block.parameters[1], word, const Constant.integer(0)),
        );
      }
      if (failure == 'events' && target == runtime.runEvents ||
          failure == 'release' && target == runtime.release) {
        block.finish(Throw(const Constant.string('failure')));
      } else {
        block.finish(
          Return(
            target == runtime.isOutOfMemory
                ? const Constant.boolean(true)
                : null,
          ),
        );
      }
      functions.add(IrFunction(target, [block]));
    }
    final write = runtime.primitives.entries
        .singleWhere((entry) => entry.value == .writeBytes)
        .key;
    final reporting = Block(write.parameterTypes);
    observedFailure = reporting.emit(
      LoadNative(reporting.emit(NativeDataAddress(ledger)), word),
    );
    reporting.finish(Return(observedFailure));
    functions.add(IrFunction(write, [reporting]));
    exit = runtime.primitives.entries
        .singleWhere((entry) => entry.value == .exitProcess)
        .key;
    program = IrProgram(
      [],
      functions,
      externals: [IrExternal(exit, effects: {}, capturesArguments: false)],
    );
  }

  void _record(Block block, int digit) {
    final address = block.emit(NativeDataAddress(ledger));
    final previous = block.emit(LoadNative(address, word));
    block.emit(
      StoreNative(
        address,
        word,
        block.emit(
          IntBinary(
            .add,
            block.emit(
              IntBinary(.multiply, previous, const Constant.integer(10)),
            ),
            Constant.integer(digit),
          ),
        ),
      ),
    );
  }

  ProgramFlowFacts analyze() => ProgramFlow(
    program,
    [(target: root, arguments: [])],
    memoryLayout: ProgramLayout(
      [],
      functions: program.functions,
      nativeLayout: NativeLayout(Target.host()),
    ),
  ).facts;
}

Object? _number(FlowValue value) => switch (value.constant) {
  ScalarConstant(:final value) => value,
  _ => null,
};
