import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

import 'function_allocation.dart';
import 'function_emitter.dart';
import 'function_selection.dart';

/// Generates a scalar control-flow graph with explicit edge transfers.
final class ScalarFunction<R extends Object>(final FunctionEmitter<R> emitter) {
  /// Emits the body and reports direct call sites to the module generator.
  Uint8List generate(
    IrFunction function,
    void Function(Fixup, FunctionTarget) call,
  ) {
    final selection = FunctionSelection(function, emitter);
    final allocation = FunctionAllocation(function, emitter, selection);
    final labels = {
      for (final block in function.blocks) block: emitter.label(),
    };
    if (allocation.frame case final frame?) emitter.prologue(frame);
    allocation.initialize();
    void edge(Jump jump) {
      allocation.copyArguments(jump);
      emitter.jump(labels[jump.target]!);
    }

    for (final block in function.blocks) {
      emitter.bind(labels[block]!);
      allocation.begin(block);
      for (final instruction in block.instructions) {
        if (instruction case final DirectCall callInstruction) {
          final layout = selection.calls[callInstruction]!;
          allocation.flush(clobbered: layout.clobberedRegisters);
          // Stage stack words before populating registers that the scratch may alias.
          if (layout.stackBytes != 0) {
            for (final (i, location) in layout.parameters.indexed) {
              if (location case StackArgument(:final offset)) {
                final value = instruction.inputs[i];
                final scratch = emitter.allocatableRegisters.firstWhere(
                  (r) =>
                      emitter.bank(r) == selection.bank(value.type) &&
                      layout.clobberedRegisters.contains(r),
                );
                allocation.load(value, scratch);
                emitter.storeStack(scratch, offset);
                allocation.release(value);
              }
            }
          }
          // Double constants may need a general temporary before fixed general arguments.
          for (final bank in [RegisterBank.floating, RegisterBank.general]) {
            for (final (i, location) in layout.parameters.indexed) {
              if (location case RegisterArgument(:final register)
                  when emitter.bank(register) == bank) {
                final value = instruction.inputs[i];
                allocation.load(value, register);
                allocation.release(value);
              }
            }
          }
          call(emitter.call(), callInstruction.target);
          if (layout.result case final result?) {
            allocation.define(instruction, result);
          }
        } else if (instruction case StoreNativeInteger(
          :final pointer,
          :final value,
        )) {
          final base = allocation.read(pointer),
              source = allocation.read(value, except: [base]);
          final layout = FfiTypes.pointerElement(pointer.type)!.integerLayout!;
          emitter.storeMemory(source, base, bytes: layout.bytes);
          allocation.release(pointer);
          allocation.release(value);
        } else if (instruction
            case PointerFromAddress(address: final operand) ||
                PointerAddress(pointer: final operand) ||
                LoadNativeInteger(pointer: final operand)) {
          final source = allocation.read(operand);
          allocation.release(operand);
          final destination = allocation.allocate(.general, preferred: source);
          if (instruction is LoadNativeInteger) {
            final layout = FfiTypes.pointerElement(operand.type)!
                .integerLayout!;
            emitter.loadMemory(
              destination,
              source,
              bytes: layout.bytes,
              signed: layout.signed,
            );
          } else {
            emitter.move(destination, source);
          }
          allocation.define(instruction, destination);
        } else if (instruction case NumericToDouble(:final operand)) {
          final source = allocation.read(operand);
          allocation.release(operand);
          final destination = allocation.allocate(.floating, preferred: source);
          if (operand.type == .integer) {
            emitter.convertIntToDouble(destination, source);
          } else {
            emitter.move(destination, source);
          }
          allocation.define(instruction, destination);
        } else if (instruction case NumericNegate(:final operand)) {
          final source = allocation.read(operand);
          allocation.release(operand);
          final destination = allocation.allocate(.floating, preferred: source);
          final temporary = emitter.negationNeedsTemporary
              ? allocation.allocate(.general)
              : null;
          emitter.negateDouble(destination, source, temporary);
          if (temporary != null) allocation.releaseTemporary(temporary);
          allocation.define(instruction, destination);
        } else if (selection.mixedComparisons[instruction]
            case final selected?) {
          final integer = allocation.read(selected.integer);
          final floating = allocation.read(
            selected.floating,
            except: [integer],
          );
          final destination = allocation.allocate(.general, except: [integer]);
          final temporary = allocation.allocate(.general, except: [integer]);
          final converted = allocation.allocate(.floating, except: [floating]);
          _mixedComparison(
            selected.comparison,
            destination,
            integer,
            floating,
            temporary,
            converted,
          );
          allocation.release(selected.integer);
          allocation.release(selected.floating);
          allocation.releaseTemporary(temporary);
          allocation.releaseTemporary(converted);
          allocation.define(instruction, destination);
        } else {
          final (:encoding, :left, :right, :floatingInputs) =
              selection.binaries[instruction]!;
          var a = allocation.read(left),
              b = allocation.read(right, except: [a]);
          final temporaries = <R>[];
          R convert(Value value, R register) {
            if (!floatingInputs || value.type == .floating) return register;
            final temporary = allocation.allocate(.floating, except: [a, b]);
            emitter.convertIntToDouble(temporary, register);
            temporaries.add(temporary);
            return temporary;
          }

          a = convert(left, a);
          b = convert(right, b);
          allocation.release(left);
          allocation.release(right);
          temporaries.forEach(allocation.releaseTemporary);
          final destination = encoding.reuseLeft
              ? allocation.allocate(
                  selection.bank(instruction.type),
                  preferred: a,
                  except: a == b ? [] : [b],
                )
              : allocation.allocate(selection.bank(instruction.type));
          if (encoding.reuseLeft) emitter.move(destination, a);
          encoding.emit(destination, encoding.reuseLeft ? destination : a, b);
          allocation.define(instruction, destination);
        }
      }
      switch (block.end) {
        case Return(:final value):
          if (selection.entry.result case final result?) {
            emitter.move(result, allocation.read(value!));
          }
          if (allocation.frame case final frame?) {
            emitter.epilogue(frame);
          } else {
            emitter.ret();
          }
        case final Jump jump:
          if (jump.arguments.isNotEmpty) allocation.flush();
          edge(jump);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          final value = allocation.read(condition);
          if (ifTrue.arguments.isNotEmpty || ifFalse.arguments.isNotEmpty) {
            allocation.flush();
          }
          final otherwise = emitter.label();
          emitter.jumpIfZero(value, otherwise);
          edge(ifTrue);
          emitter.bind(otherwise);
          edge(ifFalse);
        default:
          throw UnsupportedError('Native terminator: ${block.end.runtimeType}');
      }
    }
    return emitter.finish();
  }

