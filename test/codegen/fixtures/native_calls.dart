import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

List<ObjectModule> nativeCalls(Target target) {
  final signatures = <String, NativeSignature>{
    for (final type in [
      Int8,
      Uint8,
      Int16,
      Uint16,
      Int32,
      Uint32,
      Int64,
      Uint64,
    ]) ...{
      'argument$type': .new(Int64, [type]),
      'result$type': .new(type, [Int64]),
    },
    'argumentFloat': .new(Double, [Float]),
    'resultFloat': .new(Float, [Double]),
    'pointer': .new(Pointer<Int64>, [Pointer<Int64>]),
    'write': .new(Void, [Pointer<Int64>, Int64]),
    'packed': .new(Int64, List.filled(24, Uint8)),
    'mixed': .new(Double, [
      Float,
      Double,
      Float,
      Double,
      Float,
      Double,
      Float,
      Double,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
      Float,
      Float,
      Int8,
      Double,
      Pointer<Double>,
    ]),
  };
  final library = Uri.parse('memory:native-calls');
  final functions = <IrFunction>[], externals = <IrExternal>[];
  final imports = <FunctionTarget, NativeImport>{};
  final exports = <FunctionTarget, NativeExport>{};
  for (final MapEntry(:key, :value) in signatures.entries) {
    final external = FunctionTarget(
      library,
      'external_$key',
      FfiTypes.valueType(value.result),
      value.parameters.map(FfiTypes.valueType).toList(),
    );
    externals.add(.new(external));
    imports[external] = .new('provided_$key', value);
    Type fullWidth(Type type) => type.isFloating
        ? Double
        : type.integerLayout != null
        ? Int64
        : type;
    final signature = switch (key) {
      'mixed' => NativeSignature(Double, [Pointer<Double>, Int64, Double]),
      'packed' => NativeSignature(Int64, [Int64]),
      _ => NativeSignature(
        value.result == Void ? Int64 : fullWidth(value.result),
        value.parameters.map(fullWidth),
      ),
    };
    final wrapper = FunctionTarget(
      library,
      key,
      FfiTypes.valueType(signature.result),
      signature.parameters.map(FfiTypes.valueType).toList(),
    );
    final block = Block(wrapper.parameterTypes);
    final parameters = block.parameters;
    final List<Value> arguments = switch (key) {
      'mixed' => [
        for (var i = 1; i <= 8; i++)
          block.emit(
            NumericBinary(.add, parameters[2], Constant.floating(i.toDouble())),
          ),
        for (var i = 1; i <= 8; i++)
          block.emit(IntBinary(.add, parameters[1], Constant.integer(i))),
        parameters[2],
        parameters[2],
        parameters[1],
        parameters[2],
        parameters[0],
      ],
      'packed' => [
        for (var i = 0; i < 24; i++)
          block.emit(
            IntBinary(.add, parameters.single, Constant.integer(i * 17)),
          ),
      ],
      _ => parameters,
    };
    Value result = block.emit(DirectCall(external, arguments));
    if (value.result == Void) {
      result = block.emit(LoadNative(parameters.first));
    } else if (key.startsWith('argument') || key == 'mixed') {
      final original = key == 'mixed' ? parameters[2] : parameters.single;
      result = block.emit(NumericBinary(.add, result, original));
    }
    block.finish(Return(result));
    functions.add(.new(wrapper, [block]));
    exports[wrapper] = .new(key, signature);
  }
  final program = IrProgram([], functions, externals: externals);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  final caller = generator.generate(
    program,
    definitions: [...functions.map((f) => f.target), ...imports.keys],
    exports: exports,
    imports: imports,
  );
  final bytes = BytesBuilder(copy: false), symbols = <Symbol>[];
  for (final MapEntry(:key, :value) in signatures.entries) {
    bytes.add(Uint8List((-bytes.length) & 15));
    final body = target.architecture == .arm64
        ? _arm(target, value)
        : _x64(target, value);
    symbols.add(
      Symbol(
        target.nativeSymbol('provided_$key'),
        0,
        bytes.length,
        body.length,
        exported: true,
      ),
    );
    bytes.add(body);
  }
  symbols.add(
    Symbol(
      target.nativeSymbol('memory'),
      1,
      0,
      64,
      kind: .data,
      exported: true,
    ),
  );
  return [
    caller,
    ObjectModule(target, [
      Section.code(bytes.takeBytes()),
      Section.zeroFill(64, alignment: 8),
    ], symbols),
  ];
}

