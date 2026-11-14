import 'package:dartc/ir.dart';

import 'flow_value.dart';

/// Normal and exceptional storage snapshots; null denotes an unreachable exit.
typedef FlowResult = ({
  FlowValue value,
  FlowState? normal,
  FlowState? exceptional,
});

/// Queries a source call in the program's shared worklist.
typedef FlowInvoke = FlowResult Function(
  FunctionTarget target,
  List<FlowValue> arguments,
  FlowState input,
);

/// Queries a callable value without discarding its captured environment.
typedef FlowCall = FlowResult Function(
  FlowValue function,
  List<FlowValue> arguments,
  FlowState input,
);

/// Storage facts at one executable program point.
///
/// Transfers return independent exit snapshots. Allocation identities and call
/// scheduling belong to the program solver, including repetition in its CFG.
final class FlowState {
  /// The immutable semantic graph whose declarations identify slots.
  final IrProgram program;
  final Map<GlobalVariable, _Slot> _globals;
  final Map<FlowObject, _ObjectState> _objects;
  FlowValue _escaped;

  new(this.program)
    : _globals = {
        for (final global in program.globals)
          global: !global.isLate && global.initializer == null
              ? _Slot.bound(_null)
              : const _Slot.unbound(),
      },
      _objects = {},
      _escaped = const .bottom();

  new _(this.program, this._globals, this._objects, this._escaped);

  /// Makes a point snapshot without sharing mutable storage maps.
  FlowState copy() => FlowState._(
    program,
    {..._globals},
    {for (final e in _objects.entries) e.key: e.value.copy()},
    _escaped,
  );

  /// Adds an executable alternative, returning whether any fact changed.
  bool join(FlowState incoming) {
    if (!identical(program, incoming.program)) {
      throw ArgumentError('Cannot join storage from a different IR graph.');
    }
    var changed = false;
    for (final entry in incoming._globals.entries) {
      final before = _globals[entry.key]!;
      final after = before.join(entry.value);
      if (before != after) {
        _globals[entry.key] = after;
        changed = true;
      }
    }
    for (final entry in incoming._objects.entries) {
      final before = _objects[entry.key];
      if (before == null) {
        _objects[entry.key] = entry.value.copy();
        changed = true;
      } else {
        changed = before.join(entry.value) || changed;
      }
    }
    final escaped = _escaped.join(incoming._escaped);
    changed = escaped != _escaped || changed;
    _escaped = escaped;
    return changed;
  }

  /// Captures of this allocation, preserving shared cell identities.
  List<FlowValue>? capturesOf(FlowObject object) => _objects[object]?.captures;

  /// Records the environment of a closure selected by the program solver.
  void retain(
    FlowObject object,
    List<FlowValue> captures, {
    required bool repeated,
  }) {
    _allocate(object, _ObjectState({}, captures: captures, summary: repeated));
  }

  /// Values that an external operation may still reach after earlier escapes.
  FlowValue get escapedValues => _reachable([_escaped]);

  /// Records external reachability, including nested closures and shared cells.
  FlowValue escape(Iterable<FlowValue> roots) {
    final reachable = _reachable(roots);
    _escaped = _escaped.join(reachable);
    for (final object in reachable.objects) {
      _objects[object]?.escaped = true;
    }
    return reachable;
  }

  /// Forgets values an external operation can write through the given roots.
  ///
  /// The caller supplies previously escaped roots and global access explicitly.
  void invalidate(Iterable<FlowValue> roots, {bool globals = false}) {
    final reachable = _reachable([
      ...roots,
      if (globals)
        for (final slot in _globals.values) ...[slot.value, slot.initializer],
    ]);
    for (final object in reachable.objects) {
      final state = _objects[object];
      if (state == null) continue;
      for (final entry in state.slots.entries.toList()) {
        final key = entry.key;
        final type = key is InstanceField
            ? key.typeFor(object.type as ClassType)
            : (object.type as CellType).content;
        final isFinal = key is InstanceField
            ? key.isFinal
            : (object.type as CellType).isFinal;
        state.slots[key] = entry.value.invalidate(type, isFinal: isFinal);
      }
    }
    if (globals) {
      for (final entry in _globals.entries.toList()) {
        _globals[entry.key] = entry.value.invalidate(
          entry.key.type,
          isFinal: entry.key.isFinal,
        );
      }
    }
  }

