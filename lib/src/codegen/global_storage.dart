import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'function_emitter.dart';
import 'program_layout.dart';

/// Generates lazy bindings in a stable, module-owned root-holder object.
final class GlobalStorage(Iterable<IrFunction> input, {IrCallable? lateError}) {
  final IrCallable? _lateError = lateError;
  static final _uri = Uri.parse('dartc:globals');
  final _type = ClassType(_uri, 'Root');
  final _getters = <GlobalVariable, IrFunction>{};
  final _setters = <GlobalVariable, IrFunction>{};
  final _fields = <GlobalVariable, (InstanceField, InstanceField)>{};

  late final IrClass declaration;

  /// The internal primitive returning the immortal root-holder object.
  late final FunctionTarget address = .new(_uri, 'address', _type, []);

  this {
    final globals = {for (final function in input) ...function.globals};
    for (final global in globals) {
      if (global.type == .voidType || global.type == .never) {
        throw UnsupportedError(
          'Native global storage requires a representable value type: '
          '${global.library} ${global.owner?.name ?? ''}.${global.name}.',
        );
      }
      if ((global.isFinal || global.isLate && global.initializer == null) &&
          lateError == null) {
        throw UnsupportedError(
          'Native final/late global storage requires the unnamed SDK '
          'dart:_internal LateError constructor: '
          '${global.library} ${global.owner?.name ?? ''}.${global.name}.',
        );
      }
      final index = _fields.length;
      _fields[global] = (
        InstanceField(_type, 'value.$index', global.type),
        InstanceField(_type, 'bound.$index', .boolean),
      );
    }
    declaration = IrClass(_type, [
      for (final (value, bound) in _fields.values) ...[value, bound],
    ]);
    for (final global in globals) {
      final index = _getters.length;
      final setter = _setter(global, index);
      _setters[global] = setter;
      _getters[global] = _getter(global, index, setter.target);
    }
  }

  bool get isEmpty => _getters.isEmpty;

  bool hasReferences(ProgramLayout layouts) =>
      declaration.fields.any((field) => layouts.isReference(field.type));

  /// Headers are relocated by the generator; null can be an already-bound value.
  Uint8List initialData(ProgramLayout layouts) {
    final storage = layouts.storageOf(_type);
    final data = Uint8List(storage.layout.size);
    final words = ByteData.sublistView(data);
    words.setUint64(ObjectHeader.sizeOffset, data.length, Endian.little);
    for (final entry in _fields.entries) {
      if (!entry.key.isLate && entry.key.initializer == null) {
        words.setUint64(storage.offsetOf(entry.value.$2), 1, Endian.little);
      }
    }
    return data;
  }

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
    final result = emitter.convention.classify(
      NativeSignature(Pointer<Void>, []),
    );
    emitter.address(result.result!, storage);
    emitter.loadImmediate(emitter.failureRegister, CallStatus.returned.index);
    emitter.ret();
    return emitter.finish();
  }

  IrFunction _getter(GlobalVariable global, int index, FunctionTarget setter) {
    final target = FunctionTarget(_uri, 'get.$index', global.type, []);
    final entry = Block();
    final base = entry.emit(DirectCall(address, []));
    final (valueField, boundField) = _fields[global]!;
    if (!global.isLate && global.initializer == null) {
      entry.finish(Return(entry.emit(LoadField(valueField, base))));
      return IrFunction(target, [entry]);
    }
    final bound = Block(), initialize = Block();
    final flag = entry.emit(LoadField(boundField, base));
    entry.finish(Branch(flag, Jump(bound), Jump(initialize)));
    bound.finish(Return(bound.emit(LoadField(valueField, base))));
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
    final (valueField, boundField) = _fields[global]!;
    final base = entry.emit(DirectCall(address, []));
    Block commit = entry;
    if (global.isFinal) {
      commit = Block();
      final failed = Block();
      blocks.addAll([commit, failed]);
      final flag = entry.emit(LoadField(boundField, base));
      entry.finish(Branch(flag, Jump(failed), Jump(commit)));
      _throwLateError(
        failed,
        global.initializer != null
            ? "Field '${global.name}' has been assigned during initialization."
            : "Field '${global.name}' has already been initialized.",
      );
    }
    commit.emit(StoreField(valueField, base, entry.parameters.single));
    commit.emit(StoreField(boundField, base, const Constant.boolean(true)));
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
}
