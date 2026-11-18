import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/assembler/code_buffer.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/native_adapter.dart';
import 'package:dartc/src/codegen/native_invocation.dart';
import 'package:dartc/src/codegen/indirect_invocation.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/scalar_function.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final integer = NativeScalarType(ffi.Int64);
  final pair = NativeCompoundType('Pair', [
    NativeField('first', integer),
    NativeField('second', integer),
  ]);
  final large = NativeCompoundType('Large', [
    NativeField('values', NativeArrayType(integer, 7)),
  ]);
  final signatures = {
    'scalar': NativeSignature(ffi.Int64, [ffi.Int64]),
    'variadic': NativeSignature(ffi.Int64, [
      ffi.Int64,
      ffi.Int64,
    ], variadicStart: 1),
    'register aggregate': NativeSignature.types(pair, [pair]),
    'indirect aggregate': NativeSignature.types(large, [large]),
  };

  for (final MapEntry(key: name, value: signature) in signatures.entries) {
    for (final indirect in [false, true]) {
      test(
        '$name ${indirect ? 'function pointer' : 'import'} adapter only converts ABI storage',
        () {
          final emitter = _RecordingEmitter();
          var calls = 0;
          NativeAdapter(emitter).generate(
            signature,
            (_, position, _) {
              calls++;
              expect(position, emitter.position);
            },
            intoDart: false,
            indirectCall: indirect
                ? (position, _) {
                    calls++;
                    expect(position, emitter.position);
                  }
                : null,
          );
          expect(calls, 1);
          expect(emitter.calls, 1);
          expect(emitter.contextReads, isEmpty);
          expect(emitter.recordWrites, isEmpty);
        },
      );
    }
  }

  test('selected native calls do not read or publish runtime state', () {
    for (final isLeaf in [false, true]) {
      final target = FunctionTarget(null, 'indirect', .integer, [.integer]);
      final entry = Block(target.parameterTypes);
      final call = NativeInvocation(
        entry.parameters.single,
        [],
        NativeSignature(ffi.Int64, []),
        isLeaf: isLeaf,
      );
      final body = SelectedFunction(
        target,
        ProgramLayout(
          [],
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        ),
        entry,
      );
      body.blocks.add(entry);
      body.instructions[entry] = [call];
      body.ends[entry] = Return(call);
      final emitter = _RecordingEmitter();
      final selection = FunctionSelection(body, emitter);
      final addresses = <int>[];
      ScalarFunction(FunctionAllocation(selection), emitter).generate(
        (_, _) => fail('Expected indirect native call'),
        (_, _) => fail('Unexpected constant storage'),
        (_, _, _, _) {},
        codeAddress: (_, position) => addresses.add(position),
      );
      expect(emitter.calls, 1);
      expect(emitter.contextReads, isEmpty);
      expect(emitter.recordWrites, isEmpty);
      expect(addresses, isEmpty);
    }
  });

  for (final type in <ValueType>[.integer, .floating, .object]) {
    test('indirect Dart $type call retains completion and live references', () {
      final target = FunctionTarget(null, 'managedIndirect', type, [
        .integer,
        .object,
        type,
      ]);
      final entry = Block(target.parameterTypes);
      final [address, environment, argument] = entry.parameters;
      final callee = FunctionTarget(null, 'entry', type, [.object, type]);
      final source = DirectCall(callee, [environment, argument]);
      final call = IndirectInvocation(
        source,
        address,
        [environment, argument],
        callee.signature,
        ExecutionShapes().entryOf(callee),
      );
      final returned = Block([type]), failed = Block([.object, .stackTrace]);
      final handler = Jump(failed, [
        UnwindValue.exception,
        UnwindValue.stackTrace,
      ]);
      final body = SelectedFunction(
        target,
        ProgramLayout(
          [],
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        ),
        entry,
      );
      body.blocks.addAll([entry, returned, failed]);
      body.instructions[entry] = [call, source];
      body.instructions[returned] = [];
      body.instructions[failed] = [];
      body.aliases.add(source);
      body.operands[source] = [call];
      body.ends[entry] = Invoke(
        source,
        onReturn: Jump(returned, [source]),
        onThrow: handler,
      );
      body.ends[returned] = Return(returned.parameters.single);
      body.ends[failed] = Return(argument);
      final emitter = _RecordingEmitter();
      final selection = FunctionSelection(body, emitter);
      expect(selection.calls[call]!.target, isNull);
      expect(selection.calls[call]!.onThrow, same(handler));
      if (type == ValueType.object) {
        expect(selection.liveReferences[call], contains(argument));
      }
      var safepoints = 0;
      ScalarFunction(FunctionAllocation(selection), emitter).generate(
        (_, _) => fail('Expected a code-address call'),
        (_, _) => fail('Unexpected constant storage'),
        (_, _, _, _) => safepoints++,
        failures: true,
      );
      expect(emitter.calls, 1);
      expect(emitter.completionChecks, 1);
      expect(safepoints, 1);
      expect(emitter.contextReads, isEmpty);
      expect(emitter.recordWrites, isEmpty);
    });
  }
}

