import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'function_emitter.dart';
import 'function_selection.dart';

/// Assigns block-entry registers, edge transfers and distinct frame homes.
///
/// Calls still publish initialized stack roots. Edge transfers preserve parallel
/// semantics even when loop parameters exchange registers or stack locations.
final class FunctionAllocation<R extends Object>(
  final FunctionEmitter<R> emitter,
  final FunctionSelection<R> selection,
  final void Function(Constant, R) loadObject,
) {
  final _entryRegisters = <Block, Map<Value, R>>{};
  final _edgeScratch = {
    for (final register in emitter.allocatableRegisters)
      emitter.bank(register): register,
  };
  final _slots = <Value, int>{};
  final _registers = <Value, R>{};
  final _spilled = <Value>{};
  final _free = <R>[];
  late Map<Value, int> _uses;
  late Set<Value> _liveOut;
  late final int _stagingOffset;

  /// Stack locations fixed before emission; only the return PCs remain unknown.
  late final Map<Value, StackRoots> safepoints;

  /// The queried frame, absent when the function needs no stack storage or calls.
  late final FrameLayout<R>? frame;

  this {
    final owners = <Value, Block>{}, shared = <Value>{};
    for (final block in selection.body.blocks) {
      for (final value in [
        ...selection.body.parametersOf(block),
        ...selection.body.instructions[block]!,
      ]) {
        owners[value] = block;
      }
    }
    final liveness = selection.liveness;
    final used = liveness.uses.values.expand((uses) => uses.keys).toSet();
    var edgeWords = 0;
    for (final block in selection.body.blocks) {
      for (final value in liveness.liveIn[block]!) {
        if (selection.cells.contains(value)) continue;
        if (owners[value] != block ||
            block != selection.body.entry && value is BlockParameter) {
          shared.add(value);
        }
      }
      for (final edge in selection.body.successors(block)) {
        final words = liveness.liveParameters[edge.target]!.length;
        if (words > edgeWords) edgeWords = words;
      }
    }
    _assignEntries();
    final incoming = <Value, int>{
      for (final (i, location) in selection.entry.parameters.indexed)
        if (location case StackArgument(:final offset))
          selection.body.entryParameters[i]: offset,
    };
    final framed =
        selection.body.ends.values.any((end) => end is Throw) ||
        selection.cells.isNotEmpty ||
        incoming.isNotEmpty ||
        selection.calls.isNotEmpty ||
        selection.binaries.values.any((b) => b.encoding.fixed != null) ||
        shared.isNotEmpty ||
        liveness.uses.values.any(
          (uses) => RegisterBank.values.any(
            (bank) =>
                uses.keys
                        .where(
                          (v) =>
                              selection.bank(selection.body.typeOf(v)) == bank,
                        )
                        .length +
                    selection.temporaries(bank) >=
                emitter.allocatableRegisters
                    .where((r) => emitter.bank(r) == bank)
                    .length,
          ),
        );
    if (framed) {
      for (final value in owners.keys) {
        if (!incoming.containsKey(value) &&
            (used.contains(value) || shared.contains(value))) {
          _slots[value] = _slots.length * 8;
        }
      }
      for (final cell in selection.cells) {
        _slots[cell] = _slots.length * 8;
      }
      for (final value in used.whereType<UnwindValue>()) {
        _slots[value] = _slots.length * 8;
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
    safepoints = Map.unmodifiable({
      for (final MapEntry(:key, :value) in selection.liveReferences.entries)
        key: _stackRoots(value),
    });
  }

  StackRoots _stackRoots(Set<Value> values) {
    final frame = this.frame!;
    final offsets = <int>[];
    for (final value in values) {
      final offset = _slot(value);
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

  /// The traced continuation home relative to this function's stack pointer.
  int? get contextOffset => selection.body.stackContext == null
      ? null
      : _slot(selection.body.stackContext!);

  void _assignEntries() {
    final preferred = <Value, R>{};
    final predecessors = <Block, List<Jump>>{};
    for (final block in selection.body.blocks) {
      for (final edge in selection.body.successors(block)) {
        (predecessors[edge.target] ??= []).add(edge);
      }
    }
    final entry = selection.body.entry;
    final incoming = _entryRegisters[entry] = <Value, R>{};
    for (final (i, parameter) in selection.body.entryParameters.indexed) {
      if (!selection.liveness.liveIn[entry]!.contains(parameter)) continue;
      switch (selection.entry.parameters[i]) {
        case RegisterAggregate() || IndirectArgument():
          throw StateError('Internal aggregate values require storage.');
        case RegisterArgument(:final register):
          incoming[parameter] = preferred[parameter] = register;
        case StackArgument():
          break;
      }
    }
    for (final block in selection.body.blocks) {
      if (block == entry) continue;
      final assigned = _entryRegisters[block] = <Value, R>{};
      final available = emitter.allocatableRegisters
          .where((register) => !_edgeScratch.containsValue(register))
          .toList();
      final parameters = selection.body.parametersOf(block);
      for (final value in selection.liveness.liveIn[block]!) {
        if (selection.cells.contains(value)) continue;
        final bank = selection.bank(selection.body.typeOf(value));
        var register = preferred[value];
        final index = value is BlockParameter ? parameters.indexOf(value) : -1;
        if (register == null && index >= 0) {
          for (final edge in predecessors[block] ?? const <Jump>[]) {
            final argument = selection.body.argumentsOf(edge)[index];
            register =
                preferred[argument is TestedValue
                    ? argument.test.operand
                    : argument];
            if (register != null && available.contains(register)) break;
          }
        }
        if (register == null ||
            emitter.bank(register) != bank ||
            !available.contains(register)) {
          register = available
              .where((register) => emitter.bank(register) == bank)
              .lastOrNull;
        }
        if (register != null) {
          assigned[value] = register;
          preferred.putIfAbsent(value, () => register!);
          available.remove(register);
        }
      }
    }
  }

  /// Adopts locations established by every incoming edge, independent of order.
  void begin(Block block) {
    _uses = Map.of(selection.liveness.uses[block]!);
    _liveOut = selection.liveness.liveOut[block]!;
    _registers
      ..clear()
      ..addAll(_entryRegisters[block]!);
    _free
      ..clear()
      ..addAll(
        emitter.allocatableRegisters.where(
          (register) => !_registers.containsValue(register),
        ),
      );
    _spilled
      ..clear()
      ..addAll(
        selection.liveness.liveIn[block]!.where(
          (value) =>
              !selection.cells.contains(value) &&
              !_registers.containsKey(value),
        ),
      );
  }

  /// Reads an operand without evicting registers in [except].
  R read(Value value, {Iterable<R> except = const []}) {
    if (_registers[value] case final register?) return register;
    final register = allocate(
      selection.bank(selection.body.typeOf(value)),
      except: except,
    );
    load(value, register, except: except);
    return _registers[value] = register;
  }

  /// Loads the current contents without treating the cell as an SSA value.
  void readCell(ReadCell operation) {
    final register = allocate(selection.bank(operation.type));
    emitter.loadStack(register, _slot(operation.cell));
    define(operation, register);
  }

  /// Makes unbound reference storage safe to scan without binding the local.
  void clearCell(Value cell) {
    final register = allocate(.general);
    emitter.loadImmediate(register, 0);
    emitter.storeStack(register, _slot(cell));
    releaseTemporary(register);
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
    bool fromHome = false,
  }) {
    if (value is TestedValue) {
      // A refinement changes the type, not the original value's storage.
      asType ??= value.type;
      value = value.test.operand;
    }
    final storedType = selection.body.typeOf(value);
    final from = selection.layouts.representation(storedType);
    final to = selection.layouts.representation(asType ?? storedType);
    if (from != to) {
      if (to == .reference) {
        if (value is Constant) {
          loadObject(value, destination);
        } else {
          if (storedType != .boolean) {
            throw StateError('Allocating conversion was not selected.');
          }
          final no = emitter.label(), done = emitter.label();
          load(value, destination, except: except, fromHome: fromHome);
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
        load(value, source, except: except, fromHome: fromHome);
        emitter.loadMemory(
          destination,
          source,
          offset: ObjectHeader.fieldsOffset,
          bytes: 8,
          signed: false,
        );
        if (source != destination) releaseTemporary(source);
      }
    } else if (_registers[value] case final register? when !fromHome) {
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
    } else if (value is Constant) {
      loadObject(value, destination);
    } else if (value is UnwindValue || _spilled.contains(value)) {
      emitter.loadStack(destination, _slot(value));
    } else {
      throw StateError('Missing native value: $value');
    }
  }

  /// Homes the exceptional results before edge argument staging can clobber them.
  void saveUnwind() {
    for (final (value, register) in [
      (UnwindValue.exception, emitter.exceptionRegister),
      (UnwindValue.stackTrace, emitter.traceRegister),
    ]) {
      if (_slots[value] case final offset?) {
        emitter.storeStack(register, offset);
      }
    }
  }

  /// Places both exceptional results without overwriting either source operand.
  void placeException(Value exception, Value trace) {
    flush();
    load(exception, emitter.exceptionRegister, asType: .object);
    load(trace, emitter.traceRegister, except: [emitter.exceptionRegister]);
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

  /// Homes occupants before reserving fixed inputs, results and clobbers.
  void reserve(Set<R> registers) {
    _registers.removeWhere((value, register) {
      if (!registers.contains(register)) return false;
      _spill(value, register);
      return true;
    });
    _free.removeWhere(registers.contains);
  }

  /// Keeps a result resident until its final local use or outgoing edge.
  void define(Value value, R register) {
    if (_uses.containsKey(value) || _liveOut.contains(value)) {
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
      if (!_liveOut.contains(value)) {
        if (_registers.remove(value) case final register?) _free.add(register);
      }
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

  /// Assigns the fixed or overlapping operands required by the selected encoding.
  ({R result, R left, R right, Set<R> reserved}) binaryOperands(
    Value operation,
  ) {
    final (:encoding, :left, :right, :floatingInputs) =
        selection.binaries[operation]!;
    if (encoding.fixed case final fixed?) {
      final reserved = {
        fixed.left,
        fixed.right,
        fixed.result,
        ...fixed.clobbered,
      };
      reserve(reserved);
      load(left, fixed.left, except: reserved);
      load(right, fixed.right, except: reserved);
      release(left);
      release(right);
      return (
        result: fixed.result,
        left: fixed.left,
        right: fixed.right,
        reserved: reserved,
      );
    }
    var a = read(left), b = read(right, except: [a]);
    final temporaries = <R>[];
    R convert(Value value, R register) {
      if (!floatingInputs || value.type == .floating) return register;
      final temporary = allocate(.floating, except: [a, b]);
      emitter.convertIntToDouble(temporary, register);
      temporaries.add(temporary);
      return temporary;
    }

    a = convert(left, a);
    b = convert(right, b);
    release(left);
    release(right);
    temporaries.forEach(releaseTemporary);
    final destination = encoding.reuseLeft
        ? allocate(
            selection.bank(operation.type),
            preferred: a,
            except: a == b ? [] : [b],
          )
        : allocate(selection.bank(operation.type));
    if (encoding.reuseLeft) emitter.move(destination, a);
    return (
      result: destination,
      left: encoding.reuseLeft ? destination : a,
      right: b,
      reserved: const {},
    );
  }

  /// Releases selected clobbers and publishes the already assigned result.
  void finishBinary(
    Value operation,
    ({R result, R left, R right, Set<R> reserved}) operands,
  ) {
    operands.reserved
        .where((register) => register != operands.result)
        .forEach(releaseTemporary);
    define(operation, operands.result);
  }

  /// Initializes the already assigned roots and preserves call-clobbered values.
  void prepareCall(Value instruction) {
    final roots = selection.liveReferences[instruction]!;
    final clobbered = selection.calls[instruction]!.layout.clobberedRegisters;
    _registers.removeWhere((value, register) {
      if (!clobbered.contains(register) && !roots.contains(value)) return false;
      _spill(value, register);
      _free.add(register);
      return true;
    });
    for (final root in roots) {
      if (!selection.cells.contains(root) && !_spilled.contains(root)) {
        throw StateError('Live reference has no initialized stack home.');
      }
    }
  }

  Iterable<(Value, Value)> _edgeValues(Jump edge) sync* {
    final parameters = selection.body.parametersOf(edge.target);
    for (final value in selection.liveness.liveIn[edge.target]!) {
      if (selection.cells.contains(value)) continue;
      final index = value is BlockParameter ? parameters.indexOf(value) : -1;
      yield (
        value,
        index < 0 ? value : selection.body.argumentsOf(edge)[index],
      );
    }
  }

  bool _sameRegister(Value value, Value argument, R? register) {
    if (register == null) return false;
    final stored = argument is TestedValue ? argument.test.operand : argument;
    return _registers[stored] == register &&
        selection.layouts.representation(selection.body.typeOf(stored)) ==
            selection.layouts.representation(selection.body.typeOf(value));
  }

  /// Homes changed transfers before branching, keeping identical locations live.
  void prepareEdges(Block block) {
    final needed = <Value>{};
    for (final edge in selection.body.successors(block)) {
      final assigned = _entryRegisters[edge.target]!;
      for (final (value, argument) in _edgeValues(edge)) {
        if (!_sameRegister(value, argument, assigned[value])) {
          needed.add(
            argument is TestedValue ? argument.test.operand : argument,
          );
        }
      }
    }
    _registers.removeWhere((value, register) {
      if (needed.contains(value)) _spill(value, register);
      if (_liveOut.contains(value) && !_edgeScratch.containsValue(register)) {
        return false;
      }
      _free.add(register);
      return true;
    });
  }

  /// Transfers an edge without overwriting simultaneous sources on either path.
  void copyArguments(Jump edge) {
    final assigned = _entryRegisters[edge.target]!;
    final protected = assigned.values.toSet();
    final stacked = <Value>[];
    for (final (value, argument) in _edgeValues(edge)) {
      if (assigned.containsKey(value)) continue;
      if (value == argument && _spilled.contains(value)) continue;
      final type = selection.body.typeOf(value);
      final scratch = _edgeScratch[selection.bank(type)]!;
      load(argument, scratch, asType: type, except: protected, fromHome: true);
      emitter.storeStack(scratch, _stagingOffset + stacked.length * 8);
      stacked.add(value);
    }
    // shortcut: changed locations reload homes; add register-cycle moves if edge traffic dominates.
    for (final (value, argument) in _edgeValues(edge)) {
      final register = assigned[value];
      if (register == null || _sameRegister(value, argument, register)) {
        continue;
      }
      load(
        argument,
        register,
        asType: selection.body.typeOf(value),
        except: protected,
        fromHome: true,
      );
    }
    for (final (slot, value) in stacked.indexed) {
      final scratch =
          _edgeScratch[selection.bank(selection.body.typeOf(value))]!;
      emitter.loadStack(scratch, _stagingOffset + slot * 8);
      emitter.storeStack(scratch, _slot(value));
    }
  }

  void _spill(Value value, R register) {
    if (value is Constant || !_spilled.add(value)) return;
    emitter.storeStack(register, _slot(value));
  }

  int _slot(Value value) => _slots[value]!;
}
