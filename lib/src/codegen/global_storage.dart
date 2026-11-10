import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'function_emitter.dart';

/// Generates lazy scalar bindings in module-owned zero-filled storage.
final class GlobalStorage(Iterable<IrFunction> input, {IrCallable? lateError}) {
  final IrCallable? _lateError = lateError;
  static final _uri = Uri.parse('dartc:globals');
  static final _wordPointer = FfiTypes.resolve(
    NativePointerType(NativeScalarType(Int64)),
  );
  static final _doublePointer = FfiTypes.resolve(
    NativePointerType(NativeScalarType(Double)),
  );
  final _getters = <GlobalVariable, IrFunction>{};
  final _setters = <GlobalVariable, IrFunction>{};

  /// The internal primitive returning the address of the first storage record.
  final FunctionTarget address = .new(_uri, 'address', .integer, []);

  this {
    final globals = {for (final function in input) ...function.globals};
    for (final global in globals) {
      if (global.type != .integer &&
          global.type != .floating &&
          global.type != .boolean) {
        throw UnsupportedError(
          'Native global storage requires int, double or bool: '
          '${global.library} ${global.owner?.name ?? ''}.${global.name}.',
        );
      }
      if ((global.isFinal || global.initializer == null) && lateError == null) {
        throw UnsupportedError(
          'Native final/late global storage requires the unnamed SDK '
          'dart:_internal LateError constructor: '
          '${global.library} ${global.owner?.name ?? ''}.${global.name}.',
        );
      }
    }
    for (final global in globals) {
      final index = _getters.length;
      final setter = _setter(global, index);
      _setters[global] = setter;
      _getters[global] = _getter(global, index, setter.target);
    }
  }

  bool get isEmpty => _getters.isEmpty;

  /// Each record contains the value bits followed by an independent bound word.
  int get bytes => _getters.length * 16;

  Iterable<IrFunction> get functions =>
      _getters.values.followedBy(_setters.values);

  FunctionTarget? callFor(Instruction instruction) => switch (instruction) {
    LoadGlobal(:final global) => _getters[global]?.target,
    StoreGlobal(:final global) => _setters[global]?.target,
    _ => null,
  };

  Uint8List emitAddress<R extends Object>(
    FunctionEmitter<R> emitter,
    void Function(Fixup) storage,
  ) {
    final result = emitter.convention.classify(NativeSignature(Int64, []));
    emitter.address(result.result!, storage);
    emitter.loadImmediate(emitter.failureRegister, CallStatus.returned.index);
    emitter.ret();
    return emitter.finish();
  }

  IrFunction _getter(GlobalVariable global, int index, FunctionTarget setter) {
    final target = FunctionTarget(_uri, 'get.$index', global.type, []);
    final entry = Block(), bound = Block(), initialize = Block();
    final base = entry.emit(DirectCall(address, []));
    final flag = entry.emit(
      LoadNative(_pointer(entry, base, index * 16 + 8, _wordPointer)),
    );
    entry.finish(
      Branch(
        entry.emit(Equals(flag, const Constant.integer(0))),
        Jump(initialize),
        Jump(bound),
      ),
    );
    final stored = bound.emit(
      LoadNative(_pointer(bound, base, index * 16, _pointerType(global))),
    );
    bound.finish(
      Return(
        global.type == .boolean
            ? bound.emit(Equals(stored, const Constant.integer(1)))
            : stored,
      ),
    );
    if (global.initializer case final initializer?) {
      final value = initialize.emit(DirectCall(initializer, []));
      // Commit only after success; writes by a throwing initializer survive.
      initialize.emit(DirectCall(setter, [value]));
      initialize.finish(Return(value));
    } else {
      _throwLateError(
        initialize,
        "Field '${global.name}' has not been initialized.",
      );
    }
    return IrFunction(target, [entry, bound, initialize]);
  }

  IrFunction _setter(GlobalVariable global, int index) {
    final target = FunctionTarget(_uri, 'set.$index', .voidType, [global.type]);
    final entry = Block(target.parameterTypes);
    final blocks = [entry];
    Block commit = entry;
    Value value = entry.parameters.single;
    if (global.isFinal) {
      commit = Block();
      final failed = Block();
      blocks.addAll([commit, failed]);
      final base = entry.emit(DirectCall(address, []));
      final flag = entry.emit(
        LoadNative(_pointer(entry, base, index * 16 + 8, _wordPointer)),
      );
      entry.finish(
        Branch(
          entry.emit(Equals(flag, const Constant.integer(0))),
          Jump(commit),
          Jump(failed),
        ),
      );
      _throwLateError(
        failed,
        global.initializer != null
            ? "Field '${global.name}' has been assigned during initialization."
            : "Field '${global.name}' has already been initialized.",
      );
    }
    if (global.type == .boolean) {
      final convert = commit;
      commit = Block([.integer]);
      blocks.add(commit);
      convert.finish(
        Branch(
          value,
          Jump(commit, [const Constant.integer(1)]),
          Jump(commit, [const Constant.integer(0)]),
        ),
      );
      value = commit.parameters.single;
    }
    final base = commit.emit(DirectCall(address, []));
    commit.emit(
      StoreNative(
        _pointer(commit, base, index * 16, _pointerType(global)),
        value,
      ),
    );
    commit.emit(
      StoreNative(
        _pointer(commit, base, index * 16 + 8, _wordPointer),
        const Constant.integer(1),
      ),
    );
    commit.finish(const Return());
    return IrFunction(target, blocks);
  }

  void _throwLateError(Block block, String message) {
    block.finish(
      Throw(
        block.emit(Construct(_lateError!.target, [Constant.string(message)])),
      ),
    );
  }

  static ClassType _pointerType(GlobalVariable global) =>
      global.type == .floating ? _doublePointer : _wordPointer;

  static Value _pointer(Block block, Value base, int offset, ClassType type) =>
      block.emit(
        PointerFromAddress(
          offset == 0
              ? base
              : block.emit(IntBinary(.add, base, Constant.integer(offset))),
          type,
        ),
      );
}
