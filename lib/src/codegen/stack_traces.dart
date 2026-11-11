import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'frame_lookup.dart';
import 'function_emitter.dart';
import 'heap_functions.dart';

/// Captures managed call frames as an ordinary, GC-traced object chain.
final class StackTraces(final FrameLookup frames) {
  static final _uri = Uri.parse('dartc:stack');
  final type = ClassType(_uri, 'Trace', interfaces: [ValueType.stackTrace]);
  late final pc = InstanceField(type, 'pc', .integer, isFinal: true);
  late final caller = InstanceField(
    type,
    'caller',
    type.nullable,
    isFinal: true,
  );
  late final initializer = FunctionTarget(
    _uri,
    'Trace',
    .voidType,
    [.integer, type.nullable],
    owner: type,
    kind: .initializer,
  );
  late final capture = FunctionTarget(_uri, 'capture', type, []);
  late final _walk = FunctionTarget(_uri, 'captureFrames', type, [
    .integer,
    .integer,
    .integer,
  ]);
  late final declaration = IrClass(
    type,
    [pc, caller],
    constructors: [initializer],
  );

  List<IrFunction> functions(FunctionTarget invalid) {
    final init = Block(initializer.parameterTypes);
    init.emit(StoreField(pc, init.parameters[0], init.parameters[1]));
    init.emit(StoreField(caller, init.parameters[0], init.parameters[2]));
    init.finish(const Return());

    Value add(Block block, Value a, Value b) =>
        block.emit(IntBinary(.add, a, b));
    Value load(Block block, Value base, [int offset = 0]) => block.emit(
      LoadNative(
        offset == 0 ? base : add(block, base, Constant.integer(offset)),
        .new(Int64),
      ),
    );
    final entry = Block(_walk.parameterTypes);
    final loop = Block([.integer, .integer, type.nullable]);
    final found = Block(), append = Block(), done = Block(), failed = Block();
    final result = Block([type]);
    final [table, initialSp, initialPc] = entry.parameters;
    entry.finish(
      Jump(loop, [initialSp, initialPc, const Constant.nullValue()]),
    );
    final [sp, returnPc, head] = loop.parameters;
    final record = loop.emit(DirectCall(frames.target, [table, returnPc]));
    loop.finish(
      Branch(
        loop.emit(Equals(record, const Constant.integer(0))),
        Jump(failed),
        Jump(found),
      ),
    );
    final delta = load(found, record, 8);
    found.finish(
      Branch(
        found.emit(Equals(delta, const Constant.integer(0))),
        Jump(done),
        Jump(append),
      ),
    );
    final node = append.emit(Construct(initializer, [returnPc, head]));
    append.finish(
      Jump(loop, [
        add(append, sp, delta),
        load(append, add(append, sp, load(append, record, 16))),
        node,
      ]),
    );
    final present = done.emit(TypeTest(head, type));
    done.finish(
      Branch(present, Jump(result, [present.refinement(true)!]), Jump(failed)),
    );
    result.finish(Return(result.parameters.single));
    failed.finish(Unreachable(failed.emit(DirectCall(invalid, []))));
    return [
      IrFunction(initializer, [init]),
      IrFunction(_walk, [entry, loop, found, append, done, failed, result]),
    ];
  }

  /// Records the first throw on Error subclasses, without invoking a user getter.
  void recordError<R extends Object>(FunctionEmitter<R> emitter) {
    final offset = emitter.failureRegister;
    final scratch = emitter.allocatableRegisters.lastWhere(
      (r) =>
          emitter.bank(r) == .general &&
          r != offset &&
          r != emitter.exceptionRegister &&
          r != emitter.traceRegister,
    );
    final done = emitter.label(), store = emitter.label();
    emitter.loadMemory(
      offset,
      emitter.exceptionRegister,
      offset: 0,
      bytes: 8,
      signed: false,
    );
    emitter.loadMemory(scratch, offset, offset: 8, bytes: 8, signed: false);
    emitter.addScaled(offset, offset, scratch, scale: 8);
    emitter.loadMemory(offset, offset, offset: 16, bytes: 8, signed: false);
    emitter.jumpIfZero(offset, done);
    emitter.addScaled(offset, emitter.exceptionRegister, offset, scale: 1);
    emitter.loadMemory(scratch, offset, offset: 0, bytes: 8, signed: false);
    emitter.jumpIfZero(scratch, store);
    emitter.jump(done);
    emitter.bind(store);
    emitter.storeMemory(emitter.traceRegister, offset, offset: 0, bytes: 8);
    emitter.bind(done);
  }

  Uint8List emit<R extends Object>(
    FunctionEmitter<R> emitter,
    void Function(Fixup, FunctionTarget) call,
    void Function(int, StackRoots) safepoint,
  ) {
    final layout = emitter.convention.classify(
      NativeSignature(Int64, [Int64, Int64, Int64]),
    );
    final arguments = layout.parameters
        .map((p) => (p as RegisterArgument<R>).register)
        .toList();
    final frame = emitter.convention.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: layout.stackBytes,
    );
    emitter.prologue(frame);
    emitter.loadMemory(
      arguments[0],
      emitter.heapRegister,
      offset: HeapFunctions.maps,
      bytes: 8,
      signed: false,
    );
    emitter.stackAddress(arguments[1], frame.incomingStackOffset);
    emitter.loadStack(arguments[2], frame.returnAddressOffset);
    call(emitter.call(), _walk);
    safepoint(
      emitter.position,
      StackRoots(frame.incomingStackOffset, frame.returnAddressOffset, []),
    );
    emitter.epilogue(frame);
    return emitter.finish();
  }
}
