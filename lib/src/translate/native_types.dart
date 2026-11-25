import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/native.dart';

/// The field of a struct or union, or a variable of C: how it is declared, where
/// it is, and what it is.
typedef NativeField = ({
  PropertyInducingElement element,
  int offset,
  NativeType type,

  /// For arrays, how many elements each dimension has.
  List<int> dimensions,
});

/// What the types of `dart:ffi` are in C.
final class NativeTypes(final Target target) {
  final _compounds = <InterfaceElement, NativeCompound>{};
  final _fields = <InterfaceElement, List<NativeField>>{};

  static bool isFfi(Element? element) =>
      '${element?.library?.uri}' == 'dart:ffi';

  /// How functions with [signature] are called.
  CallPassing passing(NativeSignature signature) =>
      passingOf(signature, target);

  /// What [type] is, or null if it is no type of a value in C.
  NativeType? of(DartType type) {
    if (type is! InterfaceType) return null;
    final element = type.element;
    if (isFfi(element)) {
      final found = _basic(element.name!);
      if (found != null) return found;
    }
    for (final supertype in type.allSupertypes) {
      if (!isFfi(supertype.element)) continue;
      switch (supertype.element.name) {
        case 'AbiSpecificInteger':
          return _specific(element);
        case 'Struct' || 'Union':
          return compound(element);
      }
    }
    return null;
  }

  static NativeType? _basic(String name) => switch (name) {
    'Int8' => const NativeInteger(1, isSigned: true),
    'Int16' => const NativeInteger(2, isSigned: true),
    'Int32' => const NativeInteger(4, isSigned: true),
    'Int64' || 'IntPtr' => const NativeInteger(8, isSigned: true),
    'Uint8' => const NativeInteger(1, isSigned: false),
    'Uint16' => const NativeInteger(2, isSigned: false),
    'Uint32' => const NativeInteger(4, isSigned: false),
    'Uint64' || 'UintPtr' => const NativeInteger(8, isSigned: false),
    'Float' => const NativeFloating(4),
    'Double' => const NativeFloating(8),
    'Bool' => const NativeBoolean(),
    'Void' => const NativeVoid(),
    'Pointer' => const NativePointer(),
    _ => null,
  };

