import 'dart:typed_data';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'classes.dart';
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
  final HirConstObject? Function(ExecutableElement element) _functionObject,

  /// Tells that there are objects of a class.
  final void Function(ClassElement class_) _instantiate,
) {
  final _objects = <String, HirConstObject>{};
  final _numbers = <HirConstObject, int>{};

  /// What [object] is as a value of [type], or null if not supported yet.
  Constant? of(HirType? type, DartObject? object) {
    final value = switch (type) {
      .integer => object?.toIntValue(),
      .float => object?.toDoubleValue(),
      .boolean => object?.toBoolValue(),
      .reference =>
        object == null
            ? null
            : _number(object) ?? _function(object) ?? _object(object),
      null => null,
    };
    if (value != null) return Constant(value);
    final isNull = type == .reference && (object?.isNull ?? false);
    return isNull ? Constant(null) : null;
  }

  /// The value that [parameter] has where a call leaves it out.
  HirInstruction defaultOf(FormalParameterElement parameter) {
    FormalParameterElement found = parameter;
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
    return element == null ? null : _functionObject(element);
  }

  HirConstObject? _number(DartObject object) {
    final value =
        object.toIntValue() ?? object.toDoubleValue() ?? object.toBoolValue();
    return value == null ? null : box(value);
  }

  /// The object that [value], an `int`, `double` or `bool`, is.
  HirConstObject box(Object value) {
    final name = switch (value) {
      int() => 'int',
      double() => 'double',
      _ => 'bool',
    };
    final class_ = _core.getClass(name)!;
    final target = _classes.classOf(class_);
    _instantiate(class_);
    return _canonical(
      class_,
      HirConstObject(target, {target.fields.single: value}),
    );
  }

  HirConstObject? _object(DartObject object) {
    final type = object.type, class_ = classOf(type);
    if (class_ == null || class_.library.isInSdk) return null;
    final target = _classes.classOf(class_);
    final fields = <HirField, Object?>{};
    DartObject? part = object;
    InterfaceType? level = type as InterfaceType;
    while (level != null && !level.isDartCoreObject) {
      for (final field in ClassTable.instanceFields(
        level.element as ClassElement,
      )) {
        final own = _classes.fieldOf(field);
        final value = of(own.type, part?.getField(field.name!));
        if (value == null) return null;
        fields[own] = value.value;
      }
      part = part?.getField('(super)');
      level = level.superclass;
    }
    _instantiate(class_);
    return _canonical(class_, HirConstObject(target, fields));
  }

  /// The object that [found] is the same as.
  HirConstObject _canonical(ClassElement class_, HirConstObject found) {
    final HirConstObject(:target, :fields) = found;
    final key = [
      class_.library.uri,
      target.name,
      for (final field in target.fields) _key(fields[field]),
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
