import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart' show ScalarConstant;

import 'function_emitter.dart';
import 'heap_entry.dart';
import 'native_callback.dart';

/// Converts native scalar and aggregate calls to internal value locations.
final class NativeAdapter<R extends Object>(final FunctionEmitter<R> emitter) {
  /// Emits an incoming or outgoing native boundary and reports its direct call.
  Uint8List generate(
    NativeSignature signature,
    void Function(Fixup, int, FrameLayout<R>) call, {
    required bool intoDart,
    HeapEntry<R>? heap,
    void Function(Fixup, int)? codeAddress,
    void Function(int, FrameLayout<R>)? indirectCall,
    NativeCallback<R>? callback,
  }) {
    if (callback != null && !intoDart) {
      throw ArgumentError('A callback requires an incoming native boundary.');
    }
    signature = NativeSignature.types(
      signature.result.resolveAbi(emitter.convention.target.abi),
      signature.parameters.map(
        (type) => type.resolveAbi(emitter.convention.target.abi),
      ),
    );
    if (callback != null ||
        indirectCall != null ||
        signature.result is NativeCompoundType ||
        signature.parameters.any((type) => type is NativeCompoundType)) {
      return _aggregate(
        signature,
        call,
        intoDart: intoDart,
        heap: heap,
        codeAddress: codeAddress,
        indirectCall: indirectCall,
        callback: callback,
      );
    }
    final native = emitter.convention.classify(signature);
    NativeTypeRef fullWidth(NativeTypeRef type) => type.isFloating
        ? NativeScalarType(Double)
        : type.integerLayout != null
        ? NativeScalarType(Int64)
        : type;
    final body = emitter.convention.classify(
      NativeSignature.types(
        signature.result.isVoid
            ? NativePointerType(NativeScalarType(Void))
            : fullWidth(signature.result),
        signature.parameters.map(fullWidth),
      ),
    );
    final (source, destination) = intoDart ? (native, body) : (body, native);
    final frame = intoDart && heap != null
        ? heap.frame(destination.stackBytes)
        : emitter.convention.frameLayout(
            localBytes: 0,
            localAlignment: 8,
            savedRegisters: [],
            outgoingStackBytes: destination.stackBytes,
          );
    emitter.prologue(frame);
    if (intoDart) heap?.enter(frame);
    for (final (i, location) in source.parameters.indexed) {
      final type = signature.parameters[i];
      final integer = type.integerLayout;
      switch (location) {
        case RegisterAggregate() || IndirectArgument():
          throw StateError('Aggregate calls require storage conversion.');
        case RegisterArgument(:final register):
          convert(register, type, intoDart: intoDart);
        case StackArgument(:final offset):
          final scratch = emitter.allocatableRegisters.lastWhere(
            (r) =>
                emitter.bank(r) ==
                    (type.isFloating
                        ? RegisterBank.floating
                        : RegisterBank.general) &&
                destination.clobberedRegisters.contains(r) &&
                !source.parameters.any(
                  (p) => p is RegisterArgument<R> && p.register == r,
                ),
          );
          emitter.loadStack(
            scratch,
            frame.incomingStackOffset + offset,
            bytes: intoDart ? type.nativeSize : 8,
            signed: intoDart && (integer?.signed ?? false),
          );
          if (type.isSinglePrecision) {
            convert(scratch, type, intoDart: intoDart);
          }
          emitter.storeStack(
            scratch,
            (destination.parameters[i] as StackArgument<R>).offset,
            bytes: intoDart ? 8 : type.nativeSize,
          );
      }
    }
    final parked = !intoDart && heap?.persistent == true
        ? HeapEntry.park(
            emitter,
            emitter.allocatableRegisters.lastWhere(
              (r) =>
                  emitter.bank(r) == .general &&
                  r != emitter.failureRegister &&
                  destination.clobberedRegisters.contains(r) &&
                  !destination.parameters.any(
                    (p) => p is RegisterArgument<R> && p.register == r,
                  ),
            ),
          )
        : const <Fixup>[];
    final fixup = emitter.call();
    call(fixup, emitter.position, frame);
    for (final address in parked) {
      codeAddress!(address, emitter.position);
    }
    if (intoDart) heap?.leave(frame, destination.resultRegister);
    if (destination.resultRegister case final result?) {
      convert(result, signature.result, intoDart: !intoDart);
    }
    if (!intoDart && signature.result.isVoid) {
      emitter.loadImmediate(body.resultRegister!, 0);
    }
    if (!intoDart && heap != null) {
      emitter.loadImmediate(emitter.failureRegister, 0);
    }
    emitter.epilogue(frame);
    return emitter.finish();
  }

