import 'dart:typed_data';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
// Only this tells the type arguments of functions.
// ignore: implementation_imports
import 'package:analyzer/src/dart/constant/value.dart'
    show DartObjectImpl, FunctionState;
import 'package:dartc/hir.dart';

import 'classes.dart';
import 'members.dart';
import 'text_hash.dart';
import 'types.dart';

/// A value known when compiling: an `int`, `double`, `bool`, object or null.
final class Constant(final Object? value) {
  HirInstruction get instruction => switch (value) {
    null => HirNull(),
    final HirConstObject object => HirStatic(object),
    final value => HirConst(value),
  };
}

/// The program's constants, where equal objects are the same one.
final class ConstantTable(
  final Declarations _declarations,
  final ClassTable _classes,
  final LibraryElement _core,
  final ClassElement Function(HirType type) _boxElement,

  /// A library of the SDK.
  final LibraryElement Function(String uri) _library,

  /// The object that a function is as one of a type, given its type arguments
  /// if they are known.
  final HirConstObject? Function(
    ExecutableElement element,
    DartType type,
    List<DartType>? types,
  )
  _functionObject,

  /// The object for a list of types.
  final Constant? Function(List<DartType> types) _listOf,

  /// The object that a type is.
  final HirConstObject? Function(DartType type) _typeObject,

  /// Tells that there are objects of a class.
  final void Function(InterfaceElement class_) _instantiate,
) {
  final _objects = <String, HirConstObject>{};
  final _numbers = <HirConstObject, int>{};

  /// What [object] is as a value of [type], or null if not supported yet.
  Constant? of(HirType? type, DartObject? object) {
    if (type == .reference && (object?.isNull ?? false)) return Constant(null);
    final value = switch (type) {
      .integer => object?.toIntValue(),
      .float => object?.toDoubleValue(),
      .boolean => object?.toBoolValue(),
      .reference =>
        object == null
            ? null
            : _number(object) ??
                  _text(object) ??
                  _type(object) ??
                  _symbol(object) ??
                  _function(object) ??
                  _list(object) ??
                  _map(object) ??
                  _set(object) ??
                  _record(object) ??
                  _object(object),
      null => null,
    };
    return value == null ? null : Constant(value);
  }

  /// The value that [parameter] has where a call leaves it out.
  HirInstruction defaultOf(FormalParameterElement parameter) {
    FormalParameterElement found = parameter;
    for (
      var next = redirectedParameter(found);
      next != null;
      next = redirectedParameter(next)
    ) {
      found = next;
    }
    while (!found.hasDefaultValue && found is SuperFormalParameterElement) {
      final inherited = found.superConstructorParameter;
      if (inherited == null) break;
      found = inherited;
    }
    final type = valueType(parameter.type);
    final value = found.hasDefaultValue
        ? of(type, found.computeConstantValue())
        : Constant(null);
    if (value != null && (value.value != null || type == .reference)) {
      return value.instruction;
    }
    throw _declarations.unsupported(
      found.enclosingElement!,
      'a default of type ${found.type}',
    );
  }

  HirConstObject? _function(DartObject object) {
    final element = object.toFunctionValue();
    if (element == null) return null;
    final state = (object as DartObjectImpl).state as FunctionState;
    // For constructors they can be those of an alias.
    final types = element is ConstructorElement ? null : state.typeArguments;
    return _functionObject(element.baseElement, object.type, types);
  }

  HirConstObject? _text(DartObject object) {
    final value = object.toStringValue();
    return value == null ? null : text(value);
  }

  HirConstObject? _record(DartObject object) {
    final record = object.toRecordValue();
    if (record == null) return null;
    final fieldNames = record.named.keys.toList()..sort();
    final elements = [
      for (final field in record.positional) of(.reference, field),
      for (final name in fieldNames) of(.reference, record.named[name]),
    ];
    if (elements.contains(null)) return null;
    final class_ = _core.getClass('_Record')!;
    final target = _classes.classOf(class_);
    _instantiate(class_);
    return canonical(
      class_,
      HirConstObject(
        target,
        {target.fields.single: names(fieldNames)},
        [for (final element in elements) _boxed(element!.value)],
      ),
    );
  }

  /// The list of [names], of which equal ones are the same.
  HirConstObject names(List<String> names) {
    final class_ = _core.getClass('_List')!;
    final target = _classes.classOf(class_);
    _instantiate(class_);
    final types = _listOf([_core.typeProvider.stringType])!;
    return canonical(
      class_,
      HirConstObject(
        target,
        {target.fields.single: types.value},
        [for (final name in names) text(name)],
      ),
    );
  }

  /// The string [value].
  HirConstObject text(String value) {
    final units = value.codeUnits;
    final isNarrow = units.every((unit) => unit < 256);
    final class_ = _core.getClass(
      isNarrow ? '_OneByteString' : '_TwoByteString',
    )!;
    final target = _classes.classOf(class_);
    _instantiate(class_);
    return canonical(
      class_,
      HirConstObject(
        target,
        {target.fields.single: hashOfText(units)},
        isNarrow
            ? units
            : [
                for (final unit in units) ...[unit & 255, unit >> 8],
              ],
      ),
    );
  }

  HirConstObject? _symbol(DartObject object) {
    final name = object.toSymbolValue();
    if (name == null) return null;
    final class_ = _library('dart:_internal').getClass('Symbol')!;
    final target = _classes.classOf(class_);
    _instantiate(class_);
    return canonical(
      class_,
      HirConstObject(target, {target.fields.single: text(name)}),
    );
  }

  HirConstObject? _type(DartObject object) {
    final type = object.toTypeValue();
    return type == null ? null : _typeObject(type);
  }

  HirConstObject? _list(DartObject object) {
    final values = object.toListValue();
    if (values == null) return null;
    final class_ = _core.getClass('_ImmutableList')!;
    final target = _classes.classOf(class_);
    final types = _listOf((object.type as InterfaceType).typeArguments);
    final elements = [for (final value in values) of(.reference, value)];
    if (types == null || elements.contains(null)) return null;
    _instantiate(class_);
    return canonical(
      class_,
      HirConstObject(
        target,
        {target.fields.single: types.value},
        [for (final element in elements) _boxed(element!.value)],
      ),
    );
  }

  HirConstObject? _map(DartObject object) {
    final values = object.toMapValue();
    return values == null
        ? null
        : _hashed(object, '_ConstMap', [
            for (final MapEntry(:key, :value) in values.entries) ...[
              key,
              value,
            ],
          ]);
  }

  HirConstObject? _set(DartObject object) {
    final values = object.toSetValue();
    return values == null
        ? null
        : _hashed(object, '_ConstSet', values.toList());
  }

  /// A map or set of `dart:_compact_hash` that holds [values].
  HirConstObject? _hashed(
    DartObject object,
    String name,
    List<DartObject?> values,
  ) {
    final class_ = _library('dart:_compact_hash').getClass(name)!;
    final type = object.type as InterfaceType;
    final types = _listOf(type.typeArguments);
    final elements = [for (final value in values) of(.reference, value)];
    if (types == null || elements.contains(null)) return null;
    final target = _classes.classOf(class_);
    _instantiate(class_);
    final dataClass = _core.getClass('_List')!;
    final dataTarget = _classes.classOf(dataClass);
    _instantiate(dataClass);
    final dataTypes = _listOf([class_.library.typeProvider.dynamicType])!;
    final data = canonical(
      dataClass,
      HirConstObject(
        dataTarget,
        {dataTarget.fields.single: dataTypes.value},
        [for (final element in elements) _boxed(element!.value)],
      ),
    );
    // As the maps do it when they make their index.
    final least = (object.toMapValue() != null ? 1 : 2) * values.length;
    final size = least <= 8 ? 8 : 1 << (least - 1).bitLength;
    return canonical(
      class_,
      HirConstObject(target, {
        for (final field in target.fields)
          field: switch (field.name) {
            '_data' => data,
            '_usedData' => values.length,
            '_hashMask' => (1 << (32 - (size.bitLength - 2))) - 1,
            '_deletedKeys' => 0,
            '_place' => _places['$name ${_key(data)}'] ??= _places.length,
            '_ownIndex' => null,
            _ => types.value,
          },
      }),
    );
  }

  final _places = <String, int>{};

  Object? _boxed(Object? value) =>
      value is int || value is double || value is bool ? box(value!) : value;

  HirConstObject? _number(DartObject object) {
    final value =
        object.toIntValue() ?? object.toDoubleValue() ?? object.toBoolValue();
    return value == null ? null : box(value);
  }

  /// The object that [value], an `int`, `double` or `bool`, is.
  HirConstObject box(Object value) {
    final class_ = _boxElement(switch (value) {
      int() => .integer,
      double() => .float,
      _ => .boolean,
    });
    final target = _classes.classOf(class_);
    _instantiate(class_);
    return canonical(
      class_,
      HirConstObject(target, {target.fields.single: value}),
    );
  }

  HirConstObject? _object(DartObject object) {
    final type = object.type, class_ = classOf(type);
    if (class_ == null || _declarations[class_] == null) return null;
    // The analyzer does not know every value.
    if (plainType(class_) != null) return null;
    final target = _classes.classOf(class_);
    final fields = <HirField, Object?>{};
    DartObject? part = object;
    var own = type as InterfaceType;
    for (final level in _classes.levels.of(class_).chain) {
      final element = level.element;
      if (class_ is EnumElement && element.name == '_Enum') {
        // The analyzer does not know that enums extend it.
        for (final field in ClassTable.instanceFields(element)) {
          final place = _classes.fieldOf(level, field).value;
          fields[place] = of(place.type, object.getField(field.name!))!.value;
        }
        break;
      }
      if (element is ClassElement && element.isDartCoreObject) break;
      final actual = level.isMixin
          ? own.mixins.firstWhere((mixin) => mixin.element == element)
          : level.class_ == own.element
          ? own
          : own = own.superclass!;
      if (_classes.argumentsOf(level) case final list?) {
        final types = _listOf(actual.typeArguments);
        if (types == null) return null;
        fields[list] = types.value;
      }
      for (final field in ClassTable.instanceFields(element)) {
        // Mixins cannot declare fields for constants.
        if (level.isMixin) return null;
        // The analyzer puts the name of an enum's constant in its place.
        if (class_ is EnumElement && field.name == '_name') return null;
        final place = _classes.fieldOf(level, field).value;
        final value = of(place.type, part?.getField(field.name!));
        if (value == null) return null;
        fields[place] = value.value;
      }
      if (!level.isMixin) part = part?.getField('(super)');
    }
    _instantiate(class_);
    return canonical(class_, HirConstObject(target, fields));
  }

  /// The object that [found] is the same as.
  HirConstObject canonical(InterfaceElement class_, HirConstObject found) {
    final HirConstObject(:target, :fields, :elements) = found;
    final key = [
      class_.library.uri,
      target.name,
      class_.typeParameters.length,
      for (final field in target.fields) _key(fields[field]),
      for (final element in elements ?? const []) _key(element),
    ].join(' ');
    return _objects.putIfAbsent(key, () {
      _numbers[found] = _numbers.length;
      return found;
    });
  }

  /// Tells different values of one type apart.
  String _key(Object? value) => switch (value) {
    HirConstObject() => '${_numbers[value] ??= _numbers.length}',
    double() => '${(ByteData(8)..setFloat64(0, value)).getInt64(0)}',
    _ => '$value',
  };
}
