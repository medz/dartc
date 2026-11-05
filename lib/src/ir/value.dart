import 'core_types.dart';
import 'signature.dart';
import 'type.dart';

/// An operand in static single assignment (SSA) form.
///
/// A use refers to its defining instruction or block parameter by identity.
/// A [Constant] can be used in any block.
sealed class const Value(
  /// The static Dart type before machine representation selection.
  final ValueType type,
);

/// An edge-only result supplied by one Await's successful resumption.
///
/// Its type also selects the `Future<T>` arm of the await protocol. It is not
/// a normal instruction and may only be passed on its owning resume edge.
final class AwaitResult(ValueType type) extends Value {
  this : super(type) {
    if (!isDartType(type)) {
      throw ArgumentError('Await requires a Dart result type.');
    }
  }
}

/// A compile-time value that can be used in any block.
sealed class const Constant(super.type) extends Value {
  /// Creates an integer literal with the value [value].
  const factory integer(int value) = ScalarConstant._integer;

  /// Creates a boolean literal with the value [value].
  const factory boolean(bool value) = ScalarConstant._boolean;

  /// Creates a double literal, preserving the sign of zero.
  const factory floating(double value) = ScalarConstant._floating;

  /// Creates a string literal from its decoded [value].
  const factory string(String value) = ScalarConstant._string;

  /// Creates the Dart `null` value.
  const factory nullValue() = ScalarConstant._nullValue;
}

/// A closed source-level Dart type represented as a canonical Type value.
final class TypeConstant(final ValueType representedType) extends Constant {
  this : super(.typeType) {
    if (!isDartType(representedType) ||
        typeParametersIn(representedType).isNotEmpty) {
      throw ArgumentError('A type constant requires a closed Dart type.');
    }
  }
}

/// Reifies a type template using the current lexical type environment.
final class ReifyType(final ValueType template) extends Instruction {
  this : super(.typeType) {
    if (!isDartType(template)) throw ArgumentError('Expected a Dart type.');
  }
  @override
  Iterable<Value> get inputs => const [];
}

/// Reads Dart Object.hashCode, retaining virtual dispatch for user objects.
final class ObjectHashCode(
  final Value operand, {

  /// Whether `super` selected Object's identity hash without virtual dispatch.
  final bool direct = false,
}) extends Instruction {
  this : super(.integer) {
    if (operand.type is CellType) throw ArgumentError('Expected a Dart value.');
  }
  @override
  Iterable<Value> get inputs => [operand];
}

/// A canonical tear-off of a top-level function, static method or constructor.
final class FunctionConstant(
  /// The referenced declaration, including the source factory for a redirect.
  final FunctionTarget target, {
  final ClassType? ownerType,
  Iterable<ValueType>? typeArguments,

  /// The generic callable view of a constructor alias, including its owner template.
  final FunctionType? constructorSignature,

  /// The nominal identity retained by a non-proper generic constructor alias.
  final (Uri, String)? constructorAlias,
}) extends Constant {
  final List<ValueType>? typeArguments = typeArguments == null
      ? null
      : .unmodifiable(typeArguments);
  this
    : super(
        typeArguments == null
            ? constructorSignature ??
                  target.tearOffSignature(ownerType: ownerType)
            : (constructorSignature ??
                      target.tearOffSignature(ownerType: ownerType))
                  .instantiate(typeArguments),
      ) {
    ownerType?.validateTypeArguments();
    if (constructorAlias != null &&
        (constructorSignature == null ||
            constructorSignature!.typeParameters.isEmpty)) {
      throw ArgumentError(
        'A constructor alias identity requires a generic callable view.',
      );
    }
    if (constructorSignature case final signature?) {
      if (ownerType != null ||
          (target.kind != .initializer && target.kind != .factory)) {
        throw ArgumentError(
          'A constructor callable view requires an unapplied constructor.',
        );
      }
      final owner = signature.result;
      if (owner is! ClassType ||
          owner.declaration != target.owner?.declaration) {
        throw ArgumentError(
          'Constructor callable view returns an incompatible owner.',
        );
      }
      owner.validateTypeArguments();
      final expected = target.signatureFor(owner);
      final genericExpected = FunctionType(
        expected.result,
        expected.parameters,
        typeParameters: signature.typeParameters,
        optionalPositional:
            expected.positionalCount - expected.requiredPositional,
        namedParameters: {
          for (final e in expected.named.entries) e.key: e.value.required,
        },
      );
      if (signature != genericExpected) {
        throw ArgumentError(
          'Constructor callable view does not match its declaration.',
        );
      }
    }
    if (target.kind == .closure ||
        target.kind == .fieldInitializer ||
        target.kind.isVirtual ||
        target.kind == .initializer && target.owner!.isAbstract) {
      throw ArgumentError('Expected a callable without a bound receiver.');
    }
  }
}

/// A scalar literal with its Dart value and static type.
final class const ScalarConstant._(
  /// The Dart scalar represented by this operand.
  final Object? value,
  super.type,
) extends Constant {
  const new _integer(int value) : this._(value, .integer);
  const new _boolean(bool value) : this._(value, .boolean);
  const new _floating(double value) : this._(value, .floating);
  const new _string(String value) : this._(value, .string);
  const new _nullValue() : this._(null, .nullType);
}

/// A constant record with a constant operand for each slot in its type.
final class RecordConstant(RecordType type, Iterable<Constant> fields)
    extends Constant {
  /// The constant fields in slot order.
  final List<Constant> fields = .unmodifiable(fields);

  this : super(type) {
    checkArguments(type.fields, this.fields);
  }
}

/// An immutable core list or set, in iteration order.
final class SequenceConstant(ClassType type, Iterable<Constant> elements)
    extends Constant {
  final List<Constant> elements = .unmodifiable(elements);

  this : super(type) {
    if (type.declaration != CoreTypes.list &&
        type.declaration != CoreTypes.set) {
      throw ArgumentError('Expected a core List or Set constant.');
    }
    type.validateTypeArguments();
    for (final element in this.elements) {
      if (!type.typeArguments.single.accepts(element.type)) {
        throw ArgumentError('Incompatible constant element.');
      }
    }
  }
}

