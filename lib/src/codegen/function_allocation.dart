import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'double_bits.dart';
import 'function_emitter.dart' show RegisterBank;
import 'function_selection.dart';
import 'native_invocation.dart';
import 'storage_access.dart';
import 'type_values.dart';

/// A physical location or a constant that needs no persistent storage.
sealed class AllocationLocation<R extends Object>();

final class AllocationRegister<R extends Object>(final R register)
    extends AllocationLocation<R>;

enum _StackArea() {
  local,
  incoming,
}

/// A stack word whose final SP-relative offset is fixed before emission.
final class AllocationStack<R extends Object>._(
  final int displacement,
  final _StackArea _area,
) extends AllocationLocation<R> {
  late final int offset;
}

final class AllocationConstant<R extends Object>(final Constant value)
    extends AllocationLocation<R>;

/// A value transfer, including representation conversion and its scratch.
final class AllocationMove<R extends Object>(
  final AllocationLocation<R> source,
  final AllocationLocation<R> destination,
  final ValueRepresentation from,
  final ValueRepresentation to, {
  final R? temporary,
  final R? auxiliary,
});

/// One ABI argument, materialized before its optional native conversion.
final class AllocatedArgument<R extends Object>(
  Iterable<AllocationMove<R>> loads,
  final R register, {
  final int? stackOffset,
  final NativeTypeRef? nativeType,
}) {
  final List<AllocationMove<R>> loads = List.unmodifiable(loads);
}

/// Locations and transfers for an original selected operation or terminator.
final class AllocatedOperation<R extends Object>({
  Iterable<AllocationMove<R>> before = const [],
  Iterable<R> inputs = const [],
  final R? result,
  Iterable<R> temporaries = const [],
  Iterable<AllocatedArgument<R>> arguments = const [],
  Iterable<AllocationMove<R>> after = const [],
  Iterable<AllocationMove<R>> resultMoves = const [],
  final bool emptyResult = false,
}) {
  final List<AllocationMove<R>> before = List.unmodifiable(before);
  final List<R> inputs = List.unmodifiable(inputs);
  final List<R> temporaries = List.unmodifiable(temporaries);
  final List<AllocatedArgument<R>> arguments = List.unmodifiable(arguments);
  final List<AllocationMove<R>> after = List.unmodifiable(after);
  final List<AllocationMove<R>> resultMoves = List.unmodifiable(resultMoves);
}

/// Complete allocation for the existing selected graph, without emission.
///
/// Frame homes, instruction operands, parallel edge copies and initialized
/// safepoint roots are fixed together before any machine instruction is written.
final class FunctionAllocation<R extends Object>._(
  final FunctionSelection<R> selection,
  final FrameLayout<R>? frame,
  Map<Value, AllocatedOperation<R>> operations,
  Map<Block, AllocatedOperation<R>> terminators,
  Map<(Block, Jump), List<AllocationMove<R>>> edges,
  Map<Block, Map<Value, AllocationLocation<R>>> entries,
  Map<Value, AllocationStack<R>> homes,
  Map<Value, StackRoots> safepoints,
) {
  factory(FunctionSelection<R> selection) => _Allocator(selection).build();

  this
    : operations = Map.unmodifiable(operations),
      terminators = Map.unmodifiable(terminators),
      edges = Map.unmodifiable({
        for (final entry in edges.entries)
          entry.key: List<AllocationMove<R>>.unmodifiable(entry.value),
      }),
      entries = Map.unmodifiable({
        for (final entry in entries.entries)
          entry.key: Map<Value, AllocationLocation<R>>.unmodifiable(
            entry.value,
          ),
      }),
      homes = Map.unmodifiable(homes),
      safepoints = Map.unmodifiable(safepoints);

  final Map<Value, AllocatedOperation<R>> operations;
  final Map<Block, AllocatedOperation<R>> terminators;

  /// A shared jump needs separate transfers for each predecessor state.
  final Map<(Block, Jump), List<AllocationMove<R>>> edges;
  final Map<Block, Map<Value, AllocationLocation<R>>> entries;
  final Map<Value, AllocationStack<R>> homes;
  final Map<Value, StackRoots> safepoints;

  int? get contextOffset => homes[selection.body.stackContext]?.offset;
}

