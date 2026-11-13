import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final pair = NativeCompoundType('Pair', [
    NativeField('x', NativeScalarType(Double)),
    NativeField('y', NativeScalarType(Double)),
  ]);
  final large = NativeCompoundType('Large', [
    NativeField('values', NativeArrayType(NativeScalarType(Int64), 3)),
  ]);

  test('Apple anonymous arguments use eight-byte stack slots, including aggregates', () {
    final signature = NativeSignature.types(NativeScalarType(Void), [
      NativeScalarType(Int32),
      NativeScalarType(Double),
      NativeScalarType(Int32),
      NativeScalarType(Double),
      pair,
      large,
    ], variadicStart: 2);
    final call = Arm64Abi(const Target(.macos, .arm64)).classify(signature);
    expect((call.parameters[0] as RegisterArgument).register, arm.Register.x0);
    expect(
      (call.parameters[1] as RegisterArgument).register,
      arm.FloatRegister.d0,
    );
    expect(
      [
        for (final location
            in call.parameters.skip(2).take(3).cast<StackArgument>())
          (location.offset, location.size, location.alignment),
      ],
      [(0, 8, 8), (8, 8, 8), (16, 16, 8)],
    );
    expect(
      ((call.parameters[5] as IndirectArgument).pointer as StackArgument)
          .offset,
      32,
    );
    expect(call.stackBytes, 48);
    final linux = Arm64Abi(const Target(.linux, .arm64)).classify(signature);
    expect((linux.parameters[2] as RegisterArgument).register, arm.Register.x1);
    expect(
      (linux.parameters[3] as RegisterArgument).register,
      arm.FloatRegister.d1,
    );
    expect(linux.parameters[4].registers, [
      arm.FloatRegister.d2,
      arm.FloatRegister.d3,
    ]);
    expect(linux.parameters[5].registers, [arm.Register.x2]);
    expect(linux.stackBytes, 0);
  });

  test(
    'Apple aligns anonymous arguments after compact fixed stack arguments',
    () {
      final call = Arm64Abi(const Target(.macos, .arm64)).classify(
        NativeSignature(Void, [
          ...List.filled(9, Int8),
          Int32,
          Double,
        ], variadicStart: 9),
      );
      expect(
        [
          for (final location in call.parameters.skip(8).cast<StackArgument>())
            (location.offset, location.size),
        ],
        [(0, 1), (8, 8), (16, 8)],
      );
    },
  );

  test('SysV AL counts fixed and anonymous vector registers, excluding stack spills', () {
    for (final os in OperatingSystem.values) {
      final abi = X64Abi(Target(os, .x64));
      final call = abi.classify(
        NativeSignature(Void, [
          Int32,
          ...List.filled(10, Double),
        ], variadicStart: 2),
      );
      expect(call.registerInputs, {x64.Register.rax: 8});
      expect(call.stackBytes, 16);
      expect(
        abi
            .classify(NativeSignature(Void, [Int32], variadicStart: 1))
            .registerInputs,
        {x64.Register.rax: 0},
      );
      expect(
        abi.classify(NativeSignature(Void, [Int32])).registerInputs,
        isEmpty,
      );
      final aggregate = abi.classify(
        NativeSignature.types(NativeScalarType(Void), [pair], variadicStart: 0),
      );
      expect(aggregate.registerInputs, {x64.Register.rax: 2});
    }
  });

  test(
    'implicit register inputs cannot overwrite parameters or survive a call',
    () {
      expect(
        () => CallLayout(
          [const RegisterArgument(x64.Register.rdi)],
          null,
          const {x64.Register.rdi},
          registerInputs: const {x64.Register.rdi: 1},
        ),
        throwsArgumentError,
      );
      expect(
        () => CallLayout<x64.Register>(
          [],
          null,
          const {},
          registerInputs: const {x64.Register.rax: 1},
        ),
        throwsArgumentError,
      );
    },
  );
}
