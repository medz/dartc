/// @docImport 'function.dart';
library;

import 'dart:typed_data';

import 'package:dartc/interop.dart';

import 'core_types.dart';
import 'ffi_types.dart';
import 'signature.dart';
import 'type.dart';

/// An operand in static single assignment (SSA) form.
///
/// A use refers to its defining instruction or block parameter by identity.
/// A [Constant] can be used in any block.
/// Other domains may define values for their own graphs; an [IrFunction]
/// accepts only constants and values defined by its verified blocks.
abstract class const Value(
  /// The semantic or compiler storage type, independent of machine locations.
  final ValueType type,
) {
  /// The operand type before statically justified upcasts.
  ValueType get unviewedType {
    Value value = this;
    while (value is TypeView) {
      value = value.operand;
    }
    return value.type;
  }
}

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
  /// A structural identity key without executing Dart user equality or hashing.
  ///
  /// Scalar representation, collection order, nominal field slots and complete
  /// function instantiations are retained. Constructor sites are not identities.
  Object get structuralKey => switch (this) {
    TypeConstant(:final representedType) => (
      TypeConstant,
      representedType.normalize(),
    ),
    ScalarConstant(:final type, :final value) => (
      type,
      value is double
          ? (ByteData(8)..setFloat64(0, value)).getUint64(0)
          : value,
    ),
    final FunctionConstant value => _functionConstantKey(value),
    RecordConstant(:final type, :final fields) => (
      type.normalize(),
      fields.fold<Object?>(null, (tail, field) => (tail, field.structuralKey)),
    ),
    SequenceConstant(:final type, :final elements) => (
      type.normalize(),
      elements.fold<Object?>(
        null,
        (tail, element) => (tail, element.structuralKey),
      ),
    ),
    MapConstant(:final type, :final entries) => (
      type.normalize(),
      entries.fold<Object?>(
        null,
        (tail, entry) => (tail, entry.$1.structuralKey, entry.$2.structuralKey),
      ),
    ),
    ObjectConstant(:final type, :final fields) => (
      type.normalize(),
      _orderedFields(fields).fold<Object?>(
        null,
        (tail, field) => (tail, field, (fields[field]!).structuralKey),
      ),
    ),
  };

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
        representedType.freeTypeParameters.isNotEmpty) {
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

/// Reads Dart Object.runtimeType, retaining virtual dispatch for user objects.
final class ObjectRuntimeType(
  final Value operand, {

  /// Whether `super` selected the built-in getter without virtual dispatch.
  final bool direct = false,
}) extends Instruction {
  this : super(.typeType) {
    if (operand.type is CellType) throw ArgumentError('Expected a Dart value.');
  }
  @override
  Iterable<Value> get inputs => [operand];
}

/// Reads Dart Object.hashCode, retaining virtual dispatch for user objects.
final class ObjectHashCode(
  final Value operand, {

  /// Whether to use Object's identity hash without virtual dispatch.
  final bool direct = false,
}) extends Instruction {
  this : super(.integer) {
    if (operand.type is CellType) throw ArgumentError('Expected a Dart value.');
  }
  @override
  Iterable<Value> get inputs => [operand];
}

/// Reads the implementation class name without invoking an overridable getter.
final class ObjectClassName(final Value operand) extends Instruction {
  this : super(.string) {
    if (operand.type is CellType) throw ArgumentError('Expected a Dart value.');
  }
  @override
  Iterable<Value> get inputs => [operand];
}

/// A canonical tear-off of a top-level function, static method or constructor.
///
/// All types must be closed. Use [InstantiateFunction] to apply lexical types.
final class FunctionConstant._(
  /// The referenced declaration, including the source factory for a redirect.
  final FunctionTarget target,
  final ClassType? ownerType,
  final List<ValueType>? typeArguments,

  /// The generic callable view of a constructor alias.
  final FunctionType? constructorSignature,

  /// The nominal identity retained by a non-proper generic constructor alias.
  final (Uri, String)? constructorAlias,

  /// The target type arguments in an erased constructor alias's binder scope.
  final List<ValueType>? constructorTypeArguments,
) extends Constant {
  new(
    FunctionTarget target, {
    ClassType? ownerType,
    Iterable<ValueType>? typeArguments,
    FunctionType? constructorSignature,
    (Uri, String)? constructorAlias,
    Iterable<ValueType>? constructorTypeArguments,
  }) : this._(
         target,
         ownerType,
         typeArguments == null ? null : .unmodifiable(typeArguments),
         constructorSignature,
         constructorAlias,
         constructorTypeArguments == null
             ? null
             : .unmodifiable(constructorTypeArguments),
       );
  this
    : super(
        typeArguments == null
            ? constructorSignature ??
                  target.tearOffSignature(ownerType: ownerType)
            : (constructorSignature ??
                      target.tearOffSignature(ownerType: ownerType))
                  .instantiate(typeArguments),
      ) {
    if (type.freeTypeParameters.isNotEmpty ||
        typeArguments?.any((type) => type.freeTypeParameters.isNotEmpty) ==
            true ||
        constructorTypeArguments != null &&
            FunctionType(
              .voidType,
              constructorTypeArguments!,
              typeParameters: constructorSignature?.typeParameters ?? const [],
            ).freeTypeParameters.isNotEmpty) {
      throw ArgumentError('Function constants require closed types.');
    }
    ownerType?.validateTypeArguments();
    if (constructorAlias != null &&
        (constructorSignature == null ||
            constructorSignature!.typeParameters.isEmpty)) {
      throw ArgumentError(
        'A constructor alias identity requires a generic callable view.',
      );
    }
    if (constructorTypeArguments != null &&
        (constructorAlias == null || target.kind != .function)) {
      throw ArgumentError(
        'Erased constructor arguments require a static alias callable.',
      );
    }
    if (constructorSignature case final signature?) {
      if (ownerType != null ||
          (constructorTypeArguments == null &&
              target.kind != .initializer &&
              target.kind != .factory)) {
        throw ArgumentError(
          'A constructor callable view requires an unapplied constructor.',
        );
      }
      final FunctionType expected;
      if (constructorTypeArguments case final arguments?) {
        expected = target.signature.instantiate(arguments);
      } else {
        final owner = signature.result;
        if (owner is! ClassType ||
            owner.declaration != target.owner?.declaration) {
          throw ArgumentError(
            'Constructor callable view returns an incompatible owner.',
          );
        }
        owner.validateTypeArguments();
        expected = target.signatureFor(owner);
      }
      final genericExpected = FunctionType(
        expected.result,
        expected.parameters,
        typeParameters: signature.typeParameters,
        optionalPositional: expected.optionalPositional,
        namedParameters: expected.namedParameters,
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
    owner?.normalize(),
    value.constructorAlias,
    arguments?.fold<Object?>(null, (tail, type) => (tail, type.normalize())),
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

/// Possible effects of evaluating an instruction with its operands already available.
enum Effect() {
  /// Observes mutable state outside the SSA operands.
  readsStorage,

  /// Changes observable storage, including lazy initialization.
  writesStorage,

  /// Creates a value or storage, independently of its machine representation.
  allocates,

  /// May invoke Dart code with arbitrary effects.
  callsUserCode,

  /// May transfer control to a Dart exception handler.
  mayThrow,
}

/// An operation executed at its position in a block's instruction list.
sealed class Instruction(super.type) extends Value {
  /// The SSA operands consumed by the operation.
  Iterable<Value> get inputs;

  /// The virtual member invoked by an operation with a built-in spelling.
  ({ValueType receiver, MemberSelector selector})? get implicitMember =>
      switch (this) {
        GetIterator(:final iterable) => (
          receiver: iterable.type,
          selector: (kind: .getter, name: 'iterator', privateScope: null),
        ),
        IteratorMoveNext(:final iterator) => (
          receiver: iterator.type,
          selector: (kind: .method, name: 'moveNext', privateScope: null),
        ),
        IteratorCurrent(:final iterator) => (
          receiver: iterator.type,
          selector: (kind: .getter, name: 'current', privateScope: null),
        ),
        CollectionLength(:final collection) => (
          receiver: collection.type,
          selector: (kind: .getter, name: 'length', privateScope: null),
        ),
        CollectionGet(:final collection) => (
          receiver: collection.type,
          selector: (kind: .method, name: '[]', privateScope: null),
        ),
        ListSet(:final collection) => (
          receiver: collection.type,
          selector: (kind: .method, name: '[]=', privateScope: null),
        ),
        MapPut(:final map) => (
          receiver: map.type,
          selector: (kind: .method, name: '[]=', privateScope: null),
        ),
        MapContainsKey(:final map) => (
          receiver: map.type,
          selector: (kind: .method, name: 'containsKey', privateScope: null),
        ),
        MapEntries(:final map) => (
          receiver: map.type,
          selector: (kind: .getter, name: 'entries', privateScope: null),
        ),
        ListSublist(:final list) => (
          receiver: list.type,
          selector: (kind: .method, name: 'sublist', privateScope: null),
        ),
        CollectionAdd(:final collection) => (
          receiver: collection.type,
          selector: (kind: .method, name: 'add', privateScope: null),
        ),
        CollectionSpread(:final collection, isMethodCall: true) => (
          receiver: collection.type,
          selector: (kind: .method, name: 'addAll', privateScope: null),
        ),
        ObjectRuntimeType(:final operand, direct: false) => (
          receiver: operand.type,
          selector: (kind: .getter, name: 'runtimeType', privateScope: null),
        ),
        ObjectHashCode(:final operand, direct: false) => (
          receiver: operand.type,
          selector: (kind: .getter, name: 'hashCode', privateScope: null),
        ),
        Equals(:final left, :final right, mayCallUserCode: true)
            when left is! TypeConstant &&
                left is! ReifyType &&
                left.type != .nullType &&
                right.type != .nullType =>
          (
            receiver: left.type,
            selector: (kind: .method, name: '==', privateScope: null),
          ),
        _ => null,
      };

  static const _call = <Effect>{
    .readsStorage,
    .writesStorage,
    .allocates,
    .callsUserCode,
    .mayThrow,
  };
  static const _allocate = <Effect>{.allocates, .mayThrow};
  static const _checkedWrite = <Effect>{.writesStorage, .mayThrow};
  static const _bindOnce = <Effect>{.readsStorage, .writesStorage, .mayThrow};

  /// A conservative bound on this operation's effects on every path.
  ///
  /// Calls include all effects their callees could have. Allocation describes
  /// the operation itself; temporary boxes and GC safepoints depend on the backend.
  Set<Effect> get effects => switch (this) {
    NativeCallbackEntry() => const {.readsStorage, .writesStorage},
    ObjectHashCode(direct: true) => _bindOnce,
    ObjectRuntimeType(direct: true) => const {.readsStorage},
    ObjectClassName() => const {.readsStorage},
    ObjectRuntimeType() ||
    ObjectHashCode() ||
    ListSublist() ||
    MapContainsKey() ||
    MapEntries() ||
    CollectionLength() ||
    CollectionGet() ||
    ListSet() ||
    CollectionAdd() ||
    CollectionSpread() ||
    MapPut() ||
    GetIterator() ||
    StringFromCharCodes() ||
    ListFrom() ||
    IteratorMoveNext() ||
    IteratorCurrent() ||
    DirectCall() ||
    NativeCall() ||
    LoadLibrary() ||
    InstanceCall() ||
    DynamicDispatch() ||
    FunctionCall() ||
    Construct() ||
    BindMethod(direct: false) ||
    Equals(mayCallUserCode: true) => _call,
    NewCollection() ||
    ListFilled() ||
    MakeInvocation() ||
    BindMethod(direct: true) ||
    InstantiateFunction() ||
    InstantiateFunctionFrom() ||
    MakeClosure() ||
    NewCell() ||
    MakeRecord() ||
    StringConcat() ||
    StringFromCharCode() ||
    AssertionFailure() ||
    PatternMatchFailure() => _allocate,
    CopyCell() => const {.readsStorage, .allocates, .mayThrow},
    CopyNative() => const {.readsStorage, .writesStorage},
    LoadGlobal(global: GlobalVariable(initializer: != null)) ||
    LoadField(field: InstanceField(initializer: != null)) ||
    ReadCell(cell: Value(type: CellType(isLate: true))) => _call,
    CheckLibraryLoaded() ||
    LoadGlobal(global: GlobalVariable(isLate: true)) ||
    LoadField(field: InstanceField(isLate: true)) ||
    LoadField(
      field: InstanceField(requiresReadCheck: true),
    ) => const {.readsStorage, .mayThrow},
    LoadGlobal() ||
    LoadField() ||
    ReadCell() ||
    StringLength() ||
    LoadObjectData() ||
    LoadObjectReference() ||
    ReferenceAddress() ||
    ReferenceFromAddress() ||
    LoadNative() => const {.readsStorage},
    StringCodeUnitAt() => const {.readsStorage, .mayThrow},
    StoreGlobal(global: GlobalVariable(isFinal: true)) ||
    StoreField(field: InstanceField(isLate: true, isFinal: true)) ||
    WriteCell(
      cell: Value(type: CellType(isLate: true, isFinal: true)),
    ) => _bindOnce,
    StoreField(:final field) when field.type.freeTypeParameters.isNotEmpty =>
      _checkedWrite,
    WriteCell(
      cell: Value(type: CellType(:final content)),
      value: Value(type: final source),
    )
        when (source == .integer || source == .floating) && source != content =>
      _checkedWrite,
    StoreGlobal() ||
    StoreField() ||
    WriteCell() ||
    StoreNative() ||
    StoreObjectReference() ||
    StoreObjectData() => const {.writesStorage},
    TypeCast() ||
    NullCheck() ||
    IntBinary(operator: IntOperator(mayThrow: true)) ||
    NumericBinary(canThrow: true) => const {.mayThrow},
    NumericToInt(operand: Value(type: final type)) when type != .integer =>
      const {.mayThrow},
    TypeView(:final operand) || UncheckedCast(:final operand)
        when (operand.type == .integer || operand.type == .floating) &&
            type != .integer &&
            type != .floating =>
      _allocate,
    TypeTest(testedType: != ValueType.nullType) => _allocate,
    ReifyType() ||
    PointerFromAddress() ||
    PointerOffset() ||
    NewPayload() ||
    NativeView() => _allocate,
    Identical() ||
    Equals() ||
    IntBinary() ||
    NumericBinary() ||
    NumericNegate() ||
    NumericToDouble() ||
    FloatBitCast() ||
    NumericRoundToDouble() ||
    NumericToInt() ||
    NumericSquareRoot() ||
    TypeTest() ||
    TypeView() ||
    UncheckedCast() ||
    RecordGet() ||
    PointerAddress() ||
    NativeAddress() ||
    NativeSymbolAddress() ||
    NativeSize() ||
    NativeFieldOffset() ||
    KeepAlive() => const {},
  };

  /// Whether evaluation can transfer control to a Dart exception handler.
  bool get mayThrow => effects.contains(Effect.mayThrow);
}

/// The link-resolved address of a native declaration, without reading it.
final class NativeSymbolAddress(final NativeReference reference)
    extends Instruction {
  this : super(.integer);

  @override
  Iterable<Value> get inputs => const [];
}

/// A typed native entry whose escaping exceptions return a declared value.
sealed class NativeCallbackEntry(
  FunctionType nativeType,
  final FunctionType callbackType,
  final Constant? exceptionalReturn,
) extends Instruction {
  final NativeSignature signature = (FfiTypes.describe(
    FfiTypes.nativeFunction.instantiate([nativeType]),
  ) as NativeFunctionType).signature;
  final FunctionType dartSignature = FfiTypes.dartSignature(nativeType);

  this : super(.integer) {
    final type = callbackType;
    if (type.typeParameters.isNotEmpty ||
        !type.acceptsShape(dartSignature.parameters.length, const [])) {
      throw ArgumentError('Expected a matching callback.');
    }
    for (final (native, expected, actual, result) in [
      (signature.result, dartSignature.result, type.result, true),
      for (final (i, parameter) in signature.parameters.indexed)
        (parameter, dartSignature.parameters[i], type.parameters[i], false),
    ]) {
      final compatible =
          native is NativePointerType || native is NativeCompoundType
          ? result
                ? expected.accepts(actual)
                : actual.accepts(expected)
          : native.isVoid && result || expected == actual;
      if (!compatible) {
        throw ArgumentError('Incompatible native callback signature.');
      }
    }
    final implicit =
        signature.result.isVoid ||
        signature.result is NativePointerType ||
        signature.result is NativeCompoundType;
    if (implicit
        ? exceptionalReturn != null
        : exceptionalReturn is! ScalarConstant ||
              !dartSignature.result.accepts(exceptionalReturn!.type)) {
      throw ArgumentError('Invalid callback exceptional return.');
    }
  }

  @override
  Iterable<Value> get inputs => const [];
}

/// Binds a static callback to the current thread until its module is unloaded.
final class NativeCallbackAddress(
  final FunctionTarget function,
  FunctionType nativeType, {
  Constant? exceptionalReturn,
}) extends NativeCallbackEntry {
  this : super(nativeType, function.signature, exceptionalReturn) {
    if (function.kind != .function || function.typeParameters.isNotEmpty) {
      throw ArgumentError('Expected a nongeneric static callback.');
    }
  }
}

/// Returns a closure entry entered through a registered native trampoline.
///
/// [lookup] retrieves the live function for the trampoline address. The caller
/// registers that function and owns the trampoline's lifetime.
final class NativeClosureEntryAddress(
  final FunctionTarget lookup,
  FunctionType callbackType,
  FunctionType nativeType, {
  Constant? exceptionalReturn,
}) extends NativeCallbackEntry {
  this : super(nativeType, callbackType, exceptionalReturn) {
    if (lookup.kind != .function ||
        lookup.signature != FunctionType(.function, [.integer])) {
      throw ArgumentError('Expected an address-to-function callback lookup.');
    }
  }
}

/// Observes a reference's current address; null has address zero.
///
/// Trusted memory code must not retain the address across a moving collection.
final class ReferenceAddress(final Value object) extends Instruction {
  this : super(.integer) {
    if (!ValueType.object.nullable.accepts(object.type) ||
        object.type == .integer ||
        object.type == .floating ||
        object.type == .boolean) {
      throw ArgumentError('Expected an object reference.');
    }
  }
  @override
  Iterable<Value> get inputs => [object];
}

/// Recovers an existing reference from initialized storage without allocating.
///
/// The caller proves the address has [type], remains live and obeys its layout.
/// Zero is permitted only when [type] admits null. This is not a checked cast.
final class ReferenceFromAddress(final Value address, super.type)
    extends Instruction {
  this {
    if (address.type != .integer ||
        type == .voidType ||
        type == .never ||
        type == .integer ||
        type == .floating ||
        type == .boolean ||
        type is CellType) {
      throw ArgumentError('Expected an integer address and a value type.');
    }
  }
  @override
  Iterable<Value> get inputs => [address];
}

/// Creates a native pointer without accessing or owning its target.
final class PointerFromAddress(final Value address, ClassType type)
    extends Instruction {
  this : super(type) {
    if (address.type != .integer || !FfiTypes.isPointer(type)) {
      throw ArgumentError(
        'Expected an integer address and native pointer type.',
      );
    }
  }
  @override
  Iterable<Value> get inputs => [address];
}

/// Extracts a native pointer's address without dereferencing it.
final class PointerAddress(final Value pointer) extends Instruction {
  this : super(.integer) {
    if (!FfiTypes.isPointer(pointer.type)) {
      throw ArgumentError('Expected a native pointer.');
    }
  }
  @override
  Iterable<Value> get inputs => [pointer];
}

/// Allocates zeroed inline storage for a runtime class or built-in String.
final class NewPayload(ClassType type, final Value bytes) extends Instruction {
  this : super(type) {
    if (type.isAbstract && type != ValueType.string ||
        type.freeTypeParameters.isNotEmpty ||
        bytes.type != .integer) {
      throw ArgumentError(
        'Expected concrete payload storage and a byte count.',
      );
    }
  }
  @override
  Iterable<Value> get inputs => [bytes];
}

/// A typed native view retaining the owner of its backing storage.
///
/// An absent [address] allocates zeroed managed storage; [copy] copies a supplied
/// address into independent managed storage. Borrowed addresses require an owner
/// or an external lifetime guarantee.
final class NativeView(
  ClassType type, {
  final Value? address,
  final Value owner = const Constant.nullValue(),
  final bool copy = false,
}) extends Instruction {
  this : super(type) {
    if (address != null && address!.type != .integer ||
        type.nativeType is! NativeCompoundType ||
        !ValueType.object.nullable.accepts(owner.type) ||
        owner.type == .integer ||
        owner.type == .floating ||
        owner.type == .boolean) {
      throw ArgumentError('Expected native compound storage and its owner.');
    }
  }
  @override
  Iterable<Value> get inputs => [?address, owner];
}

/// The address of a native compound view; the view owns any managed backing.
///
/// Abstract Struct/Union views need no concrete native layout to expose storage.
final class NativeAddress(final Value view) extends Instruction {
  this : super(.integer) {
    if (!FfiTypes.isCompound(view.type)) {
      throw ArgumentError('Expected a native compound view.');
    }
  }
  @override
  Iterable<Value> get inputs => [view];
}

/// A native type's byte size, determined from the output target's ABI.
final class NativeSize(final NativeTypeRef nativeType) extends Instruction {
  this : super(.integer) {
    if (!nativeType.isSized) {
      throw ArgumentError('Expected sized native storage.');
    }
  }
  @override
  Iterable<Value> get inputs => const [];
}

/// A field's byte offset in the output target's native layout.
final class NativeFieldOffset(final NativeCompoundType owner, final int index)
    extends Instruction {
  this : super(.integer) {
    RangeError.checkValidIndex(index, owner.fields);
  }
  @override
  Iterable<Value> get inputs => const [];
}

/// Copies one native value, including overlapping source and destination storage.
final class CopyNative(
  final Value destination,
  final Value source,
  final NativeTypeRef nativeType,
) extends Instruction {
  this : super(.voidType) {
    if (destination.type != .integer ||
        source.type != .integer ||
        !nativeType.isSized) {
      throw ArgumentError('Expected addresses and sized native storage.');
    }
  }
  @override
  Iterable<Value> get inputs => [destination, source];
}

/// Retains a managed owner through preceding native accesses or calls.
final class KeepAlive(final Value value) extends Instruction {
  this : super(.voidType);
  @override
  Iterable<Value> get inputs => [value];
}

/// Offsets a native pointer by a signed number of elements, without accessing it.
///
/// The result retains the element type. Address arithmetic wraps at the target
/// pointer width; this operation neither owns storage nor checks its bounds.
final class PointerOffset(final Value pointer, final Value index)
    extends Instruction {
  this : super(pointer.type) {
    if (FfiTypes.pointerElement(pointer.type) == null ||
        index.type != .integer) {
      throw ArgumentError(
        'Expected a pointer to sized native storage and integer index.',
      );
    }
  }
  @override
  Iterable<Value> get inputs => [pointer, index];
}

/// Reads [nativeType] storage at an integer [address].
///
/// The caller must keep the storage alive, aligned and readable. Invalid native
/// memory access is not a Dart exception and is not checked by this operation.
final class LoadNative(final Value address, final NativeTypeRef nativeType)
    extends Instruction {
  this : super(FfiTypes.valueType(nativeType)) {
    if (address.type != .integer || !nativeType.isScalar || nativeType.isVoid) {
      throw ArgumentError(
        'Expected an integer address and sized native scalar.',
      );
    }
  }
  @override
  Iterable<Value> get inputs => [address];
}

/// Writes [value] at an integer [address] using [nativeType]'s width and precision.
///
/// The caller must keep the storage alive, aligned and writable. The write is
/// observable through every alias, even when its result is unused.
final class StoreNative(
  final Value address,
  final NativeTypeRef nativeType,
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    if (address.type != .integer ||
        !nativeType.isScalar ||
        nativeType.isVoid ||
        value.type != FfiTypes.valueType(nativeType)) {
      throw ArgumentError(
        'Expected an integer address, sized native scalar and matching value.',
      );
    }
  }
  @override
  Iterable<Value> get inputs => [address, value];
}

/// Reads scalar storage at [byteOffset] from a managed [object]'s header.
///
/// The layout owner must prove bounds and alignment. The object stays traced;
/// no interior address escapes this operation or survives a safepoint.
final class LoadObjectData(
  final Value object,
  final Value byteOffset,
  final NativeScalarType nativeType,
) extends Instruction {
  this : super(FfiTypes.valueType(nativeType)) {
    _checkObjectData(object, byteOffset);
    if (nativeType.isVoid) throw ArgumentError('A sized scalar is required.');
  }
  @override
  Iterable<Value> get inputs => [object, byteOffset];
}

/// Writes scalar [value] into a managed object's inline storage.
///
/// The layout owner must prove bounds, alignment and exclusive initialization
/// of immutable data. Managed references cannot be written through this operation.
final class StoreObjectData(
  final Value object,
  final Value byteOffset,
  final NativeScalarType nativeType,
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    _checkObjectData(object, byteOffset);
    if (nativeType.isVoid || value.type != FfiTypes.valueType(nativeType)) {
      throw ArgumentError('The stored value must match the native scalar.');
    }
  }
  @override
  Iterable<Value> get inputs => [object, byteOffset, value];
}

/// Reads a traced reference slot from a managed object's inline payload.
///
/// The layout owner must prove bounds, alignment and collector metadata.
final class LoadObjectReference(final Value object, final Value byteOffset)
    extends Instruction {
  this : super(.object.nullable) {
    _checkObjectData(object, byteOffset);
  }
  @override
  Iterable<Value> get inputs => [object, byteOffset];
}

/// Writes a traced reference slot, retaining both operands across safepoints.
///
/// The layout owner must prove bounds, alignment, mutability and collector metadata.
final class StoreObjectReference(
  final Value object,
  final Value byteOffset,
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    _checkObjectData(object, byteOffset);
    if (!ValueType.object.nullable.accepts(value.type)) {
      throw ArgumentError('A Dart value is required.');
    }
  }
  @override
  Iterable<Value> get inputs => [object, byteOffset, value];
}

void _checkObjectData(Value object, Value offset) {
  final type = object.type;
  if (type is! ClassType ||
      type.mayBeNull ||
      type == ValueType.integer ||
      type == ValueType.floating ||
      type == ValueType.boolean ||
      offset.type != .integer) {
    throw ArgumentError(
      'A non-null managed object and integer offset are required.',
    );
  }
}

/// Starts loading a deferred import and returns its completion Future.
///
/// Successful completion enables this prefix. Repeated loads after success
/// succeed. Compilation failures persist; other failures permit another attempt.
/// Failures complete the Future with an error and leave the prefix unloaded.
final class LoadLibrary(final DeferredImport reference) extends Instruction {
  this : super(CoreTypes.futureOf(.dynamicType));

  @override
  Iterable<Value> get inputs => const [];
}

/// Raises a dynamic error unless this deferred prefix has finished loading.
///
/// The check precedes argument evaluation and must retain exception edges.
final class CheckLibraryLoaded(final DeferredImport reference)
    extends Instruction {
  this : super(.voidType);

  @override
  Iterable<Value> get inputs => const [];
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
  this : super(_memberSignature(method, receiver, ownerType)) {
    if (method.kind != .method || direct && method.isAbstract) {
      throw ArgumentError('Invalid method tear-off.');
    }
  }
  @override
  Iterable<Value> get inputs => [receiver];
}

/// Applies explicit or inferred type arguments to a generic function value.
final class InstantiateFunction._(
  final Value function,
  final List<ValueType> typeArguments,
) extends Instruction {
  new(Value function, Iterable<ValueType> typeArguments)
    : this._(function, .unmodifiable(typeArguments));
  this : super(_functionSignature(function).instantiate(typeArguments)) {
    if (typeArguments.isEmpty) {
      throw ArgumentError('Expected a generic function value.');
    }
  }
  @override
  Iterable<Value> get inputs => [function];
}

/// Instantiates a generic function with an instance's actual nominal arguments.
///
/// [declaration] selects the supertype view; the instance's static arguments
/// do not replace its actual arguments. Function bounds remain checked.
final class InstantiateFunctionFrom(
  final Value function,
  final Value instance,
  final ClassType declaration,
) extends Instruction {
  this : super(.function) {
    final signature = _functionSignature(function);
    if (declaration != declaration.declaration ||
        declaration.typeParameters.isEmpty ||
        declaration.typeParameters.length != signature.typeParameters.length ||
        instance.type is! ClassType ||
        (instance.type as ClassType).asInstanceOf(declaration) == null) {
      throw ArgumentError('Expected matching nominal and function binders.');
    }
  }
  @override
  Iterable<Value> get inputs => [function, instance];
}

FunctionType _functionSignature(Value function) => switch (function.type) {
  final FunctionType type => type,
  _ => throw ArgumentError('Expected a non-nullable function signature.'),
};

/// Invokes a function value with the supplied arguments and the destination's defaults.
final class FunctionCall._(
  /// The evaluated function value.
  final Value function,

  /// Supplied positional arguments.
  final List<Value> positional,

  /// Supplied named arguments.
  final Map<String, Value> named,
  final List<ValueType> typeArguments,
) extends Instruction {
  new(
    Value function,
    Iterable<Value> positional, [
    Map<String, Value> named = const {},
    Iterable<ValueType> typeArguments = const [],
  ]) : this._(
         function,
         .unmodifiable(positional),
         .unmodifiable(named),
         .unmodifiable(typeArguments),
       );
  this
    : super(
        _callResult(
          _functionSignature(function).instantiate(typeArguments),
          positional,
          named,
        ),
      );
  @override
  Iterable<Value> get inputs => [function, ...positional, ...named.values];
}

ValueType _callResult(
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
  return signature.result;
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
  this : super(field.typeFor(_classReceiver(receiver.type, field.owner)));
  @override
  Iterable<Value> get inputs => [receiver];
}

/// Invokes a member on the runtime class with the arguments supplied by the caller.
///
/// The implementation supplies its own optional defaults and performs its
/// parameter type checks before entering the body.
final class InstanceCall._(
  /// The statically resolved member and signature.
  final FunctionTarget member,

  /// The evaluated dispatch receiver.
  final Value receiver,

  /// Explicit positional arguments.
  final List<Value> positional,

  /// Explicit named arguments, in their source order.
  final Map<String, Value> named,
  final ClassType? ownerType,
  final List<ValueType> typeArguments,
) extends Instruction {
  new(
    FunctionTarget member,
    Value receiver,
    Iterable<Value> positional, [
    Map<String, Value> named = const {},
    ClassType? ownerType,
    Iterable<ValueType> typeArguments = const [],
  ]) : this._(
         member,
         receiver,
         .unmodifiable(positional),
         .unmodifiable(named),
         ownerType,
         .unmodifiable(typeArguments),
       );
  this
    : super(
        _callResult(
          _memberSignature(
            member,
            receiver,
            ownerType,
          ).instantiate(typeArguments),
          positional,
          named,
        ),
      );

  @override
  Iterable<Value> get inputs sync* {
    yield receiver;
    yield* positional;
    yield* named.values;
  }
}

FunctionType _memberSignature(
  FunctionTarget member,
  Value receiver,
  ClassType? ownerType,
) {
  if (!member.kind.isVirtual) {
    throw ArgumentError('Expected an instance member.');
  }
  final actual = _classReceiver(receiver.type, member.owner);
  if (ownerType == null) return member.signatureFor(actual);
  if (!ownerType.accepts(receiver.type) ||
      actual.asInstanceOf(member.owner!) == null) {
    throw ArgumentError('Incompatible dispatch receiver.');
  }
  return member.signatureFor(ownerType);
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
  if (selector.privateScope is ClassType) {
    throw ArgumentError(
      'A generated private member has no Dart invocation name.',
    );
  }
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
  /// The instance type produced by this constructor invocation.
  ClassType get instantiatedType => type as ClassType;
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

/// A trusted type assertion with no runtime check.
///
/// The producer must establish that subsequent uses are valid. This changes
/// the static view, not object identity or runtime type; it cannot expose cells.
final class UncheckedCast(final Value operand, super.type) extends Instruction {
  this {
    if (operand.type is CellType || type is CellType) {
      throw ArgumentError('A trusted cast cannot expose storage.');
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

  /// The remainder with the dividend's sign after truncating division.
  remainder(.integer),

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
    remainder ||
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

/// Dart object identity, including integer values and double bit patterns.
///
/// Does not call user equality. Records do not promise persistent identity.
final class Identical(final Value left, final Value right) extends Instruction {
  this : super(.boolean);

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

/// A call through a typed native function pointer or a native symbol address.
///
/// Arguments and results are Dart values. The native signature determines their
/// boundary conversions, including integer truncation and float rounding.
final class NativeCall._(
  /// A `Pointer<NativeFunction<T>>` value or [NativeSymbolAddress] of a function.
  final Value pointer,

  /// The evaluated Dart arguments in native parameter order.
  final List<Value> arguments,

  /// The native signature derived from [pointer]'s type.
  final NativeSignature signature,

  /// Whether the caller promises a short, nonblocking call without Dart callbacks.
  final bool isLeaf,

  /// Owners of raw integer address arguments, keyed by argument position.
  ///
  /// Only leaf calls may borrow storage. The caller must derive each address
  /// from its owner after argument evaluation; owners stay live through the call.
  final Map<int, Value> borrowedOwners,
  super.type,
) extends Instruction {
  factory(
    Value pointer,
    Iterable<Value> arguments, {
    bool isLeaf = false,
    Map<int, Value> borrowedOwners = const {},
  }) {
    if (!FfiTypes.isPointer(pointer.type)) {
      throw ArgumentError('A typed native function pointer is required.');
    }
    if (FfiTypes.describe(pointer.type) case NativePointerType(
      element: NativeFunctionType(:final signature),
    )) {
      final declaration =
          (((pointer.type as ClassType).typeArguments.single as ClassType)
                  .typeArguments
                  .single
              as FunctionType);
      return _checked(
        pointer,
        arguments,
        signature,
        FfiTypes.dartSignature(declaration),
        isLeaf,
        borrowedOwners,
      );
    }
    throw ArgumentError('A typed native function pointer is required.');
  }

  /// Calls a native symbol using its checked Dart signature, including nominal types.
  factory symbol(
    NativeSymbolAddress pointer,
    FunctionType dartSignature,
    Iterable<Value> arguments, {
    Map<int, Value> borrowedOwners = const {},
  }) {
    final reference = pointer.reference;
    if (reference.type case NativeFunctionType(:final signature)
        when FfiTypes.canCall(signature, dartSignature)) {
      return _checked(
        pointer,
        arguments,
        signature,
        dartSignature,
        reference.isLeaf,
        borrowedOwners,
      );
    }
    throw ArgumentError(
      'The native symbol requires a matching Dart signature.',
    );
  }

  static NativeCall _checked(
    Value pointer,
    Iterable<Value> arguments,
    NativeSignature signature,
    FunctionType dartSignature,
    bool isLeaf,
    Map<int, Value> borrowedOwners,
  ) {
    final values = List<Value>.unmodifiable(arguments);
    final owners = Map<int, Value>.unmodifiable(borrowedOwners);
    for (final MapEntry(key: index, value: owner) in owners.entries) {
      if (!isLeaf ||
          index < 0 ||
          index >= signature.parameters.length ||
          signature.parameters[index] is! NativePointerType ||
          !ValueType.object.accepts(owner.type) ||
          owner.type == .integer ||
          owner.type == .floating ||
          owner.type == .boolean) {
        throw ArgumentError(
          'Borrowed addresses require a leaf pointer argument and a reference owner.',
        );
      }
    }
    checkArguments([
      for (final (i, type) in dartSignature.parameters.indexed)
        owners.containsKey(i) ? ValueType.integer : type,
    ], values);
    return ._(pointer, values, signature, isLeaf, owners, dartSignature.result);
  }

  @override
  Iterable<Value> get inputs => [
    pointer,
    ...arguments,
    ...borrowedOwners.values,
  ];
}

/// A call to a statically bound function.
///
/// The call may change state or throw even when its result is unused.
final class DirectCall._(
  /// The declaration selected during binding.
  final FunctionTarget target,
  @override final List<Value> inputs,
  final ClassType? ownerType,
  final List<ValueType> typeArguments,
  super.type,
) extends Instruction {
  factory(
    FunctionTarget target,
    Iterable<Value> arguments, {
    ClassType? ownerType,
    Iterable<ValueType> typeArguments = const [],
  }) {
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
        : target.environmentFor(ownerType);
    final types = List<ValueType>.unmodifiable(typeArguments);
    final inputs = List<Value>.unmodifiable(arguments);
    final signature = (target.signature.substitute(
      ownerEnvironment,
    ) as FunctionType).instantiate(types);
    checkArguments([
      if (target.kind.hasReceiver)
        target.parameterTypes.first.substitute(ownerEnvironment),
      ...signature.parameters,
    ], inputs);
    return ._(
      target,
      inputs,
      ownerType,
      types,
      target.kind == .initializer ? .voidType : signature.result,
    );
  }
}

/// Checks the arity and assignability of [arguments] against [types].
void checkArguments(Iterable<ValueType> types, List<Value> arguments) {
  var i = 0;
  for (final type in types) {
    if (i == arguments.length) throw ArgumentError('Missing argument $i.');
    final actual = arguments[i++].type;
    if (!type.accepts(actual)) {
      throw ArgumentError(
        'Argument ${i - 1} has type ${actual.dartName}; expected ${type.dartName}.',
      );
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

  /// The remainder with the dividend's sign after truncating division.
  remainder,

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
      (operator == .modulo || operator == .remainder) &&
          left.type != .floating &&
          right.type != .floating;

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

/// Converts a number to double, rounding integers to the nearest IEEE value.
final class NumericToDouble(final Value operand) extends Instruction {
  this : super(.floating) {
    if (!ValueType.number.accepts(operand.type)) {
      throw ArgumentError('A non-nullable numeric operand is required.');
    }
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// Reinterprets an integer as IEEE floating bits, or extracts a double's bits.
///
/// A 32-bit conversion widens binary32 to Dart double on reads and rounds to
/// binary32 on writes. Integer inputs use their low [width] bits.
final class FloatBitCast(final Value operand, {final int width = 64})
    extends Instruction {
  this : super(operand.type == .integer ? .floating : .integer) {
    if (operand.type != .integer && operand.type != .floating ||
        width != 32 && width != 64) {
      throw ArgumentError('Expected int/double and an IEEE width of 32 or 64.');
    }
  }
  @override
  Iterable<Value> get inputs => [operand];
}

/// The rounding direction used to obtain an integral numeric value.
enum IntegerRounding() {
  /// Discards the fractional part.
  truncate,

  /// Rounds towards negative infinity.
  floor,

  /// Rounds towards positive infinity.
  ceil,

  /// Chooses the nearest integer, resolving ties away from zero.
  round,
}

/// Converts a number to an integer with explicit rounding.
///
/// Finite values outside the native integer range clamp to its bounds.
/// Non-finite values throw UnsupportedError; integer operands retain their value.
final class NumericToInt(final Value operand, final IntegerRounding rounding)
    extends Instruction {
  this : super(.integer) {
    if (!ValueType.number.accepts(operand.type)) {
      throw ArgumentError('A non-nullable numeric operand is required.');
    }
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// Rounds a number to an integral double without clamping its range.
///
/// Non-finite and already integral doubles, including negative zero, are
/// unchanged. A negative value rounded to zero produces negative zero.
final class NumericRoundToDouble(
  final Value operand,
  final IntegerRounding rounding,
) extends Instruction {
  this : super(.floating) {
    if (!ValueType.number.accepts(operand.type)) {
      throw ArgumentError('A non-nullable numeric operand is required.');
    }
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// Converts a number to double and computes its nonnegative square root.
///
/// Preserves negative zero; other negative inputs and NaN produce NaN.
final class NumericSquareRoot(final Value operand) extends Instruction {
  this : super(.floating) {
    if (!ValueType.number.accepts(operand.type)) {
      throw ArgumentError('A non-nullable numeric operand is required.');
    }
  }

  @override
  Iterable<Value> get inputs => [operand];
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

/// Constructs a string from one Unicode code point or UTF-16 code unit.
final class StringFromCharCode(final Value code) extends Instruction {
  this : super(.string) {
    if (!ValueType.integer.accepts(code.type)) {
      throw ArgumentError('An integer character code is required.');
    }
  }
  @override
  Iterable<Value> get inputs => [code];
}

/// Constructs a string from the selected range of [codes], iterating once.
final class StringFromCharCodes(
  final Value codes, [
  final Value start = const Constant.integer(0),
  final Value end = const Constant.nullValue(),
]) extends Instruction {
  this : super(.string) {
    if (!CoreTypes.iterableOf(.integer).accepts(codes.type) ||
        !ValueType.integer.accepts(start.type) ||
        !ValueType.integer.nullable.accepts(end.type)) {
      throw ArgumentError('Integer character codes and range are required.');
    }
  }
  @override
  Iterable<Value> get inputs => [codes, start, end];
}

/// Reads the number of UTF-16 code units in a string.
final class StringLength(final Value string) extends Instruction {
  this : super(.integer) {
    if (!ValueType.string.accepts(string.type)) {
      throw ArgumentError('A non-nullable string is required.');
    }
  }
  @override
  Iterable<Value> get inputs => [string];
}

/// Reads one UTF-16 code unit, throwing [RangeError] for an invalid [index].
final class StringCodeUnitAt(final Value string, final Value index)
    extends Instruction {
  this : super(.integer) {
    if (!ValueType.string.accepts(string.type) ||
        !ValueType.integer.accepts(index.type)) {
      throw ArgumentError(
        'A non-nullable string and integer index are required.',
      );
    }
  }
  @override
  Iterable<Value> get inputs => [string, index];
}

ClassType _classReceiver(ValueType type, [ClassType? owner]) {
  if (type == ValueType.nullType && owner == ValueType.nullClass) return owner!;
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
final class NewCollection(
  ClassType super.type, {

  /// Whether a new List can change length. Literal collections default to growable.
  final Value? growable,
}) extends Instruction {
  /// The collection type, including its reified element or key and value types.
  ClassType get collectionType => type as ClassType;
  this {
    if (![
      CoreTypes.list,
      CoreTypes.set,
      CoreTypes.map,
    ].contains(collectionType.declaration)) {
      throw ArgumentError('Expected a core literal collection type.');
    }
    if (growable != null &&
        (collectionType.declaration != CoreTypes.list ||
            growable!.type != .boolean)) {
      throw ArgumentError('Only a List accepts a boolean growability operand.');
    }
  }
  @override
  Iterable<Value> get inputs => [?growable];
}

/// Creates a fixed-length or growable List whose entries share [fill].
final class ListFilled(
  ClassType super.type,
  final Value length,
  final Value fill,
  final Value growable,
) extends Instruction {
  this {
    if ((type as ClassType).declaration != CoreTypes.list ||
        length.type != .integer ||
        growable.type != .boolean ||
        !(type as ClassType).typeArguments.single.accepts(fill.type)) {
      throw ArgumentError('Invalid filled List operands.');
    }
  }
  @override
  Iterable<Value> get inputs => [length, fill, growable];
}

/// Copies [elements] into a fresh List, checking each element against its type.
final class ListFrom(
  ClassType super.type,
  final Value elements,
  final Value growable,
) extends Instruction {
  this {
    if ((type as ClassType).declaration != CoreTypes.list ||
        !CoreTypes.iterableOf(.object.nullable).accepts(elements.type) ||
        growable.type != .boolean) {
      throw ArgumentError('Invalid List copy operands.');
    }
  }
  @override
  Iterable<Value> get inputs => [elements, growable];
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
