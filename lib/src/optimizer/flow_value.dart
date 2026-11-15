import 'package:dartc/ir.dart';

import 'integer_range.dart';

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

/// Native allocation identity, kept separate from managed Dart references.
final class FlowRegion(final FlowObject allocation) {
  @override
  bool operator ==(Object other) =>
      other is FlowRegion && allocation == other.allocation;

  @override
  int get hashCode => allocation.hashCode;
}

/// An address in managed storage, a constant, a layout descriptor or a callback.
///
/// Unknown offsets do not establish that access stays in bounds.
final class FlowAddress.ranged(
  final Object base,
  FlowIntegerRange? offsets, {
  final ValueType type = ValueType.integer,
}) {
  /// Inclusive byte offsets, or null when the displacement is unbounded.
  final FlowIntegerRange? offsets = offsets == FlowIntegerRange.full
      ? null
      : offsets;

  new(Object base, int? offset, {ValueType type = ValueType.integer})
    : this.ranged(
        base,
        offset == null ? null : FlowIntegerRange(offset, offset),
        type: type,
      );

  /// The exact displacement when every alternative has the same offset.
  int? get offset => offsets?.constant;

  this {
    if (base is! FlowObject &&
            base is! Constant &&
            base is! ClassType &&
            base is! FlowRegion &&
            base is! NativeCallbackTarget ||
        type != ValueType.integer && !FfiTypes.isPointer(type)) {
      throw ArgumentError(
        'An address requires a known base and an address type.',
      );
    }
  }

  /// Storage identity, independent of this address's offset and pointer view.
  Object get identity => switch (base) {
    Constant(:final structuralKey) => structuralKey,
    _ => base,
  };

  /// The capability retained by this address, without a concrete numeric value.
  FlowValue get reference => switch (base) {
    final FlowObject object => FlowValue.object(object),
    final Constant constant => FlowValue.constant(constant),
    ClassType() => const FlowValue.bottom(),
    FlowRegion() => FlowValue._(const {}, const {}, const {}, const {}, null, {
      FlowAddress(base, 0),
    }),
    final NativeCallbackTarget target => FlowValue._(
      const {},
      const {},
      const {},
      const {},
      null,
      {FlowAddress(target, 0)},
    ),
    _ => throw StateError('Invalid address base.'),
  };

  @override
  bool operator ==(Object other) =>
      other is FlowAddress &&
      identity == other.identity &&
      offsets == other.offsets &&
      type == other.type;

  @override
  int get hashCode => Object.hash(identity, offsets, type);
}

/// Values arriving on executable paths, including explicit unknown bounds.
///
/// Empty facts mean no value has arrived. Integer alternatives retain bounds;
/// other scalar alternatives widen to their type. Callable identities remain.
final class FlowValue {
  final Map<Object, Constant> _constants;

  /// Runtime allocations, without assuming that a site denotes one object.
  final Set<FlowObject> objects;

  /// Address alternatives, separate from completely unknown scalar values.
  final Set<FlowAddress> addresses;

  /// Bounds for values whose identity or contents are not established.
  final Set<ValueType> unknownTypes;

  /// Equivalent SSA definitions, not merely possible values of the same type.
  ///
  /// A replacement must also dominate its use and belong to the rewritten
  /// activation. Joins retain only aliases valid on every incoming path.
  final Set<FlowSource> sources;
  final FlowValue? _references;
  final FlowIntegerRange? _integers;

  /// Capabilities retained through raw memory, including native storage.
  ///
  /// These are not additional alternatives for this value's type.
  FlowValue get references => _references ?? const FlowValue.bottom();