/// An immutable core map whose entries retain insertion order.
final class MapConstant(ClassType type, Iterable<(Constant, Constant)> entries)
    extends Constant {
  final List<(Constant, Constant)> entries = .unmodifiable(entries);

  this : super(type) {
    if (type.declaration != CoreTypes.map) {
      throw ArgumentError('Expected a core Map constant.');
    }
    type.validateTypeArguments();
    for (final (key, value) in this.entries) {
      if (!type.typeArguments[0].accepts(key.type) ||
          !type.typeArguments[1].accepts(value.type)) {
        throw ArgumentError('Incompatible constant map entry.');
      }
    }
  }
}

/// A fully initialized immutable instance, independent of its constructor site.
final class ObjectConstant(ClassType type, Map<InstanceField, Constant> fields)
    extends Constant {
  final Map<InstanceField, Constant> fields = .unmodifiable(fields);

  this : super(type) {
    type.validateTypeArguments();
    if (type.isAbstract) {
      throw ArgumentError('Expected a concrete constant object type.');
    }
    for (final MapEntry(:key, :value) in this.fields.entries) {
      if (!key.isFinal || !key.typeFor(type).accepts(value.type)) {
        throw ArgumentError('Invalid immutable instance field.');
      }
    }
  }
}

/// A structural identity key without executing Dart user equality or hashing.
///
/// Scalar representation, collection order, nominal field slots and complete
/// function instantiations are retained. Constructor sites are not identities.
Object constantKey(Constant value) => switch (value) {
  TypeConstant(:final representedType) => (TypeConstant, representedType),
  ScalarConstant(:final type, :final value) => (
    type,
    value is double ? value.toString() : value,
  ),
  FunctionConstant() => _functionConstantKey(value),
  RecordConstant(:final type, :final fields) => (
    type,
    fields.fold<Object?>(null, (tail, field) => (tail, constantKey(field))),
  ),
  SequenceConstant(:final type, :final elements) => (
    type,
    elements.fold<Object?>(
      null,
      (tail, element) => (tail, constantKey(element)),
    ),
  ),
  MapConstant(:final type, :final entries) => (
    type,
    entries.fold<Object?>(
      null,
      (tail, entry) => (tail, constantKey(entry.$1), constantKey(entry.$2)),
    ),
  ),
  ObjectConstant(:final type, :final fields) => (
    type,
    _orderedFields(fields).fold<Object?>(
      null,
      (tail, field) => (tail, field, constantKey(fields[field]!)),
    ),
  ),
};

Object _functionConstantKey(FunctionConstant value) {
  final constructor =
      value.target.kind == .initializer || value.target.kind == .factory;
  final signature = value.type as FunctionType;
  // Applying a constructor's owner and instantiating its generic tear-off
  // denote the same runtime function. Proper aliases add no nominal identity.
  final owner = constructor && signature.typeParameters.isEmpty
      ? signature.result
      : value.ownerType;
  final arguments = constructor && value.constructorAlias == null
      ? null
      : value.typeArguments;
  return (
    value.target,
    owner,
    value.constructorAlias,
    arguments?.fold<Object?>(null, (tail, type) => (tail, type)),
  );
}

List<InstanceField> _orderedFields(Map<InstanceField, Constant> fields) =>
    fields.keys.toList()..sort((a, b) {
      final owner = a.owner.library.toString().compareTo(
        b.owner.library.toString(),
      );
      if (owner != 0) return owner;
      final name = a.owner.name.compareTo(b.owner.name);
      if (name != 0) return name;
      final field = a.name.compareTo(b.name);
      return field != 0
          ? field
          : identityHashCode(a).compareTo(identityHashCode(b));
    });

/// A value supplied on entry to a block by the caller or an incoming jump.
final class BlockParameter._(super.type) extends Value;

/// An operand supplied by the runtime only on an exceptional edge.
final class const UnwindValue._(super.type) extends Value {
  /// The non-null exception that caused control to leave the operation.
  static const exception = UnwindValue._(.object);

  /// The stack trace associated with that throw.
  static const stackTrace = UnwindValue._(.stackTrace);
}

/// Allocates a distinct SSA parameter for each entry in [types].
List<BlockParameter> blockParameters(Iterable<ValueType> types) =>
    .unmodifiable(types.map(BlockParameter._));

/// An operation executed at its position in a block's instruction list.
sealed class Instruction(super.type) extends Value {
  /// The SSA operands consumed by the operation.
  Iterable<Value> get inputs;

  /// Whether evaluation can transfer control to a Dart exception handler.
  bool get mayThrow => switch (this) {
    ObjectHashCode() ||
    ListSublist() ||
    MapContainsKey() ||
    MapEntries() ||
    PatternMatchFailure() ||
    CollectionLength() ||
    CollectionGet() ||
    ListSet() ||
    NewCollection() ||
    CollectionAdd() ||
    CollectionSpread() ||
    MapPut() ||
    GetIterator() ||
    IteratorMoveNext() ||
    IteratorCurrent() ||
    AssertionFailure() ||
    DirectCall() ||
    InstanceCall() ||
    DynamicDispatch() ||
    MakeInvocation() ||
    FunctionCall() ||
    InstantiateFunction() ||
    BindMethod() ||
    LoadGlobal() ||
    MakeClosure() ||
    NewCell() ||
    CopyCell() ||
    Construct() ||
    TypeCast() ||
    NullCheck() ||
    MakeRecord() ||
    Interpolate() ||
    StringConcat() => true,
    StoreGlobal(:final global) => global.isFinal,
    StoreField(:final field) => field.isLate && field.isFinal,
    LoadField(:final field) => field.isLate,
    Equals(:final mayCallUserCode) => mayCallUserCode,
    IntBinary(:final operator) => operator.mayThrow,
    NumericBinary(:final canThrow) => canThrow,
    NumericNegate() || ReifyType() => false,
    ReadCell(:final cell) => (cell.type as CellType).isLate,
    WriteCell(:final cell) =>
      (cell.type as CellType).isLate && (cell.type as CellType).isFinal,
    TypeTest() || TypeView() || RecordGet() => false,
  };
}