  /// Evaluates storage operations; null leaves other operations to the solver.
  FlowResult? transfer(
    Instruction operation,
    List<FlowValue> operands, {
    required FlowObject Function(Instruction) allocate,
    required bool repeated,
    required FlowInvoke invoke,
    required FlowCall call,
  }) {
    if (operands.length != operation.inputs.length) {
      throw ArgumentError('Storage transfer requires every operand.');
    }
    switch (operation) {
      case Construct(:final initializer):
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final object = allocate(operation);
        final type = object.type as ClassType;
        final next = copy();
        final slots = <Object, _Slot>{};
        for (ClassType? view = type; view != null; view = view.superclass) {
          for (final field in _class(view)?.fields ?? <InstanceField>[]) {
            slots[field] = !field.isLate && field.typeFor(type).mayBeNull
                ? _Slot.bound(_null)
                : const _Slot.unbound();
          }
        }
        next._allocate(object, _ObjectState(slots, summary: repeated));
        final value = FlowValue.object(object);
        final result = invoke(initializer, [value, ...operands], next);
        return (
          value: result.normal == null ? const .bottom() : value,
          normal: result.normal,
          exceptional: result.exceptional,
        );
      case NewCell(:final initial, :final initializer):
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final object = allocate(operation);
        final checked = initial == null
            ? (value: const FlowValue.bottom(), mayFail: false)
            : (object.type as CellType).isLate
            ? _check(operands.first, (object.type as CellType).content)
            : (value: operands.first, mayFail: false);
        if (initial != null && checked.value.isBottom) {
          return (value: const .bottom(), normal: null, exceptional: copy());
        }
        final slot = initial != null
            ? _Slot.bound(checked.value)
            : _Slot.unbound(
                initializer: initializer == null
                    ? const .bottom()
                    : operands.single,
              );
        final next = copy();
        next._allocate(object, _ObjectState({_cell: slot}, summary: repeated));
        return (
          value: .object(object),
          normal: next,
          exceptional: checked.mayFail ? copy() : null,
        );
      case CopyCell():
        if (operands.single.isBottom) return _unreachable;
        final object = allocate(operation);
        _Slot? copied;
        for (final source in operands.single.objects) {
          final slot =
              _objects[source]?.slots[_cell] ??
              _Slot.unknown((source.type as CellType).content);
          copied = copied == null ? slot : copied.join(slot);
        }
        if (operands.single.unknownTypes.isNotEmpty) {
          final slot = _Slot.unknown((object.type as CellType).content);
          copied = copied == null ? slot : copied.join(slot);
        }
        if (copied == null) return _unreachable;
        final next = copy();
        next._allocate(
          object,
          _ObjectState({_cell: copied}, summary: repeated),
        );
        return _normal(.object(object), next);
      case MakeClosure():
        if (operands.any((value) => value.isBottom)) return _unreachable;
        final object = allocate(operation);
        final next = copy()..retain(object, operands, repeated: repeated);
        return _normal(.object(object), next);
      case LoadGlobal(:final global):
        _requireGlobal(global);
        return _read(
          (null, global),
          global.type,
          isFinal: global.isFinal,
          initialize: global.initializer == null
              ? null
              : (input) => invoke(global.initializer!, [], input),
        );
      case StoreGlobal(:final global):
        _requireGlobal(global);
        return _write(
          (null, global),
          operands.single,
          global.type,
          isFinal: global.isFinal,
        );
      case ReadCell():
        return _readObjects(
          operands.single,
          _cell,
          operation.type,
          invoke: invoke,
          call: call,
        );
      case LoadField(:final field):
        return _readObjects(
          operands.single,
          field,
          operation.type,
          invoke: invoke,
          call: call,
        );
      case WriteCell():
        return _writeObjects(operands.first, _cell, operands.last);
      case StoreField(:final field):
        return _writeObjects(operands.first, field, operands.last);
      default:
        return null;
    }
  }

