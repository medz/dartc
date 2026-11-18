import 'dart:typed_data';
import 'dart:ffi' as ffi;

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/src/assembler/code_buffer.dart' show CodeBuffer;
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/codegen/binary_encoding.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/indirect_invocation.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/src/codegen/scalar_function.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:allocation');
  SelectedFunction select(FunctionTarget target, List<Block> blocks) {
    final body = SelectedFunction(
      target,
      ProgramLayout(
        [],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      ),
      blocks.first,
    );
    for (final block in blocks) {
      body.blocks.add(block);
      body.instructions[block] = [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ];
      body.ends[block] = block.end;
    }
    return body;
  }

  FunctionAllocation<CpuRegister> allocate(SelectedFunction body) =>
      FunctionAllocation(FunctionSelection(body, _Constraints()));

  test('an indirect result retains its proven floating ABI register', () {
    final root = FunctionTarget(uri, 'consume', .voidType, [.integer]);
    final declaration = FunctionTarget(uri, 'produce', .object, []);
    final block = Block(root.parameterTypes);
    final indirect = IndirectInvocation(
      DirectCall(declaration, []),
      block.parameters.single,
      [],
      declaration.signature,
      ExecutionSignature([], ExecutionShape.floating),
    );
    block.emit(KeepAlive(indirect));
    block.finish(const Return());
    final selected = select(root, [block]);
    selected.instructions[block]!.insert(0, indirect);
    final allocation = allocate(selected);
    expect(allocation.operations[indirect]!.result, FloatRegister.d0);
    expect(allocation.operations[indirect]!.resultMoves, isEmpty);
  });

  test(
    'binding owns one saved context slot on normal and exceptional exits',
    () {
      for (final mode in ['return', 'throw', 'forward']) {
        final target = FunctionTarget(uri, 'bind_$mode', .integer, [
          .integer,
          if (mode == 'throw') ...[ValueType.object, ValueType.stackTrace],
        ]);
        final entry = Block(target.parameterTypes);
        entry.emit(BindNativeContext(entry.parameters.first));
        entry.emit(BindNativeContext(entry.parameters.first));
        final callee = FunctionTarget(uri, 'fails', .voidType, []);
        final call = mode == 'forward'
            ? entry.emit(DirectCall(callee, []))
            : null;
        if (mode == 'throw') {
          entry.finish(
            Throw(entry.parameters[1], stackTrace: entry.parameters[2]),
          );
        } else {
          entry.finish(Return(entry.emit(ReadNativeContext())));
        }
        IrFunction(target, [entry]);
        final body = select(target, [entry]);
        if (call != null) body.invocations[call] = callee;
        final result = allocate(body);
        final frame = result.frame!;
        expect(
          frame.savedRegisters.keys.where(
            (register) => register == Register.x28,
          ),
          hasLength(1),
        );
        final sink = _ContextSink();
        ScalarFunction(result, sink).generate(
          (_, _) {},
          (_, _) => fail('Unexpected constant data'),
          (_, _, _, _) {},
          failures: true,
        );
        expect(sink.entered, same(frame));
        expect(sink.exits, hasLength(mode == 'forward' ? 2 : 1));
        expect(sink.exits, everyElement(same(frame)));
        expect(
          sink.moves.where((move) => move.$1 == Register.x28),
          hasLength(2),
        );
      }
    },
  );

  test(
    'reading an inherited context does not create a frame or saved binding',
    () {
      final target = FunctionTarget(uri, 'readContext', .integer, []);
      final entry = Block();
      entry.finish(Return(entry.emit(ReadNativeContext())));
      final result = allocate(select(target, [entry]));
      expect(result.frame, isNull);
      final sink = _ContextSink();
      ScalarFunction(result, sink).generate(
        (_, _) => fail('Unexpected call'),
        (_, _) => fail('Unexpected data'),
        (_, _, _, _) => fail('Unexpected safepoint'),
      );
      expect(sink.moves.single, (Register.x0, Register.x28));
      expect(sink.exits, isEmpty);
    },
  );

  test(
    'native blocks use target layout and cannot overlap address spill homes',
    () {
      final target = FunctionTarget(uri, 'localStorage', .integer, []);
      final callee = FunctionTarget(uri, 'observe', .voidType, [.integer]);
      final entry = Block();
      final bytes = entry.emit(
        NativeLocalStorage(
          NativeArrayType(.of(ffi.Uint8), 77),
          zeroInitialize: true,
        ),
      );
      final word = entry.emit(NativeLocalStorage(.of(ffi.Int64)));
      final call = entry.emit(DirectCall(callee, [bytes]));
      entry.finish(Return(entry.emit(IntBinary(.subtract, word, bytes))));
      final body = select(target, [entry])..invocations[call] = callee;
      final result = allocate(body);
      final byteOffset = result.nativeStorage[bytes]!.offset;
      final wordOffset = result.nativeStorage[word]!.offset;
      expect(wordOffset % 8, 0);
      expect(wordOffset, greaterThanOrEqualTo(byteOffset + 77));
      for (final home in result.homes.values) {
        expect(
          home.offset < byteOffset || home.offset >= byteOffset + 77,
          isTrue,
        );
        expect(
          home.offset < wordOffset || home.offset >= wordOffset + 8,
          isTrue,
        );
      }
      expect(result.safepoints[call]!.offsets, isEmpty);
      expect(result.operations[bytes]!.temporaries, hasLength(2));
    },
  );

  test(
    'small native block emission clears every byte and no neighboring bytes',
    () {
      for (final size in [1, 2, 3, 7, 8, 9, 17, 64]) {
        final target = FunctionTarget(uri, 'zero$size', .integer, []);
        final entry = Block();
        final storage = entry.emit(
          NativeLocalStorage(
            NativeArrayType(.of(ffi.Uint8), size),
            zeroInitialize: true,
          ),
        );
        entry.finish(Return(storage));
        final result = allocate(select(target, [entry]));
        final emitter = _StorageSink();
        ScalarFunction(result, emitter).generate(
          (_, _) => fail('Local storage called a function'),
          (_, _) => fail('Local storage referenced constant data'),
          (_, _, _, _) => fail('Local storage introduced a safepoint'),
        );
        final offset = result.nativeStorage[storage]!.offset;
        expect(emitter.cleared, {for (var i = 0; i < size; i++) offset + i: 0});
        expect(emitter.registers[result.operations[storage]!.result], offset);
      }
    },
  );

  test('cloned storage evaluations retain their activation block', () {
    final target = FunctionTarget(uri, 'clonedStorage', .integer, []);
    final entry = Block();
    final first = entry.emit(NativeLocalStorage(.of(ffi.Int64)));
    final clone =
        entry.emit(first.mapInputs((value) => value)) as NativeLocalStorage;
    entry.finish(Return(entry.emit(IntBinary(.subtract, first, clone))));
    final result = allocate(select(target, [entry]));
    expect(result.nativeStorage[first], same(result.nativeStorage[clone]));
  });

  test('oversized and empty native blocks fail before emission', () {
    for (final type in [
      NativeArrayType(.of(ffi.Uint8), 0, variableLength: true),
      NativeArrayType(.of(ffi.Uint8), 0x1000000),
    ]) {
      final target = FunctionTarget(uri, 'invalidStorage', .integer, []);
      final entry = Block();
      entry.finish(Return(entry.emit(NativeLocalStorage(type))));
      expect(() => allocate(select(target, [entry])), throwsArgumentError);
    }
  });

  test('call-frame arguments bind ABI locations without SSA homes', () {
    final callee = FunctionTarget(
      uri,
      'scan',
      .voidType,
      List.filled(10, ValueType.integer),
    );
    final target = FunctionTarget(uri, 'caller', .voidType, []);
    final entry = Block();
    final call = entry.emit(
      DirectCall(callee, [
        CallFrameValue.stackPointer,
        CallFrameValue.returnAddress,
        for (var i = 2; i < 8; i++) Constant.integer(i),
        CallFrameValue.stackPointer,
        CallFrameValue.returnAddress,
      ]),
    );
    entry.finish(const Return());
    IrFunction(target, [entry]);
    final body = select(target, [entry])..invocations[call] = callee;
    final allocation = allocate(body);
    final bound = allocation.operations[call]!.arguments
        .where((argument) => argument.frameValue != null)
        .toList();
    expect(bound.length, 4);
    expect(bound.where((argument) => argument.stackOffset != null).length, 2);
    expect(bound.every((argument) => argument.loads.isEmpty), isTrue);
    expect(allocation.safepoints[call]!.offsets, isEmpty);
  });

  test('shared Jump keeps transfers for each predecessor', () {
    final target = FunctionTarget(uri, 'sharedEdge', .integer, [
      .boolean,
      .integer,
    ]);
    final callee = FunctionTarget(uri, 'clobber', .voidType, []);
    final start = Block(target.parameterTypes);
    final left = Block(), right = Block(), done = Block([ValueType.integer]);
    final shared = Jump(done, [start.parameters[1]]);
    final toLeft = Jump(left), toRight = Jump(right);
    start.finish(Branch(start.parameters[0], toLeft, toRight));
    final call = left.emit(DirectCall(callee, []));
    left.finish(shared);
    right.finish(shared);
    done.finish(Return(done.parameters.single));
    final blocks = [start, left, right, done];
    IrFunction(target, blocks);
    final body = select(target, blocks)..invocations[call] = callee;
    final allocation = allocate(body);
    for (final clobbered in [false, true]) {
      final machine = _Locations();
      machine.registers.addAll({
        Register.x0: clobbered ? 1 : 0,
        Register.x1: 41,
      });
      machine.apply(allocation.edges[(start, clobbered ? toLeft : toRight)]!);
      if (clobbered) {
        machine.apply(allocation.operations[call]!.before);
        machine.registers.clear();
      }
      machine.apply(allocation.edges[(clobbered ? left : right, shared)]!);
      expect(
        machine.read(allocation.entries[done]![done.parameters.single]!),
        41,
      );
    }
  });

  test('allocation freezes locations and matching edges without emission', () {
    final target = FunctionTarget(
      uri,
      'forward',
      .integer,
      List.filled(3, ValueType.integer),
    );
    final entry = Block(target.parameterTypes),
        next = Block(target.parameterTypes);
    final edge = Jump(next, entry.parameters);
    entry.finish(edge);
    next.emit(KeepAlive(next.parameters[1]));
    next.emit(KeepAlive(next.parameters[2]));
    next.finish(Return(next.parameters.first));
    final allocation = allocate(select(target, [entry, next]));
    expect(allocation.edges[(entry, edge)], isEmpty);
    expect(allocation.frame, isNull);
    expect(() => allocation.operations.clear(), throwsUnsupportedError);
    expect(() => allocation.entries[next]!.clear(), throwsUnsupportedError);
    for (var i = 0; i < 3; i++) {
      expect(
        (allocation.entries[next]![next.parameters[i]] as AllocationRegister)
            .register,
        Register.values[i],
      );
    }
  });

  test('one allocation emits independently into fresh buffers', () {
    final target = FunctionTarget(uri, 'sum', .integer, [.integer, .integer]);
    final block = Block(target.parameterTypes);
    final sum = block.emit(
      IntBinary(.add, block.parameters[0], block.parameters[1]),
    );
    block.finish(Return(sum));
    final original = _Sink();
    final selection = FunctionSelection(select(target, [block]), original);
    final allocation = FunctionAllocation(selection);
    for (var i = 0; i < 2; i++) {
      final sink = _Sink();
      final bytes = ScalarFunction(allocation, sink).generate(
        (_, _) => fail('Unexpected call'),
        (_, _) => fail('Unexpected constant'),
        (_, _, _, _) => fail('Unexpected safepoint'),
      );
      expect(bytes, [0xa0, 0xc0]);
      expect(original.position, 0);
    }
  });

  test(
    'reference address casts preserve raw bits without boxing or unboxing',
    () {
      for (final fromReference in [false, true]) {
        final inputType = fromReference ? ValueType.object : ValueType.integer;
        final resultType = fromReference ? ValueType.integer : ValueType.object;
        final target = FunctionTarget(uri, 'address', resultType, [inputType]);
        final block = Block(target.parameterTypes);
        final operation = block.emit(
          fromReference
              ? ReferenceAddress(block.parameters.single)
              : ReferenceFromAddress(block.parameters.single, resultType),
        );
        block.finish(Return(operation));
        final allocation = allocate(select(target, [block])),
            machine = _Locations();
        machine.registers[Register.x0] = 0x12345678;
        final plan = allocation.operations[operation]!;
        machine.apply(plan.before);
        machine.registers[plan.result!] =
            machine.registers[plan.inputs.single]!;
        machine.apply(plan.resultMoves);
        machine.apply(allocation.terminators[block]!.before);
        expect(machine.registers[Register.x0], 0x12345678);
      }
    },
  );

  test(
    'an explicit constant carrier keeps the constant relocation payload',
    () {
      final target = FunctionTarget(uri, 'boxed', .object, []);
      final block = Block();
      final view = block.emit(ConstantCarrier(const Constant.integer(17)));
      block.finish(Return(view));
      final body = select(target, [block])..aliases.add(view);
      final allocation = allocate(body);
      final copy = allocation.operations[view]!.before.single;
      expect(copy.source, isA<AllocationConstant>());
      expect(
        (copy.source as AllocationConstant).value,
        const Constant.integer(17),
      );
      expect(copy.from, ValueRepresentation.word);
      expect(copy.to, ValueRepresentation.reference);
    },
  );

  test('register swap cycles use a scratch register in either bank', () {
    for (final type in [ValueType.integer, ValueType.floating]) {
      final target = FunctionTarget(uri, 'rotate', type, List.filled(3, type));
      final entry = Block(target.parameterTypes),
          loop = Block(target.parameterTypes);
      final start = Jump(loop, entry.parameters);
      entry.finish(start);
      for (final value in loop.parameters) {
        loop.emit(KeepAlive(value));
      }
      final rotate = Jump(loop, [
        ...loop.parameters.skip(1),
        loop.parameters.first,
      ]);
      loop.finish(rotate);
      final allocation = allocate(select(target, [entry, loop]));
      final machine = _Locations();
      for (var i = 0; i < 3; i++) {
        machine.write(allocation.entries[entry]![entry.parameters[i]]!, i + 10);
      }
      machine.apply(allocation.edges[(entry, start)]!);
      final moves = allocation.edges[(loop, rotate)]!;
      expect(moves, hasLength(4));
      expect(
        moves.every(
          (move) =>
              move.source is AllocationRegister &&
              move.destination is AllocationRegister,
        ),
        isTrue,
      );
      expect(allocation.frame, isNull);
      machine.apply(moves);
      expect(
        loop.parameters.map((p) => machine.read(allocation.entries[loop]![p]!)),
        [11, 12, 10],
      );
    }
  });

  test(
    'critical edges preserve register and stack rotations independently',
    () {
      for (final reverse in [false, true]) {
        final target = FunctionTarget(
          uri,
          'rotate',
          .integer,
          List.filled(4, ValueType.integer),
        );
        final entry = Block(target.parameterTypes),
            loop = Block(target.parameterTypes);
        final start = Jump(loop, entry.parameters);
        entry.finish(start);
        final rotate = Jump(loop, [
          ...loop.parameters.skip(1),
          loop.parameters.first,
        ]);
        final backwards = Jump(loop, loop.parameters.reversed);
        for (final value in loop.parameters) {
          loop.emit(KeepAlive(value));
        }
        loop.finish(Branch(const Constant.boolean(true), rotate, backwards));
        final allocation = allocate(select(target, [entry, loop]));
        final machine = _Locations();
        for (var i = 0; i < 4; i++) {
          machine.write(
            allocation.entries[entry]![entry.parameters[i]]!,
            i + 10,
          );
        }
        machine.apply(allocation.edges[(entry, start)]!);
        var expected = [10, 11, 12, 13];
        for (var i = 0; i < 7; i++) {
          expect(
            loop.parameters.map(
              (p) => machine.read(allocation.entries[loop]![p]!),
            ),
            expected,
          );
          machine.apply(allocation.terminators[loop]!.before);
          machine.apply(
            allocation.edges[(loop, reverse ? backwards : rotate)]!,
          );
          expected = reverse
              ? expected.reversed.toList()
              : [...expected.skip(1), expected.first];
        }
      }
    },
  );

  test(
    'stack cycles use one temporary word and preserve unchanged registers',
    () {
      final target = FunctionTarget(
        uri,
        'stackRotate',
        .integer,
        List.filled(6, ValueType.integer),
      );
      final entry = Block(target.parameterTypes),
          loop = Block(target.parameterTypes);
      final start = Jump(loop, entry.parameters);
      entry.finish(start);
      for (final value in loop.parameters.reversed) {
        loop.emit(KeepAlive(value));
      }
      final rotate = Jump(loop, [
        ...loop.parameters.take(3),
        ...loop.parameters.skip(4),
        loop.parameters[3],
      ]);
      loop.finish(rotate);
      final allocation = allocate(select(target, [entry, loop]));
      final machine = _Locations();
      for (var i = 0; i < 6; i++) {
        machine.write(allocation.entries[entry]![entry.parameters[i]]!, i + 10);
      }
      machine.apply(allocation.edges[(entry, start)]!);
      machine.apply(allocation.edges[(loop, rotate)]!);
      expect(
        loop.parameters.map((p) => machine.read(allocation.entries[loop]![p]!)),
        [10, 11, 12, 14, 15, 13],
      );
      expect(allocation.frame!.localBytes, 4 * 8);
    },
  );

  test(
    'calls initialize only live roots and later uses reload moved homes',
    () {
      final target = FunctionTarget(uri, 'caller', .object, [
        .object,
        .integer,
        .object,
        ...List.filled(5, ValueType.integer),
        .object,
      ]);
      final block = Block(target.parameterTypes);
      final callee = FunctionTarget(uri, 'collect', .voidType, [.object]);
      final call = block.emit(DirectCall(callee, [block.parameters[2]]));
      final reference = block.emit(
        ObjectHashCode(block.parameters[0], direct: true),
      );
      final integer = block.emit(NumericToInt(block.parameters[1], .truncate));
      block.finish(Return(block.parameters[8]));
      final body = select(target, [block])..invocations[call] = callee;
      final allocation = allocate(body), machine = _Locations();
      for (final (i, value) in block.parameters.indexed) {
        if (allocation.entries[block]![value] case final location?) {
          machine.write(location, (i + 1) * 0x100);
        }
      }
      machine.apply(allocation.operations[call]!.before);
      final roots = allocation.safepoints[call]!;
      expect(roots.offsets.map((offset) => machine.stack[offset]).toSet(), {
        0x100,
        0x900,
      });
      for (final offset in roots.offsets) {
        machine.stack[offset] = (machine.stack[offset]! as int) + 1;
      }
      machine.registers.clear();
      machine.apply(allocation.operations[reference]!.before);
      expect(
        machine.registers[allocation.operations[reference]!.inputs.single],
        0x101,
      );
      machine.apply(allocation.operations[integer]!.before);
      expect(
        machine.registers[allocation.operations[integer]!.inputs.single],
        0x200,
      );
      machine.apply(allocation.terminators[block]!.before);
      expect(machine.registers[Register.x0], 0x901);
    },
  );

  test(
    'normal and exceptional call edges use independent post-call locations',
    () {
      final target = FunctionTarget(uri, 'tryCall', .object, [.object]);
      final callee = FunctionTarget(uri, 'throwing', .object, []);
      final entry = Block(target.parameterTypes);
      final normal = Block([ValueType.object, ValueType.object]);
      final handler = Block([
        ValueType.object,
        ValueType.stackTrace,
        ValueType.object,
      ]);
      final call = DirectCall(callee, []);
      final returned = Jump(normal, [call, entry.parameters.single]);
      final failed = Jump(handler, [
        UnwindValue.exception,
        UnwindValue.stackTrace,
        entry.parameters.single,
      ]);
      entry.finish(Invoke(call, onReturn: returned, onThrow: failed));
      normal.emit(KeepAlive(normal.parameters[1]));
      normal.finish(Return(normal.parameters.first));
      handler.emit(KeepAlive(handler.parameters[1]));
      handler.emit(KeepAlive(handler.parameters[2]));
      handler.finish(Return(handler.parameters.first));
      final body = select(target, [entry, normal, handler])
        ..invocations[call] = callee;
      final allocation = allocate(body);
      for (final fails in [false, true]) {
        final machine = _Locations();
        machine.registers[Register.x0] = 0x100;
        machine.apply(allocation.operations[call]!.before);
        final root = allocation.safepoints[call]!.offsets.single;
        machine.stack[root] = 0x101;
        machine.registers
          ..clear()
          ..addAll({Register.x0: fails ? 0xe0 : 0xa0, Register.x1: 0xe1});
        machine.apply(allocation.edges[(entry, fails ? failed : returned)]!);
        final block = fails ? handler : normal;
        expect(
          block.parameters.map(
            (value) => machine.read(allocation.entries[block]![value]!),
          ),
          fails ? [0xe0, 0xe1, 0x101] : [0xa0, 0x101],
        );
      }
    },
  );

  test('fixed inputs preserve swapped sources and other clobbered values', () {
    final target = FunctionTarget(
      uri,
      'fixed',
      .integer,
      List.filled(3, ValueType.integer),
    );
    final block = Block(target.parameterTypes);
    final operation = block.emit(
      IntBinary(.subtract, block.parameters[1], block.parameters[0]),
    );
    block.emit(KeepAlive(block.parameters[2]));
    block.finish(Return(operation));
    final allocation = allocate(select(target, [block])),
        machine = _Locations();
    machine.registers.addAll({
      Register.x0: 3,
      Register.x1: 20,
      Register.x2: 99,
    });
    final plan = allocation.operations[operation]!;
    machine.apply(plan.before);
    expect(plan.inputs, [Register.x0, Register.x1]);
    machine.registers[plan.result!] =
        (machine.registers[plan.inputs[0]]! as int) -
        (machine.registers[plan.inputs[1]]! as int);
    expect(machine.read(allocation.homes[block.parameters[2]]!), 99);
    machine.apply(allocation.terminators[block]!.before);
    expect(machine.registers[Register.x0], 17);
  });
}

