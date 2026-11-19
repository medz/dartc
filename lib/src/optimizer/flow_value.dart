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
  final CellStorage? cellStorage,
  final StorageView? storageView,
}) {
  /// The semantic type after known activation arguments have been substituted.
  final ValueType type = type ?? site.type;

  /// The real managed layout, distinct from a callable's language signature.
  ClassType? get storageType =>
      callableStorage?.type ?? (type is ClassType ? type as ClassType : null);

  CallableStorage? get callableStorage => switch (site) {
    AllocatedObject(:final callableStorage) ||
    Construct(:final callableStorage) => callableStorage,
    _ => null,
  };

  bool hasCellType(CellType cell) => storageView?.capability == cell &&
      cellStorage != null && storageType != null &&
      cellStorage!.contains(cell, storageType!);

  @override
  bool operator ==(Object other) =>
      other is FlowObject &&
      identical(site, other.site) &&
      identical(activation, other.activation) &&
      type == other.type &&
      variant == other.variant &&
      storageView == other.storageView;

  @override
  int get hashCode => Object.hash(
    identityHashCode(site),
    identityHashCode(activation),
    type,
    variant,
    storageView,
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

/// Immutable module metadata whose bytes depend on final machine locations.
enum FlowMetadata() {
  stackMaps,
  moduleRoots,
}

/// A native address whose base identity survives numeric address arithmetic.
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
            base is! FlowMetadata &&
            base is! FunctionTarget &&
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
    FunctionTarget() => const FlowValue.bottom(),
    FlowRegion() => FlowValue._(const {}, const {}, const {}, const {}, null, {
      FlowAddress(base, 0),
    }),
    FlowMetadata() => FlowValue._(
      const {},
      const {},
      const {},
      const {},
      null,
      {FlowAddress(base, 0)},
    ),
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

  /// Allocations carrying this value, without adding semantic alternatives or
  /// granting a raw-memory capability to the represented Dart value.
  final Set<FlowObject> managedBackings;

  /// Some reference carriers have no established allocation identity.
  ///
  /// A join must not project only its known carriers and lose these paths.
  final bool hasUnknownBacking;

  /// Unknown scalar-storage capabilities revealed by an actual raw observation.
  ///
  /// These bounds are not semantic alternatives and are absent from ordinary
  /// scalar values. They survive byte snapshots even when no address is known.
  final Set<ValueType> rawBackingTypes;

  /// Address alternatives, separate from completely unknown scalar values.
  final Set<FlowAddress> addresses;

  /// Bounds for values whose identity or contents are not established.
  final Set<ValueType> unknownTypes;

  /// Unknown references originating outside this execution's local heap.
  ///
  /// These bounds can alias modeled objects only through a capability already
  /// exposed to that heap. A later local allocation alone creates no alias.
  /// Bounds absent here retain unrestricted aliasing, including raw snapshots.
  final Set<ValueType> externalUnknownTypes;

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
      managedBackings = const {},
      hasUnknownBacking = false,
      rawBackingTypes = const {},
      unknownTypes = const {},
      externalUnknownTypes = const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new constant(Constant value)
    : _constants = Map.unmodifiable({value.structuralKey: value}),
      objects = const {},
      managedBackings = const {},
      hasUnknownBacking = false,
      rawBackingTypes = const {},
      unknownTypes = const {},
      externalUnknownTypes = const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new object(FlowObject value)
    : _constants = const {},
      objects = Set.unmodifiable({value}),
      managedBackings = const {},
      hasUnknownBacking = false,
      rawBackingTypes = const {},
      unknownTypes = const {},
      externalUnknownTypes = const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new unknown(ValueType type, {bool external = false})
    : _constants = const {},
      objects = const {},
      managedBackings = const {},
      hasUnknownBacking = false,
      rawBackingTypes = const {},
      unknownTypes = Set.unmodifiable({type}),
      externalUnknownTypes = external && _mayCarryReference(type)
          ? Set.unmodifiable({type})
          : const {},
      sources = const {},
      addresses = const {},
      _integers = null,
      _references = null;

  new address(FlowAddress address)
    : _constants = const {},
      objects = const {},
      managedBackings = const {},
      hasUnknownBacking = false,
      rawBackingTypes = const {},
      unknownTypes = const {},
      externalUnknownTypes = const {},
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
    Set<ValueType> externalUnknownTypes = const {},
    Set<FlowObject> managedBackings = const {},
    this.hasUnknownBacking = false,
    Set<ValueType> rawBackingTypes = const {},
  ]) : _constants = Map.unmodifiable(constants),
       objects = Set.unmodifiable(objects),
       managedBackings = Set.unmodifiable(managedBackings),
       rawBackingTypes = Set.unmodifiable(rawBackingTypes),
       unknownTypes = Set.unmodifiable(unknownTypes),
       externalUnknownTypes = Set.unmodifiable(
         externalUnknownTypes
             .intersection(unknownTypes)
             .where(_mayCarryReference),
       ),
       sources = Set.unmodifiable(sources),
       addresses = Set.unmodifiable(addresses),
       _integers = integers,
       _references = references;

  /// Binds actual entry arguments to the heap outside this execution.
  ///
  /// This proof is valid only before local allocations, or for independently
  /// admitted external arguments. Retained raw capabilities keep their origin.
  FlowValue asExternal() => unknownTypes.isEmpty
      ? this
      : FlowValue._(
          _constants,
          objects,
          unknownTypes,
          sources,
          _references,
          addresses,
          _integers,
          unknownTypes.where(_mayCarryReference).toSet(),
          managedBackings,
          hasUnknownBacking,
          rawBackingTypes,
        );

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

  /// Established bounds for static execution, retaining value-level proofs.
  ///
  /// These bounds are not observable runtime identities; use [runtimeTypes] for
  /// runtime comparisons and [check] with its runtimeTypes flag for type tests.
  Iterable<ValueType> get types sync* {
    yield* unknownTypes;
    yield* constants.map((value) => value.provenValueType);
    yield* objects.map((value) => value.type);
    yield* addresses.map((value) => value.type);
  }

  /// Runtime type bounds, reified without losing the underlying value facts.
  ///
  /// Known constants provide their actual composed type. Unknown values and
  /// allocation bounds remain bounds, not exact runtime identity proofs.
  Iterable<ValueType> get runtimeTypes sync* {
    yield* unknownTypes.map((type) => type.runtimeValueBound);
    yield* constants.map((value) => value.runtimeValueType);
    yield* objects.map((value) => value.type.runtimeValueBound);
    yield* addresses.map((value) => value.type.runtimeValueBound);
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
        null,
        externalUnknownTypes,
        managedBackings,
        hasUnknownBacking,
        rawBackingTypes,
      );
    }
    if (existing == null) return this;
    final narrowed = existing.intersect(range);
    if (narrowed == null) return const FlowValue.bottom();
    if (narrowed == existing) return this;
    return FlowValue.integerRange(narrowed)
        .withSources(sources)
        .withReferences([references])
        .withManagedBackings(managedBackings, unknown: hasUnknownBacking)
        ._withRawBackingTypes(rawBackingTypes);
  }

  /// Whether a nominal receiver candidate matches known values or unknown bounds.
  ///
  /// An exact allocation cannot gain a subclass merely through a broader view.
  /// Physical carriers of functions and records belong to representation.
  bool mayHaveInstance(ClassType type) {
    if (unknownTypes.any((bound) => bound.mayHaveInstance(type))) return true;
    return [
      ...constants.map((value) => value.runtimeValueType),
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
      externalUnknownTypes,
      managedBackings,
      hasUnknownBacking,
      rawBackingTypes,
    );
  }

  /// Changes analysis allocation identities while preserving semantic values.
  FlowValue mapObjects(FlowObject Function(FlowObject) transform) {
    if (objects.isEmpty &&
        managedBackings.isEmpty &&
        addresses.isEmpty &&
        _references == null) {
      return this;
    }
    final mapped = objects.map(transform).toSet();
    final backings = managedBackings.map(transform).toSet();
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
        backings.length == managedBackings.length &&
        backings.containsAll(managedBackings) &&
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
      externalUnknownTypes,
      backings,
      hasUnknownBacking,
      rawBackingTypes,
    );
  }

  /// Rebinds constant implementations without changing their semantic identity.
  ///
  /// Graph rewrites must also update constants supplied by actual entry inputs,
  /// including native address bases and retained references. Identity comparison
  /// detects these changes even though the represented values remain equal.
  FlowValue rebindConstants(Constant Function(Constant) transform) {
    var changed = false;
    Constant rebind(Constant value) {
      final result = transform(value);
      if (result.structuralKey != value.structuralKey ||
          result.type != value.type) {
        throw ArgumentError('Constant rebinding must preserve value and type.');
      }
      changed |= !identical(result, value);
      return result;
    }

    final constants = {
      for (final entry in _constants.entries) entry.key: rebind(entry.value),
    };
    final references = _references?.rebindConstants(transform);
    changed |= !identical(references, _references);
    final mappedAddresses = {
      for (final address in addresses)
        if (address.base case final Constant value)
          FlowAddress.ranged(rebind(value), address.offsets, type: address.type)
        else
          address,
    };
    return changed
        ? FlowValue._(
            constants,
            objects,
            unknownTypes,
            sources,
            references,
            mappedAddresses,
            _integers,
            externalUnknownTypes,
            managedBackings,
            hasUnknownBacking,
            rawBackingTypes,
          )
        : this;
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
      externalUnknownTypes,
      managedBackings,
      hasUnknownBacking,
      rawBackingTypes,
    );
  }

  /// Retains address provenance without changing the represented Dart value.
  FlowValue withReferences(Iterable<FlowValue> values) {
    var retained = references;
    for (final value in values) {
      retained = retained
          .join(
            FlowValue._(
              value._constants,
              value.objects,
              value.unknownTypes,
              const {},
              null,
              const {},
              null,
              value.externalUnknownTypes,
              const {},
              false,
              value.rawBackingTypes,
            ),
          )
          .join(value.references);
      for (final address in value.addresses) {
        retained = retained.join(address.reference);
      }
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
      externalUnknownTypes,
      managedBackings,
      hasUnknownBacking,
      rawBackingTypes,
    );
  }

  /// Attaches the actual physical allocation to the same semantic value.
  ///
  /// The allocation is retained by GC and call-state projection, but is not a
  /// second possible value and is not accessible through [references].
  FlowValue withManagedBackings(
    Iterable<FlowObject> values, {
    bool unknown = false,
  }) {
    if (isBottom) return this;
    final backings = values.toSet();
    if (unknown == hasUnknownBacking &&
        backings.length == managedBackings.length &&
        backings.containsAll(managedBackings)) {
      return this;
    }
    return FlowValue._(
      _constants,
      objects,
      unknownTypes,
      sources,
      _references,
      addresses,
      _integers,
      externalUnknownTypes,
      backings,
      unknown,
      rawBackingTypes,
    );
  }

  /// Replaces carrier-dependent scalar facts with their current payloads.
  /// Other executable alternatives retain their identities and provenance.
  FlowValue withScalarPayloads(Iterable<FlowValue> payloads) {
    bool scalar(ValueType type) =>
        ValueType.number.accepts(type) || ValueType.boolean.accepts(type);
    final current = payloads.toList();
    // An unknown carrier already admits each covered scalar payload. Keep its
    // immutable value when no new address/capability or scalar fact is added;
    // in particular, a byte write introducing a raw reference cannot use this.
    if (hasUnknownBacking && _integers == null &&
        constants.every((value) => !scalar(value.type)) &&
        current.every((value) =>
            value.objects.isEmpty && value.addresses.isEmpty &&
            value.managedBackings.isEmpty && !value.hasUnknownBacking &&
            value.constants.every((constant) =>
                scalar(constant.type) && unknownTypes.contains(constant.type)) &&
            value.unknownTypes.every((type) =>
                scalar(type) && unknownTypes.contains(type)) &&
            value.rawBackingTypes.every(rawBackingTypes.contains) &&
            (value.references.isBottom || value.references == references))) {
      return this;
    }
    final retained = FlowValue._(
      {
        for (final entry in _constants.entries)
          if (!scalar(entry.value.type)) entry.key: entry.value,
      },
      objects,
      {
        for (final type in unknownTypes)
          if (hasUnknownBacking || !scalar(type)) type,
      },
      sources,
      _references,
      addresses,
      null,
      externalUnknownTypes,
      const {},
      false,
      rawBackingTypes,
    );
    return FlowValue.joined([
      retained,
      if (hasUnknownBacking)
        for (final constant in constants)
          if (scalar(constant.type)) FlowValue.unknown(constant.type),
      ...current,
    ])
        .withSources(sources)
        .withReferences([references])
        ._withRawBackingTypes(rawBackingTypes)
        .withManagedBackings(managedBackings, unknown: hasUnknownBacking);
  }

  /// The capabilities revealed by explicitly observing this carrier's bytes.
  ///
  /// Ordinary Dart value propagation must keep [managedBackings] private. Raw
  /// reads of a traced slot instead observe its physical reference, so they
  /// retain the backing allocation rather than the semantic scalar payload.
  FlowValue get carrierReferences {
    if (managedBackings.isEmpty && !hasUnknownBacking) return this;
    return FlowValue.joined([
      ...managedBackings.map(FlowValue.object),
      ...objects.map(FlowValue.object),
      for (final constant in constants)
        if (constant is! ScalarConstant) FlowValue.constant(constant),
      if (hasUnknownBacking)
        FlowValue.joined(types.map((type) => FlowValue.unknown(type,
            external: externalUnknownTypes.contains(type))))
            ._withRawBackingTypes(types),
    ])._withRawBackingTypes(rawBackingTypes).withReferences([references]);
  }

  FlowValue _withRawBackingTypes(Iterable<ValueType> bounds) {
    final retained = {...rawBackingTypes, ...bounds};
    if (retained.length == rawBackingTypes.length) return this;
    return FlowValue._(
      _constants,
      objects,
      unknownTypes,
      sources,
      _references,
      addresses,
      _integers,
      externalUnknownTypes,
      managedBackings,
      hasUnknownBacking,
      retained,
    );
  }

  /// Selects the known alternatives whose runtime class supplied a dispatch
  /// target. Unknown bounds still describe all instances allowed by the bound.
  FlowValue forReceiverClass(ClassType type) {
    if (type == ValueType.nullClass) {
      return FlowValue.constant(const Constant.nullValue()).withSources(sources);
    }
    final selected = check(type).value;
    bool matches(ValueType actual) =>
        actual == type || actual is FunctionType && type == ValueType.function;
    if (selected.constants.every((c) => matches(c.provenValueType)) &&
        selected.objects.every((o) => matches(o.type)) &&
        selected.addresses.every((a) => matches(a.type))) {
      return selected;
    }
    return FlowValue._(
      Map.of(selected._constants)
        ..removeWhere((_, value) => !matches(value.provenValueType)),
      selected.objects.where((object) => matches(object.type)).toSet(),
      selected.unknownTypes,
      selected.sources,
      selected._references,
      selected.addresses.where((address) => matches(address.type)).toSet(),
      selected._integers,
      selected.externalUnknownTypes,
      selected.managedBackings,
      selected.hasUnknownBacking,
      selected.rawBackingTypes,
    );
  }

  /// Filters a static execution bound or an explicit runtime type test.
  ///
  /// Aliases and the original constants survive either kind of successful check.
  /// The `mayFail` result reports whether values can take the opposite outcome.
  /// [runtimeTypes] distinguishes observed Dart type metadata from the static
  /// value constraints used for assignments and storage analysis.
  ({FlowValue value, bool mayFail}) check(
    ValueType type, {
    bool negated = false,
    bool runtimeTypes = false,
    ValueType? Function(FlowObject object)? runtimeTypeOf,
  }) {
    if (runtimeTypes) type = type.runtimeCheckType;
    var mayFail = false;
    bool retain(ValueType actual) {
      if (runtimeTypes) actual = actual.runtimeValueBound;
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
        if (retain(
          !runtimeTypes &&
                  entry.value is FunctionConstant &&
                  type == FunctionStorage.type
              ? FunctionStorage.type
              : runtimeTypes
              ? entry.value.runtimeValueType
              : entry.value.provenValueType,
        ))
          entry.key: entry.value,
    };
    final objects = this.objects.where((object) {
      if (!runtimeTypes && type is CellType && object.hasCellType(type)) {
        mayFail |= negated;
        return !negated;
      }
      if (object.callableStorage != null &&
          (runtimeTypes || type is FunctionType)) {
        if (runtimeTypes) {
          if (runtimeTypeOf?.call(object) case final actual?) {
            return retain(actual);
          }
        }
        // Physical function storage carries a static bound. Its descriptor is
        // the runtime signature; a narrower function test cannot be rejected
        // using only that bound. Keep the original allocation and aliases.
        final bound = object.type.runtimeValueBound;
        final bool? matches = type.accepts(bound)
            ? true
            : type is FunctionType || type is TypeParameterType
            ? null
            : false;
        mayFail |= matches == null || matches == negated;
        return matches == null || matches != negated;
      }
      return retain(
        !runtimeTypes &&
                object.type is CellType &&
                (type == ValueType.object || type == ValueType.object.nullable)
            ? ValueType.object
            : !runtimeTypes &&
                  object.callableStorage != null &&
                  type is ClassType &&
                  object.storageType!.asInstanceOf(type) != null
            ? object.storageType!
            : object.type,
      );
    }).toSet();
    final addresses = this.addresses
        .where((address) => retain(address.type))
        .toSet();
    final backings = managedBackings
        .where((backing) => retain(backing.type))
        .toSet();
    final unknown = <ValueType>{};
    final external = <ValueType>{};
    final unrestricted = <ValueType>{};
    const nullValue = Constant.nullValue();
    for (final storedBound in unknownTypes) {
      final bound = runtimeTypes ? storedBound.runtimeValueBound : storedBound;
      void addUnknown(ValueType bound) {
        unknown.add(bound);
        (externalUnknownTypes.contains(storedBound) ? external : unrestricted)
            .add(bound);
      }

      if (bound == ValueType.never) continue;
      if (bound == ValueType.nullType) {
        if (retain(bound)) {
          constants[nullValue.structuralKey] = nullValue;
        }
        continue;
      }
      if (type.accepts(bound)) {
        mayFail |= negated;
        if (!negated) addUnknown(bound);
        continue;
      }
      if (type == ValueType.never ||
          type == ValueType.nullType && !bound.mayBeNull) {
        mayFail |= !negated;
        if (negated) addUnknown(bound);
        continue;
      }
      mayFail = true;
      if (!negated) {
        addUnknown(type.accepts(bound.nonNullable) ? bound.nonNullable : type);
      } else if (type.accepts(ValueType.nullType)) {
        final narrowed = bound.nonNullable;
        addUnknown(narrowed.mayBeNull ? ValueType.object : narrowed);
      } else if (type.accepts(bound.nonNullable)) {
        if (bound.mayBeNull) {
          constants[nullValue.structuralKey] = nullValue;
        }
      } else {
        addUnknown(bound);
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
              external.difference(unrestricted),
              backings,
              hasUnknownBacking,
              rawBackingTypes,
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
    final seen = Set<FlowValue>.identity();
    final values = inputs
        .where((value) => !value.isBottom && seen.add(value))
        .toList();
    if (values.isEmpty) return const FlowValue.bottom();
    if (values.length == 1) return values.single;
    final constants = <Object, Constant>{};
    final objects = <FlowObject>{};
    final backings = <FlowObject>{};
    final rawBackings = <ValueType>{};
    final hasBacking = values.any(
      (value) => value.managedBackings.isNotEmpty || value.hasUnknownBacking,
    );
    var unknownBacking = false;
    final unknown = <ValueType>{};
    final external = <ValueType>{};
    final unrestricted = <ValueType>{};
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
      backings.addAll(value.managedBackings);
      rawBackings.addAll(value.rawBackingTypes);
      unknownBacking |=
          hasBacking &&
          (value.hasUnknownBacking || value.managedBackings.isEmpty);
      unknown.addAll(value.unknownTypes);
      external.addAll(value.externalUnknownTypes);
      unrestricted.addAll(
        value.unknownTypes.difference(value.externalUnknownTypes),
      );
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
      external.difference(unrestricted),
      backings,
      unknownBacking,
      rawBackings,
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
          managedBackings.length == other.managedBackings.length &&
          managedBackings.containsAll(other.managedBackings) &&
          hasUnknownBacking == other.hasUnknownBacking &&
          rawBackingTypes.length == other.rawBackingTypes.length &&
          rawBackingTypes.containsAll(other.rawBackingTypes) &&
          addresses.length == other.addresses.length &&
          addresses.containsAll(other.addresses) &&
          unknownTypes.length == other.unknownTypes.length &&
          unknownTypes.containsAll(other.unknownTypes) &&
          externalUnknownTypes.length == other.externalUnknownTypes.length &&
          externalUnknownTypes.containsAll(other.externalUnknownTypes) &&
          sources.length == other.sources.length &&
          sources.containsAll(other.sources) &&
          _integers == other._integers &&
          _references == other._references;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(_constants.keys),
    Object.hashAllUnordered(objects),
    Object.hashAllUnordered(managedBackings),
    hasUnknownBacking,
    Object.hashAllUnordered(rawBackingTypes),
    Object.hashAllUnordered(addresses),
    Object.hashAllUnordered(unknownTypes),
    Object.hashAllUnordered(externalUnknownTypes),
    Object.hashAllUnordered(sources),
    _integers,
    _references,
  );
}

// Numeric and boolean values carry no managed reference identity. Raw addresses
// use FlowAddress/references separately, even when their scalar bound is int.
bool _mayCarryReference(ValueType type) => ![
  ValueType.number.nullable,
  ValueType.boolean.nullable,
].any((scalar) => scalar.accepts(type));