final class _Allocator<R extends Object>(final FunctionSelection<R> selection) {
  final _operations = <Value, AllocatedOperation<R>>{};
  final _terminators = <Block, AllocatedOperation<R>>{};
  final _edges = <(Block, Jump), List<AllocationMove<R>>>{};
  final _entries = <Block, Map<Value, AllocationLocation<R>>>{};
  final _homes = <Value, AllocationStack<R>>{};
  final _locations = <R, AllocationRegister<R>>{};
  final _stacks = <AllocationStack<R>>[];
  final _registers = <Value, R>{};
  final _spilled = <Value>{};
  final _free = <R>[];
  late Map<Value, int> _uses;
  late Set<Value> _liveOut;
  late List<AllocationMove<R>> _moves;
  int _localWords = 0;
  AllocationStack<R>? _cycle;

  AllocationRegister<R> _register(R register) =>
      _locations.putIfAbsent(register, () => AllocationRegister(register));

  AllocationStack<R> _stack(int displacement, _StackArea area) {
    final result = AllocationStack<R>._(displacement, area);
    _stacks.add(result);
    return result;
  }

  AllocationStack<R> _slot(Value value) =>
      _homes.putIfAbsent(value, () => _stack(_localWords++ * 8, .local));

  Value _stored(Value value) =>
      value is TestedValue ? value.test.operand : value;

  ValueRepresentation _representation(Value value) =>
      selection.layouts.representation(selection.body.typeOf(value));

  RegisterBank _bank(ValueRepresentation representation) =>
      representation == .floating ? .floating : .general;