Uint8List _arm(Target target, NativeSignature signature) {
  final assembler = arm.Assembler(), abi = Arm64Abi(target);
  final layout = abi.classify(signature);
  if (signature.parameters.length > 2) {
    assembler
      ..loadImmediate(.x9, 0)
      ..moveBitsToDouble(.d16, .x9);
    for (final (i, location) in layout.parameters.indexed) {
      final type = signature.parameters[i];
      if (type.isFloating) {
        switch (location) {
          case RegisterArgument(:final register):
            assembler.moveDouble(.d17, register as arm.FloatRegister);
          case StackArgument(:final offset):
            if (type == Float) {
              assembler.loadFloat(.d17, .sp, offset);
            } else {
              assembler.loadDouble(.d17, .sp, offset);
            }
        }
        if (type == Float) assembler.convertFloatToDouble(.d17, .d17);
      } else {
        switch (location) {
          case RegisterArgument(:final register):
            assembler.move(.x9, register as arm.Register);
          case StackArgument(:final offset):
            assembler.load(
              .x9,
              .sp,
              offset,
              bytes: type.nativeSize,
              signed: type.integerLayout?.signed ?? false,
            );
        }
        if (type.pointerElement != null) {
          assembler.loadDouble(.d17, .x9, 0);
        } else {
          final integer = type.integerLayout!;
          assembler.extendInteger(
            .x9,
            .x9,
            bytes: integer.bytes,
            signed: integer.signed,
          );
          assembler.convertIntToDouble(.d17, .x9);
        }
      }
      assembler.addDouble(.d16, .d16, .d17);
    }
    if (signature.result == Double) {
      assembler.moveDouble(.d0, .d16);
    } else {
      assembler.truncateDoubleToInt(.x0, .d16);
    }
  } else if (signature.result == Void) {
    assembler.store(.x1, .x0, 0);
  } else if (signature.parameters.single == Float) {
    assembler.convertFloatToDouble(.d0, .d0);
  } else if (signature.result == Float) {
    assembler.convertDoubleToFloat(.d0, .d0);
  } else if (signature.parameters.single.integerLayout case final integer?) {
    // Apple callers extend narrow arguments to 32 bits; check that promise too.
    assembler.extendInteger(
      .x0,
      .x0,
      bytes: target.operatingSystem == .macos && integer.bytes < 4
          ? 4
          : integer.bytes,
      signed: integer.signed,
    );
  }
  assembler.ret();
  return assembler.finish();
}

Uint8List _x64(Target target, NativeSignature signature) {
  final assembler = x64.Assembler(), abi = X64Abi(target);
  final layout = abi.classify(signature);
  if (signature.parameters.length > 2) {
    assembler
      ..loadImmediate(.r10, 0)
      ..moveBitsToDouble(.xmm14, .r10);
    for (final (i, location) in layout.parameters.indexed) {
      final type = signature.parameters[i];
      if (type.isFloating) {
        switch (location) {
          case RegisterArgument(:final register):
            assembler.moveDouble(.xmm15, register as x64.FloatRegister);
          case StackArgument(:final offset):
            if (type == Float) {
              assembler.loadFloat(.xmm15, .rsp, offset + 8);
            } else {
              assembler.loadDouble(.xmm15, .rsp, offset + 8);
            }
        }
        if (type == Float) assembler.convertFloatToDouble(.xmm15, .xmm15);
      } else {
        switch (location) {
          case RegisterArgument(:final register):
            assembler.move(.r10, register as x64.Register);
          case StackArgument(:final offset):
            assembler.load(
              .r10,
              .rsp,
              offset + 8,
              bytes: type.nativeSize,
              signed: type.integerLayout?.signed ?? false,
            );
        }
        if (type.pointerElement != null) {
          assembler.loadDouble(.xmm15, .r10, 0);
        } else {
          final integer = type.integerLayout!;
          assembler.extendInteger(
            .r10,
            .r10,
            bytes: integer.bytes,
            signed: integer.signed,
          );
          assembler.convertIntToDouble(.xmm15, .r10);
        }
      }
      assembler.addDouble(.xmm14, .xmm15);
    }
    if (signature.result == Double) {
      assembler.moveDouble(.xmm0, .xmm14);
    } else {
      assembler.truncateDoubleToInt(.rax, .xmm14);
    }
  } else if (signature.result == Void) {
    assembler.store(.rsi, .rdi, 0);
  } else if (signature.parameters.single == Float) {
    assembler.convertFloatToDouble(.xmm0, .xmm0);
  } else if (signature.result == Float) {
    assembler.convertDoubleToFloat(.xmm0, .xmm0);
  } else if (signature.parameters.single.integerLayout case final integer?) {
    assembler.extendInteger(
      .rax,
      .rdi,
      bytes: integer.bytes,
      signed: integer.signed,
    );
  } else {
    assembler.move(.rax, .rdi);
  }
  assembler.ret();
  return assembler.finish();
}