  const new bottom()
    : _constants = const {},
      objects = const {},
      unknownTypes = const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new constant(Constant value)
    : _constants = Map.unmodifiable({value.structuralKey: value}),
      objects = const {},
      unknownTypes = const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new object(FlowObject value)
    : _constants = const {},
      objects = Set.unmodifiable({value}),
      unknownTypes = const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new unknown(ValueType type)
    : _constants = const {},
      objects = const {},
      unknownTypes = Set.unmodifiable({type}),
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new address(FlowAddress address)
    : _constants = const {},
      objects = const {},
      unknownTypes = const {},
      sources = const {},
      addresses = Set.unmodifiable({address}),
      _integers = null,
      _references = address.reference;

  /// A scalar integer constrained by executable paths.
  factory integerRange(FlowIntegerRange range) => switch (range.constant) {
    final value? => FlowValue.constant(Constant.integer(value)),
    null => ._(
      const {},
      const {},
      {ValueType.integer},
      const {},
      null,
      const {},
      range == FlowIntegerRange.full ? null : range,
    ),
  };

  new _(
    Map<Object, Constant> constants,
    Set<FlowObject> objects,
    Set<ValueType> unknownTypes, [
    Set<FlowSource> sources = const {},
    FlowValue? references,
    Set<FlowAddress> addresses = const {},
    FlowIntegerRange? integers,
  ]) : _constants = Map.unmodifiable(constants),
       objects = Set.unmodifiable(objects),
       unknownTypes = Set.unmodifiable(unknownTypes),
       sources = Set.unmodifiable(sources),
       addresses = Set.unmodifiable(addresses),
       _integers = integers,
       _references = references;

  /// Constants identified structurally, without invoking user equality.
  Iterable<Constant> get constants => _constants.values;

  /// Whether no executable input has supplied a value.
  bool get isBottom =>
      _constants.isEmpty &&
      objects.isEmpty &&
      addresses.isEmpty &&
      unknownTypes.isEmpty;

  /// The unique established constant, if no other value is admitted.
  Constant? get constant =>
      _constants.length == 1 &&
          objects.isEmpty &&
          addresses.isEmpty &&
          unknownTypes.isEmpty
      ? _constants.values.single
      : null;

  /// Semantic types admitted by these facts.
  Iterable<ValueType> get types sync* {
    yield* unknownTypes;
    yield* constants.map((value) => value.type);
    yield* objects.map((value) => value.type);
    yield* addresses.map((value) => value.type);
  }

  /// Bounds apply only to scalar integers, never to raw address capabilities.
  FlowIntegerRange? get integers {
    if (isBottom ||
        objects.isNotEmpty ||
        addresses.isNotEmpty ||
        unknownTypes.any((type) => type != ValueType.integer) ||
        constants.any(
          (value) => value is! ScalarConstant || value.value is! int,
        )) {
      return null;
    }
    if (_integers != null) return _integers;
    if (constant case ScalarConstant(value: final int value)) {
      return FlowIntegerRange(value, value);
    }
    return FlowIntegerRange.full;
  }

  /// Intersects a numeric path condition without changing SSA equivalence.
  FlowValue restrictIntegers(FlowIntegerRange range) {
    final existing = integers;
    if (existing == null &&
        addresses.isNotEmpty &&
        (range.constant == 0 || !range.contains(0))) {
      final zero = range.constant == 0;
      final constants = {
        for (final entry in _constants.entries)
          if (entry.value is! ScalarConstant ||
              (entry.value as ScalarConstant).value != 0 ||
              zero)
            entry.key: entry.value,
      };
      final retained = addresses
          .where((address) => !zero || address.offset != 0)
          .toSet();
      if (zero) {
        constants.removeWhere(
          (_, value) => value is! ScalarConstant || value.value != 0,
        );
        if (unknownTypes.contains(ValueType.integer) || retained.isNotEmpty) {
          const value = Constant.integer(0);
          constants[value.structuralKey] = value;
        }
      }
      return FlowValue._(
        constants,
        objects,
        zero ? const {} : unknownTypes,
        sources,
        _references,
        zero ? const {} : retained,
      );
    }
    if (existing == null) return this;
    final narrowed = existing.intersect(range);
    if (narrowed == null) return const FlowValue.bottom();
    if (narrowed == existing) return this;
    return FlowValue.integerRange(narrowed)
        .withSources(sources)
        .withReferences([references]);
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
      ...addresses.map((value) => value.type),
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
    return FlowValue._(
      _constants,
      objects,
      unknownTypes,
      {...sources, source},
      _references,
      addresses,
      _integers,
    );
  }