  FlowResult _readObjects(
    FlowValue receiver,
    Object key,
    ValueType resultType, {
    required FlowInvoke invoke,
    required FlowCall call,
  }) {
    var result = _unreachable;
    for (final object in receiver.objects) {
      final field = key is InstanceField ? key : null;
      final cell = field == null ? object.type as CellType : null;
      final type = field?.typeFor(object.type as ClassType) ?? cell!.content;
      final slot = _objects[object]?.slots[key];
      if (slot == null) {
        result = _merge(
          result,
          _unknownRead(.object(object), key, type, invoke: invoke, call: call),
        );
        continue;
      }
      var read = _read(
        (object, key),
        type,
        isFinal: field?.isFinal ?? cell!.isFinal,
        initialize: field != null
            ? field.initializer == null
                  ? null
                  : (input) =>
                        invoke(field.initializer!, [.object(object)], input)
            : slot.initializer.isBottom
            ? null
            : (input) => call(slot.initializer, [], input),
      );
      if (field != null && _weak(field) && read.normal != null) {
        read = (
          value: read.value.join(_null),
          normal: read.normal,
          exceptional: read.exceptional,
        );
      }
      if (field?.requiresReadCheck ?? false) {
        read = _checkedRead(read, resultType);
      }
      result = _merge(result, read);
    }
    for (final constant in receiver.constants) {
      if (key is InstanceField && constant is ObjectConstant) {
        final value = constant.fields[key];
        if (value != null) {
          var read = _normal(FlowValue.constant(value), copy());
          if (_weak(key)) read = _normal(read.value.join(_null), read.normal!);
          if (key.requiresReadCheck) read = _checkedRead(read, resultType);
          result = _merge(result, read);
          continue;
        }
      }
      result = _merge(
        result,
        _unknownRead(
          .constant(constant),
          key,
          resultType,
          invoke: invoke,
          call: call,
        ),
      );
    }
    for (final bound in receiver.unknownTypes) {
      result = _merge(
        result,
        _unknownRead(
          .unknown(bound),
          key,
          resultType,
          invoke: invoke,
          call: call,
        ),
      );
    }
    return result;
  }

  FlowResult _unknownRead(
    FlowValue receiver,
    Object key,
    ValueType type, {
    required FlowInvoke invoke,
    required FlowCall call,
  }) {
    final field = key is InstanceField ? key : null;
    final cell = field == null ? receiver.types.single as CellType : null;
    var result = _normal(FlowValue.unknown(type), copy());
    if (field?.isLate ?? cell!.isLate) {
      final initialized = field == null
          ? call(.unknown(FunctionType(type, [])), [], copy())
          : field.initializer == null
          ? _unreachable
          : invoke(field.initializer!, [receiver], copy());
      if (initialized.normal case final normal?) {
        final committed = normal._writeObjects(
          receiver,
          key,
          initialized.value,
        );
        result = _merge(result, (
          value: committed.normal == null ? const .bottom() : .unknown(type),
          normal: committed.normal,
          exceptional: committed.exceptional,
        ));
      }
      result = _merge(result, (
        value: const .bottom(),
        normal: null,
        exceptional: initialized.exceptional,
      ));
      result = _merge(result, (
        value: const .bottom(),
        normal: null,
        exceptional: _joinStates(this, initialized.normal),
      ));
    } else if (field?.requiresReadCheck ?? false) {
      result = (
        value: result.value,
        normal: result.normal,
        exceptional: copy(),
      );
    }
    return result;
  }

  FlowResult _writeObjects(FlowValue receiver, Object key, FlowValue value) {
    if (value.isBottom) return _unreachable;
    var result = _unreachable;
    final unknownBounds = {
      ...receiver.unknownTypes,
      ...receiver.constants.map((value) => value.type),
    };
    for (final object in receiver.objects) {
      final field = key is InstanceField ? key : null;
      final cell = field == null ? object.type as CellType : null;
      if (_objects[object]?.slots[key] == null) {
        unknownBounds.add(object.type);
        continue;
      }
      result = _merge(
        result,
        _write(
          (object, key),
          value,
          field?.typeFor(object.type as ClassType) ?? cell!.content,
          isFinal: field == null
              ? cell!.isFinal
              : field.isLate && field.isFinal,
        ),
      );
    }
    if (unknownBounds.isNotEmpty) {
      final next = copy();
      for (final object in next._objects.keys) {
        final state = next._objects[object]!;
        final slot = state.slots[key];
        if (slot == null ||
            !unknownBounds.any(
              (t) => object.type is ClassType
                  ? t.mayHaveInstance(object.type as ClassType)
                  : t.accepts(object.type),
            )) {
          continue;
        }
        final type = key is InstanceField
            ? key.typeFor(object.type as ClassType)
            : (object.type as CellType).content;
        final isFinal = key is InstanceField
            ? key.isLate && key.isFinal
            : (object.type as CellType).isFinal;
        if (isFinal && !slot.unbound) continue;
        final checked = _check(value, type);
        if (!checked.value.isBottom) {
          state.slots[key] = slot.join(_Slot.bound(checked.value));
          if (state.escaped) next.escape([checked.value]);
        }
      }
      result = _merge(result, (
        value: _null,
        normal: next,
        exceptional: copy(),
      ));
    }
    return result;
  }

