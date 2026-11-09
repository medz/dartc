import 'dart:typed_data';

import 'package:dartc/ir.dart';

import 'function_allocation.dart';
import 'function_emitter.dart';

/// Generates an integer/boolean control-flow graph with explicit edge transfers.
final class IntegerFunction<R extends Object>(
  final FunctionEmitter<R> emitter,
) {
  /// Emits the body and reports direct call sites to the module generator.
  Uint8List generate(
    IrFunction function,
    void Function(int, FunctionTarget) call,
  ) {
    final abi = emitter.convention;
    if (function.bodyKind != .synchronous ||
        function.target.kind.hasReceiver ||
        function.target.kind == .closure ||
        function.target.typeParameters.isNotEmpty ||
        function.target.signature.optionalSlots.isNotEmpty ||
        function.target.signature.namedParameters.isNotEmpty ||
        !_word(function.target.returnType) ||
        function.target.parameterTypes.any((type) => !_word(type)) ||
        function.entry.parameters.length > abi.parameters.length) {
      throw UnsupportedError(
        'Native scalar signature: ${function.target.name}',
      );
    }
    final allocation = FunctionAllocation(function, emitter);
    final positions = <Block, int>{};
    final jumps = <(int, Block)>[], localJumps = <(int, int)>[];
    if (allocation.framed) abi.enterFrame(allocation.frameBytes);
    allocation.initialize();
    void edge(Jump jump) {
      allocation.copyArguments(jump);
      jumps.add((emitter.jump(), jump.target));
    }

    for (final block in function.blocks) {
      positions[block] = emitter.position;
      allocation.begin(block);
      for (final instruction in block.instructions) {
        switch (instruction) {
          case DirectCall(:final inputs, :final type, :final typeArguments):
            if (!_word(type) ||
                typeArguments.isNotEmpty ||
                inputs.length > abi.parameters.length ||
                inputs.any((v) => !_word(v.type))) {
              throw UnsupportedError(
                'Native call requires register scalar arguments.',
              );
            }
            allocation.flush();
            for (final (i, value) in inputs.indexed) {
              allocation.load(value, abi.parameters[i]);
              allocation.release(value);
            }
            call(emitter.call(), instruction.target);
            allocation.define(instruction, abi.result);
          case IntBinary(:final operator, :final left, :final right):
            final a = allocation.read(left),
                b = allocation.read(right, except: a);
            allocation.release(left);
            allocation.release(right);
            final destination = allocation.allocate();
            switch (operator) {
              case .add:
                emitter.add(destination, a, b);
              case .subtract:
                emitter.subtract(destination, a, b);
              case .lessThan:
                emitter.compare(destination, a, b, .lessThan);
              case .lessOrEqual:
                emitter.compare(destination, a, b, .lessOrEqual);
              case .greaterThan:
                emitter.compare(destination, a, b, .greaterThan);
              case .greaterOrEqual:
                emitter.compare(destination, a, b, .greaterOrEqual);
              default:
                throw UnsupportedError('Native integer operation: $operator');
            }
            allocation.define(instruction, destination);
          case Equals(:final left, :final right, :final negated):
            if (!_word(left.type) || !_word(right.type)) {
              throw UnsupportedError(
                'Native equality requires integer or boolean operands.',
              );
            }
            final a = allocation.read(left),
                b = allocation.read(right, except: a);
            allocation.release(left);
            allocation.release(right);
            final destination = allocation.allocate();
            if (left.type == right.type) {
              emitter.compare(destination, a, b, negated ? .notEqual : .equal);
            } else {
              emitter.loadImmediate(destination, negated ? 1 : 0);
            }
            allocation.define(instruction, destination);
          default:
            throw UnsupportedError(
              'Native operation: ${instruction.runtimeType}',
            );
        }
      }
      switch (block.end) {
        case Return(value: final result?):
          final value = allocation.read(result);
          if (allocation.framed) abi.leaveFrame(allocation.frameBytes);
          abi.returnValue(value);
        case final Jump jump:
          if (jump.arguments.isNotEmpty) allocation.flush();
          edge(jump);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          final value = allocation.read(condition);
          if (ifTrue.arguments.isNotEmpty || ifFalse.arguments.isNotEmpty) {
            allocation.flush();
          }
          final falseJump = emitter.jumpIfZero(value);
          edge(ifTrue);
          localJumps.add((falseJump, emitter.position));
          edge(ifFalse);
        default:
          throw UnsupportedError('Native terminator: ${block.end.runtimeType}');
      }
    }
    final code = emitter.takeBytes(), data = ByteData.sublistView(code);
    for (final (offset, target) in jumps) {
      emitter.patchJump(data, offset, positions[target]!);
    }
    for (final (offset, target) in localJumps) {
      emitter.patchJump(data, offset, target);
    }
    return code;
  }

  bool _word(ValueType type) => type == .integer || type == .boolean;
}