  /// Changes analysis allocation identities while preserving semantic values.
  FlowValue mapObjects(FlowObject Function(FlowObject) transform) {
    if (objects.isEmpty && addresses.isEmpty && _references == null) {
      return this;
    }
    final mapped = objects.map(transform).toSet();
    final references = _references?.mapObjects(transform);
    final mappedAddresses = {
      for (final address in addresses)
        FlowAddress.ranged(
          switch (address.base) {
            final FlowObject object => transform(object),
            FlowRegion(:final allocation) => FlowRegion(transform(allocation)),
            final base => base,
          },
          address.offsets,
          type: address.type,
        ),
    };
    if (mapped.length == objects.length &&
        mapped.containsAll(objects) &&
        mappedAddresses.length == addresses.length &&
        mappedAddresses.containsAll(addresses) &&
        references == _references) {
      return this;
    }
    return FlowValue._(
      _constants,
      mapped,
      unknownTypes,
      sources,
      references,
      mappedAddresses,
      _integers,
    );
  }

  /// Replaces equivalent SSA definitions at a call or graph boundary.
  FlowValue withSources(Iterable<FlowSource> values) {
    if (isBottom) return this;
    final mapped = values.toSet();
    if (mapped.length == sources.length && mapped.containsAll(sources)) {
      return this;
    }
    return FlowValue._(
      _constants,
      objects,
      unknownTypes,
      mapped,
      _references,
      addresses,
      _integers,
    );
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
    return FlowValue._(
      _constants,
      objects,
      unknownTypes,
      sources,
      retained,
      addresses,
      _integers,
    );
  }

  /// Filters a runtime type test, retaining aliases on the selected outcome.
  /// The `mayFail` result reports whether values can take the opposite outcome.
  ({FlowValue value, bool mayFail}) check(
    ValueType type, {
    bool negated = false,
  }) {
    var mayFail = false;
    bool retain(ValueType actual) {
      final bool? matches = type.accepts(actual)
          ? true
          : type == ValueType.never ||
                actual == ValueType.nullType && !type.mayBeNull ||
                actual is ClassType && !type.mayHaveInstance(actual)
          ? false
          : type.freeTypeParameters.isNotEmpty ||
                actual.freeTypeParameters.isNotEmpty
          ? null
          : false;
      mayFail |= matches == null || matches == negated;
      return matches == null || matches != negated;
    }

    final constants = {
      for (final entry in _constants.entries)
        if (retain(entry.value.type)) entry.key: entry.value,
    };
    final objects = this.objects.where((object) => retain(object.type)).toSet();
    final addresses = this.addresses
        .where((address) => retain(address.type))
        .toSet();
    final unknown = <ValueType>{};
    const nullValue = Constant.nullValue();
    for (final bound in unknownTypes) {
      if (bound == ValueType.never) continue;
      if (bound == ValueType.nullType) {
        if (retain(bound)) {
          constants[nullValue.structuralKey] = nullValue;
        }
        continue;
      }
      if (type.accepts(bound)) {
        mayFail |= negated;
        if (!negated) unknown.add(bound);
        continue;
      }
      if (type == ValueType.never ||
          type == ValueType.nullType && !bound.mayBeNull) {
        mayFail |= !negated;
        if (negated) unknown.add(bound);
        continue;
      }
      mayFail = true;
      if (!negated) {
        unknown.add(type.accepts(bound.nonNullable) ? bound.nonNullable : type);
      } else if (type.accepts(ValueType.nullType)) {
        final narrowed = bound.nonNullable;
        unknown.add(narrowed.mayBeNull ? ValueType.object : narrowed);
      } else if (type.accepts(bound.nonNullable)) {
        if (bound.mayBeNull) {
          constants[nullValue.structuralKey] = nullValue;
        }
      } else {
        unknown.add(bound);
      }
    }
    constants.removeWhere(
      (_, value) => value is ScalarConstant && unknown.contains(value.type),
    );
    return (
      value:
          constants.isEmpty &&
              objects.isEmpty &&
              addresses.isEmpty &&
              unknown.isEmpty
          ? const .bottom()
          : ._(
              constants,
              objects,
              unknown,
              sources,
              _references,
              addresses,
              _integers,
            ),
      mayFail: mayFail,
    );
  }