  FlowResult _read(
    (FlowObject?, Object) location,
    ValueType type, {
    required bool isFinal,
    required FlowResult Function(FlowState)? initialize,
  }) {
    final slot = _slot(location);
    var result = _unreachable;
    if (!slot.value.isBottom) {
      final bound = copy().._refine(location, _Slot.bound(slot.value));
      result = _normal(slot.value, bound);
    }
    if (slot.unbound) {
      final unbound = copy()
        .._refine(location, _Slot.unbound(initializer: slot.initializer));
      if (initialize == null) {
        result = _merge(result, (
          value: const .bottom(),
          normal: null,
          exceptional: unbound,
        ));
      } else {
        final initialized = initialize(unbound);
        var bound = (
          value: const FlowValue.bottom(),
          normal: null as FlowState?,
          exceptional: initialized.exceptional,
        );
        if (initialized.normal case final normal?) {
          bound = _merge(
            bound,
            normal._write(location, initialized.value, type, isFinal: isFinal),
          );
        }
        result = _merge(result, bound);
      }
    }
    return result;
  }

  FlowResult _write(
    (FlowObject?, Object) location,
    FlowValue value,
    ValueType type, {
    required bool isFinal,
  }) {
    final checked = _check(value, type);
    FlowState? exceptional = checked.mayFail ? copy() : null;
    if (checked.value.isBottom) {
      return (value: const .bottom(), normal: null, exceptional: exceptional);
    }
    final slot = _slot(location);
    if (isFinal && !slot.value.isBottom) {
      final bound = copy().._refine(location, _Slot.bound(slot.value));
      exceptional = _joinStates(exceptional, bound);
    }
    if (isFinal && !slot.unbound) {
      return (value: const .bottom(), normal: null, exceptional: exceptional);
    }
    final next = copy();
    next._set(location, _Slot.bound(checked.value));
    if (location.$1 case final object? when next._objects[object]!.escaped) {
      next.escape([checked.value]);
    }
    return (value: checked.value, normal: next, exceptional: exceptional);
  }

  void _allocate(FlowObject object, _ObjectState state) {
    final prior = _objects[object];
    if (prior == null) {
      _objects[object] = state;
    } else {
      // The input already contains an earlier allocation, not a solver revisit.
      prior.summary = true;
      prior.join(state);
    }
  }

  _Slot _slot((FlowObject?, Object) location) => location.$1 == null
      ? _globals[location.$2 as GlobalVariable]!
      : _objects[location.$1]!.slots[location.$2]!;

  void _set((FlowObject?, Object) location, _Slot slot) {
    final object = location.$1;
    if (object == null) {
      _globals[location.$2 as GlobalVariable] = slot;
    } else {
      final state = _objects[object]!;
      state.slots[location.$2] = state.summary || state.escaped
          ? state.slots[location.$2]!.join(slot)
          : slot;
    }
  }

  void _refine((FlowObject?, Object) location, _Slot slot) {
    final object = location.$1;
    if (object == null ||
        !(_objects[object]!.summary || _objects[object]!.escaped)) {
      _set(location, slot);
    }
  }

  void _requireGlobal(GlobalVariable global) {
    if (!_globals.containsKey(global)) {
      throw ArgumentError('Global does not belong to this IR graph.');
    }
  }

  IrClass? _class(ClassType type) => program.classes
      .where((definition) => identical(definition.type, type.declaration))
      .firstOrNull;

  bool _weak(InstanceField field) {
    final definition = _class(field.owner);
    return definition != null &&
        (definition.weakFields.contains(field) ||
            definition.ephemerons.containsKey(field) ||
            definition.ephemerons.containsValue(field));
  }

  FlowValue _reachable(Iterable<FlowValue> roots) {
    var result = const FlowValue.bottom();
    final pending = roots.toList();
    final objects = <FlowObject>{};
    final constants = <Object>{};
    while (pending.isNotEmpty) {
      final value = pending.removeLast();
      result = result.join(value);
      for (final object in value.objects) {
        if (!objects.add(object)) continue;
        final state = _objects[object];
        if (state == null) continue;
        pending.addAll(state.captures ?? const []);
        for (final slot in state.slots.values) {
          pending.add(slot.value);
          if (slot.unbound) pending.add(slot.initializer);
        }
      }
      for (final constant in value.constants) {
        if (!constants.add(constant.structuralKey)) continue;
        final nested = switch (constant) {
          ObjectConstant(:final fields) => fields.values,
          RecordConstant(:final fields) => fields,
          SequenceConstant(:final elements) => elements,
          MapConstant(:final entries) => entries.expand((e) => [e.$1, e.$2]),
          _ => const <Constant>[],
        };
        pending.addAll(nested.map(FlowValue.constant));
      }
    }
    return result;
  }
}

