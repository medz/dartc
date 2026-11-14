import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/layout.dart';

import 'double_bits.dart';
import 'function_allocation.dart';
import 'function_emitter.dart';
import 'heap_entry.dart';
import 'native_adapter.dart';
import 'native_invocation.dart';
import 'scalar_binary.dart';
import 'storage_access.dart';
import 'type_values.dart';

/// Emits a completely allocated function, binding its calls and roots to PCs.
final class ScalarFunction<R extends Object>(
  final FunctionAllocation<R> allocation,
  final FunctionEmitter<R> emitter,
) {
  final selection = allocation.selection;
  final layouts = allocation.selection.layouts;

  Uint8List generate(
    void Function(Fixup, FunctionTarget) call,
    void Function(Fixup, Constant) constant,
    void Function(int, StackRoots, SourceLocation?, int?) safepoint, {
    bool failures = false,
    bool persistent = false,
    void Function(Fixup, NativeReference)? nativeAddress,
    void Function(Fixup, int)? codeAddress,
  }) {
    final adapter = NativeAdapter(emitter);
    final labels = {
      for (final block in selection.body.blocks) block: emitter.label(),
    };
    void transfers(Iterable<AllocationMove<R>> moves) {
      for (final move in moves) {
        _transfer(move, constant);
      }
    }

    void edge(Block block, Jump jump) {
      transfers(allocation.edges[(block, jump)]!);
      emitter.jump(labels[jump.target]!);
    }

    void leave() {
      if (allocation.frame case final frame?) {
        emitter.epilogue(frame);
      } else {
        emitter.ret();
      }
    }

    if (allocation.frame case final frame?) emitter.prologue(frame);
    for (final block in selection.body.blocks) {
      emitter.bind(labels[block]!);
      for (final instruction in selection.body.instructions[block]!) {
        final plan = allocation.operations[instruction];
        if (plan == null) continue;
        transfers(plan.before);
        final inputs = plan.inputs;
        final result = plan.result;
        if (selection.calls[instruction] case final selected?) {
          final native = instruction is NativeInvocation ? instruction : null;
          final parked = persistent && native != null
              ? HeapEntry.park(emitter, selected.parkRegister!)
              : const <Fixup>[];
          for (final argument in plan.arguments) {
            transfers(argument.loads);
            if (argument.nativeType case final type?) {
              adapter.convert(argument.register, type, intoDart: false);
            }
            if (argument.stackOffset case final offset?) {
              emitter.storeStack(
                argument.register,
                offset,
                bytes: argument.nativeType?.nativeSize ?? 8,
              );
            }
          }
          if (native == null) {
            call(emitter.call(), selected.target!);
          } else {
            for (final entry in selected.layout.registerInputs.entries) {
              emitter.loadImmediate(entry.key, entry.value);
            }
            emitter.callRegister(selected.addressRegister!);
          }
          for (final fixup in parked) {
            codeAddress!(fixup, emitter.position);
          }
          safepoint(
            emitter.position,
            allocation.safepoints[instruction]!,
            selection.body.sourceLocations[instruction],
            allocation.contextOffset,
          );
          if (failures && native == null) {
            final returned = emitter.label();
            emitter.jumpIfZero(emitter.failureRegister, returned);
            if (selected.onThrow case final failed?) {
              edge(block, failed);
            } else {
              leave();
            }
            emitter.bind(returned);
          }
          transfers(plan.after);
          if (selected.layout.resultRegister case final rawResult?
              when !plan.emptyResult) {
            if (instruction
                case Equals(negated: true) || TypeTest(negated: true)) {
              final scratch = plan.temporaries.single;
              emitter.loadImmediate(scratch, 1);
              emitter.bitXor.emit(rawResult, rawResult, scratch);
            }
            if (native != null) {
              adapter.convert(
                rawResult,
                native.signature.result,
                intoDart: true,
              );
            }
          }
        } else if (selection.body.aliases.contains(instruction) &&
            selection.body.inputsOf(instruction).isEmpty) {
          // The zero result below is the only selected work.
        } else if (selection.constantTests[instruction] case final value?) {
          emitter.loadImmediate(result!, value ? 1 : 0);
        } else if (instruction case NativeSymbolAddress(:final reference)) {
          emitter.address(
            result!,
            (fixup) => nativeAddress!(fixup, reference),
            indirect: true,
          );
        } else if (instruction is DoubleBits) {
          emitter.move(result!, inputs.single);
        } else if (instruction
            case ObjectRuntimeType(:final operand) ||
                ObjectHashCode(:final operand, direct: true)
            when !selection.body.aliases.contains(instruction) &&
                (instruction is ObjectHashCode || operand.type != .nullType) &&
                layouts.representation(operand.type) == .reference) {
          final done = emitter.label();
          if (instruction is ObjectRuntimeType) {
            emitter.address(
              result!,
              (fixup) => constant(fixup, layouts.types.constant(.nullType)),
            );
          } else {
            emitter.loadImmediate(result!, 0);
          }
          emitter.jumpIfZero(inputs.single, done);
          emitter.loadMemory(
            result,
            inputs.single,
            offset: instruction is ObjectRuntimeType
                ? ObjectHeader.typeOffset
                : ObjectHeader.identityHashOffset,
            bytes: 8,
            signed: false,
          );
          emitter.bind(done);
        } else if (instruction case NewCell(:final initial)
            when selection.cells.contains(instruction)) {
          final slot = allocation.homes[instruction]!.offset;
          if (initial != null) {
            emitter.storeStack(inputs.single, slot);
          } else if (plan.temporaries.isNotEmpty) {
            final scratch = plan.temporaries.single;
            emitter.loadImmediate(scratch, 0);
            emitter.storeStack(scratch, slot);
          }
        } else if (instruction is KeepAlive) {
          // Lifetime is represented by the allocation; there is no instruction.
        } else if (instruction is ReadCell &&
            !selection.body.aliases.contains(instruction)) {
          emitter.loadStack(
            result!,
            allocation.homes[instruction.cell]!.offset,
          );
        } else if (instruction case WriteCell(:final cell)
            when selection.cells.contains(cell)) {
          emitter.storeStack(inputs.single, allocation.homes[cell]!.offset);
        } else if (instruction
            case StoreField(:final field) || StorageWrite(:final field)) {
          emitter.storeMemory(
            inputs.last,
            inputs.first,
            offset: layouts.fieldOffset(field),
            bytes: 8,
          );
        } else if (instruction
            case LoadField(:final field) || StorageRead(:final field)
            when !selection.body.aliases.contains(instruction)) {
          final stored = plan.temporaries.single;
          emitter.loadMemory(
            stored,
            inputs.single,
            offset: layouts.fieldOffset(field),
            bytes: 8,
            signed: false,
          );
        } else if (instruction is ReferenceAddress ||
            instruction is ReferenceFromAddress ||
            selection.body.aliases.contains(instruction) ||
            instruction is TypeView ||
            instruction is UncheckedCast ||
            instruction is TypeReference ||
            instruction is ReifyType ||
            instruction is ObjectRuntimeType) {
          emitter.move(result!, inputs.single);
        } else if (instruction is StoreObjectReference ||
            instruction is LoadObjectReference ||
            instruction is StoreObjectData ||
            instruction is LoadObjectData ||
            instruction is StoreNative ||
            instruction is LoadNative) {
          final object =
              instruction is StoreObjectReference ||
              instruction is LoadObjectReference ||
              instruction is StoreObjectData ||
              instruction is LoadObjectData;
          final store =
              instruction is StoreObjectReference ||
              instruction is StoreObjectData ||
              instruction is StoreNative;
          final base = object ? plan.temporaries.first : inputs.first;
          if (object) {
            emitter.addScaled(base, inputs[0], inputs[1], scale: 1);
          }
          final NativeTypeRef? native = switch (instruction) {
            StoreObjectData(nativeType: final NativeTypeRef type) ||
            LoadObjectData(nativeType: final NativeTypeRef type) ||
            StoreNative(nativeType: final NativeTypeRef type) ||
            LoadNative(
              nativeType: final NativeTypeRef type,
            ) => type.resolveAbi(emitter.convention.target.abi),
            _ => null,
          };
          if (store) {
            var value = inputs.last;
            if (native?.isSinglePrecision ?? false) {
              value = plan.temporaries.last;
              emitter.convertDoubleToFloat(value, inputs.last);
            }
            emitter.storeMemory(value, base, bytes: native?.nativeSize ?? 8);
          } else {
            emitter.loadMemory(
              result!,
              base,
              bytes: native?.nativeSize ?? 8,
              signed: native?.integerLayout?.signed ?? false,
            );
            if (native?.isSinglePrecision ?? false) {
              emitter.convertFloatToDouble(result, result);
            }
          }
        } else if (instruction case FloatBitCast(:final width)) {
          final toFloat = instruction.type == .floating;
          if (!toFloat && width == 32) {
            emitter.convertDoubleToFloat(
              plan.temporaries.single,
              inputs.single,
            );
            emitter.move(result!, plan.temporaries.single);
            emitter.extendInteger(result, bytes: 4, signed: false);
          } else {
            emitter.move(result!, inputs.single);
            if (toFloat && width == 32) {
              emitter.convertFloatToDouble(result, result);
            }
          }
        } else if (instruction case NumericToInt(:final operand)) {
          if (operand.type == .integer) {
            emitter.move(result!, inputs.single);
          } else {
            emitter.truncateDoubleToInt(result!, inputs.single);
          }
        } else if (instruction
            case NumericToDouble(:final operand) ||
                NumericRoundToDouble(:final operand) ||
                NumericSquareRoot(:final operand)) {
          if (operand.type == .integer) {
            emitter.convertIntToDouble(result!, inputs.single);
          } else if (instruction is! NumericSquareRoot) {
            emitter.move(result!, inputs.single);
          }
          if (instruction is NumericSquareRoot) {
            emitter.squareRootDouble(
              result!,
              operand.type == .integer ? result : inputs.single,
            );
          }
        } else if (instruction is NumericNegate) {
          emitter.negateDouble(
            result!,
            inputs.single,
            plan.temporaries.singleOrNull,
          );
        } else if (selection.mixedComparisons[instruction]
            case final selected?) {
          _mixedComparison(
            selected.comparison,
            result!,
            inputs[0],
            inputs[1],
            plan.temporaries[0],
            plan.temporaries[1],
          );
        } else {
          final binary = selection.binaries[instruction]!;
          scalarBinaryEncoding(
            emitter,
            instruction,
            floating: binary.floatingInputs,
            comparison: binary.comparison,
            constant: binary.constant,
          ).emit(result!, inputs[0], inputs[1]);
        }
        transfers(plan.resultMoves);
        if (plan.emptyResult && result != null) {
          emitter.loadImmediate(result, 0);
        }
      }
      final end = selection.body.ends[block]!;
      final plan = allocation.terminators[block]!;
      transfers(plan.before);
      switch (end) {
        case Return():
          if (failures) {
            emitter.loadImmediate(
              emitter.failureRegister,
              CallStatus.returned.index,
            );
          }
          leave();
        case Invoke(:final onReturn):
          if (onReturn == null) {
            emitter.abort(71);
          } else {
            edge(block, onReturn);
          }
        case Throw(:final onThrow):
          if (onThrow == null) {
            emitter.loadImmediate(
              emitter.failureRegister,
              CallStatus.threw.index,
            );
            leave();
          } else {
            edge(block, onThrow);
          }
        case Unreachable():
          emitter.abort(71);
        case final Jump jump:
          edge(block, jump);
        case Branch(:final ifTrue, :final ifFalse):
          final otherwise = emitter.label();
          emitter.jumpIfZero(plan.inputs.single, otherwise);
          edge(block, ifTrue);
          emitter.bind(otherwise);
          edge(block, ifFalse);
        default:
          throw StateError('Unallocated terminator.');
      }
    }
    return emitter.finish();
  }

  void _transfer(
    AllocationMove<R> move,
    void Function(Fixup, Constant) constant,
  ) {
    void object(Constant value, R destination) =>
        emitter.address(destination, (fixup) => constant(fixup, value));
    void load(AllocationLocation<R> source, R destination) {
      switch (source) {
        case AllocationRegister(:final register):
          if (destination != register) emitter.move(destination, register);
        case AllocationStack(:final offset):
          emitter.loadStack(destination, offset);
        case AllocationConstant(value: final value):
          switch (value) {
            case ScalarConstant(value: final int number):
              emitter.loadImmediate(destination, number);
            case ScalarConstant(value: final bool flag):
              emitter.loadImmediate(destination, flag ? 1 : 0);
            case ScalarConstant(value: final double number):
              final bits = ByteData(8)..setFloat64(0, number, .little);
              emitter.loadImmediate(move.auxiliary!, bits.getInt64(0, .little));
              emitter.move(destination, move.auxiliary!);
            case ScalarConstant(value: null):
              emitter.loadImmediate(destination, 0);
            default:
              object(value, destination);
          }
      }
    }

    final source = move.source, destination = move.destination;
    if (destination is AllocationStack<R> &&
        source is AllocationRegister<R> &&
        move.from == move.to) {
      emitter.storeStack(source.register, destination.offset);
      return;
    }
    final register = destination is AllocationRegister<R>
        ? destination.register
        : move.temporary!;
    if (source is AllocationConstant<R> &&
        move.to == .reference &&
        move.from != .reference) {
      object(source.value, register);
    } else if (move.from == move.to) {
      load(source, register);
    } else if (move.to == .reference) {
      load(source, register);
      final no = emitter.label(), done = emitter.label();
      emitter.jumpIfZero(register, no);
      object(const Constant.boolean(true), register);
      emitter.jump(done);
      emitter.bind(no);
      object(const Constant.boolean(false), register);
      emitter.bind(done);
    } else if (move.from == .reference) {
      final base = source is AllocationRegister<R>
          ? source.register
          : move.to == .floating
          ? move.auxiliary!
          : register;
      load(source, base);
      emitter.loadMemory(
        register,
        base,
        offset: ObjectHeader.fieldsOffset,
        bytes: 8,
        signed: false,
      );
    } else if (move.from == .word && move.to == .floating) {
      final base = source is AllocationRegister<R>
          ? source.register
          : move.auxiliary!;
      load(source, base);
      emitter.convertIntToDouble(register, base);
    } else {
      throw StateError('Unsupported allocated representation transfer.');
    }
    if (destination is AllocationStack<R>) {
      emitter.storeStack(register, destination.offset);
    }
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