  /// The internal bridge passes aggregate storage addresses and an output buffer.
  static NativeSignature bridgeSignature(NativeSignature signature) {
    NativeTypeRef word(NativeTypeRef type) =>
        type.isFloating ? NativeScalarType(Double) : NativeScalarType(Int64);
    return NativeSignature.types(word(signature.result), [
      if (signature.result is NativeCompoundType) NativeScalarType(Int64),
      ...signature.parameters.map(word),
    ]);
  }

  Uint8List _aggregate(
    NativeSignature signature,
    void Function(Fixup, int, FrameLayout<R>) call, {
    required bool intoDart,
    HeapEntry<R>? heap,
    void Function(Fixup, int)? codeAddress,
    void Function(int, FrameLayout<R>)? indirectCall,
    NativeCallback<R>? callback,
  }) {
    final storage = NativeLayout(emitter.convention.target);
    final native = emitter.convention.classify(signature);
    final bridge = bridgeSignature(signature);
    final body = emitter.convention.classify(
      indirectCall == null
          ? bridge
          : NativeSignature.types(bridge.result, [
              NativeScalarType(Int64),
              ...bridge.parameters,
            ]),
    );
    final compoundResult = signature.result is NativeCompoundType;
    final callShift = indirectCall == null ? 0 : 1;
    final shift = callShift + (compoundResult ? 1 : 0);
    final destination = intoDart ? body : native;
    var bytes = 0;
    int reserve(int size) {
      final start = bytes;
      bytes += (size + 7) & ~7;
      return start;
    }

    final slots = [
      for (final type in signature.parameters)
        reserve(type is NativeCompoundType ? storage.of(type).size : 8),
    ];
    final resultSlot = reserve(
      compoundResult ? storage.of(signature.result).size : 8,
    );
    final resultPointer = reserve(8);
    final callPointer = indirectCall == null ? null : reserve(8);
    final frame = intoDart && heap != null
        ? heap.frame(destination.stackBytes, extraBytes: bytes)
        : emitter.convention.frameLayout(
            localBytes: bytes,
            localAlignment: 8,
            savedRegisters: [],
            outgoingStackBytes: destination.stackBytes,
          );
    final base =
        frame.localOffset +
        (intoDart && heap != null ? HeapEntry.localBytes : 0);
    final occupied = {
      for (final location in [...native.parameters, ...body.parameters])
        ...location.registers,
    };
    final scratch = emitter.allocatableRegisters
        .where(
          (r) =>
              emitter.bank(r) == .general &&
              r != emitter.failureRegister &&
              destination.clobberedRegisters.contains(r) &&
              !occupied.contains(r),
        )
        .toList();
    if (scratch.length < 2) {
      throw StateError('Native aggregate bridge requires two temporaries.');
    }
    final address = scratch[0], value = scratch[1];
    final floating = emitter.allocatableRegisters.firstWhere(
      (r) =>
          emitter.bank(r) == .floating &&
          destination.clobberedRegisters.contains(r) &&
          !occupied.contains(r),
    );
    int width(int remaining) => remaining >= 8
        ? 8
        : remaining >= 4
        ? 4
        : remaining >= 2
        ? 2
        : 1;
    int registerWidth(int size) => size > 4
        ? 8
        : size > 2
        ? 4
        : size;
    void readScalar(ArgumentLocation<R> location, R register, {int size = 8}) {
      if (location case RegisterArgument(register: final source)) {
        emitter.move(register, source);
      } else {
        emitter.loadStack(
          register,
          frame.incomingStackOffset + (location as StackArgument<R>).offset,
          bytes: size,
        );
      }
    }

    void writeScalar(ArgumentLocation<R> location, R register, {int size = 8}) {
      if (location case RegisterArgument(register: final output)) {
        emitter.move(output, register);
      } else {
        emitter.storeStack(
          register,
          (location as StackArgument<R>).offset,
          bytes: size,
        );
      }
    }

    void copyToStack(R pointer, int offset, int size) {
      for (var i = 0; i < size;) {
        final count = width(size - i);
        emitter.loadMemory(
          value,
          pointer,
          offset: i,
          bytes: count,
          signed: false,
        );
        emitter.storeStack(value, offset + i, bytes: count);
        i += count;
      }
    }

    void copyFromStack(int offset, R pointer, int size) {
      for (var i = 0; i < size;) {
        final count = width(size - i);
        emitter.loadStack(value, offset + i, bytes: count);
        emitter.storeMemory(value, pointer, offset: i, bytes: count);
        i += count;
      }
    }

    emitter.prologue(frame);
    if (callPointer != null) {
      readScalar(body.parameters.first, address);
      emitter.storeStack(address, base + callPointer);
    }
    if (compoundResult) {
      final location = intoDart ? native.result : body.parameters[callShift];
      if (location is IndirectArgument<R> || !intoDart) {
        readScalar(
          location is IndirectArgument<R> ? location.pointer : location!,
          address,
        );
        emitter.storeStack(address, base + resultPointer);
      }
    }
    // Snapshot incoming registers before argument remapping or heap entry can clobber them.
    for (final (i, type) in signature.parameters.indexed) {
      final location = intoDart
          ? native.parameters[i]
          : body.parameters[i + shift];
      final slot = base + slots[i];
      if (intoDart && type is NativeCompoundType) {
        if (location case RegisterAggregate(:final parts)) {
          for (final part in parts) {
            emitter.storeStack(
              part.register,
              slot + part.offset,
              bytes: registerWidth(part.size),
            );
          }
        } else if (location case IndirectArgument(:final pointer)) {
          readScalar(pointer, address);
          copyToStack(address, slot, storage.of(type).size);
        } else {
          emitter.stackAddress(
            address,
            frame.incomingStackOffset + (location as StackArgument<R>).offset,
          );
          copyToStack(address, slot, storage.of(type).size);
        }
      } else {
        final register = type.isFloating ? floating : address;
        readScalar(location, register, size: intoDart ? type.nativeSize : 8);
        emitter.storeStack(register, slot);
      }
    }
    callback?.checkThread();
    if (intoDart) heap?.enter(frame);
    if (!intoDart) {
      for (final (i, type) in signature.parameters.indexed) {
        if (type is NativeCompoundType) {
          emitter.loadStack(address, base + slots[i]);
          copyToStack(address, base + slots[i], storage.of(type).size);
        }
      }
    }
    // Root publication may clobber the native hidden result-address register.
    final parked = !intoDart && heap?.persistent == true
        ? HeapEntry.park(emitter, address)
        : const <Fixup>[];
    if (compoundResult) {
      if (intoDart) {
        emitter.stackAddress(address, base + resultSlot);
        writeScalar(body.parameters.first, address);
      } else if (native.result case IndirectArgument(:final pointer)) {
        emitter.loadStack(address, base + resultPointer);
        writeScalar(pointer, address);
      }
    }
    for (final (i, type) in signature.parameters.indexed) {
      final location = intoDart
          ? body.parameters[i + shift]
          : native.parameters[i];
      final slot = base + slots[i];
      if (type is NativeCompoundType) {
        if (intoDart || location is IndirectArgument<R>) {
          emitter.stackAddress(address, slot);
          writeScalar(
            location is IndirectArgument<R> ? location.pointer : location,
            address,
          );
        } else if (location case RegisterAggregate(:final parts)) {
          for (final part in parts) {
            emitter.loadStack(
              part.register,
              slot + part.offset,
              bytes: registerWidth(part.size),
            );
          }
        } else {
          emitter.stackAddress(address, slot);
          copyToStack(
            address,
            (location as StackArgument<R>).offset,
            storage.of(type).size,
          );
        }
      } else {
        final register = type.isFloating ? floating : address;
        emitter.loadStack(register, slot);
        convert(register, type, intoDart: intoDart);
        writeScalar(location, register, size: intoDart ? 8 : type.nativeSize);
      }
    }
    if (indirectCall == null) {
      call(emitter.call(), emitter.position, frame);
    } else {
      emitter.loadStack(address, base + callPointer!);
      emitter.callRegister(address);
      indirectCall(emitter.position, frame);
    }
    for (final fixup in parked) {
      codeAddress!(fixup, emitter.position);
    }
    if (callback != null) {
      final returned = emitter.label();
      emitter.jumpIfZero(emitter.failureRegister, returned);
      if (compoundResult) {
        emitter.loadImmediate(address, 0);
        for (var offset = 0; offset < storage.of(signature.result).size;) {
          final count = width(storage.of(signature.result).size - offset);
          emitter.storeStack(address, base + resultSlot + offset, bytes: count);
          offset += count;
        }
      } else if (!signature.result.isVoid) {
        final value =
            (callback.definition.exceptionalReturn as ScalarConstant?)?.value;
        final bits = switch (value) {
          double() => (ByteData(8)..setFloat64(0, value)).getInt64(0),
          int() => value,
          bool() => value ? 1 : 0,
          _ => 0,
        };
        emitter.loadImmediate(address, bits);
        emitter.move(body.resultRegister!, address);
      }
      emitter.loadImmediate(emitter.failureRegister, 0);
      emitter.bind(returned);
    }
    if (intoDart) heap?.leave(frame, body.resultRegister);
    if (compoundResult) {
      final size = storage.of(signature.result).size;
      if (intoDart) {
        if (native.result case RegisterAggregate(:final parts)) {
          for (final part in parts) {
            emitter.loadStack(
              part.register,
              base + resultSlot + part.offset,
              bytes: registerWidth(part.size),
            );
          }
        } else if (native.result case IndirectArgument(
          :final returnedAddress,
        )) {
          emitter.loadStack(address, base + resultPointer);
          copyFromStack(base + resultSlot, address, size);
          if (returnedAddress != null) emitter.move(returnedAddress, address);
        }
      } else {
        if (native.result case RegisterAggregate(:final parts)) {
          for (final part in parts) {
            emitter.storeStack(
              part.register,
              base + resultSlot + part.offset,
              bytes: registerWidth(part.size),
            );
          }
          emitter.loadStack(address, base + resultPointer);
          copyFromStack(base + resultSlot, address, size);
        }
        emitter.loadImmediate(body.resultRegister!, 0);
      }
    } else if (!signature.result.isVoid) {
      convert(
        (intoDart ? body : native).resultRegister!,
        signature.result,
        intoDart: !intoDart,
      );
    } else if (!intoDart) {
      emitter.loadImmediate(body.resultRegister!, 0);
    }
    if (!intoDart && heap != null) {
      emitter.loadImmediate(emitter.failureRegister, 0);
    }
    emitter.epilogue(frame);
    return emitter.finish();
  }

  /// Converts one scalar in place at a native call boundary.
  void convert(R register, NativeTypeRef type, {required bool intoDart}) {
    type = type.resolveAbi(emitter.convention.target.abi);
    if (type.integerLayout case final integer? when integer.bytes < 8) {
      emitter.extendInteger(
        register,
        bytes: integer.bytes,
        signed: integer.signed,
      );
    }
    if (type.isBoolean && intoDart) {
      final done = emitter.label();
      emitter.jumpIfZero(register, done);
      emitter.loadImmediate(register, 1);
      emitter.bind(done);
    } else if (type.isSinglePrecision) {
      if (intoDart) {
        emitter.convertFloatToDouble(register, register);
      } else {
        emitter.convertDoubleToFloat(register, register);
      }
    }
  }
}