/// Raises an assertion error after the failed condition and optional message.
final class AssertionFailure(
  /// The lazily evaluated assertion message, absent when omitted.
  final Value? message,
) extends Instruction {
  this : super(.never) {
    if (message != null && !ValueType.object.nullable.accepts(message!.type)) {
      throw ArgumentError('Expected a Dart assertion message value.');
    }
  }

  @override
  Iterable<Value> get inputs => [?message];
}

/// Creates a local function value retaining its capture slots by identity.
final class MakeClosure(
  /// The body executed by this closure.
  final FunctionTarget target,
  Iterable<Value> captures,
) extends Instruction {
  /// The captured values or shared cells in entry order.
  @override
  final List<Value> inputs = .unmodifiable(captures);
  this : super(target.signature) {
    if (target.kind != .closure) {
      throw ArgumentError('Expected a lexical function.');
    }
    checkArguments(target.captures, inputs);
  }
}

/// Allocates storage for one activation of a local variable.
///
/// A late cell may retain a zero-argument [initializer] function until its first
/// read. Otherwise, without [initial], a write must occur before a successful
/// read. Definite-assignment analysis establishes this for non-late locals.
final class NewCell(
  CellType type,

  /// The starting value, absent for a definitely-assigned deferred local.
  final Value? initial, {

  /// The lazy zero-argument function value, separate from a bound [initial].
  final Value? initializer,
}) extends Instruction {
  this : super(type) {
    if (initial != null && !type.content.accepts(initial!.type)) {
      throw ArgumentError('Incorrect capture initializer.');
    }
    if (initializer != null) {
      final signature = initializer!.type;
      if (!type.isLate ||
          initial != null ||
          signature is! FunctionType ||
          signature.typeParameters.isNotEmpty ||
          signature.parameters.isNotEmpty ||
          !type.content.accepts(signature.result)) {
        throw ArgumentError('Invalid lazy capture initializer.');
      }
    }
  }
  @override
  Iterable<Value> get inputs => [?initial, ?initializer];
}

/// Reads the current value of a captured variable.
final class ReadCell(
  /// The shared storage to read.
  final Value cell,
) extends Instruction {
  this
    : super(switch (cell.type) {
        CellType(:final content) => content,
        _ => throw ArgumentError('Expected capture storage.'),
      });
  @override
  Iterable<Value> get inputs => [cell];
}

/// Copies a captured loop binding without reading a possibly uninitialized value.
final class CopyCell(
  /// The previous iteration's storage.
  final Value cell,
) extends Instruction {
  this : super(cell.type) {
    if (cell.type is! CellType) {
      throw ArgumentError('Expected capture storage.');
    }
  }

  @override
  Iterable<Value> get inputs => [cell];
}

/// Replaces the value observed by all closures sharing [cell].
final class WriteCell(
  /// The shared storage to write.
  final Value cell,

  /// The new variable value.
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    final type = cell.type;
    if (type is! CellType || !type.content.accepts(value.type)) {
      throw ArgumentError('Incorrect capture write.');
    }
  }
  @override
  Iterable<Value> get inputs => [cell, value];
}

/// Binds a method to its evaluated receiver, performing virtual selection at extraction.
///
/// The selected implementation's reified signature must satisfy this value's
/// static function type. A mismatch raises `TypeError` during extraction, before
/// any later function instantiation or invocation.
final class BindMethod(
  /// The method selected statically at this access.
  final FunctionTarget method,

  /// The receiver retained for subsequent calls.
  final Value receiver, {

  /// Whether `super` has already selected the implementation.
  final bool direct = false,
  final ClassType? ownerType,
}) extends Instruction {
  this
    : super(
        method.signatureFor(
          ownerType ?? _classReceiver(receiver.type, method.owner),
        ),
      ) {
    if (method.kind != .method ||
        _classReceiver(
              receiver.type,
              method.owner,
            ).asInstanceOf(method.owner!) ==
            null ||
        direct && method.isAbstract) {
      throw ArgumentError('Invalid method tear-off.');
    }
    if (ownerType != null && !ownerType!.accepts(receiver.type)) {
      throw ArgumentError('Static method view cannot accept the receiver.');
    }
  }
  @override
  Iterable<Value> get inputs => [receiver];
}

/// Applies explicit or inferred type arguments to a generic function value.
final class InstantiateFunction(
  final Value function,
  Iterable<ValueType> typeArguments,
) extends Instruction {
  final List<ValueType> typeArguments = .unmodifiable(typeArguments);
  this : super(_functionSignature(function).instantiate(typeArguments)) {
    if (_functionSignature(function).typeParameters.isEmpty) {
      throw ArgumentError('Expected a generic function value.');
    }
  }
  @override
  Iterable<Value> get inputs => [function];
}

FunctionType _functionSignature(Value function) => switch (function.type) {
  FunctionType() => function.type as FunctionType,
  _ => throw ArgumentError('Expected a non-nullable function signature.'),
};

/// Invokes a function value with the supplied arguments and the destination's defaults.
final class FunctionCall(
  /// The evaluated function value.
  final Value function,
  Iterable<Value> positional, [
  Map<String, Value> named = const {},
  Iterable<ValueType> typeArguments = const [],
]) extends Instruction {
  final List<ValueType> typeArguments = .unmodifiable(typeArguments);

  /// Supplied positional arguments.
  final List<Value> positional = .unmodifiable(positional);

  /// Supplied named arguments.
  final Map<String, Value> named = .unmodifiable(named);
  this : super(_functionSignature(function).instantiate(typeArguments).result) {
    _checkCall(
      _functionSignature(function).instantiate(typeArguments),
      this.positional,
      this.named,
    );
  }
  @override
  Iterable<Value> get inputs => [function, ...positional, ...named.values];
}