  FunctionAllocation<R> build() {
    _assignEntries();
    for (final block in selection.body.blocks) {
      _begin(block);
      for (final operation in selection.body.instructions[block]!) {
        if (!selection.liveness.omitted.contains(operation)) {
          _operations[operation] = _operation(operation, block);
        }
      }
      _terminators[block] = _terminator(block);
    }
    final framed =
        _stacks.isNotEmpty ||
        selection.calls.isNotEmpty ||
        selection.body.ends.values.any((end) => end is Throw);
    final frame = framed
        ? selection.convention.frameLayout(
            localBytes: _localWords * 8,
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
    for (final slot in _stacks) {
      slot.offset =
          slot.displacement +
          switch (slot._area) {
            .local => frame!.localOffset,
            .incoming => frame!.incomingStackOffset,
          };
    }
    final safepoints = <Value, StackRoots>{};
    for (final entry in selection.liveReferences.entries) {
      final offsets = <int>[];
      for (final value in entry.value) {
        final offset = _homes[value]!.offset;
        final local =
            offset >= frame!.localOffset &&
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
      safepoints[entry.key] = StackRoots(
        frame!.incomingStackOffset,
        frame.returnAddressOffset,
        offsets,
      );
    }
    return FunctionAllocation._(
      selection,
      frame,
      _operations,
      _terminators,
      _edges,
      _entries,
      _homes,
      safepoints,
    );
  }

  void _assignEntries() {
    final preferred = <Value, R>{};
    final predecessors = <Block, List<Jump>>{};
    for (final block in selection.body.blocks) {
      for (final edge in selection.body.successors(block)) {
        (predecessors[edge.target] ??= []).add(edge);
      }
    }
    final entry = selection.body.entry;
    final incoming = _entries[entry] = {};
    for (final (i, value) in selection.body.entryParameters.indexed) {
      if (!selection.liveness.liveIn[entry]!.contains(value)) continue;
      switch (selection.entry.parameters[i]) {
        case RegisterArgument(:final register):
          incoming[value] = _register(register);
          preferred[value] = register;
        case StackArgument(:final offset):
          incoming[value] = _homes[value] = _stack(offset, .incoming);
        default:
          throw StateError('Internal aggregate values require storage.');
      }
    }
    final scratch = {
      for (final register in selection.registers)
        selection.registerBanks[register]: register,
    };
    for (final block in selection.body.blocks) {
      if (block == entry) continue;
      final assigned = _entries[block] = {};
      final available = selection.registers
          .where((register) => !scratch.containsValue(register))
          .toList();
      final parameters = selection.body.parametersOf(block);
      for (final value in selection.liveness.liveIn[block]!) {
        if (selection.cells.contains(value)) continue;
        final bank = selection.bank(selection.body.typeOf(value));
        var register = preferred[value];
        final index = value is BlockParameter ? parameters.indexOf(value) : -1;
        if (register == null && index >= 0) {
          for (final edge in predecessors[block] ?? const <Jump>[]) {
            register =
                preferred[_stored(selection.body.argumentsOf(edge)[index])];
            if (register != null && available.contains(register)) break;
          }
        }
        if (register == null ||
            selection.registerBanks[register] != bank ||
            !available.contains(register)) {
          register = available
              .where((register) => selection.registerBanks[register] == bank)
              .lastOrNull;
        }
        if (register == null) {
          assigned[value] = _slot(value);
        } else {
          assigned[value] = _register(register);
          preferred.putIfAbsent(value, () => register!);
          available.remove(register);
        }
      }
    }
  }

  void _begin(Block block) {
    _uses = Map.of(selection.liveness.uses[block]!);
    _liveOut = selection.liveness.liveOut[block]!;
    _registers.clear();
    _spilled.clear();
    for (final entry in _entries[block]!.entries) {
      switch (entry.value) {
        case AllocationRegister(:final register):
          _registers[entry.key] = register;
        case AllocationStack():
          _spilled.add(entry.key);
        default:
          throw StateError('A block entry cannot be a constant.');
      }
    }
    _free
      ..clear()
      ..addAll(
        selection.registers.where(
          (register) => !_registers.containsValue(register),
        ),
      );
  }

  AllocationLocation<R> _location(Value value) {
    value = _stored(value);
    if (value is Constant) return AllocationConstant(value);
    if (_registers[value] case final register?) return _register(register);
    if (_spilled.contains(value)) return _slot(value);
    throw StateError('Missing allocated value: $value');
  }

  R _read(Value value, {Iterable<R> except = const []}) {
    value = _stored(value);
    if (_registers[value] case final register?) return register;
    final source = _location(value);
    final register = _allocate(
      selection.bank(selection.body.typeOf(value)),
      except: except,
    );
    _transfer(
      source,
      _register(register),
      _representation(value),
      _representation(value),
      except: except,
    );
    _registers[value] = register;
    return register;
  }

  R _allocate(
    RegisterBank bank, {
    Iterable<R> except = const [],
    R? preferred,
  }) {
    if (preferred != null &&
        !except.contains(preferred) &&
        selection.registerBanks[preferred] == bank &&
        _free.remove(preferred)) {
      return preferred;
    }
    final index = _free.lastIndexWhere(
      (register) =>
          !except.contains(register) &&
          selection.registerBanks[register] == bank,
    );
    if (index >= 0) return _free.removeAt(index);
    final entry = _registers.entries.firstWhere(
      (entry) =>
          !except.contains(entry.value) &&
          selection.registerBanks[entry.value] == bank,
    );
    _spill(entry.key, entry.value);
    _registers.remove(entry.key);
    return entry.value;
  }

  void _freeTemporary(R register) {
    if (!_registers.containsValue(register) && !_free.contains(register)) {
      _free.add(register);
    }
  }

  void _spill(Value value, R register) {
    if (value is Constant || !_spilled.add(value)) return;
    _moves.add(
      AllocationMove(
        _register(register),
        _slot(value),
        _representation(value),
        _representation(value),
      ),
    );
  }

  void _release(Value value) {
    value = _stored(value);
    final count = _uses[value]! - 1;
    if (count == 0) {
      _uses.remove(value);
      if (!_liveOut.contains(value)) {
        if (_registers.remove(value) case final register?) {
          _freeTemporary(register);
        }
      }
    } else {
      _uses[value] = count;
    }
  }

  void _define(Value value, R register) {
    if (_uses.containsKey(value) || _liveOut.contains(value)) {
      _registers[value] = register;
      _free.remove(register);
    } else {
      _freeTemporary(register);
    }
  }

  bool _used(Value value) =>
      _uses.containsKey(value) || _liveOut.contains(value);

  AllocationMove<R> _move(
    AllocationLocation<R> source,
    AllocationLocation<R> destination,
    ValueRepresentation from,
    ValueRepresentation to,
    R Function(RegisterBank, Set<R>) scratch,
  ) {
    final protected = <R>{
      if (source case AllocationRegister(:final register)) register,
      if (destination case AllocationRegister(:final register)) register,
    };
    R? temporary, auxiliary;
    if (destination is AllocationStack &&
        !(source is AllocationRegister && from == to)) {
      temporary = scratch(_bank(to), protected);
      protected.add(temporary);
    }
    final target = destination is AllocationRegister<R>
        ? destination.register
        : temporary;
    if (to == .floating &&
        (source is AllocationConstant ||
            from != .floating && source is! AllocationRegister)) {
      auxiliary = scratch(.general, {...protected, ?target});
    }
    return AllocationMove(
      source,
      destination,
      from,
      to,
      temporary: temporary,
      auxiliary: auxiliary,
    );
  }

  void _transfer(
    AllocationLocation<R> source,
    AllocationLocation<R> destination,
    ValueRepresentation from,
    ValueRepresentation to, {
    Iterable<R> except = const [],
  }) {
    if (identical(source, destination) && from == to) return;
    final temporaries = <R>[];
    final move = _move(source, destination, from, to, (bank, protected) {
      final register = _allocate(bank, except: {...except, ...protected});
      temporaries.add(register);
      return register;
    });
    _moves.add(move);
    temporaries.forEach(_freeTemporary);
  }

  AllocatedOperation<R> _operation(Value operation, Block block) {
    if (selection.calls.containsKey(operation)) return _call(operation, block);
    final before = _moves = <AllocationMove<R>>[];
    final inputs = <R>[], values = <Value>[], temporaryInputs = <R>[];
    final temporaries = <R>[];
    final resultMoves = <AllocationMove<R>>[];
    R? result;
    var empty = false;
    final preferredResult = switch (selection.body.ends[block]) {
      Return(:final value) when value == operation =>
        selection.entry.resultRegister,
      _ => null,
    };
    R output(
      RegisterBank bank, {
      R? preferred,
      Iterable<R> except = const [],
    }) => _allocate(
      bank,
      preferred: preferredResult ?? preferred,
      except: except,
    );
    R input(Value value, {ValueType? asType}) {
      final from = _representation(_stored(value));
      final to = selection.layouts.representation(
        asType ?? selection.body.typeOf(value),
      );
      final R assigned;
      if (from == to) {
        assigned = _read(value, except: inputs);
      } else {
        final source = _location(value);
        final protected = {
          ...inputs,
          if (source case AllocationRegister(:final register)) register,
        };
        assigned = _allocate(_bank(to), except: protected);
        _transfer(source, _register(assigned), from, to, except: protected);
        temporaryInputs.add(assigned);
      }
      inputs.add(assigned);
      values.add(value);
      return assigned;
    }

    void consume() {
      values.forEach(_release);
      temporaryInputs.forEach(_freeTemporary);
    }

    void emptyResult() {
      empty = true;
      if (_used(operation)) result = output(.general);
    }

    R scratch(RegisterBank bank, {Iterable<R> except = const []}) {
      final register = _allocate(
        bank,
        except: {...inputs, ?result, ...temporaries, ...except},
      );
      temporaries.add(register);
      return register;
    }

    if (selection.body.aliases.contains(operation) &&
        selection.body.inputsOf(operation).isEmpty) {
      emptyResult();
    } else if (selection.constantTests.containsKey(operation) ||
        operation is NativeSymbolAddress) {
      result = output(.general);
    } else if (operation case NewCell(:final initial)
        when selection.cells.contains(operation)) {
      _slot(operation);
      if (initial != null) {
        input(
          selection.body.inputsOf(operation).single,
          asType: (operation.type as CellType).content,
        );
        consume();
      } else if (selection.layouts.isReference(
        selection.body.typeOf(operation),
      )) {
        scratch(.general);
      }
    } else if (operation is KeepAlive) {
      _release(selection.body.inputsOf(operation).single);
      emptyResult();
    } else if (operation is ReadCell &&
        !selection.body.aliases.contains(operation)) {
      _slot(operation.cell);
      result = output(selection.bank(operation.type));
    } else if (operation case WriteCell(:final cell)
        when selection.cells.contains(cell)) {
      input(
        selection.body.inputsOf(operation).last,
        asType: (cell.type as CellType).content,
      );
      consume();
      emptyResult();
    } else if (selection.binaries[operation] case final binary?) {
      final fixed = binary.fixed;
      if (fixed != null) {
        final reserved = {
          fixed.left,
          fixed.right,
          fixed.result,
          ...fixed.clobbered,
        };
        _registers.removeWhere((value, register) {
          if (!reserved.contains(register)) return false;
          _spill(value, register);
          return true;
        });
        _free.removeWhere(reserved.contains);
        for (final (value, register) in [
          (binary.left, fixed.left),
          (binary.right, fixed.right),
        ]) {
          _transfer(
            _location(value),
            _register(register),
            _representation(_stored(value)),
            _representation(_stored(value)),
            except: reserved,
          );
          _release(value);
          inputs.add(register);
        }
        result = fixed.result;
        reserved.where((r) => r != result).forEach(_freeTemporary);
      } else {
        final left = input(
          binary.left,
          asType: binary.floatingInputs ? ValueType.floating : null,
        );
        final right = input(
          binary.right,
          asType: binary.floatingInputs ? ValueType.floating : null,
        );
        consume();
        result = output(
          selection.bank(operation.type),
          preferred: left,
          except: binary.reuseLeft && left != right ? [right] : [],
        );
        if (binary.reuseLeft) {
          _transfer(
            _register(left),
            _register(result!),
            binary.floatingInputs
                ? .floating
                : _representation(_stored(binary.left)),
            binary.floatingInputs
                ? .floating
                : _representation(_stored(binary.left)),
            except: [right],
          );
          inputs[0] = result!;
        }
      }
    } else if (selection.mixedComparisons[operation] case final mixed?) {
      final integer = input(mixed.integer);
      input(mixed.floating);
      consume();
      result = output(.general, except: [integer]);
      scratch(.general);
      scratch(.floating);
    } else if (operation is DoubleBits) {
      input(selection.body.inputsOf(operation).single);
      consume();
      result = output(.general);
    } else if (operation
        case ObjectRuntimeType(:final operand) ||
            ObjectHashCode(:final operand, direct: true)
        when !selection.body.aliases.contains(operation) &&
            (operation is ObjectHashCode || operand.type != .nullType) &&
            selection.layouts.representation(operand.type) == .reference) {
      input(selection.body.inputsOf(operation).single);
      consume();
      result = output(.general, except: inputs);
    } else if (operation
        case StoreField(:final field) || StorageWrite(:final field)) {
      input(selection.body.inputsOf(operation).first);
      input(selection.body.inputsOf(operation).last, asType: field.type);
      consume();
      emptyResult();
    } else if (operation
        case LoadField(:final field) || StorageRead(:final field)
        when !selection.body.aliases.contains(operation)) {
      final source = input(selection.body.inputsOf(operation).first);
      consume();
      final stored = _allocate(selection.bank(field.type), preferred: source);
      result =
          selection.layouts.representation(field.type) ==
                  selection.layouts.representation(
                    selection.body.typeOf(operation),
                  ) ||
              selection.bank(selection.body.typeOf(operation)) ==
                  selection.registerBanks[stored]
          ? stored
          : _allocate(
              selection.bank(selection.body.typeOf(operation)),
              except: [stored],
            );
      temporaries.add(stored);
      final from = selection.layouts.representation(field.type);
      final to = selection.layouts.representation(
        selection.body.typeOf(operation),
      );
      if (from != to) {
        resultMoves.add(
          AllocationMove(_register(stored), _register(result!), from, to),
        );
      }
    } else if (operation is ReferenceAddress ||
        operation is ReferenceFromAddress) {
      final source = input(selection.body.inputsOf(operation).single);
      consume();
      result = output(.general, preferred: source);
    } else if (selection.body.aliases.contains(operation) ||
        operation is TypeView ||
        operation is UncheckedCast ||
        operation is TypeReference ||
        operation is ReifyType ||
        operation is ObjectRuntimeType) {
      final value = selection.body.inputsOf(operation).single;
      final source = input(value, asType: selection.body.typeOf(operation));
      consume();
      result = output(
        selection.bank(selection.body.typeOf(operation)),
        preferred: source,
      );
    } else if (operation is StoreObjectReference ||
        operation is LoadObjectReference ||
        operation is StoreObjectData ||
        operation is LoadObjectData ||
        operation is StoreNative ||
        operation is LoadNative) {
      final object =
          operation is StoreObjectReference ||
          operation is LoadObjectReference ||
          operation is StoreObjectData ||
          operation is LoadObjectData;
      final store =
          operation is StoreObjectReference ||
          operation is StoreObjectData ||
          operation is StoreNative;
      for (final value in selection.body.inputsOf(operation)) {
        input(value);
      }
      consume();
      if (object) scratch(.general);
      final NativeTypeRef? native = switch (operation) {
        StoreObjectData(nativeType: final NativeTypeRef nativeType) ||
        LoadObjectData(nativeType: final NativeTypeRef nativeType) ||
        StoreNative(nativeType: final NativeTypeRef nativeType) ||
        LoadNative(
          :final nativeType,
        ) => nativeType.resolveAbi(selection.convention.target.abi),
        _ => null,
      };
      if (store) {
        if (native?.isSinglePrecision ?? false) scratch(.floating);
        emptyResult();
      } else {
        result = output(
          selection.bank(operation.type),
          preferred: object ? temporaries.first : inputs.first,
        );
      }
    } else if (operation is FloatBitCast ||
        operation is NumericToInt ||
        operation is NumericToDouble ||
        operation is NumericRoundToDouble ||
        operation is NumericSquareRoot ||
        operation is NumericNegate) {
      final source = input(selection.body.inputsOf(operation).single);
      consume();
      result = output(selection.bank(operation.type), preferred: source);
      if (operation is FloatBitCast &&
          operation.width == 32 &&
          operation.type == .integer) {
        scratch(.floating);
      }
      if (operation is NumericNegate && selection.negationNeedsTemporary) {
        scratch(.general);
      }
    } else {
      throw StateError(
        'Unallocated selected operation: ${operation.runtimeType}',
      );
    }
    for (final register in temporaries) {
      if (register != result) _freeTemporary(register);
    }
    if (result != null) _define(operation, result!);
    return AllocatedOperation(
      before: before,
      inputs: inputs,
      result: result,
      temporaries: temporaries,
      resultMoves: resultMoves,
      emptyResult: empty,
    );
  }

  AllocatedOperation<R> _call(Value operation, Block block) {
    final selected = selection.calls[operation]!;
    final before = _moves = <AllocationMove<R>>[];
    final roots = selection.liveReferences[operation]!;
    _registers.removeWhere((value, register) {
      if (!selected.layout.clobberedRegisters.contains(register) &&
          !roots.contains(value)) {
        return false;
      }
      _spill(value, register);
      _free.add(register);
      return true;
    });
    for (final value in roots) {
      _slot(value);
      if (!selection.cells.contains(value) && !_spilled.contains(value)) {
        throw StateError('Live reference has no initialized stack home.');
      }
    }
    final native = operation is NativeInvocation ? operation : null;
    final arguments = <AllocatedArgument<R>>[];
    void argument(int index, R register, {int? stackOffset}) {
      final value = selected.arguments[index];
      final loads = _moves = <AllocationMove<R>>[];
      _transfer(
        _location(value),
        _register(register),
        _representation(_stored(value)),
        selection.layouts.representation(
          selected.parameterTypes?[index] ?? selection.body.typeOf(value),
        ),
      );
      _release(value);
      arguments.add(
        AllocatedArgument(
          loads,
          register,
          stackOffset: stackOffset,
          nativeType: native?.signature.parameters[index].resolveAbi(
            selection.convention.target.abi,
          ),
        ),
      );
    }

    for (final (i, location) in selected.layout.parameters.indexed) {
      if (location case StackArgument(:final offset)) {
        argument(
          i,
          selected.stackScratch[selection.bank(
            selected.parameterTypes?[i] ??
                selection.body.typeOf(selected.arguments[i]),
          )]!,
          stackOffset: offset,
        );
      }
    }
    for (final bank in [RegisterBank.floating, RegisterBank.general]) {
      for (final (i, location) in selected.layout.parameters.indexed) {
        if (location case RegisterArgument(:final register)
            when selection.registerBanks[register] == bank) {
          argument(i, register);
        }
      }
    }
    if (native != null) {
      final loads = _moves = <AllocationMove<R>>[];
      final value = selection.body.inputsOf(native).first;
      _transfer(
        _location(value),
        _register(selected.addressRegister!),
        _representation(_stored(value)),
        .word,
      );
      _release(value);
      arguments.add(AllocatedArgument(loads, selected.addressRegister!));
    }
    if (selected.onThrow case final edge?) {
      _edges[(block, edge)] = _edge(
        edge,
        unwind: {
          UnwindValue.exception: (
            _register(selection.exceptionRegister),
            ValueRepresentation.reference,
          ),
          UnwindValue.stackTrace: (
            _register(selection.traceRegister),
            ValueRepresentation.reference,
          ),
        },
      );
    }
    final after = _moves = <AllocationMove<R>>[];
    final resultMoves = <AllocationMove<R>>[];
    final temporaries = <R>[];
    R? result;
    final empty = native != null && native.signature.result.isVoid;
    if (empty) {
      if (_used(operation)) result = _allocate(.general);
    } else if (selected.layout.resultRegister case final register?) {
      if (operation case Equals(negated: true) || TypeTest(negated: true)) {
        temporaries.add(_allocate(.general, except: [register]));
      }
      final from = native == null
          ? selection.layouts.representation(
              selection.layouts.returnType(selected.target!),
            )
          : _representation(operation);
      final to = _representation(operation);
      result = from == to
          ? register
          : _allocate(_bank(to), preferred: register);
      _moves = resultMoves;
      _transfer(_register(register), _register(result), from, to);
    }
    temporaries.forEach(_freeTemporary);
    if (result != null) _define(operation, result);
    return AllocatedOperation(
      before: before,
      result: result,
      temporaries: temporaries,
      arguments: arguments,
      after: after,
      resultMoves: resultMoves,
      emptyResult: empty,
    );
  }

  AllocatedOperation<R> _terminator(Block block) {
    final before = _moves = <AllocationMove<R>>[];
    final inputs = <R>[];
    final end = selection.body.ends[block]!;
    switch (end) {
      case Return(value: final value?):
        if (selection.entry.resultRegister case final result?) {
          _transfer(
            _location(value),
            _register(result),
            _representation(_stored(value)),
            selection.layouts.representation(
              selection.layouts.returnType(selection.body.target),
            ),
          );
        }
      case Branch(:final condition, :final ifTrue, :final ifFalse):
        inputs.add(_read(condition));
        _edges[(block, ifTrue)] = _edge(ifTrue);
        _edges[(block, ifFalse)] = _edge(ifFalse);
      case final Jump edge:
        _edges[(block, edge)] = _edge(edge);
      case Invoke(:final onReturn):
        if (onReturn != null) _edges[(block, onReturn)] = _edge(onReturn);
      case Throw(:final exception, stackTrace: final trace!, :final onThrow):
        final unwind = {
          UnwindValue.exception: (
            _location(exception),
            _representation(_stored(exception)),
          ),
          UnwindValue.stackTrace: (
            _location(trace),
            _representation(_stored(trace)),
          ),
        };
        if (onThrow == null) {
          before.addAll(
            _parallel([
              AllocationMove(
                unwind[UnwindValue.exception]!.$1,
                _register(selection.exceptionRegister),
                unwind[UnwindValue.exception]!.$2,
                .reference,
              ),
              AllocationMove(
                unwind[UnwindValue.stackTrace]!.$1,
                _register(selection.traceRegister),
                unwind[UnwindValue.stackTrace]!.$2,
                .reference,
              ),
            ]),
          );
        } else {
          _edges[(block, onThrow)] = _edge(onThrow, unwind: unwind);
        }
      case Return() || Unreachable():
        break;
      default:
        throw StateError('Unallocated terminator: ${end.runtimeType}');
    }
    return AllocatedOperation(before: before, inputs: inputs);
  }

  List<AllocationMove<R>> _edge(
    Jump edge, {
    Map<UnwindValue, (AllocationLocation<R>, ValueRepresentation)> unwind =
        const {},
  }) {
    final parameters = selection.body.parametersOf(edge.target);
    return _parallel([
      for (final entry in _entries[edge.target]!.entries)
        (() {
          final index = entry.key is BlockParameter
              ? parameters.indexOf(entry.key as BlockParameter)
              : -1;
          final argument = _stored(
            index < 0 ? entry.key : selection.body.argumentsOf(edge)[index],
          );
          final source = unwind[argument];
          return AllocationMove<R>(
            source?.$1 ?? _location(argument),
            entry.value,
            source?.$2 ?? _representation(argument),
            _representation(entry.key),
          );
        })(),
    ]);
  }

  List<AllocationMove<R>> _parallel(List<AllocationMove<R>> copies) {
    final pending = copies
        .where(
          (move) =>
              !identical(move.source, move.destination) || move.from != move.to,
        )
        .toList();
    final result = <AllocationMove<R>>[];
    final destinations = {
      for (final move in copies)
        if (move.destination case AllocationRegister(:final register)) register,
    };
    while (pending.isNotEmpty) {
      final sources = {
        for (final move in pending)
          if (move.source case AllocationRegister(:final register)) register,
      };
      R? free(RegisterBank bank, Set<R> except) => selection.registers
          .where(
            (register) =>
                selection.registerBanks[register] == bank &&
                !destinations.contains(register) &&
                !sources.contains(register) &&
                !except.contains(register),
          )
          .lastOrNull;
      var completed = false;
      for (final move in pending) {
        if (pending.any(
          (other) =>
              !identical(other, move) &&
              identical(other.source, move.destination),
        )) {
          continue;
        }
        final AllocationMove<R> scheduled;
        try {
          scheduled = _move(
            move.source,
            move.destination,
            move.from,
            move.to,
            (bank, except) => free(bank, except) ?? (throw const _NoScratch()),
          );
        } on _NoScratch {
          continue;
        }
        result.add(scheduled);
        pending.remove(move);
        completed = true;
        break;
      }
      if (completed) continue;
      final occupiedScratch = pending
          .where(
            (move) =>
                move.source is AllocationRegister<R> &&
                !destinations.contains(
                  (move.source as AllocationRegister<R>).register,
                ),
          )
          .firstOrNull;
      final cycle =
          occupiedScratch ??
          pending.firstWhere(
            (move) =>
                move.source is! AllocationConstant &&
                pending.any(
                  (other) => identical(other.destination, move.source),
                ),
          );
      final source = cycle.source;
      final temporaryRegister =
          occupiedScratch == null && source is AllocationRegister
          ? free(_bank(cycle.from), {})
          : null;
      final AllocationLocation<R> temporary;
      if (temporaryRegister != null) {
        temporary = _register(temporaryRegister);
      } else {
        final slot = _cycle ??= _stack(_localWords++ * 8, .local);
        if (pending.any((move) => identical(move.source, slot))) {
          throw StateError(
            'Parallel transfer cannot release its cycle scratch.',
          );
        }
        temporary = slot;
      }
      result.add(
        _move(
          source,
          temporary,
          cycle.from,
          cycle.from,
          (bank, except) =>
              free(bank, except) ??
              (throw StateError('Parallel transfer lacks a scratch register.')),
        ),
      );
      for (var i = 0; i < pending.length; i++) {
        final move = pending[i];
        if (identical(move.source, source)) {
          pending[i] = AllocationMove(
            temporary,
            move.destination,
            move.from,
            move.to,
          );
        }
      }
    }
    return result;
  }
}

final class const _NoScratch() implements Exception;