/// Records the relevant memory operations while using the actual target ABI.
final class _RecordingEmitter() implements FunctionEmitter<CpuRegister> {
  final _code = CodeBuffer();
  final contextReads = <int>[];
  final recordWrites = <int>[];
  var calls = 0, returnPc = 0;
  var completionChecks = 0;
  @override
  int position = 0;
  @override
  final convention = Arm64Abi(const Target(.linux, .arm64));
  @override
  final allocatableRegisters = <CpuRegister>[
    ...Register.values.take(16),
    ...FloatRegister.values.take(8),
  ];
  @override
  CpuRegister get heapRegister => Register.x28;
  @override
  CpuRegister get failureRegister => Register.x16;
  @override
  CpuRegister get exceptionRegister => Register.x0;
  @override
  CpuRegister get traceRegister => Register.x1;
  @override
  bool get negationNeedsTemporary => false;
  @override
  RegisterBank bank(CpuRegister register) =>
      register is Register ? .general : .floating;
  @override
  void prologue(FrameLayout<CpuRegister> frame) {}
  @override
  void epilogue(FrameLayout<CpuRegister> frame) {}
  @override
  Label label() => _code.label();
  @override
  void bind(Label label) => _code.bind(label);
  @override
  void ret() {}
  @override
  void jump(Label target) {}
  @override
  void jumpIfZero(CpuRegister value, Label target) {
    if (value == failureRegister) completionChecks++;
  }

  @override
  void move(CpuRegister destination, CpuRegister source) {}
  @override
  void loadImmediate(CpuRegister destination, int value) {}
  @override
  void stackAddress(CpuRegister destination, int offset) {}
  @override
  void extendInteger(
    CpuRegister register, {
    required int bytes,
    required bool signed,
  }) {}
  @override
  void loadStack(
    CpuRegister destination,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) {}
  @override
  void storeStack(CpuRegister source, int offset, {int bytes = 8}) {}
  @override
  void loadMemory(
    CpuRegister destination,
    CpuRegister base, {
    int offset = 0,
    required int bytes,
    required bool signed,
  }) {
    if (base == heapRegister) contextReads.add(offset);
  }

  @override
  void storeMemory(
    CpuRegister source,
    CpuRegister base, {
    int offset = 0,
    required int bytes,
  }) {
    if (base == failureRegister) recordWrites.add(offset);
  }

  @override
  void address(
    CpuRegister destination,
    void Function(Fixup) reference, {
    bool indirect = false,
  }) => reference(const Fixup(0, FixupEncoding.arm64Page21));
  @override
  Fixup call() {
    callRegister(Register.x15);
    return const Fixup(0, FixupEncoding.arm64Call26);
  }

  @override
  void callRegister(CpuRegister register) {
    calls++;
    position += 4;
    returnPc = position;
  }

  @override
  Uint8List finish() => _code.finish();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