final _cell = Object();
final _null = FlowValue.constant(const Constant.nullValue());
const FlowResult _unreachable = (
  value: FlowValue.bottom(),
  normal: null,
  exceptional: null,
);

FlowResult _normal(FlowValue value, FlowState state) =>
    (value: value, normal: state, exceptional: null);

FlowState? _joinStates(FlowState? left, FlowState? right) {
  if (left == null) return right?.copy();
  if (right == null) return left.copy();
  return left.copy()..join(right);
}

FlowResult _merge(FlowResult left, FlowResult right) => (
  value: left.value.join(right.value),
  normal: _joinStates(left.normal, right.normal),
  exceptional: _joinStates(left.exceptional, right.exceptional),
);

({FlowValue value, bool mayFail}) _check(FlowValue value, ValueType type) {
  var checked = const FlowValue.bottom();
  var mayFail = false;
  for (final constant in value.constants) {
    if (type.freeTypeParameters.isNotEmpty) {
      mayFail = true;
      checked = checked.join(.constant(constant));
    } else if (type.accepts(constant.type)) {
      checked = checked.join(.constant(constant));
    } else {
      mayFail = true;
    }
  }
  for (final object in value.objects) {
    if (type.freeTypeParameters.isNotEmpty ||
        object.type.freeTypeParameters.isNotEmpty) {
      mayFail = true;
      checked = checked.join(.object(object));
    } else if (type.accepts(object.type)) {
      checked = checked.join(.object(object));
    } else {
      mayFail = true;
    }
  }
  for (final bound in value.unknownTypes) {
    if (type.freeTypeParameters.isEmpty &&
        bound.freeTypeParameters.isEmpty &&
        type.accepts(bound)) {
      checked = checked.join(.unknown(bound));
    } else {
      mayFail = true;
      checked = checked.join(.unknown(type));
    }
  }
  return (value: checked, mayFail: mayFail);
}

FlowResult _checkedRead(FlowResult result, ValueType type) {
  if (result.normal == null) return result;
  final checked = _check(result.value, type);
  return (
    value: checked.value,
    normal: checked.value.isBottom ? null : result.normal,
    exceptional: checked.mayFail
        ? _joinStates(result.exceptional, result.normal)
        : result.exceptional,
  );
}

final class _Slot {
  final FlowValue value;
  final bool unbound;
  final FlowValue initializer;

  const new unbound({this.initializer = const .bottom()})
    : value = const .bottom(),
      unbound = true;
  const new bound(this.value) : unbound = false, initializer = const .bottom();
  new unknown(ValueType type)
    : value = .unknown(type),
      unbound = true,
      initializer = .unknown(FunctionType(type, []));
  const new _(this.value, this.unbound, this.initializer);

  _Slot join(_Slot other) => _Slot._(
    value.join(other.value),
    unbound || other.unbound,
    initializer.join(other.initializer),
  );

  _Slot invalidate(ValueType type, {required bool isFinal}) =>
      isFinal && !unbound
      ? this
      : _Slot._(value.join(.unknown(type)), unbound, initializer);

  @override
  bool operator ==(Object other) =>
      other is _Slot &&
      other.value == value &&
      other.unbound == unbound &&
      other.initializer == initializer;
  @override
  int get hashCode => Object.hash(value, unbound, initializer);
}

final class _ObjectState(
  final Map<Object, _Slot> slots, {
  List<FlowValue>? captures,
  bool summary = false,
  bool escaped = false,
}) {
  List<FlowValue>? captures = captures == null ? null : .unmodifiable(captures);
  bool summary = summary;
  bool escaped = escaped;

  _ObjectState copy() => _ObjectState(
    {...slots},
    captures: captures,
    summary: summary,
    escaped: escaped,
  );

  bool join(_ObjectState incoming) {
    var changed = incoming.summary && !summary || incoming.escaped && !escaped;
    summary |= incoming.summary;
    escaped |= incoming.escaped;
    for (final entry in incoming.slots.entries) {
      final before = slots[entry.key];
      final after = before?.join(entry.value) ?? entry.value;
      if (before != after) {
        slots[entry.key] = after;
        changed = true;
      }
    }
    if (incoming.captures case final other?) {
      if (captures == null) {
        captures = other;
        changed = true;
      } else {
        if (captures!.length != other.length) {
          throw StateError('One closure allocation has incompatible captures.');
        }
        final joined = <FlowValue>[];
        for (var i = 0; i < other.length; i++) {
          final value = captures![i].join(other[i]);
          changed = value != captures![i] || changed;
          joined.add(value);
        }
        captures = List.unmodifiable(joined);
      }
    }
    return changed;
  }
}
