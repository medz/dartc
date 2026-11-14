import 'package:dartc/ir.dart';

/// An SSA definition whose value equals this fact in one activation.
final class FlowSource(final Value value, final Object activation) {
  @override
  bool operator ==(Object other) =>
      other is FlowSource &&
      identical(value, other.value) &&
      identical(activation, other.activation);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(value), identityHashCode(activation));
}

/// One allocation site in one analysis activation.
final class FlowObject(
  final Instruction site,
  final Object activation, {
  ValueType? type,
  final Object? variant,
}) {
  /// The semantic type after known activation arguments have been substituted.
  final ValueType type = type ?? site.type;

  @override
  bool operator ==(Object other) =>
      other is FlowObject &&
      identical(site, other.site) &&
      identical(activation, other.activation) &&
      type == other.type &&
      variant == other.variant;

  @override
  int get hashCode => Object.hash(
    identityHashCode(site),
    identityHashCode(activation),
    type,
    variant,
  );
}

/// Values arriving on executable paths, including explicit unknown bounds.
///
/// Empty facts mean no value has arrived. Distinct scalar constants widen to
/// their type; function and allocation identities remain distinct.
final class FlowValue {
  final Map<Object, Constant> _constants;

  /// Runtime allocations, without assuming that a site denotes one object.
  final Set<FlowObject> objects;

  /// Bounds for values whose identity or contents are not established.
  final Set<ValueType> unknownTypes;

  /// Equivalent SSA definitions, not merely possible values of the same type.
  ///
  /// A replacement must also dominate its use and belong to the rewritten
  /// activation. Joins retain only aliases valid on every incoming path.
  final Set<FlowSource> sources;
  final FlowValue? _references;

  /// Managed values still reachable through a raw address or native pointer.
  ///
  /// These are capabilities, not additional alternatives for this value's type.
  FlowValue get references => _references ?? const FlowValue.bottom();

  const new bottom()
    : _constants = const {},
      objects = const {},
      unknownTypes = const {},
      sources = const {},
      _references = null;

  new constant(Constant value)
    : _constants = Map.unmodifiable({value.structuralKey: value}),
      objects = const {},
      unknownTypes = const {},
      sources = const {},
      _references = null;

  new object(FlowObject value)
    : _constants = const {},
      objects = Set.unmodifiable({value}),
      unknownTypes = const {},
      sources = const {},
      _references = null;

  new unknown(ValueType type)
    : _constants = const {},
      objects = const {},
      unknownTypes = Set.unmodifiable({type}),
      sources = const {},
      _references = null;

  new _(
    Map<Object, Constant> constants,
    Set<FlowObject> objects,
    Set<ValueType> unknownTypes, [
    Set<FlowSource> sources = const {},
    FlowValue? references,
  ]) : _constants = Map.unmodifiable(constants),
       objects = Set.unmodifiable(objects),
       unknownTypes = Set.unmodifiable(unknownTypes),
       sources = Set.unmodifiable(sources),
       _references = references;

  /// Constants identified structurally, without invoking user equality.
  Iterable<Constant> get constants => _constants.values;

  /// Whether no executable input has supplied a value.
  bool get isBottom =>
      _constants.isEmpty && objects.isEmpty && unknownTypes.isEmpty;

  /// The unique established constant, if no other value is admitted.
  Constant? get constant =>
      _constants.length == 1 && objects.isEmpty && unknownTypes.isEmpty
      ? _constants.values.single
      : null;

  /// Semantic types admitted by these facts.
  Iterable<ValueType> get types sync* {
    yield* unknownTypes;
    yield* constants.map((value) => value.type);
    yield* objects.map((value) => value.type);
  }

  /// Whether a nominal receiver candidate matches known values or unknown bounds.
  ///
  /// An exact allocation cannot gain a subclass merely through a broader view.
  /// Physical carriers of functions and records belong to representation.
  bool mayHaveInstance(ClassType type) {
    if (unknownTypes.any((bound) => bound.mayHaveInstance(type))) return true;
    return [
      ...constants.map((value) => value.type),
      ...objects.map((value) => value.type),
    ].any((actual) {
      if (actual == .nullType) return type == ValueType.nullClass;
      return actual is ClassType &&
          actual.declaration == type.declaration &&
          type.mayHaveInstance(actual);
    });
  }

