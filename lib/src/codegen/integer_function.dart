import 'dart:typed_data';

import 'package:dartc/ir.dart';

import 'function_emitter.dart';

/// Allocates registers and spill slots for a straight-line integer function.
final class IntegerFunction<R extends Object>(
  final FunctionEmitter<R> emitter,
) {
  final _uses = <Value, int>{};
  final _registers = <Value, R>{};
  final _slots = <Value, int>{};
  final _spilled = <Value>{};
  final _free = <R>[];

  /// Emits the body and reports direct call sites to the module generator.
  Uint8List generate(
    IrFunction function,
    void Function(int, FunctionTarget) call,
  ) {
    final abi = emitter.convention;
    if (function.bodyKind != .synchronous ||
        function.blocks.length != 1 ||
        function.target.kind.hasReceiver ||
        function.target.kind == .closure ||
        function.target.typeParameters.isNotEmpty ||
        function.target.signature.optionalSlots.isNotEmpty ||
        function.target.signature.namedParameters.isNotEmpty ||
        function.target.returnType != .integer ||
        function.target.parameterTypes.any((type) => type != .integer) ||
        function.entry.parameters.length > abi.parameters.length) {
      throw UnsupportedError(
        'Native integer signature or control flow: ${function.target.name}',
      );
    }
    final block = function.entry;
    if (block.end case Return(value: final result?)) {
      var hasCall = false;
      for (final instruction in block.instructions) {
        switch (instruction) {
          case IntBinary(operator: .add || .subtract):
            break;
          case DirectCall(:final inputs, :final type, :final typeArguments):
            if (type != .integer ||
                typeArguments.isNotEmpty ||
                inputs.length > abi.parameters.length ||
                inputs.any((v) => v.type != .integer)) {
              throw UnsupportedError(
                'Native call requires register integer arguments.',
              );
            }
            hasCall = true;
          default:
            throw UnsupportedError(
              'Native operation: ${instruction.runtimeType}',
            );
        }
        for (final value in instruction.inputs) {
          _uses.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      _uses.update(result, (n) => n + 1, ifAbsent: () => 1);
      final values = [...block.parameters, ...block.instructions];
      final framed = hasCall || _uses.length > abi.callerSaved.length;
      if (framed) {
        for (final value in values) {
          if (_uses.containsKey(value)) _slots[value] = _slots.length * 8;
        }
      }
      final frameBytes = (_slots.length * 8 + 15) & ~15;
      if (framed) abi.enterFrame(frameBytes);
      _free.addAll(abi.callerSaved);
      for (final (i, parameter) in block.parameters.indexed) {
        if (_uses.containsKey(parameter)) {
          _registers[parameter] = abi.parameters[i];
          _free.remove(abi.parameters[i]);
        }
      }
      for (final instruction in block.instructions) {
        if (instruction is DirectCall) {
          // Spill before assigning arguments so permutations cannot clobber inputs.
          for (final entry in _registers.entries) {
            _spill(entry.key, entry.value);
          }
          _registers.clear();
          _free
            ..clear()
            ..addAll(abi.callerSaved);
          for (final (i, value) in instruction.inputs.indexed) {
            _load(value, abi.parameters[i]);
            _release(value);
          }
          call(emitter.call(), instruction.target);
          if (_uses.containsKey(instruction)) {
            _registers[instruction] = abi.result;
            _free.remove(abi.result);
          }
        } else if (instruction is IntBinary) {
          final left = _register(instruction.left);
          final right = _register(instruction.right, except: left);
          _release(instruction.left);
          _release(instruction.right);
          final destination = _allocate();
          if (instruction.operator == .add) {
            emitter.add(destination, left, right);
          } else {
            emitter.subtract(destination, left, right);
          }
          if (_uses.containsKey(instruction)) {
            _registers[instruction] = destination;
          } else {
            _free.add(destination);
          }
        }
      }
      final value = _register(result);
      if (framed) abi.leaveFrame(frameBytes);
      abi.returnValue(value);
      return emitter.takeBytes();
    }
    throw UnsupportedError('Native function requires an integer return.');
  }

  R _register(Value value, {R? except}) {
    if (_registers[value] case final register?) return register;
    final register = _allocate(except: except);
    _load(value, register);
    return _registers[value] = register;
  }

  void _load(Value value, R destination) {
    if (value case ScalarConstant(value: final int number)) {
      emitter.loadImmediate(destination, number);
    } else if (_spilled.contains(value)) {
      emitter.loadStack(destination, _slots[value]!);
    } else {
      throw StateError('Missing native value: $value');
    }
  }

  R _allocate({R? except}) {
    if (_free.isNotEmpty) return _free.removeLast();
    final entry = _registers.entries.firstWhere((e) => e.value != except);
    _spill(entry.key, entry.value);
    _registers.remove(entry.key);
    return entry.value;
  }

  void _spill(Value value, R register) {
    if (value is ScalarConstant || !_spilled.add(value)) return;
    emitter.storeStack(register, _slots[value]!);
  }

  void _release(Value value) {
    final count = _uses[value]! - 1;
    if (count == 0) {
      _uses.remove(value);
      if (_registers.remove(value) case final register?) _free.add(register);
    } else {
      _uses[value] = count;
    }
  }
}