  /// Joins values from executable alternatives without inventing call targets.
  FlowValue join(FlowValue other, {bool widen = false}) {
    if (isBottom) return other;
    if (other.isBottom || this == other) return this;
    return FlowValue.joined([this, other], widen: widen);
  }

  /// Collects alternatives without repeatedly copying a growing object graph.
  factory joined(Iterable<FlowValue> inputs, {bool widen = false}) {
    final values = inputs.where((value) => !value.isBottom).toList();
    if (values.isEmpty) return const FlowValue.bottom();
    if (values.length == 1) return values.single;
    final constants = <Object, Constant>{};
    final objects = <FlowObject>{};
    final unknown = <ValueType>{};
    final sources = values.first.sources.toSet();
    final scalars = <ValueType, Object>{};
    final addresses = <(Object, ValueType), FlowAddress>{};
    var integers = values.first.integers;
    for (final (index, value) in values.indexed) {
      if (index != 0) {
        final other = value.integers;
        integers = integers != null && other != null
            ? integers.join(other, widen: widen)
            : null;
      }
      objects.addAll(value.objects);
      unknown.addAll(value.unknownTypes);
      sources.removeWhere((source) => !value.sources.contains(source));
      for (final entry in value._constants.entries) {
        constants[entry.key] = entry.value;
        if (entry.value is! ScalarConstant) continue;
        final type = entry.value.type;
        if (scalars.containsKey(type) && scalars[type] != entry.key) {
          unknown.add(type);
        } else {
          scalars[type] = entry.key;
        }
      }
      for (final address in value.addresses) {
        final key = (address.identity, address.type);
        final previous = addresses[key];
        addresses[key] = previous == null || previous == address
            ? address
            : FlowAddress.ranged(
                address.base,
                previous.offsets == null || address.offsets == null
                    ? null
                    : previous.offsets!.join(address.offsets!, widen: widen),
                type: address.type,
              );
      }
    }
    constants.removeWhere(
      (_, value) => value is ScalarConstant && unknown.contains(value.type),
    );
    final references = FlowValue.joined(
      values.map((value) => value.references),
      widen: widen,
    );
    return FlowValue._(
      constants,
      objects,
      unknown,
      sources,
      references.isBottom ? null : references,
      addresses.values.toSet(),
      integers?.constant == null && integers != FlowIntegerRange.full
          ? integers
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowValue &&
          _constants.length == other._constants.length &&
          _constants.keys.every(other._constants.containsKey) &&
          objects.length == other.objects.length &&
          objects.containsAll(other.objects) &&
          addresses.length == other.addresses.length &&
          addresses.containsAll(other.addresses) &&
          unknownTypes.length == other.unknownTypes.length &&
          unknownTypes.containsAll(other.unknownTypes) &&
          sources.length == other.sources.length &&
          sources.containsAll(other.sources) &&
          _integers == other._integers &&
          _references == other._references;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(_constants.keys),
    Object.hashAllUnordered(objects),
    Object.hashAllUnordered(addresses),
    Object.hashAllUnordered(unknownTypes),
    Object.hashAllUnordered(sources),
    _integers,
    _references,
  );
}