  /// Associates a definition with the exact value computed on this path.
  FlowValue withSource(Value value, Object activation) {
    if (isBottom) return this;
    final source = FlowSource(value, activation);
    if (sources.contains(source)) return this;
    return FlowValue._(_constants, objects, unknownTypes, {
      ...sources,
      source,
    }, _references);
  }

  /// Changes analysis allocation identities while preserving semantic values.
  FlowValue mapObjects(FlowObject Function(FlowObject) transform) {
    if (objects.isEmpty && _references == null) return this;
    final mapped = objects.map(transform).toSet();
    final references = _references?.mapObjects(transform);
    if (mapped.length == objects.length &&
        mapped.containsAll(objects) &&
        references == _references) {
      return this;
    }
    return FlowValue._(_constants, mapped, unknownTypes, sources, references);
  }

  /// Replaces equivalent SSA definitions at a call or graph boundary.
  FlowValue withSources(Iterable<FlowSource> values) {
    if (isBottom) return this;
    final mapped = values.toSet();
    if (mapped.length == sources.length && mapped.containsAll(sources)) {
      return this;
    }
    return FlowValue._(_constants, objects, unknownTypes, mapped, _references);
  }

  /// Retains address provenance without changing the represented Dart value.
  FlowValue withReferences(Iterable<FlowValue> values) {
    var retained = references;
    for (final value in values) {
      retained = retained
          .join(FlowValue._(value._constants, value.objects, const {}))
          .join(value.references);
    }
    if (retained == references) return this;
    return FlowValue._(_constants, objects, unknownTypes, sources, retained);
  }

  /// Filters values by a runtime type check without losing successful aliases.
  ({FlowValue value, bool mayFail}) check(ValueType type) {
    var checked = const FlowValue.bottom();
    var mayFail = false;
    for (final constant in constants) {
      if (type.freeTypeParameters.isNotEmpty) {
        mayFail = true;
        checked = checked.join(.constant(constant));
      } else if (type.accepts(constant.type)) {
        checked = checked.join(.constant(constant));
      } else {
        mayFail = true;
      }
    }
    for (final object in objects) {
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
    for (final bound in unknownTypes) {
      if (type.freeTypeParameters.isEmpty &&
          bound.freeTypeParameters.isEmpty &&
          type.accepts(bound)) {
        checked = checked.join(.unknown(bound));
      } else {
        mayFail = true;
        checked = checked.join(.unknown(type));
      }
    }
    return (
      value: checked.isBottom
          ? checked
          : FlowValue._(
              checked._constants,
              checked.objects,
              checked.unknownTypes,
              sources,
              _references,
            ),
      mayFail: mayFail,
    );
  }

  /// Joins values from executable alternatives without inventing call targets.
  FlowValue join(FlowValue other) {
    if (isBottom) return other;
    if (other.isBottom || this == other) return this;
    final constants = {..._constants, ...other._constants};
    final objects = {...this.objects, ...other.objects};
    final unknown = {...unknownTypes, ...other.unknownTypes};
    final scalars = <ValueType, Object>{};
    for (final entry in constants.entries) {
      if (entry.value is! ScalarConstant) continue;
      final type = entry.value.type;
      if (scalars.containsKey(type) && scalars[type] != entry.key) {
        unknown.add(type);
      } else {
        scalars[type] = entry.key;
      }
    }
    constants.removeWhere(
      (_, value) => value is ScalarConstant && unknown.contains(value.type),
    );
    return FlowValue._(
      constants,
      objects,
      unknown,
      sources.intersection(other.sources),
      references.isBottom && other.references.isBottom
          ? null
          : references.join(other.references),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FlowValue &&
      _constants.length == other._constants.length &&
      _constants.keys.every(other._constants.containsKey) &&
      objects.length == other.objects.length &&
      objects.containsAll(other.objects) &&
      unknownTypes.length == other.unknownTypes.length &&
      unknownTypes.containsAll(other.unknownTypes) &&
      sources.length == other.sources.length &&
      sources.containsAll(other.sources) &&
      _references == other._references;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(_constants.keys),
    Object.hashAllUnordered(objects),
    Object.hashAllUnordered(unknownTypes),
    Object.hashAllUnordered(sources),
    _references,
  );
}