void _checkCall(
  FunctionType signature,
  List<Value> positional,
  Map<String, Value> named,
) {
  final slots = signature.bind<Value?>(positional, named, (_) => null);
  for (final (i, value) in slots.indexed) {
    if (value != null && !signature.parameters[i].accepts(value.type)) {
      throw ArgumentError('Incompatible argument for ${signature.dartName}.');
    }
  }
}

/// Reads a declared global slot, lazily running its initializer when unbound.
///
/// An unbound read without an initializer raises a late initialization error.
/// Recursive reads run the initializer again without a separate busy state.
/// A successful result replaces mutable storage, but cannot replace a final
/// binding created recursively. A thrown exception preserves writes already
/// made; an unbound slot retries its initializer on the next read.
final class LoadGlobal(
  /// The source declaration whose storage is read.
  final GlobalVariable global,
) extends Instruction {
  this : super(global.type);

  @override
  Iterable<Value> get inputs => const [];
}

/// Binds a writable global slot after evaluating and converting [value].
///
/// A late final variable without an initializer rejects a second binding.
final class StoreGlobal(
  /// The source declaration whose storage is written.
  final GlobalVariable global,

  /// The already evaluated, statically compatible value.
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    if (!global.isWritable || !global.type.accepts(value.type)) {
      throw ArgumentError('Incompatible or read-only global write.');
    }
  }

  @override
  Iterable<Value> get inputs => [value];
}

/// Reads storage selected by its declaring class, without invoking a getter.
///
/// Late fields use the same unbound-read protocol as [LoadGlobal], passing the
/// receiver and its actual owner type arguments to the initializer.
final class LoadField(
  /// The declared slot to read.
  final InstanceField field,

  /// The object containing the slot.
  final Value receiver,
) extends Instruction {
  this : super(field.typeFor(_classReceiver(receiver.type, field.owner))) {
    if (_classReceiver(receiver.type, field.owner).asInstanceOf(field.owner) ==
        null) {
      throw ArgumentError('Incompatible field receiver.');
    }
  }
  @override
  Iterable<Value> get inputs => [receiver];
}

/// Invokes a member on the runtime class with the arguments supplied by the caller.
///
/// The implementation supplies its own optional defaults and performs its
/// parameter type checks before entering the body.
final class InstanceCall(
  /// The statically resolved member and signature.
  final FunctionTarget member,

  /// The evaluated dispatch receiver.
  final Value receiver,
  Iterable<Value> positional, [
  Map<String, Value> named = const {},
  final ClassType? ownerType,
  Iterable<ValueType> typeArguments = const [],
]) extends Instruction {
  final List<ValueType> typeArguments = .unmodifiable(typeArguments);

  /// Explicit positional arguments.
  final List<Value> positional = .unmodifiable(positional);

  /// Explicit named arguments, in their source order.
  final Map<String, Value> named = .unmodifiable(named);
  this
    : super(
        member
            .signatureFor(
              ownerType ?? _classReceiver(receiver.type, member.owner),
            )
            .instantiate(typeArguments)
            .result,
      ) {
    if (!member.kind.isVirtual ||
        _classReceiver(
              receiver.type,
              member.owner,
            ).asInstanceOf(member.owner!) ==
            null) {
      throw ArgumentError('Incompatible dispatch receiver.');
    }
    if (ownerType != null && !ownerType!.accepts(receiver.type)) {
      throw ArgumentError('Static member view cannot accept the receiver.');
    }
    _checkCall(
      member
          .signatureFor(
            ownerType ?? _classReceiver(receiver.type, member.owner),
          )
          .instantiate(typeArguments),
      this.positional,
      this.named,
    );
  }

  @override
  Iterable<Value> get inputs sync* {
    yield receiver;
    yield* positional;
    yield* named.values;
  }
}

/// Dispatches an unresolved selector on a runtime value.
///
/// Arguments are already evaluated, in source order. The runtime implementation
/// checks the selected callable's shape, generic bounds and parameter types.
/// Empty [typeArguments] means that type arguments were omitted.
final class DynamicDispatch(
  final Value receiver,
  final MemberSelector selector,
  Iterable<Value> positional, [
  Map<String, Value> named = const {},
  Iterable<ValueType> typeArguments = const [],
]) extends Instruction {
  final List<Value> positional = .unmodifiable(positional);
  final Map<String, Value> named = .unmodifiable(named);
  final List<ValueType> typeArguments = .unmodifiable(typeArguments);

  this : super(.dynamicType) {
    _checkInvocationArguments(
      selector,
      this.positional,
      this.named,
      this.typeArguments,
    );
    if (!isDartType(receiver.type)) {
      throw ArgumentError('Dynamic dispatch requires a Dart receiver.');
    }
  }

  @override
  Iterable<Value> get inputs => [receiver, ...positional, ...named.values];
}

/// Builds the runtime invocation mirror used by noSuchMethod forwarders.
///
/// Canonical symbols retain private-library identity. Named arguments are exposed in
/// their supplied order; argument collections are immutable runtime snapshots.
final class MakeInvocation(
  final MemberSelector selector,
  Iterable<Value> positional, [
  Map<String, Value> named = const {},
  Iterable<ValueType> typeArguments = const [],
]) extends Instruction {
  final List<Value> positional = .unmodifiable(positional);
  final Map<String, Value> named = .unmodifiable(named);
  final List<ValueType> typeArguments = .unmodifiable(typeArguments);

  this : super(CoreTypes.invocation) {
    _checkInvocationArguments(
      selector,
      this.positional,
      this.named,
      this.typeArguments,
    );
  }

  @override
  Iterable<Value> get inputs => [...positional, ...named.values];
}

