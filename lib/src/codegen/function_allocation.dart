import 'package:dartc/ir.dart';

import 'function_emitter.dart';

/// Keeps block-local registers and distinct frame homes for values crossing blocks.
///
/// Homes are not reused across SSA definitions. Edge arguments are staged before
/// assignment so loop-carried swaps and rotations retain simultaneous semantics.
final class FunctionAllocation<R extends Object>(
  final IrFunction function,
  final FunctionEmitter<R> emitter,
) {
  final _owners = <Value, Block>{};
  final _blockUses = <Block, Map<Value, int>>{};
  final _shared = <Value>{};
  final _slots = <Value, int>{};
  final _registers = <Value, R>{};
  final _spilled = <Value>{};
  final _free = <R>[];
  late Map<Value, int> _uses;

  /// Whether calls, edges or register pressure require a frame.
  late final bool framed;

  /// The aligned space for stable homes, spills and simultaneous edge arguments.
  late final int frameBytes;

  this {
    for (final block in function.blocks) {
      for (final value in [...block.parameters, ...block.instructions]) {
        _owners[value] = block;
      }
    }
    final used = <Value>{};
    var calls = false, edgeWords = 0;
    for (final block in function.blocks) {
      final uses = _blockUses[block] = {};
      void use(Value value) {
        used.add(value);
        uses.update(value, (n) => n + 1, ifAbsent: () => 1);
        if (value is! Constant && _owners[value] != block) _shared.add(value);
      }

      for (final instruction in block.instructions) {
        calls |= instruction is DirectCall;
        instruction.inputs.forEach(use);
      }
      switch (block.end) {
        case Return(value: final value?):
          use(value);
        case Branch(:final condition):
          use(condition);
        case Jump():
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
    framed =
        calls ||
        _shared.isNotEmpty ||
        _blockUses.values.any(
          (uses) => uses.length >= emitter.convention.callerSaved.length,
        );
    if (framed) {
      for (final value in _owners.keys) {
        if (used.contains(value) || _shared.contains(value)) {
          _slots[value] = _slots.length * 8;
        }
      }
    }
    frameBytes = ((_slots.length + edgeWords) * 8 + 15) & ~15;
  }

  /// Saves incoming arguments whose homes must survive beyond entry.
  void initialize() {
    for (final (i, parameter) in function.entry.parameters.indexed) {
      if (_shared.contains(parameter)) {
        emitter.storeStack(
          emitter.convention.parameters[i],
          _slots[parameter]!,
        );
      }
    }
  }

  /// Starts independent register-use accounting at a block boundary.
  void begin(Block block) {
    _uses = Map.of(_blockUses[block]!);
    _registers.clear();
    _free
      ..clear()
      ..addAll(emitter.convention.callerSaved);
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
          final register = emitter.convention.parameters[i];
          _registers[parameter] = register;
          _free.remove(register);
        }
      }
    }
  }

  /// Reads an operand without evicting the other operand's [except] register.
  R read(Value value, {R? except}) {
    if (_registers[value] case final register?) return register;
    final register = allocate(except: except);
    load(value, register);
    return _registers[value] = register;
  }

  /// Loads a constant or a saved value into an explicitly chosen register.
  void load(Value value, R destination) {
    if (value case ScalarConstant(value: final int number)) {
      emitter.loadImmediate(destination, number);
    } else if (value case ScalarConstant(value: final bool flag)) {
      emitter.loadImmediate(destination, flag ? 1 : 0);
    } else if (_spilled.contains(value)) {
      emitter.loadStack(destination, _slots[value]!);
    } else {
      throw StateError('Missing native value: $value');
    }
  }

  /// Allocates one register, spilling a different resident value if necessary.
  R allocate({R? except}) {
    if (_free.isNotEmpty) return _free.removeLast();
    final entry = _registers.entries.firstWhere((e) => e.value != except);
    _spill(entry.key, entry.value);
    _registers.remove(entry.key);
    return entry.value;
  }

  /// Publishes a result and stores its home if other blocks can read it.
  void define(Value value, R register) {
    if (_shared.contains(value)) {
      emitter.storeStack(register, _slots[value]!);
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

  /// Saves resident values before a call or before assigning edge arguments.
  void flush() {
    for (final entry in _registers.entries) {
      _spill(entry.key, entry.value);
    }
    _registers.clear();
    _free
      ..clear()
      ..addAll(emitter.convention.callerSaved);
  }

  /// Assigns block parameters simultaneously after [flush], using one register.
  void copyArguments(Jump edge) {
    final scratch = emitter.convention.callerSaved.last;
    final staging = _slots.length * 8;
    for (final (i, argument) in edge.arguments.indexed) {
      load(argument, scratch);
      emitter.storeStack(scratch, staging + i * 8);
    }
    for (final (i, parameter) in edge.target.parameters.indexed) {
      emitter.loadStack(scratch, staging + i * 8);
      emitter.storeStack(scratch, _slots[parameter]!);
    }
  }

  void _spill(Value value, R register) {
    if (value is ScalarConstant || !_spilled.add(value)) return;
    emitter.storeStack(register, _slots[value]!);
  }
}
