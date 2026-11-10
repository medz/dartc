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
  final _blockUses = <Block, Map<Value, int>>{};
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
    for (final block in function.blocks) {
      for (final value in [...block.parameters, ...block.instructions]) {
        _owners[value] = block;
      }
    }
    final used = <Value>{};
    var edgeWords = 0;
    for (final block in function.blocks) {
      final uses = _blockUses[block] = {};
      void use(Value value) {
        if (value is TestedValue) value = value.test.operand;
        if (value is NewCell) return;
        used.add(value);
        uses.update(value, (n) => n + 1, ifAbsent: () => 1);
        if (value is! Constant && _owners[value] != block) _shared.add(value);
      }

      for (final instruction in block.instructions) {
        if (selection.constantTests.containsKey(instruction)) continue;
        if (selection.binaries[instruction] case final binary?) {
          use(binary.left);
          use(binary.right);
        } else {
          instruction.inputs.forEach(use);
        }
      }
      switch (block.end) {
        case Return(value: final value?):
          if (value.type != .voidType) use(value);
        case Branch(:final condition):
          use(condition);
        case Jump() || Return():
          break;
        default:
          throw UnsupportedError('Native terminator: ${block.end.runtimeType}');
      }
      for (final edge in block.successors) {
        edge.arguments.forEach(use);
        _shared.addAll(edge.target.parameters);
        if (edge.arguments.length > edgeWords) {
          edgeWords = edge.arguments.length;
        }
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
        _blockUses.values.any(
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
              (bytes, call) =>
                  call.stackBytes > bytes ? call.stackBytes : bytes,
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
    _uses = Map.of(_blockUses[block]!);
    _registers.clear();
    _free
      ..clear()
      ..addAll(emitter.allocatableRegisters);
    _spilled
      ..clear()
      ..addAll(
        _uses.keys.where(
          (v) =>
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
          assert(value.type == .boolean);
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

  /// Saves resident values in the selected clobber set, or all values for an edge.
  void flush({Set<R>? clobbered}) {
    _registers.removeWhere((value, register) {
      if (clobbered != null && !clobbered.contains(register)) return false;
      _spill(value, register);
      _free.add(register);
      return true;
    });
  }

  /// Assigns block parameters simultaneously after [flush], using one register.
  void copyArguments(Jump edge) {
    for (final (i, argument) in edge.arguments.indexed) {
      final type = edge.target.parameters[i].type;
      final scratch = emitter.allocatableRegisters.lastWhere(
        (r) => emitter.bank(r) == selection.bank(type),
      );
      load(argument, scratch, asType: type);
      emitter.storeStack(scratch, _stagingOffset + i * 8);
    }
    for (final (i, parameter) in edge.target.parameters.indexed) {
      final scratch = emitter.allocatableRegisters.lastWhere(
        (r) => emitter.bank(r) == selection.bank(parameter.type),
      );
      emitter.loadStack(scratch, _stagingOffset + i * 8);
      emitter.storeStack(scratch, _slot(parameter));
    }
  }

  void _spill(Value value, R register) {
    if (value is Constant || !_spilled.add(value)) return;
    emitter.storeStack(register, _slot(value));
  }

  int _slot(Value value) => _slots[value]!;
}
