import 'package:dartc/hir.dart';

import 'reduce.dart';

/// What is known where code is, beyond what is known at a place that every path
/// to it passes through.
final class Scope([final Scope? _outer]) {
  final _known = <Object, HirValue>{};

  /// The value known for [key].
  HirValue? operator [](Object key) {
    for (Scope? scope = this; scope != null; scope = scope._outer) {
      if (scope._known[key] case final value?) return value;
    }
    return null;
  }

  void operator []=(Object key, HirValue value) => _known[key] = value;

  final _classes = <HirValue, Set<HirClass>>{};

  /// The classes that [value] can be of unless it is null, if they are known.
  Set<HirClass>? classesOf(HirValue value) {
    for (Scope? scope = this; scope != null; scope = scope._outer) {
      if (scope._classes[value] case final classes?) return classes;
    }
    return switch (value) {
      HirNew(:final target) ||
      HirNewArray(:final target) ||
      HirBox(:final target) => {target},
      HirStatic(:final object) => {object.target},
      _ => null,
    };
  }

  void setClasses(HirValue value, Set<HirClass> classes) =>
      _classes[value] = classes;
}

/// What fields of objects and global variables hold, until something changes
/// them.
final class Memory() {
  Map<(HirField, HirValue), HirValue> _fields = {};
  Map<HirGlobal, HirValue> _globals = {};

  Memory copy() => Memory()
    .._fields = Map.of(_fields)
    .._globals = Map.of(_globals);

  HirValue? field(HirField field, HirValue object) => _fields[(field, object)];
  HirValue? global(HirGlobal global) => _globals[global];

  void setField(HirField field, HirValue object, HirValue value) {
    // Other values may be the same object.
    _fields.removeWhere((key, _) => key.$1 == field);
    _fields[(field, object)] = value;
  }

  void readField(HirField field, HirValue object, HirValue value) =>
      _fields[(field, object)] = value;

  void setGlobal(HirGlobal global, HirValue value) => _globals[global] = value;

  /// Forgets what other functions may change.
  void clear() {
    _fields.clear();
    _globals.clear();
  }
}

/// What tells that [instruction] always gives the same as others with an equal
/// key, or null if it may not.
Object? keyOf(HirInstruction instruction) => switch (instruction) {
  HirIntBinary(:final operator, :final left, :final right) => (
    operator,
    _part(left),
    _part(right),
  ),
  HirFloatBinary(:final operator, :final left, :final right) => (
    operator,
    _part(left),
    _part(right),
  ),
  HirBoolBinary(:final operator, :final left, :final right) => (
    operator,
    _part(left),
    _part(right),
  ),
  HirUnary(:final operator, :final operand) => (operator, _part(operand)),
  HirCompare(:final relation, :final left, :final right) => (
    relation,
    _part(left),
    _part(right),
  ),
  HirUnbox(:final field, :final object) => (field, _part(object)),
  HirLoad(:final field, :final object) when field.isFinal => (
    field,
    _part(object),
  ),
  HirLength(:final array) => ('length', _part(array)),
  HirIsInstance(:final test, :final object) => (test, _part(object)),
  HirHasClass(:final target, :final object) => (target, _part(object)),
  _ => null,
};

/// Constants are the same wherever they are made.
Object _part(HirValue value) => switch (value) {
  HirConst(value: final double number) => ('double', bitsOf(number)),
  HirConst(:final value) => ('constant', value),
  HirNull() => 'null',
  HirStatic(:final object) => object,
  _ => value,
};
