import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'function_emitter.dart';
import 'function_selection.dart';

/// Keeps block-local registers and distinct frame homes for values crossing blocks.
///
/// Homes are not reused across SSA definitions. Edge arguments are staged before
/// assignment so loop-carried swaps and rotations retain simultaneous semantics.
final class FunctionAllocation<R extends Object>(
  final IrFunction function,
  final FunctionEmitter<R> emitter,
  final FunctionSelection<R> selection,
  final void Function(Constant, R) loadObject,
) {
  final _owners = <Value, Block>{};
  final _shared = <Value>{};
  final _slots = <Value, int>{};
  final _registers = <Value, R>{};
  final _spilled = <Value>{};
  final _free = <R>[];
  late Map<Value, int> _uses;
  late final int _stagingOffset;

  /// The queried frame, absent when the function needs no stack storage or calls.
  late final FrameLayout<R>? frame;

  this {
    for (final block in selection.body.blocks) {
      for (final value in [
        ...block.parameters,
        ...selection.body.instructions[block]!,
      ]) {
        _owners[value] = block;
      }
    }
    final liveness = selection.liveness;
    final used = liveness.uses.values.expand((uses) => uses.keys).toSet();
    var edgeWords = 0;
    for (final block in selection.body.blocks) {
      for (final value in liveness.liveIn[block]!) {
        if (value is NewCell) continue;
        if (_owners[value] != block ||
            block != function.entry && value is BlockParameter) {
          _shared.add(value);
        }
      }
      for (final edge in selection.body.successors(block)) {
        final words = liveness.liveParameters[edge.target]!.length;
        if (words > edgeWords) edgeWords = words;
      }
    }
    final incoming = <Value, int>{
      for (final (i, location) in selection.entry.parameters.indexed)
        if (location case StackArgument(:final offset))
          function.entry.parameters[i]: offset,
    };
    final framed =
        selection.cells.isNotEmpty ||
        incoming.isNotEmpty ||
        selection.calls.isNotEmpty ||
        _shared.isNotEmpty ||
        liveness.uses.values.any(
          (uses) => RegisterBank.values.any(
            (bank) =>
                uses.keys.where((v) => selection.bank(v.type) == bank).length +
                    selection.temporaries(bank) >=
                emitter.allocatableRegisters
                    .where((r) => emitter.bank(r) == bank)
                    .length,
          ),
        );
    if (framed) {
      for (final value in _owners.keys) {
        if (!incoming.containsKey(value) &&
            (used.contains(value) || _shared.contains(value))) {
          _slots[value] = _slots.length * 8;
        }
      }
      for (final cell in selection.cells) {
        _slots[cell] = _slots.length * 8;
      }
    }
    frame = framed
        ? emitter.convention.frameLayout(
            localBytes: (_slots.length + edgeWords) * 8,
            localAlignment: 8,
            savedRegisters: [],
            outgoingStackBytes: selection.calls.values.fold(
              0,
              (bytes, call) => call.layout.stackBytes > bytes
                  ? call.layout.stackBytes
                  : bytes,
            ),
          )
        : null;
    _stagingOffset = (frame?.localOffset ?? 0) + _slots.length * 8;
    if (frame case final frame?) {
      _slots.updateAll((_, offset) => frame.localOffset + offset);
      for (final MapEntry(:key, :value) in incoming.entries) {
        _slots[key] = frame.incomingStackOffset + value;
      }
    }
  }

  /// Saves incoming arguments whose homes must survive beyond entry.
  void initialize() {
    for (final (i, parameter) in function.entry.parameters.indexed) {
      if (_shared.contains(parameter)) {
        if (selection.entry.parameters[i] case RegisterArgument(
          :final register,
        )) {
          emitter.storeStack(register, _slot(parameter));
        }
      }
    }
  }

  /// Starts independent register-use accounting at a block boundary.
  void begin(Block block) {
    _uses = Map.of(selection.liveness.uses[block]!);
    _registers.clear();
    _free
      ..clear()
      ..addAll(emitter.allocatableRegisters);
    _spilled
      ..clear()
      ..addAll(
        selection.liveness.liveIn[block]!.where(
          (v) =>
              v is! NewCell &&
              _shared.contains(v) &&
              (v is BlockParameter || _owners[v] != block),
        ),
      );
    if (block == function.entry) {
      for (final (i, parameter) in block.parameters.indexed) {
        if (_uses.containsKey(parameter)) {
          switch (selection.entry.parameters[i]) {
            case RegisterArgument(:final register):
              _registers[parameter] = register;
              _free.remove(register);
            case StackArgument():
              _spilled.add(parameter);
          }
        }
      }
    }
  }

  /// Reads an operand without evicting registers in [except].
  R read(Value value, {Iterable<R> except = const []}) {
    if (_registers[value] case final register?) return register;
    final register = allocate(selection.bank(value.type), except: except);
    load(value, register, except: except);
    return _registers[value] = register;
  }

  /// Loads the current contents without treating the cell as an SSA value.
  void readCell(ReadCell operation) {
    final register = allocate(selection.bank(operation.type));
    emitter.loadStack(register, _slot(operation.cell));
    define(operation, register);
  }

  /// Stores a value in its activation's fixed local slot.
  void writeCell(Value cell, Value value) {
    final type = (cell.type as CellType).content;
    if (selection.layouts.representation(value.type) ==
        selection.layouts.representation(type)) {
      emitter.storeStack(read(value), _slot(cell));
      release(value);
      return;
    }
    final register = allocate(selection.bank(type));
    load(value, register, asType: type);
    emitter.storeStack(register, _slot(cell));
    release(value);
    releaseTemporary(register);
  }

  /// Transfers a value using the representation required by [asType].
  void load(
    Value value,
    R destination, {
    Iterable<R> except = const [],
    ValueType? asType,
  }) {
    if (value is TestedValue) {
      // A refinement changes the type, not the original value's storage.
      asType ??= value.type;
      value = value.test.operand;
    }
    final from = selection.layouts.representation(value.type);
    final to = selection.layouts.representation(asType ?? value.type);
    if (from != to) {
      if (to == .reference) {
        if (value is Constant) {
          loadObject(value, destination);
        } else {
          if (value.type != .boolean) {
            throw StateError('Allocating conversion was not selected.');
          }
          final no = emitter.label(), done = emitter.label();
          load(value, destination, except: except);
          emitter.jumpIfZero(destination, no);
          loadObject(const Constant.boolean(true), destination);
          emitter.jump(done);
          emitter.bind(no);
          loadObject(const Constant.boolean(false), destination);
          emitter.bind(done);
        }
      } else {
        final source = emitter.bank(destination) == .general
            ? destination
            : allocate(.general, except: except);
        load(value, source, except: except);
        emitter.loadMemory(
          destination,
          source,
          offset: ObjectLayout.alignment,
          bytes: 8,
          signed: false,
        );
        if (source != destination) releaseTemporary(source);
      }
    } else if (_registers[value] case final register?) {
      emitter.move(destination, register);
    } else if (value case ScalarConstant(value: final int number)) {
      emitter.loadImmediate(destination, number);
    } else if (value case ScalarConstant(value: final bool flag)) {
      emitter.loadImmediate(destination, flag ? 1 : 0);
    } else if (value case ScalarConstant(value: final double number)) {
      final bits = ByteData(8)..setFloat64(0, number, .little);
      final temporary = allocate(.general, except: except);
      emitter.loadImmediate(temporary, bits.getInt64(0, .little));
      emitter.move(destination, temporary);
      releaseTemporary(temporary);
    } else if (value case ScalarConstant(value: null)) {
      emitter.loadImmediate(destination, 0);
    } else if (value is ObjectConstant) {
      loadObject(value, destination);
    } else if (value is Constant) {
      throw UnsupportedError('Native constant: ${value.type}');
    } else if (_spilled.contains(value)) {
      emitter.loadStack(destination, _slot(value));
    } else {
      throw StateError('Missing native value: $value');
    }
  }

  /// Allocates one register, spilling a different resident value if necessary.
  R allocate(RegisterBank bank, {Iterable<R> except = const [], R? preferred}) {
    if (preferred != null &&
        !except.contains(preferred) &&
        emitter.bank(preferred) == bank &&
        _free.remove(preferred)) {
      return preferred;
    }
    final index = _free.lastIndexWhere(
      (r) => !except.contains(r) && emitter.bank(r) == bank,
    );
    if (index >= 0) return _free.removeAt(index);
    final entry = _registers.entries.firstWhere(
      (e) => !except.contains(e.value) && emitter.bank(e.value) == bank,
    );
    _spill(entry.key, entry.value);
    _registers.remove(entry.key);
    return entry.value;
  }

  /// Releases a temporary that has not been associated with an SSA value.
  void releaseTemporary(R register) => _free.add(register);

  /// Publishes a result and stores its home if other blocks can read it.
  void define(Value value, R register) {
    if (_shared.contains(value)) {
      emitter.storeStack(register, _slot(value));
      _spilled.add(value);
    }
    if (_uses.containsKey(value)) {
      _registers[value] = register;
      _free.remove(register);
    } else if (!_free.contains(register)) {
      _free.add(register);
    }
  }

  /// Consumes one use in the current block without ending cross-block lifetimes.
  void release(Value value) {
    final count = _uses[value]! - 1;
    if (count == 0) {
      _uses.remove(value);
      if (_registers.remove(value) case final register?) _free.add(register);
    } else {
      _uses[value] = count;
    }
  }

  /// Saves residents needed in [live], discarding other bindings.
  void flush({Set<Value>? live}) {
    _registers.removeWhere((value, register) {
      if (live == null || live.contains(value)) _spill(value, register);
      _free.add(register);
      return true;
    });
  }

  /// Homes caller-live references before argument staging and invalidates registers.
  StackRoots prepareCall(Instruction instruction, Set<R> clobbered) {
    final roots = selection.liveness.acrossCalls[instruction]!
        .where((v) => selection.layouts.isReference(v.type))
        .toSet();
    _registers.removeWhere((value, register) {
      if (!clobbered.contains(register) && !roots.contains(value)) return false;
      _spill(value, register);
      _free.add(register);
      return true;
    });
    final frame = this.frame!;
    final offsets = <int>[];
    for (final root in roots) {
      if (root is! NewCell && !_spilled.contains(root)) {
        throw StateError('Live reference has no initialized stack home.');
      }
      final offset = _slot(root);
      final local =
          offset >= frame.localOffset &&
          offset < frame.localOffset + frame.localBytes;
      final incoming =
          offset >= frame.incomingStackOffset &&
          offset < frame.incomingStackOffset + selection.entry.stackBytes;
      if (!local && !incoming || frame.savedRegisters.containsValue(offset)) {
        throw StateError('Live reference is outside value storage.');
      }
      offsets.add(offset);
    }
    offsets.sort();
    return StackRoots(
      frame.incomingStackOffset,
      frame.returnAddressOffset,
      offsets,
    );
  }

  /// Assigns block parameters simultaneously after [flush], using one register.
  void copyArguments(Jump edge) {
    final parameters = selection.liveness.liveParameters[edge.target]!;
    for (final (slot, i) in parameters.indexed) {
      final argument = edge.arguments[i];
      final type = edge.target.parameters[i].type;
      final scratch = emitter.allocatableRegisters.lastWhere(
        (r) => emitter.bank(r) == selection.bank(type),
      );
      load(argument, scratch, asType: type);
      emitter.storeStack(scratch, _stagingOffset + slot * 8);
    }
    for (final (slot, i) in parameters.indexed) {
      final parameter = edge.target.parameters[i];
      final scratch = emitter.allocatableRegisters.lastWhere(
        (r) => emitter.bank(r) == selection.bank(parameter.type),
      );
      emitter.loadStack(scratch, _stagingOffset + slot * 8);
      emitter.storeStack(scratch, _slot(parameter));
    }
  }

  void _spill(Value value, R register) {
    if (value is Constant || !_spilled.add(value)) return;
    emitter.storeStack(register, _slot(value));
  }

  int _slot(Value value) => _slots[value]!;
}