final class _Locations() {
  final registers = <CpuRegister, Object>{};
  final stack = <int, Object>{};
  Object read(AllocationLocation<CpuRegister> location) => switch (location) {
    AllocationRegister(:final register) => registers[register]!,
    AllocationStack(:final offset) => stack[offset]!,
    AllocationConstant(value: ScalarConstant(:final value)) => value!,
    _ => throw StateError('Expected a scalar allocation location.'),
  };
  void write(AllocationLocation<CpuRegister> location, Object value) {
    switch (location) {
      case AllocationRegister(:final register):
        registers[register] = value;
      case AllocationStack(:final offset):
        stack[offset] = value;
      default:
        throw StateError('A constant is not writable.');
    }
  }

  void apply(Iterable<AllocationMove<CpuRegister>> moves) {
    for (final move in moves) {
      expect(move.from, move.to);
      final value = read(move.source);
      if (move.temporary case final register?) registers[register] = value;
      if (move.auxiliary case final register?) registers[register] = -999;
      write(move.destination, value);
    }
  }
}

/// Only target queries work; allocation cannot invoke an emission side effect.
class _Constraints() implements FunctionEmitter<CpuRegister> {
  @override
  final convention = Arm64Abi(const Target(.linux, .arm64));
  @override
  final allocatableRegisters = <CpuRegister>[
    Register.x0,
    Register.x1,
    Register.x2,
    Register.x3,
    FloatRegister.d0,
    FloatRegister.d1,
    FloatRegister.d2,
    FloatRegister.d3,
  ];
  @override
  RegisterBank bank(CpuRegister register) =>
      register is Register ? .general : .floating;
  @override
  CpuRegister get exceptionRegister => Register.x0;
  @override
  CpuRegister get traceRegister => Register.x1;
  @override
  CpuRegister get failureRegister => Register.x16;
  @override
  CpuRegister get heapRegister => Register.x28;
  @override
  bool get negationNeedsTemporary => false;
  @override
  BinaryEncoding<CpuRegister> get subtract => BinaryEncoding(
    (_, _, _) => throw StateError('Allocation invoked an encoder.'),
    fixed: (
      left: Register.x0,
      right: Register.x1,
      result: Register.x0,
      clobbered: {Register.x2},
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

final class _Sink() extends _Constraints {
  final _code = CodeBuffer();

  @override
  int get position => _code.length;
  @override
  Label label() => _code.label();
  @override
  void bind(Label label) => _code.bind(label);
  @override
  BinaryEncoding<CpuRegister> get add =>
      BinaryEncoding((_, _, _) => _code.addByte(0xa0));
  @override
  void ret() => _code.addByte(0xc0);
  @override
  Uint8List finish() => _code.finish();
}

final class _StorageSink() extends _Constraints {
  final _code = CodeBuffer();
  final registers = <CpuRegister, int>{};
  final cleared = <int, int>{};
  @override
  Label label() => _code.label();
  @override
  void bind(Label label) => _code.bind(label);
  @override
  void prologue(FrameLayout<CpuRegister> frame) {}
  @override
  void epilogue(FrameLayout<CpuRegister> frame) {}
  @override
  void stackAddress(CpuRegister destination, int offset) =>
      registers[destination] = offset;
  @override
  void loadImmediate(CpuRegister destination, int value) =>
      registers[destination] = value;
  @override
  void storeMemory(
    CpuRegister source,
    CpuRegister base, {
    int offset = 0,
    required int bytes,
  }) {
    final address = registers[base]! + offset;
    final value = registers[source]!;
    for (var i = 0; i < bytes; i++) {
      cleared[address + i] = (value >> (i * 8)) & 255;
    }
  }

  @override
  Uint8List finish() => _code.finish();
}

final class _ContextSink() extends _Constraints {
  final _code = CodeBuffer();
  final moves = <(CpuRegister, CpuRegister)>[];
  final exits = <FrameLayout<CpuRegister>>[];
  FrameLayout<CpuRegister>? entered;
  @override
  int get position => 0;
  @override
  Label label() => _code.label();
  @override
  void bind(Label label) => _code.bind(label);
  @override
  void jump(Label label) {}
  @override
  void jumpIfZero(CpuRegister value, Label label) {}
  @override
  void prologue(FrameLayout<CpuRegister> frame) => entered = frame;
  @override
  void epilogue(FrameLayout<CpuRegister> frame) => exits.add(frame);
  @override
  void ret() {}
  @override
  void move(CpuRegister destination, CpuRegister source) =>
      moves.add((destination, source));
  @override
  void loadImmediate(CpuRegister destination, int value) {}
  @override
  Fixup call() => const Fixup(0, FixupEncoding.arm64Call26);
  @override
  Uint8List finish() => _code.finish();
}
