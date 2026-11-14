import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/src/assembler/code_buffer.dart' show CodeBuffer;
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/codegen/binary_encoding.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/src/codegen/scalar_function.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:allocation');
  SelectedFunction select(FunctionTarget target, List<Block> blocks) {
    final body = SelectedFunction(target, ProgramLayout([]), blocks.first);
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

  test('constant boxing keeps the original constant in the transfer', () {
    final target = FunctionTarget(uri, 'boxed', .object, []);
    final block = Block();
    final view = block.emit(
      TypeView(const Constant.integer(17), ValueType.object),
    );
    block.finish(Return(view));
    final allocation = allocate(select(target, [block]));
    final copy = allocation.operations[view]!.before.single;
    expect(copy.source, isA<AllocationConstant>());
    expect(
      (copy.source as AllocationConstant).value,
      const Constant.integer(17),
    );
    expect(copy.from, ValueRepresentation.word);
    expect(copy.to, ValueRepresentation.reference);
  });

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