void _checkInvocationArguments(
  MemberSelector selector,
  List<Value> positional,
  Map<String, Value> named,
  List<ValueType> typeArguments,
) {
  checkMemberSelector(selector);
  if (named.keys.any((name) => name.isEmpty) ||
      [
        ...positional,
        ...named.values,
      ].any((value) => !isDartType(value.type)) ||
      typeArguments.any((type) => !isDartType(type))) {
    throw ArgumentError('Invocation requires named Dart values and types.');
  }
  if (selector.kind != .method &&
      (named.isNotEmpty ||
          typeArguments.isNotEmpty ||
          positional.length != (selector.kind == .setter ? 1 : 0))) {
    throw ArgumentError('Invalid invocation accessor arguments.');
  }
}

/// Allocates a fresh object, runs [initializer] on it and returns it on success.
///
/// Nullable instance slots without an initializer start as `null`.
final class Construct(
  /// The generative constructor of the allocated class.
  final FunctionTarget initializer,
  Iterable<Value> arguments, {
  ClassType? instantiatedType,
}) extends Instruction {
  final ClassType instantiatedType = instantiatedType ?? initializer.owner!;
  @override
  final List<Value> inputs = .unmodifiable(arguments);

  this
    : super(
        instantiatedType ??
            initializer.owner ??
            (throw ArgumentError('Expected a constructor.')),
      ) {
    if (initializer.kind != .initializer || initializer.owner!.isAbstract) {
      throw ArgumentError('Expected a concrete generative constructor.');
    }
    if (this.instantiatedType.declaration != initializer.owner!.declaration) {
      throw ArgumentError('Constructor belongs to a different class.');
    }
    this.instantiatedType.validateTypeArguments();
    checkArguments(
      initializer.signatureFor(this.instantiatedType).parameters,
      inputs,
    );
  }
}

/// Stores [value] directly in [field]. Ordinary final fields are constructor-only.
///
/// A late final field without an initializer rejects a second binding, after
/// checking the value against the actual receiver's field type.
final class StoreField(
  /// The slot selected by its declaring class.
  final InstanceField field,

  /// The object containing the slot.
  final Value receiver,

  /// The value written to the slot.
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    if (field.isLate && !field.isWritable ||
        _classReceiver(receiver.type, field.owner).asInstanceOf(field.owner) ==
            null ||
        !field
            .typeFor(_classReceiver(receiver.type, field.owner))
            .accepts(value.type)) {
      throw ArgumentError('Incompatible instance field write.');
    }
  }

  @override
  Iterable<Value> get inputs => [receiver, value];
}

/// Constructs a record from evaluated fields in slot order.
///
/// Runtime type checks use the actual field values. The static [type] may be wider.
final class MakeRecord(RecordType type, Iterable<Value> fields)
    extends Instruction {
  @override
  final List<Value> inputs = .unmodifiable(fields);
  this : super(type) {
    checkArguments(type.fields, inputs);
  }
}

/// Reads an immutable field from a statically known record shape.
final class RecordGet(
  /// The record that supplies the field.
  final Value record,

  /// The index in the record type's field list.
  final int slot,
) extends Instruction {
  this
    : super(switch (record.type) {
        RecordType(:final fields) => fields[slot],
        _ => throw ArgumentError('Expected a record with a known shape.'),
      });

  @override
  Iterable<Value> get inputs => [record];
}

