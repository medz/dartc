import 'dart:typed_data';
import 'dart:ffi' show Float;

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/layout.dart';

import 'function_allocation.dart';
import 'function_emitter.dart';
import 'function_selection.dart';
import 'native_adapter.dart';
import 'program_layout.dart';
import 'heap_plan.dart';
import 'stack_traces.dart';
import 'checked_casts.dart';
import 'member_calls.dart';
import 'numeric_operations.dart';
import 'global_storage.dart';
import 'heap_entry.dart';

/// Generates a control-flow graph with explicit edge transfers.
final class ScalarFunction<R extends Object>(
  final IrFunction function,
  final FunctionEmitter<R> emitter,
  final ProgramLayout layouts,
  HeapPlan heap,
  final StackTraces traces,
  CheckedCasts casts,
  MemberCalls members,
  NumericOperations arithmetic,
  GlobalStorage globals,
) {
  final selection = FunctionSelection(
    function,
    emitter,
    layouts,
    heap,
    traces,
    casts,
    members,
    arithmetic,
    globals,
  );

  bool get hasRoots => selection.liveness.acrossCalls.values.any(
    (values) =>
        values.any((v) => layouts.isReference(selection.body.typeOf(v))),
  );

  /// Emits the body and reports direct call sites to the module generator.
  Uint8List generate(
    void Function(Fixup, FunctionTarget) call,
    void Function(Fixup, Constant) constant,
    void Function(int, StackRoots) safepoint, {
    bool failures = false,
    bool persistent = false,
    void Function(Fixup, int)? codeAddress,
  }) {
    final allocation = FunctionAllocation(
      function,
      emitter,
      selection,
      (value, register) =>
          emitter.address(register, (fixup) => constant(fixup, value)),
    );
    final adapter = NativeAdapter(emitter);
    final labels = {
      for (final block in selection.body.blocks) block: emitter.label(),
    };
    if (allocation.frame case final frame?) emitter.prologue(frame);
    allocation.initialize();
    void edge(Jump jump) {
      allocation.copyArguments(jump);
      emitter.jump(labels[jump.target]!);
    }

    void leave() {
      if (allocation.frame case final frame?) {
        emitter.epilogue(frame);
      } else {
        emitter.ret();
      }
    }

    for (final block in selection.body.blocks) {
      emitter.bind(labels[block]!);
      allocation.begin(block);
      for (final instruction in selection.body.instructions[block]!) {
        if (selection.liveness.omitted.contains(instruction)) continue;
        if (selection.body.aliases.contains(instruction) &&
            instruction.type == .voidType) {
          continue;
        }
        if (selection.constantTests[instruction] case final value?) {
          final destination = allocation.allocate(.general);
          emitter.loadImmediate(destination, value ? 1 : 0);
          allocation.define(instruction, destination);
        } else if (instruction case ObjectRuntimeType(:final operand)
            when !selection.calls.containsKey(instruction) &&
                !selection.body.aliases.contains(instruction) &&
                operand.type != .nullType &&
                layouts.representation(operand.type) == .reference) {
          final value = allocation.read(operand);
          final result = allocation.allocate(.general, except: [value]);
          final done = emitter.label();
          emitter.address(
            result,
            (fixup) => constant(fixup, layouts.types.constant(.nullType)),
          );
          emitter.jumpIfZero(value, done);
          emitter.loadMemory(
            result,
            value,
            offset: ObjectLayout.typeOffset,
            bytes: 8,
            signed: false,
          );
          emitter.bind(done);
          allocation.release(operand);
          allocation.define(instruction, result);
        } else if (instruction case NewCell(:final initial)
            when selection.cells.contains(instruction)) {
          if (initial != null) {
            allocation.writeCell(
              instruction,
              selection.body.inputsOf(instruction).single,
            );
          } else if (layouts.isReference(selection.body.typeOf(instruction))) {
            allocation.clearCell(instruction);
          }
        } else if (instruction is ReadCell &&
            !selection.body.aliases.contains(instruction)) {
          allocation.readCell(instruction);
        } else if (instruction case WriteCell(:final cell)
            when selection.cells.contains(cell)) {
          allocation.writeCell(cell, selection.body.inputsOf(instruction).last);
        } else if (selection.calls[instruction] case (
          :final layout,
          :final target,
          :final arguments,
        )) {
          final native = instruction is NativeCall ? instruction : null;
          final parameterTypes = target == null
              ? null
              : layouts.entryTypes(target);
          final roots = allocation.prepareCall(
            instruction,
            layout.clobberedRegisters,
          );
          final parked = persistent && native != null
              ? HeapEntry.park(
                  emitter,
                  emitter.allocatableRegisters.firstWhere(
                    (r) =>
                        emitter.bank(r) == .general &&
                        r != emitter.failureRegister &&
                        layout.clobberedRegisters.contains(r),
                  ),
                )
              : const <Fixup>[];
          // Stage stack words before populating registers that the scratch may alias.
          if (layout.stackBytes != 0) {
            for (final (i, location) in layout.parameters.indexed) {
              if (location case StackArgument(:final offset)) {
                final value = arguments[i];
                final scratch = emitter.allocatableRegisters.firstWhere(
                  (r) =>
                      emitter.bank(r) ==
                          selection.bank(parameterTypes?[i] ?? value.type) &&
                      layout.clobberedRegisters.contains(r),
                );
                allocation.load(value, scratch, asType: parameterTypes?[i]);
                final type = native?.signature.parameters[i];
                if (type != null && type.isSinglePrecision) {
                  adapter.convert(scratch, type, intoDart: false);
                }
                emitter.storeStack(
                  scratch,
                  offset,
                  bytes: type?.nativeSize ?? 8,
                );
                allocation.release(value);
              }
            }
          }
          // Double constants may need a general temporary before fixed general arguments.
          for (final bank in [RegisterBank.floating, RegisterBank.general]) {
            for (final (i, location) in layout.parameters.indexed) {
              if (location case RegisterArgument(:final register)
                  when emitter.bank(register) == bank) {
                final value = arguments[i];
                allocation.load(value, register, asType: parameterTypes?[i]);
                if (native != null) {
                  adapter.convert(
                    register,
                    native.signature.parameters[i],
                    intoDart: false,
                  );
                }
                allocation.release(value);
              }
            }
          }
          if (native == null) {
            call(emitter.call(), target!);
          } else {
            // Load last so argument staging cannot overwrite the callee address.
            final address = emitter.allocatableRegisters.lastWhere(
              (r) =>
                  emitter.bank(r) == .general &&
                  layout.clobberedRegisters.contains(r) &&
                  !layout.parameters.any(
                    (p) => p is RegisterArgument<R> && p.register == r,
                  ),
            );
            allocation.load(native.pointer, address);
            allocation.release(native.pointer);
            emitter.callRegister(address);
          }
          for (final fixup in parked) {
            codeAddress!(fixup, emitter.position);
          }
          safepoint(emitter.position, roots);
          if (failures && native == null) {
            final returned = emitter.label();
            final end = selection.body.ends[block]!;
            if (end is Invoke && end.operation == instruction) {
              allocation.flush(live: selection.liveness.liveOut[block]);
            }
            emitter.jumpIfZero(emitter.failureRegister, returned);
            if (end case Invoke(:final operation, :final onThrow)
                when operation == instruction) {
              final propagated = emitter.label();
              final scratch = emitter.allocatableRegisters.lastWhere(
                (r) =>
                    emitter.bank(r) == .general &&
                    r != emitter.failureRegister &&
                    r != emitter.exceptionRegister &&
                    r != emitter.traceRegister,
              );
              emitter.loadImmediate(scratch, CallStatus.threw.index);
              emitter
                  .comparison(.equal)
                  .emit(scratch, emitter.failureRegister, scratch);
              emitter.jumpIfZero(scratch, propagated);
              allocation.saveUnwind();
              edge(onThrow);
              emitter.bind(propagated);
            }
            leave();
            emitter.bind(returned);
          }
          if (layout.result case final result?
              when instruction.type != .voidType) {
            final resultType = selection.body.typeOf(instruction);
            if (instruction
                case Equals(negated: true) || TypeTest(negated: true)) {
              final scratch = allocation.allocate(.general, except: [result]);
              emitter.loadImmediate(scratch, 1);
              emitter.bitXor.emit(result, result, scratch);
              allocation.releaseTemporary(scratch);
            }
            if (native != null) {
              adapter.convert(result, native.signature.result, intoDart: true);
            }
            if (native == null &&
                layouts.representation(target!.returnType) !=
                    layouts.representation(resultType)) {
              final destination = allocation.allocate(
                selection.bank(resultType),
                preferred: result,
              );
              emitter.loadMemory(
                destination,
                result,
                offset: ObjectLayout.fieldsOffset,
                bytes: 8,
                signed: false,
              );
              allocation.define(instruction, destination);
            } else {
              allocation.define(instruction, result);
            }
          }
        } else if (instruction case StoreField(:final field)) {
          final receiver = selection.body.inputsOf(instruction).first;
          final value = selection.body.inputsOf(instruction).last;
          final base = allocation.read(receiver);
          final source = allocation.allocate(
            selection.bank(field.type),
            except: [base],
          );
          allocation.load(value, source, asType: field.type, except: [base]);
          emitter.storeMemory(
            source,
            base,
            offset: layouts.fieldOffset(field),
            bytes: 8,
          );
          allocation.releaseTemporary(source);
          allocation.release(value);
          allocation.release(receiver);
        } else if (instruction case LoadField(:final field)
            when !selection.body.aliases.contains(instruction)) {
          final receiver = selection.body.inputsOf(instruction).first;
          final source = allocation.read(receiver);
          allocation.release(receiver);
          final stored = allocation.allocate(
            selection.bank(field.type),
            preferred: source,
          );
          emitter.loadMemory(
            stored,
            source,
            offset: layouts.fieldOffset(field),
            bytes: 8,
            signed: false,
          );
          var destination = stored;
          if (layouts.representation(field.type) !=
              layouts.representation(instruction.type)) {
            if (selection.bank(instruction.type) != emitter.bank(stored)) {
              destination = allocation.allocate(
                selection.bank(instruction.type),
              );
              allocation.releaseTemporary(stored);
            }
            emitter.loadMemory(
              destination,
              stored,
              offset: ObjectLayout.fieldsOffset,
              bytes: 8,
              signed: false,
            );
          }
          allocation.define(instruction, destination);
        } else if (selection.body.aliases.contains(instruction) ||
            instruction is TypeView ||
            instruction is ReifyType ||
            instruction is ObjectRuntimeType) {
          final operand = selection.body.inputsOf(instruction).single;
          final R destination;
          if (layouts.representation(selection.body.typeOf(operand)) ==
              layouts.representation(instruction.type)) {
            final source = allocation.read(operand);
            allocation.release(operand);
            destination = allocation.allocate(
              selection.bank(instruction.type),
              preferred: source,
            );
            emitter.move(destination, source);
          } else {
            destination = allocation.allocate(selection.bank(instruction.type));
            allocation.load(operand, destination, asType: instruction.type);
            allocation.release(operand);
          }
          allocation.define(instruction, destination);
        } else if (instruction case PointerOffset(
          :final pointer,
          :final index,
        )) {
          final base = allocation.read(pointer),
              offset = allocation.read(index, except: [base]);
          allocation.release(pointer);
          allocation.release(index);
          final destination = allocation.allocate(.general, preferred: base);
          emitter.addScaled(
            destination,
            base,
            offset,
            scale: FfiTypes.pointerElement(pointer.type)!.nativeSize,
          );
          allocation.define(instruction, destination);
        } else if (instruction case StoreNative(:final pointer, :final value)) {
          final base = allocation.read(pointer),
              source = allocation.read(value, except: [base]);
          final native = FfiTypes.pointerElement(pointer.type)!;
          allocation.release(value);
          if (native == Float) {
            final temporary = allocation.allocate(.floating, preferred: source);
            emitter.convertDoubleToFloat(temporary, source);
            emitter.storeMemory(temporary, base, bytes: 4);
            allocation.releaseTemporary(temporary);
          } else {
            emitter.storeMemory(source, base, bytes: native.nativeSize);
          }
          allocation.release(pointer);
        } else if (instruction
            case PointerFromAddress(address: final operand) ||
                PointerAddress(pointer: final operand) ||
                LoadNative(pointer: final operand)) {
          final source = allocation.read(operand);
          allocation.release(operand);
          final destination = allocation.allocate(
            selection.bank(instruction.type),
            preferred: source,
          );
          if (instruction is LoadNative) {
            final native = FfiTypes.pointerElement(operand.type)!;
            emitter.loadMemory(
              destination,
              source,
              bytes: native.nativeSize,
              signed: native.integerLayout?.signed ?? false,
            );
            if (native == Float) {
              emitter.convertFloatToDouble(destination, destination);
            }
          } else {
            emitter.move(destination, source);
          }
          allocation.define(instruction, destination);
        } else if (instruction case NumericToInt(:final operand)) {
          final source = allocation.read(operand);
          allocation.release(operand);
          final destination = allocation.allocate(.general, preferred: source);
          if (operand.type == .integer) {
            emitter.move(destination, source);
          } else {
            emitter.truncateDoubleToInt(destination, source);
          }
          allocation.define(instruction, destination);
        } else if (instruction
            case NumericToDouble(:final operand) ||
                NumericRoundToDouble(:final operand) ||
                NumericSquareRoot(:final operand)) {
          final source = allocation.read(operand);
          allocation.release(operand);
          final destination = allocation.allocate(.floating, preferred: source);
          if (operand.type == .integer) {
            emitter.convertIntToDouble(destination, source);
          } else if (instruction is NumericToDouble) {
            emitter.move(destination, source);
          }
          if (instruction is NumericSquareRoot) {
            emitter.squareRootDouble(
              destination,
              operand.type == .integer ? destination : source,
            );
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
          if (encoding.fixed case final fixed?) {
            final reserved = {
              fixed.left,
              fixed.right,
              fixed.result,
              ...fixed.clobbered,
            };
            allocation.reserve(reserved);
            allocation.load(left, fixed.left, except: reserved);
            allocation.load(right, fixed.right, except: reserved);
            encoding.emit(fixed.result, fixed.left, fixed.right);
            allocation.release(left);
            allocation.release(right);
            reserved
                .where((r) => r != fixed.result)
                .forEach(allocation.releaseTemporary);
            allocation.define(instruction, fixed.result);
            continue;
          }
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
      switch (selection.body.ends[block]!) {
        case Return(:final value):
          if (selection.entry.result case final result?) {
            if (layouts.representation(value!.type) ==
                layouts.representation(function.target.returnType)) {
              emitter.move(result, allocation.read(value));
            } else {
              allocation.load(
                value,
                result,
                asType: function.target.returnType,
              );
            }
          }
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
            allocation.flush(live: selection.liveness.liveOut[block]);
            edge(onReturn);
          }
        case Throw(:final exception, stackTrace: final trace!, :final onThrow):
          allocation.placeException(exception, trace);
          if ((block.end as Throw).stackTrace == null) {
            traces.recordError(emitter);
          }
          emitter.loadImmediate(
            emitter.failureRegister,
            CallStatus.threw.index,
          );
          if (onThrow == null) {
            leave();
          } else {
            allocation.saveUnwind();
            edge(onThrow);
          }
        case Unreachable():
          emitter.abort(71);
        case final Jump jump:
          allocation.flush(live: selection.liveness.liveOut[block]);
          edge(jump);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          final value = allocation.read(condition);
          allocation.flush(live: selection.liveness.liveOut[block]);
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