  /// The integer that [element] is on the system compiled for.
  NativeType? _specific(InterfaceElement element) {
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final mapping = value?.getField('mapping')?.toMapValue();
      if (mapping == null) continue;
      for (final MapEntry(:key, value: integer) in mapping.entries) {
        String? part(String name) =>
            key?.getField(name)?.getField('_name')?.toStringValue();
        if (part('_os') == target.system.name &&
            part('_architecture') == target.architecture.name) {
          return integer?.type == null ? null : of(integer!.type!);
        }
      }
    }
    return null;
  }

  /// The struct or union that [element] is.
  NativeCompound? compound(InterfaceElement element) {
    if (_compounds[element] case final known?) return known;
    final isUnion = element.allSupertypes.any(
      (type) => isFfi(type.element) && type.element.name == 'Union',
    );
    final packing = element.metadata.annotations
        .map((annotation) => annotation.computeConstantValue())
        .map((value) => value?.getField('memberAlignment')?.toIntValue())
        .nonNulls
        .firstOrNull;
    final made = _compounds[element] = NativeCompound(
      element.displayName,
      isUnion: isUnion,
      packing: packing,
    );
    final fields = <(FieldElement, NativeType, List<int>)>[];
    for (final field in element.fields) {
      if (field.isStatic || !_isExternal(field)) continue;
      final (type, dimensions) = _fieldType(field);
      if (type == null) return null;
      fields.add((field, type, dimensions));
    }
    made.define([for (final (_, type, _) in fields) type]);
    _fields[element] = [
      for (final (i, (field, type, dimensions)) in fields.indexed)
        (
          element: field,
          offset: made.offsets[i],
          type: type,
          dimensions: dimensions,
        ),
    ];
    return made;
  }

  /// Whether [element] is a struct or union.
  static bool isCompound(Element? element) =>
      element is InterfaceElement &&
      element.allSupertypes.any(
        (type) =>
            isFfi(type.element) &&
            const ['Struct', 'Union'].contains(type.element.name),
      );

  static bool _isNative(Element? element) =>
      element?.name == 'Native' && isFfi(element);

  /// Whether [field], or its getter, is in memory that C knows.
  static bool _isExternal(FieldElement field) =>
      field.isExternal || (field.getter?.isExternal ?? false);

  /// How objects of [owner] have [field], if C knows it.
  NativeField? field(InterfaceElement owner, FieldElement field) {
    compound(owner);
    return _fields[owner]?.where((f) => f.element == field).firstOrNull;
  }

  /// What the external variable [element] is in C.
  NativeField? variable(PropertyInducingElement element) =>
      switch (_fieldType(element)) {
        (final type?, final dimensions) => (
          element: element,
          offset: 0,
          type: type,
          dimensions: dimensions,
        ),
        _ => null,
      };

  (NativeType?, List<int>) _fieldType(PropertyInducingElement field) {
    final type = field.type;
    if (type is InterfaceType &&
        isFfi(type.element) &&
        type.element.name == 'Array') {
      final dimensions = _dimensionsOf(field);
      if (dimensions == null) return (null, const []);
      var element = type.typeArguments.single;
      while (element is InterfaceType && element.element.name == 'Array') {
        element = element.typeArguments.single;
      }
      var found = of(element);
      if (found == null) return (null, const []);
      for (final count in dimensions.reversed) {
        found = NativeArray(found!, count);
      }
      return (found, dimensions);
    }
    final own = of(type);
    if (own != null) return (own, const []);
    for (final value in _annotationsOf(field)) {
      final given = switch (value.type) {
        InterfaceType(:final element, :final typeArguments)
            when _isNative(element) =>
          typeArguments.single,
        final type => type,
      };
      final found = given == null ? null : of(given);
      if (found != null) return (found, const []);
    }
    return (null, const []);
  }

  static Iterable<DartObject> _annotationsOf(PropertyInducingElement field) => [
    ...field.metadata.annotations,
    ...?field.getter?.metadata.annotations,
  ].map((annotation) => annotation.computeConstantValue()).nonNulls;

  /// The elements of each dimension of the array [field].
  static List<int>? _dimensionsOf(PropertyInducingElement field) {
    for (final value in _annotationsOf(field)) {
      if (value.type?.element?.name != '_ArraySize') continue;
      final all = value.getField('dimensions')?.toListValue();
      final variable = value.getField('variableDimension')?.toIntValue();
      if (all != null) {
        return [?variable, for (final one in all) one.toIntValue()!];
      }
      return [
        for (var i = 1; i <= 5; i++)
          ?value.getField('dimension$i')?.toIntValue(),
      ];
    }
    return null;
  }

  /// The C function that functions of [type] are, or null if there is none.
  NativeSignature? signature(FunctionType type) {
    final parameters = <NativeType>[];
    int? fixedCount;
    for (final parameter in type.formalParameters) {
      final own = parameter.type;
      final isVariable =
          own is InterfaceType &&
          isFfi(own.element) &&
          own.element.name == 'VarArgs';
      if (isVariable) {
        fixedCount = parameters.length;
        final rest = own.typeArguments.single;
        if (rest is! RecordType) return null;
        for (final field in rest.positionalFields) {
          final found = of(field.type);
          if (found == null) return null;
          parameters.add(found);
        }
        continue;
      }
      final found = of(own);
      if (found == null) return null;
      parameters.add(found);
    }
    final result = of(type.returnType);
    return result == null
        ? null
        : NativeSignature(parameters, result, fixedCount: fixedCount);
  }
}

/// What `@Native` says about [element]: the function of C, and what it is in.
({String symbol, String asset})? nativeAnnotation(Element element) {
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    if (!NativeTypes._isNative(value?.type?.element)) continue;
    final symbol = value!.getField('symbol')?.toStringValue();
    final asset = value.getField('assetId')?.toStringValue();
    return (
      symbol: symbol ?? element.displayName,
      asset: asset ?? '${element.library!.uri}',
    );
  }
  return null;
}

/// The type that `@Native` gives [element].
DartType? nativeTypeOf(Element element) {
  for (final annotation in element.metadata.annotations) {
    final type = annotation.computeConstantValue()?.type;
    if (type is InterfaceType && NativeTypes._isNative(type.element)) {
      return type.typeArguments.single;
    }
  }
  return null;
}
