import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'arrays.dart';
import 'builder.dart';
import 'constant_table.dart';
import 'scope.dart';
import 'type_table.dart';

/// Types, lists and records as values, with the classes of the runtime that
/// they need.
final class TypeValues(
  final ProgramScope _scope,
  final TypeTable _types,
  final ConstantTable _constants,
  final LibraryElement _core,
) {
  HirValue record(
    FunctionBuilder builder,
    List<String> names,
    List<HirValue> values,
  ) => newArray(
    builder,
    _scope.createdClass(_scope.recordClass),
    builder.add(this.names(names)),
    values,
  );

  HirInstruction names(List<String> names) {
    _scope.createdClass(_scope.recordClass);
    return HirStatic(_constants.strings(names));
  }

  /// The objects of the types that no class but their own is of, which
  /// type arguments often are, and the tests for these classes.
  Map<HirConstObject, HirTypeTest> sealedTypes() {
    _prepare();
    return {
      for (final name in const ['int', 'String', 'double', 'bool'])
        if (_core.getClass(name) case final class_?)
          _types.constant(class_.thisType)!: _scope.testOf(class_),
    };
  }

  HirValue? value(FunctionBuilder builder, DartType type) {
    _prepare();
    return _types.value(builder, type);
  }

  HirConstObject? object(DartType type) {
    _prepare();
    final own = _types.constant(type);
    if (own == null) return null;
    final class_ = _core.getClass('_Type')!;
    final target = _scope.createdClass(class_);
    return _constants.canonical(
      class_,
      HirConstObject(target, {target.fields.single: own}),
    );
  }

  HirValue? tearOffType(
    FunctionBuilder builder,
    ExecutableElement element, {
    FunctionType? asType,
    bool instanceMethod = false,
    Set<FormalParameterElement> unchecked = const {},
  }) {
    _prepare();
    return _types.tearOffType(
      builder,
      element,
      asType: asType,
      instanceMethod: instanceMethod,
      unchecked: unchecked,
    );
  }

  HirValue? typeList(FunctionBuilder builder, List<DartType> types) {
    _prepare();
    return _types.listValue(builder, types);
  }

  HirValue list(FunctionBuilder builder, DartType type, List<HirValue> values) {
    final types = typeList(builder, [type])!;
    final class_ = _scope.createdClass(_core.getClass('_List')!);
    return newArray(builder, class_, types, values);
  }

  /// Makes the classes that describe types part of the program.
  void _prepare() {
    for (final name in const ['BasicType', 'SuperList', 'VariableType']) {
      _scope.createdClass(_scope.runtimeClass(name));
    }
  }
}
