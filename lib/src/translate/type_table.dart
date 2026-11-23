import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'classes.dart';
import 'constant_table.dart';
import 'members.dart';
import 'scope.dart';

/// The types that a program needs when it runs, as objects of the runtime.
final class TypeTable(
  final ProgramScope _scope,
  final ClassTable _classes,
  final ConstantTable _constants,
) {
  final _numbers = <InterfaceElement, int>{};
  final _parameterNames = <String>[];

  /// The classes that have numbers, in their order.
  List<InterfaceElement> get classes => _numbers.keys.toList();
  List<String> get parameterNames => _parameterNames;

  /// The number of [class_] in types.
  int numberOf(InterfaceElement class_) =>
      _numbers.putIfAbsent(class_, () => _numbers.length);

  int _nameOf(String name) {
    if (!_parameterNames.contains(name)) _parameterNames.add(name);
    return _parameterNames.indexOf(name);
  }

  HirConstObject _object(String name, List<Object?> values) {
    final class_ = _scope.runtimeClass(name);
    final target = _scope.createdClass(class_);
    return _constants.canonical(
      class_,
      HirConstObject(target, {
        for (final (i, field) in target.fields.indexed) field: values[i],
      }),
    );
  }

  /// The object for [type], which is closed or, as part of the supertypes of
  /// [owner], made of its parameters. Null if it is neither.
  HirConstObject? constant(DartType type, {InterfaceElement? owner}) {
    final plain = _constantPlain(type, owner);
    final needsForm =
        type.nullabilitySuffix == .question && !hasBasicForm(type);
    if (plain == null || !needsForm) return plain;
    return _object('NullableType', [plain]);
  }

  /// Whether [type] is one of the basic ones, with or without null.
  static bool hasBasicForm(DartType type) => _basicKind(type) != null;

  static int? _basicKind(DartType type) {
    final isNullable = type.nullabilitySuffix == .question;
    return switch (type) {
      DynamicType() => 0,
      VoidType() => 1,
      InterfaceType(isDartCoreObject: true) => isNullable ? 2 : 3,
      InterfaceType(isDartCoreNull: true) => 4,
      NeverType() => isNullable ? 4 : 5,
      _ => null,
    };
  }

  HirConstObject? _constantPlain(DartType type, InterfaceElement? owner) {
    if (_basicKind(type) case final kind?) return _object('BasicType', [kind]);
    switch (type) {
      case TypeParameterType(:final element) when _bound(element) != null:
        return _object('BoundType', [_bound(element)]);
      case TypeParameterType(:final element):
        if (owner == null || element.enclosingElement != owner) return null;
        return _object('VariableType', [owner.typeParameters.indexOf(element)]);
      case InterfaceType(isDartAsyncFutureOr: true):
        return null;
      case InterfaceType(:final element, :final typeArguments):
        final arguments = list(typeArguments, owner: owner);
        if (arguments == null) return null;
        return _object('InterfaceType', [numberOf(element), arguments.value]);
      case FunctionType():
        return _constantFunction(type, owner);
      default:
        return null;
    }
  }

  HirConstObject? _constantFunction(
    FunctionType type,
    InterfaceElement? owner,
  ) {
    final parameters = type.typeParameters;
    if (parameters.isNotEmpty) {
      return _within(parameters, () {
        final bounds = list(_boundsOf(parameters), owner: owner);
        final inner = _constantPlainFunction(type, owner);
        if (bounds == null || inner == null) return null;
        return _object('GenericType', [bounds.value, inner]);
      });
    }
    return _constantPlainFunction(type, owner);
  }

  /// The type parameters of the function types around, innermost last.
  final _binders = <List<TypeParameterElement>>[];

  T _within<T>(List<TypeParameterElement> parameters, T Function() work) {
    _binders.add(parameters);
    final result = work();
    _binders.removeLast();
    return result;
  }

  /// The number of [element] if it is one of those, the innermost first.
  int? _bound(TypeParameterElement element) {
    var before = 0;
    for (final parameters in _binders.reversed) {
      final index = parameters.indexOf(element);
      if (index >= 0) return before + index;
      before += parameters.length;
    }
    return null;
  }

  List<DartType> _boundsOf(List<TypeParameterElement> parameters) => [
    for (final parameter in parameters)
      parameter.bound ?? _scope.functionClass.library.typeProvider.dynamicType,
  ];

  HirConstObject? _constantPlainFunction(
    FunctionType type,
    InterfaceElement? owner,
  ) {
    final (:required, :optional, :named) = _parameters(type);
    final result = constant(type.returnType, owner: owner);
    final first = list(required, owner: owner);
    final second = list(optional, owner: owner);
    if (result == null || first == null || second == null) return null;
    HirConstObject? names;
    for (final parameter in named.reversed) {
      final own = constant(parameter.type, owner: owner);
      if (own == null) return null;
      names = _object('NamedList', [
        _nameOf(parameter.name!),
        own,
        parameter.isRequiredNamed,
        names,
      ]);
    }
    return _object('FunctionType', [result, first.value, second.value, names]);
  }

  static ({
    List<DartType> required,
    List<DartType> optional,
    List<FormalParameterElement> named,
  })
  _parameters(FunctionType type) {
    final all = type.formalParameters;
    return (
      required: [
        for (final p in all)
          if (p.isRequiredPositional) p.type,
      ],
      optional: [
        for (final p in all)
          if (p.isOptionalPositional) p.type,
      ],
      named: _byName(all),
    );
  }

  /// The list of [types], if all are closed or made of the parameters of
  /// [owner]. An empty list is null.
  Constant? list(List<DartType> types, {InterfaceElement? owner}) {
    HirConstObject? found;
    for (final type in types.reversed) {
      final own = constant(type, owner: owner);
      if (own == null) return null;
      found = _object('TypeList', [own, found]);
    }
    return Constant(found);
  }

  /// The supertypes of [class_], other than `Object`.
  HirConstObject? supertypesOf(InterfaceElement class_) {
    HirConstObject? found;
    for (final type in class_.allSupertypes) {
      if (type.isDartCoreObject) continue;
      final arguments = list(type.typeArguments, owner: class_);
      if (arguments == null) continue;
      found = _object('SuperList', [
        numberOf(type.element),
        arguments.value,
        found,
      ]);
    }
    return found;
  }

  // Types made of the parameters of the function that uses them.

  HirValue _create(
    FunctionBuilder builder,
    String name,
    List<HirValue> values,
  ) {
    final class_ = _scope.createdClass(_scope.runtimeClass(name));
    final object = builder.create(class_);
    for (final (i, field) in class_.fields.indexed) {
      builder.add(HirStore(field, object, values[i]));
    }
    return object;
  }

  HirField _field(String class_, String name) => _classes
      .classOf(_scope.runtimeClass(class_))
      .fields
      .firstWhere((field) => field.name == name);

  /// The object for [type] where [builder] is, or null if it is generic.
  HirValue? value(FunctionBuilder builder, DartType type) {
    if (constant(type) case final found?) return builder.add(HirStatic(found));
    final plain = _plain(builder, type);
    if (plain == null || type.nullabilitySuffix != .question) return plain;
    return builder.call(HirCall(_scope.runtime('nullable'), [plain]));
  }

  HirValue? _plain(FunctionBuilder builder, DartType type) {
    switch (type) {
      case TypeParameterType(:final element) when _bound(element) != null:
        return builder.add(HirStatic(_object('BoundType', [_bound(element)])));
      case TypeParameterType(:final element):
        return _parameter(builder, element);
      case InterfaceType(isDartAsyncFutureOr: true):
        return null;
      case InterfaceType(:final element, :final typeArguments):
        final arguments = listValue(builder, typeArguments);
        if (arguments == null) return null;
        return _create(builder, 'InterfaceType', [
          builder.add(HirConst(numberOf(element))),
          arguments,
        ]);
      case FunctionType(:final typeParameters) when typeParameters.isNotEmpty:
        return _within(typeParameters, () {
          final bounds = listValue(builder, _boundsOf(typeParameters));
          final inner = _function(
            builder,
            type.returnType,
            type.formalParameters,
          );
          if (bounds == null || inner == null) return null;
          return _create(builder, 'GenericType', [bounds, inner]);
        });
      case FunctionType():
        return _function(builder, type.returnType, type.formalParameters);
      default:
        return null;
    }
  }

  HirValue? _function(
    FunctionBuilder builder,
    DartType returnType,
    List<FormalParameterElement> parameters, {

    /// The type of a parameter.
    DartType Function(FormalParameterElement parameter)? typeOf,
  }) {
    DartType own(FormalParameterElement p) => typeOf?.call(p) ?? p.type;
    final result = value(builder, returnType);
    final required = listValue(builder, [
      for (final p in parameters)
        if (p.isRequiredPositional) own(p),
    ]);
    final optional = listValue(builder, [
      for (final p in parameters)
        if (p.isOptionalPositional) own(p),
    ]);
    if (result == null || required == null || optional == null) return null;
    HirValue names = builder.add(HirNull());
    for (final parameter in _byName(parameters).reversed) {
      final type = value(builder, own(parameter));
      if (type == null) return null;
      names = _create(builder, 'NamedList', [
        builder.add(HirConst(_nameOf(parameter.name!))),
        type,
        builder.add(HirConst(parameter.isRequiredNamed)),
        names,
      ]);
    }
    return _create(builder, 'FunctionType', [
      result,
      required,
      optional,
      names,
    ]);
  }

  static List<FormalParameterElement> _byName(
    List<FormalParameterElement> parameters,
  ) =>
      parameters.where((p) => p.isNamed).toList()
        ..sort((a, b) => a.name!.compareTo(b.name!));

  /// The type of the method [element] of an object as a function, which takes
  /// anything where it checks what it is given.
  HirValue? methodType(FunctionBuilder builder, ExecutableElement element) {
    final any = builder.library.typeProvider.objectQuestionType;
    final parameters = element.typeParameters;
    if (parameters.isNotEmpty) {
      return _within(parameters, () {
        final bounds = listValue(builder, _boundsOf(parameters));
        final inner = _method(builder, element, any);
        if (bounds == null || inner == null) return null;
        return _create(builder, 'GenericType', [bounds, inner]);
      });
    }
    return _method(builder, element, any);
  }

  HirValue? _method(
    FunctionBuilder builder,
    ExecutableElement element,
    DartType any,
  ) {
    return _function(
      builder,
      element.returnType,
      element.formalParameters,
      typeOf: (parameter) => isUnchecked(parameter) ? any : parameter.type,
    );
  }

  HirValue? _parameter(FunctionBuilder builder, TypeParameterElement element) {
    final owner = element.enclosingElement;
    final parameters = switch (owner) {
      TypeParameterizedElement(:final typeParameters) => typeParameters,
      _ => const <TypeParameterElement>[],
    };
    var list = builder.typesOf(owner);
    final receiver = builder.receiver;
    final level = builder.level;
    if (list == null && receiver != null && level != null) {
      if (level.isMixin && owner == level.element) {
        // Known where it is mixed in.
        final index = parameters.indexOf(element);
        return value(builder, level.type.typeArguments[index]);
      }
      if (owner == level.class_) {
        final field = _classes.argumentsOf(_classes.levels.of(level.class_));
        list = field == null ? null : builder.add(HirLoad(field, receiver));
      }
    }
    if (list == null) return null;
    for (var i = parameters.indexOf(element); i > 0; i--) {
      list = builder.add(HirLoad(_field('TypeList', 'tail'), list!));
    }
    return builder.add(HirLoad(_field('TypeList', 'head'), list!));
  }

  /// The list of [types], or null if one of them is generic.
  HirValue? listValue(FunctionBuilder builder, List<DartType> types) {
    if (list(types) case final found?) return builder.add(found.instruction);
    HirValue result = builder.add(HirNull());
    for (final type in types.reversed) {
      final own = value(builder, type);
      if (own == null) return null;
      result = _create(builder, 'TypeList', [own, result]);
    }
    return result;
  }
}
