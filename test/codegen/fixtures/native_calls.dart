import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/compiler.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

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
    NativeTypeRef fullWidth(NativeTypeRef type) => type.isFloating
        ? NativeScalarType(Double)
        : type.integerLayout != null
        ? NativeScalarType(Int64)
        : type;
    final signature = switch (key) {
      'mixed' => NativeSignature(Double, [Pointer<Double>, Int64, Double]),
      'packed' => NativeSignature(Int64, [Int64]),
      _ => NativeSignature.types(
        value.result.isVoid ? NativeScalarType(Int64) : fullWidth(value.result),
        value.parameters.map(fullWidth),
      ),
    };
    for (final indirect in [false, true]) {
      final exported = NativeSignature.types(signature.result, [
        if (indirect) NativeScalarType(Int64),
        ...signature.parameters,
      ]);
      final name = indirect ? 'indirect_$key' : key;
      final wrapper = FunctionTarget(
        library,
        name,
        FfiTypes.valueType(exported.result),
        exported.parameters.map(FfiTypes.valueType).toList(),
      );
      final block = Block(wrapper.parameterTypes);
      final pointer = indirect
          ? block.emit(
              PointerFromAddress(
                block.parameters.first,
                FfiTypes.resolve(NativePointerType(NativeFunctionType(value))),
              ),
            )
          : null;
      final parameters = block.parameters.skip(indirect ? 1 : 0).toList();
      final List<Value> arguments = switch (key) {
        'mixed' => [
          for (var i = 1; i <= 8; i++)
            block.emit(
              NumericBinary(
                .add,
                parameters[2],
                Constant.floating(i.toDouble()),
              ),
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
      Value result = block.emit(
        pointer == null
            ? DirectCall(external, arguments)
            : NativeCall(pointer, arguments),
      );
      final blocks = [block];
      if (value.result.isVoid) {
        final returned = Block(), failed = Block();
        blocks.addAll([returned, failed]);
        final visible = block.emit(TypeView(result, .object.nullable));
        block.finish(
          Branch(
            block.emit(Equals(visible, const Constant.nullValue())),
            Jump(returned),
            Jump(failed),
          ),
        );
        returned.finish(
          Return(
            returned.emit(
              LoadNative(
                returned.emit(PointerAddress(parameters.first)),
                .of(Int64),
              ),
            ),
          ),
        );
        failed.finish(const Return(Constant.integer(-999)));
      } else if (key.startsWith('argument') || key == 'mixed') {
        final original = key == 'mixed' ? parameters[2] : parameters.single;
        result = block.emit(NumericBinary(.add, result, original));
      }
      if (!value.result.isVoid) block.finish(Return(result));
      functions.add(.new(wrapper, blocks));
      exports[wrapper] = .new(name, exported);
    }
  }
  final repeatedSignature = NativeSignature(Int64, [Int64]);
  final callback = NativePointerType(NativeFunctionType(repeatedSignature));
  final repeatedExport = NativeSignature.types(NativeScalarType(Int64), [
    ...List.filled(8, NativeScalarType(Int64)),
    callback,
    callback,
  ]);
  final repeated = FunctionTarget(
    library,
    'repeated',
    .integer,
    repeatedExport.parameters.map(FfiTypes.valueType).toList(),
  );
  final entry = Block(repeated.parameterTypes);
  final first = Block([]), second = Block([]);
  final loop = Block([
    FfiTypes.resolve(callback),
    .integer,
    .integer,
    .integer,
  ]);
  final invoke = Block([]), exit = Block([]);
  entry.finish(
    Branch(
      entry.emit(Equals(entry.parameters[0], Constant.integer(0))),
      Jump(first),
      Jump(second),
    ),
  );
  for (final (block, selected) in [(first, 8), (second, 9)]) {
    block.finish(
      Jump(loop, [
        entry.parameters[selected],
        entry.parameters[1],
        entry.parameters[2],
        Constant.integer(0),
      ]),
    );
  }
  final [pointer, value, remaining, sum] = loop.parameters;
  loop.finish(
    Branch(
      loop.emit(IntBinary(.greaterThan, remaining, Constant.integer(0))),
      Jump(invoke),
      Jump(exit),
    ),
  );
  final result = invoke.emit(NativeCall(pointer, [value]));
  invoke.finish(
    Jump(loop, [
      pointer,
      value,
      invoke.emit(IntBinary(.subtract, remaining, Constant.integer(1))),
      invoke.emit(IntBinary(.add, sum, result)),
    ]),
  );
  exit.finish(Return(sum));
  functions.add(
    IrFunction(repeated, [entry, first, second, loop, invoke, exit]),
  );
  exports[repeated] = NativeExport('repeated', repeatedExport);
  final program = IrProgram([], functions, externals: externals);
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  final caller = generator.generate(
    Compiler(generator.target).prepare(
      program,
      runtime: heapRuntime,
      roots: [...functions.map((f) => f.target), ...imports.keys],
      exports: exports,
      imports: imports,
    ),
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
          case RegisterAggregate() || IndirectArgument():
            throw StateError('Expected a scalar fixture.');
          case RegisterArgument(:final register):
            assembler.moveDouble(.d17, register as arm.FloatRegister);
          case StackArgument(:final offset):
            if (type.isSinglePrecision) {
              assembler.loadFloat(.d17, .sp, offset);
            } else {
              assembler.loadDouble(.d17, .sp, offset);
            }
        }
        if (type.isSinglePrecision) assembler.convertFloatToDouble(.d17, .d17);
      } else {
        switch (location) {
          case RegisterAggregate() || IndirectArgument():
            throw StateError('Expected a scalar fixture.');
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
        if (type is NativePointerType) {
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
    if (signature.result.isFloating) {
      assembler.moveDouble(.d0, .d16);
    } else {
      assembler.truncateDoubleToInt(.x0, .d16);
    }
  } else if (signature.result.isVoid) {
    assembler.store(.x1, .x0, 0);
  } else if (signature.parameters.single.isSinglePrecision) {
    assembler.convertFloatToDouble(.d0, .d0);
  } else if (signature.result.isSinglePrecision) {
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
  for (final register in layout.clobberedRegisters) {
    if (register == layout.resultRegister || register == arm.Register.x30) {
      continue;
    }
    switch (register) {
      case arm.Register():
        assembler.loadImmediate(register, 0);
      case arm.FloatRegister():
        assembler.moveBitsToDouble(register, .x17);
    }
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
          case RegisterAggregate() || IndirectArgument():
            throw StateError('Expected a scalar fixture.');
          case RegisterArgument(:final register):
            assembler.moveDouble(.xmm15, register as x64.FloatRegister);
          case StackArgument(:final offset):
            if (type.isSinglePrecision) {
              assembler.loadFloat(.xmm15, .rsp, offset + 8);
            } else {
              assembler.loadDouble(.xmm15, .rsp, offset + 8);
            }
        }
        if (type.isSinglePrecision) {
          assembler.convertFloatToDouble(.xmm15, .xmm15);
        }
      } else {
        switch (location) {
          case RegisterAggregate() || IndirectArgument():
            throw StateError('Expected a scalar fixture.');
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
        if (type is NativePointerType) {
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
    if (signature.result.isFloating) {
      assembler.moveDouble(.xmm0, .xmm14);
    } else {
      assembler.truncateDoubleToInt(.rax, .xmm14);
    }
  } else if (signature.result.isVoid) {
    assembler.store(.rsi, .rdi, 0);
  } else if (signature.parameters.single.isSinglePrecision) {
    assembler.convertFloatToDouble(.xmm0, .xmm0);
  } else if (signature.result.isSinglePrecision) {
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
  for (final register in layout.clobberedRegisters) {
    if (register == layout.resultRegister) continue;
    switch (register) {
      case x64.Register():
        assembler.loadImmediate(register, 0);
      case x64.FloatRegister():
        assembler.moveBitsToDouble(register, .r11);
    }
  }
  assembler.ret();
  return assembler.finish();
}
