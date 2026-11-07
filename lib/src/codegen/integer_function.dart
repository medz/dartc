import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';

/// Allocates caller-saved registers while emitting one straight-line function.
final class IntegerFunction<R extends Object>(final IntegerAbi<R> abi) {
  final _uses = <Value, int>{};
  final _registers = <Value, R>{};
  final _free = <R>[];

  /// Emits integer constants, addition, subtraction and a final return.
  Uint8List generate(IrFunction function) {
    if (function.bodyKind != .synchronous ||
        function.blocks.length != 1 ||
        function.target.typeParameters.isNotEmpty ||
        function.target.signature.optionalSlots.isNotEmpty ||
        function.target.signature.namedParameters.isNotEmpty ||
        function.target.returnType != .integer ||
        function.target.parameterTypes.any((type) => type != .integer) ||
        function.entry.parameters.length > abi.parameters.length) {
      throw UnsupportedError(
        'Native integer leaf signature or control flow: ${function.target.name}',
      );
    }
    final block = function.entry;
    if (block.end case Return(value: final result?)) {
      for (final instruction in block.instructions) {
        if (instruction is! IntBinary ||
            instruction.operator != .add && instruction.operator != .subtract) {
          throw UnsupportedError(
            'Native operation: ${instruction.runtimeType}',
          );
        }
        for (final value in instruction.inputs) {
          _uses.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      _uses.update(result, (n) => n + 1, ifAbsent: () => 1);
      _free.addAll(abi.temporaries);
      for (final (i, parameter) in block.parameters.indexed) {
        if (_uses.containsKey(parameter)) {
          _registers[parameter] = abi.parameters[i];
          _free.remove(abi.parameters[i]);
        }
      }
      for (final instruction in block.instructions.cast<IntBinary>()) {
        final left = _register(instruction.left),
            right = _register(instruction.right);
        final destination = _allocate();
        if (instruction.operator == .add) {
          abi.add(destination, left, right);
        } else {
          abi.subtract(destination, left, right);
        }
        _release(instruction.left);
        _release(instruction.right);
        if (_uses.containsKey(instruction)) {
          _registers[instruction] = destination;
        } else {
          _free.add(destination);
        }
      }
      abi.returnValue(_register(result));
      return abi.takeBytes();
    }
    throw UnsupportedError('Native function requires an integer return.');
  }

  R _register(Value value) {
    if (_registers[value] case final register?) return register;
    if (value case ScalarConstant(value: final int number)) {
      final register = _allocate();
      abi.loadImmediate(register, number);
      return _registers[value] = register;
    }
    throw StateError('Missing register for $value');
  }

  R _allocate() {
    // shortcut: no spill slots, upgrade when the backend gains stack frames.
    if (_free.isEmpty) {
      throw UnsupportedError(
        'Native register pressure requires stack allocation.',
      );
    }
    return _free.removeLast();
  }

  void _release(Value value) {
    final count = _uses[value]! - 1;
    _uses[value] = count;
    if (count == 0) _free.add(_registers.remove(value)!);
  }
}