/// A Dart `is` or `is!` test on an already evaluated operand.
final class TypeTest(
  /// The already evaluated operand.
  final Value operand,

  /// The runtime type to match.
  final ValueType testedType, {

  /// Whether to invert the result of the match.
  final bool negated = false,
}) extends Instruction {
  this : super(.boolean) {
    if (operand.type is CellType || testedType is CellType) {
      throw ArgumentError('A Dart type test cannot inspect storage.');
    }
  }

  /// The value known on the edge with [outcome], or `null` if its type is unchanged.
  Value? refinement(bool outcome) {
    final source = operand.type;
    final ValueType narrowed;
    if (outcome != negated) {
      if (testedType == .nullType) return const Constant.nullValue();
      if (testedType.accepts(source)) return null;
      if (testedType.accepts(source.nonNullable)) {
        narrowed = source.nonNullable;
      } else {
        narrowed = source.mayBeNull ? testedType : testedType.nonNullable;
      }
    } else if (testedType.accepts(.nullType)) {
      narrowed = source.nonNullable;
    } else if (testedType.accepts(source.nonNullable)) {
      return const Constant.nullValue();
    } else {
      return null;
    }
    return narrowed == source ? null : TestedValue._(this, outcome, narrowed);
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// A narrower view of an operand on one outgoing edge of [test].
///
/// Only a jump on the side selected by [outcome] may use this value as an
/// argument. Its destination reads an ordinary block parameter.
final class TestedValue._(
  /// The test that establishes this value's type.
  final TypeTest test,

  /// The boolean result required for this refinement.
  final bool outcome,
  super.type,
) extends Value;

/// A statically justified upcast retaining the same runtime object and type arguments.
final class TypeView(final Value operand, super.type) extends Instruction {
  this {
    if (operand.type is CellType ||
        type is CellType ||
        !type.accepts(operand.type)) {
      throw ArgumentError('A type view requires a valid Dart upcast.');
    }
  }
  @override
  Iterable<Value> get inputs => [operand];
}

/// A Dart `as` cast that throws a type error if [operand] does not match [type].
final class TypeCast(
  /// The value returned unchanged on success.
  final Value operand,
  super.type,
) extends Instruction {
  this {
    if (operand.type is CellType || type is CellType) {
      throw ArgumentError('A Dart cast cannot expose storage.');
    }
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// A postfix null assertion that throws a Dart type error when [operand] is null.
final class NullCheck(
  /// The value returned unchanged on success.
  final Value operand,
) extends Instruction {
  this : super(operand.type.nonNullable);

  @override
  Iterable<Value> get inputs => [operand];
}

/// A binary operation on two non-nullable Dart integers.
enum IntOperator(
  /// The static type produced by the operation.
  final ValueType result,
) {
  /// Integer addition.
  add(.integer),

  /// Subtraction of the right operand from the left.
  subtract(.integer),

  /// Integer multiplication.
  multiply(.integer),

  /// IEEE division of the two integers.
  divide(.floating),

  /// Division truncated toward zero.
  truncateDivide(.integer),

  /// Euclidean modulo.
  modulo(.integer),

  /// Bitwise conjunction.
  bitAnd(.integer),

  /// Bitwise disjunction.
  bitOr(.integer),

  /// Bitwise exclusive or.
  bitXor(.integer),

  /// Left shift by a non-negative count.
  shiftLeft(.integer),

  /// Sign-extending right shift.
  shiftRight(.integer),

  /// Zero-extending right shift.
  unsignedShiftRight(.integer),

  /// Whether the left operand is smaller than the right.
  lessThan(.boolean),

  /// Whether the left operand is smaller than or equal to the right.
  lessOrEqual(.boolean),

  /// Whether the left operand is greater than the right.
  greaterThan(.boolean),

  /// Whether the left operand is greater than or equal to the right.
  greaterOrEqual(.boolean);

  /// Whether the operands can trigger a Dart arithmetic or shift error.
  bool get mayThrow => switch (this) {
    truncateDivide ||
    modulo ||
    shiftLeft ||
    shiftRight ||
    unsignedShiftRight => true,
    _ => false,
  };
}

/// Dart equality, including the null rule and dispatch on the left operand.
///
/// Comparing records can invoke user-defined equality on their fields.
final class Equals(
  /// The receiver that determines the equality implementation.
  final Value left,

  /// The value compared to [left].
  final Value right, {

  /// Whether to invert the result for `!=`.
  final bool negated = false,
}) extends Instruction {
  this : super(.boolean);

  /// Whether the comparison may call a user-defined equality operator.
  bool get mayCallUserCode => !left.type.hasScalarEquality;
  @override
  Iterable<Value> get inputs => [left, right];
}

/// An arithmetic or comparison instruction on two integers.
final class IntBinary(
  /// The operation applied to [left] and [right].
  final IntOperator operator,

  /// The first operand.
  final Value left,

  /// The second operand.
  final Value right,
) extends Instruction {
  /// Creates an instruction with the result type of [operator].
  ///
  /// Throws [ArgumentError] unless both operands have type [ValueType.integer].
  this : super(operator.result) {
    if (left.type != .integer || right.type != .integer) {
      throw ArgumentError('Integer operands required.');
    }
  }

  @override
  Iterable<Value> get inputs => [left, right];
}

/// A call to a statically bound function.
///
/// The call may change state or throw even when its result is unused.
final class DirectCall(
  /// The declaration selected during binding.
  final FunctionTarget target,
  Iterable<Value> arguments, {
  final ClassType? ownerType,
  Iterable<ValueType> typeArguments = const [],
}) extends Instruction {
  final List<ValueType> typeArguments = .unmodifiable(typeArguments);
  @override
  final List<Value> inputs = .unmodifiable(arguments);

  this : super(_directResult(target, ownerType, typeArguments)) {
    if (target.kind == .closure) {
      throw ArgumentError('A lexical invocation requires its closure.');
    }
    if (target.redirect != null) {
      throw ArgumentError('Bind arguments to the redirect destination.');
    }
    if (target.isAbstract) {
      throw ArgumentError('Cannot directly invoke an abstract member.');
    }
    ownerType?.validateTypeArguments();
    final ownerEnvironment = ownerType == null
        ? const <TypeParameterType, ValueType>{}
        : target.environmentFor(ownerType!);
    final signature = (substituteType(
      target.signature,
      ownerEnvironment,
    ) as FunctionType).instantiate(typeArguments);
    checkArguments([
      if (target.kind.hasReceiver)
        substituteType(target.owner!, ownerEnvironment),
      ...signature.parameters,
    ], inputs);
  }
}

ValueType _directResult(
  FunctionTarget target,
  ClassType? ownerType,
  Iterable<ValueType> typeArguments,
) {
  final signature = ownerType == null
      ? target.signature
      : target.signatureFor(ownerType);
  final applied = signature.instantiate(typeArguments);
  return target.kind == .initializer ? ValueType.voidType : applied.result;
}

/// Checks the arity and assignability of [arguments] against [types].
void checkArguments(Iterable<ValueType> types, List<Value> arguments) {
  var i = 0;
  for (final type in types) {
    if (i == arguments.length || !type.accepts(arguments[i++].type)) {
      throw ArgumentError('Argument types do not match the parameters.');
    }
  }
  if (i != arguments.length) throw ArgumentError('Unexpected arguments.');
}

/// A core arithmetic or ordered comparison operation on Dart numbers.
enum NumericOperator() {
  /// Addition with Dart's runtime integer or double representation.
  add,

  /// Subtraction of the right operand from the left.
  subtract,

  /// Multiplication of the operands.
  multiply,

  /// IEEE division, including infinities and NaN for zero divisors.
  divide,

  /// Division truncated toward zero, throwing for a non-finite quotient.
  truncateDivide,

  /// Euclidean modulo, preserving Dart's integer and floating semantics.
  modulo,

  /// Whether the left operand is smaller than the right.
  lessThan,

  /// Whether the left operand is smaller than or equal to the right.
  lessOrEqual,

  /// Whether the left operand is greater than the right.
  greaterThan,

  /// Whether the left operand is greater than or equal to the right.
  greaterOrEqual;

  /// The result type for operands with the given static types.
  ValueType result(ValueType left, ValueType right) => switch (this) {
    lessThan || lessOrEqual || greaterThan || greaterOrEqual => .boolean,
    divide => .floating,
    truncateDivide => .integer,
    _ when left == .floating || right == .floating => .floating,
    _ when left == .integer && right == .integer => .integer,
    _ => .number,
  };
}

/// A numeric operation without converting integer operands prematurely.
///
/// Runtime integer operands retain integer arithmetic and mixed comparisons
/// retain Dart's precision. Floating operands obey IEEE semantics, including
/// NaN and signed zero. The operation never dispatches to user code.
final class NumericBinary(
  /// The operation to perform.
  final NumericOperator operator,

  /// The first operand.
  final Value left,

  /// The second operand.
  final Value right,
) extends Instruction {
  this : super(operator.result(left.type, right.type)) {
    if (!ValueType.number.accepts(left.type) ||
        !ValueType.number.accepts(right.type)) {
      throw ArgumentError('Non-nullable numeric operands required.');
    }
  }

  /// Whether runtime operands can cause an arithmetic error.
  bool get canThrow =>
      operator == .truncateDivide ||
      operator == .modulo && left.type != .floating && right.type != .floating;

  @override
  Iterable<Value> get inputs => [left, right];
}

/// Negates a Dart number, preserving floating negative zero and NaN.
final class NumericNegate(
  /// The operand to negate without changing its numeric representation.
  final Value operand,
) extends Instruction {
  this : super(operand.type) {
    if (!ValueType.number.accepts(operand.type)) {
      throw ArgumentError('A non-nullable numeric operand is required.');
    }
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// Converts evaluated values in order and concatenates their string forms.
///
/// All interpolation expressions are evaluated before this instruction. Each
/// conversion uses Dart's `toString`, including virtual dispatch and null's
/// string representation. Conversion may throw or execute user code.
final class Interpolate(Iterable<Value> parts) extends Instruction {
  @override
  final List<Value> inputs = .unmodifiable(parts);
  this : super(.string) {
    if (inputs.any((value) => value.type is CellType)) {
      throw ArgumentError('Interpolation cannot expose capture storage.');
    }
  }
}

/// Concatenates two already evaluated, non-nullable strings.
final class StringConcat(
  /// The first string.
  final Value left,

  /// The second string.
  final Value right,
) extends Instruction {
  this : super(.string) {
    if (left.type != .string || right.type != .string) {
      throw ArgumentError('String operands required.');
    }
  }
  @override
  Iterable<Value> get inputs => [left, right];
}

ClassType _classReceiver(ValueType type, [ClassType? owner]) {
  if (type is PromotedTypeParameterType && owner != null) {
    final view = CoreTypes.view(type, owner);
    if (view != null) return view;
  }
  if (type is ClassType) return type;
  if (type is FutureOrType) {
    final future = CoreTypes.view(type, CoreTypes.future);
    if (future != null) return future;
    if (ValueType.object.accepts(type)) return ValueType.object;
  }
  if (type is TypeParameterType) return _classReceiver(type.bound, owner);
  if (type is NonNullableTypeParameterType) {
    final bound = type.parameter.bound.nonNullable;
    return bound.mayBeNull ? ValueType.object : _classReceiver(bound, owner);
  }
  throw ArgumentError('Expected a non-nullable class receiver.');
}

/// Allocates a fresh mutable literal, retaining its reified type arguments.
// ignore: use_super_parameters
final class NewCollection(final ClassType collectionType) extends Instruction {
  this : super(collectionType) {
    if (![
      CoreTypes.list,
      CoreTypes.set,
      CoreTypes.map,
    ].contains(collectionType.declaration)) {
      throw ArgumentError('Expected a core literal collection type.');
    }
  }
  @override
  Iterable<Value> get inputs => const [];
}

/// Appends/inserts using the actual receiver's reified element type checks.
final class CollectionAdd(final Value collection, final Value value)
    extends Instruction {
  this
    : super(
        CoreTypes.view(collection.type, CoreTypes.set) != null
            ? .boolean
            : .voidType,
      ) {
    final view =
        CoreTypes.view(collection.type, CoreTypes.list) ??
        CoreTypes.view(collection.type, CoreTypes.set);
    if (view == null || value.type is CellType) {
      throw ArgumentError('Invalid collection insertion.');
    }
  }
  @override
  Iterable<Value> get inputs => [collection, value];
}

/// Appends iterable elements or map entries in iteration order.
/// Method calls check the source type first; literal spreads check each write.
final class CollectionSpread(
  final Value collection,
  final Value source, {

  /// Whether this is an `addAll` invocation with a checked argument type.
  final bool isMethodCall = false,
}) extends Instruction {
  this : super(.voidType) {
    final map = CoreTypes.view(collection.type, CoreTypes.map);
    final target =
        map ??
        CoreTypes.view(collection.type, CoreTypes.list) ??
        CoreTypes.view(collection.type, CoreTypes.set);
    final input = CoreTypes.view(
      source.type,
      map == null ? CoreTypes.iterable : CoreTypes.map,
    );
    if (target == null || input == null) {
      throw ArgumentError('Invalid spread operand.');
    }
  }

  /// Whether a literal needs entry-wise key/value casts and the entries protocol.
  bool get checksMapEntries {
    final map = CoreTypes.view(collection.type, CoreTypes.map);
    return !isMethodCall && map != null && !map.accepts(source.type);
  }

  @override
  Iterable<Value> get inputs => [collection, source];
}

/// Assigns a map entry with runtime key/value checks and Dart key equality.
final class MapPut(final Value map, final Value key, final Value value)
    extends Instruction {
  this : super(.voidType) {
    final type = CoreTypes.view(map.type, CoreTypes.map);
    if (type == null || key.type is CellType || value.type is CellType) {
      throw ArgumentError('Invalid map insertion.');
    }
  }
  @override
  Iterable<Value> get inputs => [map, key, value];
}

/// Reads the iterable's iterator getter exactly once through Dart dispatch.
final class GetIterator(final Value iterable) extends Instruction {
  this
    : super(
        CoreTypes.iteratorOf(_protocolElement(iterable, CoreTypes.iterable)),
      );
  @override
  Iterable<Value> get inputs => [iterable];
}

/// Advances the iterator through Dart dispatch; mutation errors propagate.
final class IteratorMoveNext(final Value iterator) extends Instruction {
  this : super(.boolean) {
    _protocolElement(iterator, CoreTypes.iterator);
  }
  @override
  Iterable<Value> get inputs => [iterator];
}

/// Reads current only after a successful moveNext in lowered loops.
final class IteratorCurrent(final Value iterator) extends Instruction {
  this : super(_protocolElement(iterator, CoreTypes.iterator));
  @override
  Iterable<Value> get inputs => [iterator];
}

ValueType _protocolElement(Value value, ClassType protocol) {
  final type = CoreTypes.view(value.type, protocol);
  if (type == null) throw ArgumentError('Expected ${protocol.name} receiver.');
  return type.typeArguments.single;
}

/// Reads the map's lazy entries iterable through its Dart getter.
final class MapEntries(final Value map) extends Instruction {
  this : super(_mapEntriesType(map));
  @override
  Iterable<Value> get inputs => [map];
}

ClassType _mapEntriesType(Value value) {
  final map = CoreTypes.view(value.type, CoreTypes.map);
  if (map == null) throw ArgumentError('Expected a map receiver.');
  return CoreTypes.iterableOf(
    CoreTypes.mapEntryOf(map.typeArguments[0], map.typeArguments[1]),
  );
}

/// Reads length via the receiver's Dart collection getter.
final class CollectionLength(final Value collection) extends Instruction {
  this : super(.integer) {
    if (CoreTypes.view(collection.type, CoreTypes.iterable) == null &&
        CoreTypes.view(collection.type, CoreTypes.map) == null) {
      throw ArgumentError('Expected a collection.');
    }
  }
  @override
  Iterable<Value> get inputs => [collection];
}

/// Reads a list slot or map key, preserving bounds and missing-key behavior.
final class CollectionGet(final Value collection, final Value key)
    extends Instruction {
  this : super(_collectionIndexType(collection, key));
  @override
  Iterable<Value> get inputs => [collection, key];
}

/// Copies a list range through virtual dispatch, preserving an omitted end.
final class ListSublist(final Value list, final Value start, [final Value? end])
    extends Instruction {
  this : super(CoreTypes.listOf(_protocolElement(list, CoreTypes.list))) {
    if (!ValueType.integer.accepts(start.type) ||
        (end != null && !ValueType.integer.nullable.accepts(end!.type))) {
      throw ArgumentError('Invalid list range.');
    }
  }
  @override
  Iterable<Value> get inputs => [list, start, ?end];
}

/// Tests key presence independently from the nullable result of a map lookup.
final class MapContainsKey(final Value map, final Value key)
    extends Instruction {
  this : super(.boolean) {
    if (CoreTypes.view(map.type, CoreTypes.map) == null ||
        key.type is CellType) {
      throw ArgumentError('Invalid map key test.');
    }
  }
  @override
  Iterable<Value> get inputs => [map, key];
}

/// Raises the Dart error for a failed irrefutable pattern match.
final class PatternMatchFailure() extends Instruction {
  this : super(.never);
  @override
  Iterable<Value> get inputs => const [];
}

/// Writes a list slot, preserving bounds and actual runtime element checks.
final class ListSet(final Value collection, final Value key, final Value value)
    extends Instruction {
  this : super(.voidType) {
    final type = CoreTypes.view(collection.type, CoreTypes.list);
    if (type == null ||
        !ValueType.integer.accepts(key.type) ||
        value.type is CellType) {
      throw ArgumentError('Invalid list write.');
    }
  }
  @override
  Iterable<Value> get inputs => [collection, key, value];
}

ValueType _collectionIndexType(Value collection, Value key) {
  final list = CoreTypes.view(collection.type, CoreTypes.list);
  if (list != null && ValueType.integer.accepts(key.type)) {
    return list.typeArguments.single;
  }
  final map = CoreTypes.view(collection.type, CoreTypes.map);
  if (map != null && key.type is! CellType) {
    return map.typeArguments[1].nullable;
  }
  throw ArgumentError('Invalid collection index.');
}

/// Recognizes supported resolved dart:core operations without inventing targets.
Instruction? coreCollectionOperation(
  String name,
  Value receiver,
  List<Value> args,
) {
  final list = CoreTypes.view(receiver.type, CoreTypes.list);
  final set = CoreTypes.view(receiver.type, CoreTypes.set);
  final map = CoreTypes.view(receiver.type, CoreTypes.map);
  final iterable = CoreTypes.view(receiver.type, CoreTypes.iterable);
  final iterator = CoreTypes.view(receiver.type, CoreTypes.iterator);
  final entry = CoreTypes.view(receiver.type, CoreTypes.mapEntry);
  return switch ((name, args)) {
    ('key', []) when entry != null => LoadField(
      CoreTypes.mapEntryKey,
      receiver,
    ),
    ('value', []) when entry != null => LoadField(
      CoreTypes.mapEntryValue,
      receiver,
    ),
    ('length', []) when iterable != null || map != null => CollectionLength(
      receiver,
    ),
    ('sublist', [final start]) when list != null => ListSublist(
      receiver,
      start,
    ),
    ('sublist', [final start, final end]) when list != null => ListSublist(
      receiver,
      start,
      end,
    ),
    ('containsKey', [final key]) when map != null => MapContainsKey(
      receiver,
      key,
    ),
    ('entries', []) when map != null => MapEntries(receiver),
    ('iterator', []) when iterable != null => GetIterator(receiver),
    ('current', []) when iterator != null => IteratorCurrent(receiver),
    ('moveNext', []) when iterator != null => IteratorMoveNext(receiver),
    ('[]', [final key]) when list != null || map != null => CollectionGet(
      receiver,
      key,
    ),
    ('[]=', [final key, final value]) when list != null => ListSet(
      receiver,
      key,
      value,
    ),
    ('[]=', [final key, final value]) when map != null => MapPut(
      receiver,
      key,
      value,
    ),
    ('add', [final value]) when list != null || set != null => CollectionAdd(
      receiver,
      value,
    ),
    ('addAll', [final source])
        when list != null || set != null || map != null =>
      CollectionSpread(receiver, source, isMethodCall: true),
    _ => null,
  };
}