  void _mixedComparison(
    Comparison comparison,
    R destination,
    R integer,
    R floating,
    R temporary,
    R converted,
  ) {
    final yes = emitter.label(), no = emitter.label(), done = emitter.label();
    final less = switch (comparison) {
      .notEqual || .lessThan || .lessOrEqual => yes,
      _ => no,
    };
    final greater = switch (comparison) {
      .notEqual || .greaterThan || .greaterOrEqual => yes,
      _ => no,
    };
    final equal = switch (comparison) {
      .equal || .lessOrEqual || .greaterOrEqual => yes,
      _ => no,
    };
    void branch(
      Comparison relation,
      R left,
      R right,
      Label target, {
      bool doubleInputs = false,
    }) {
      final next = emitter.label();
      emitter
          .comparison(relation, floating: doubleInputs)
          .emit(destination, left, right);
      emitter.jumpIfZero(destination, next);
      emitter.jump(target);
      emitter.bind(next);
    }

    emitter.convertIntToDouble(converted, integer);
    branch(.lessThan, converted, floating, less, doubleInputs: true);
    branch(.greaterThan, converted, floating, greater, doubleInputs: true);
    branch(
      .notEqual,
      converted,
      floating,
      comparison == .notEqual ? yes : no,
      doubleInputs: true,
    );
    // Rounded equality needs the original integer; exclude 2^63 before truncation.
    emitter.move(temporary, floating);
    emitter.loadImmediate(destination, 0x43e0000000000000);
    branch(.equal, temporary, destination, less);
    emitter.truncateDoubleToInt(temporary, floating);
    branch(.lessThan, integer, temporary, less);
    branch(.greaterThan, integer, temporary, greater);
    emitter.jump(equal);
    emitter.bind(yes);
    emitter.loadImmediate(destination, 1);
    emitter.jump(done);
    emitter.bind(no);
    emitter.loadImmediate(destination, 0);
    emitter.bind(done);
  }
}
