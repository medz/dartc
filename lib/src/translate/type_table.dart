import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'classes.dart';
import 'constant_table.dart';
import 'members.dart';
import 'records.dart';
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

  /// The object for [declared], which is closed or, as part of the supertypes of
  /// [owner], made of its parameters. Null if it is neither.
  HirConstObject? constant(DartType declared, {InterfaceElement? owner}) {
    final type = declared.extensionTypeErasure;
    final plain = _constantPlain(type, owner);
    if (plain == null || type.nullabilitySuffix != .question) return plain;
    return hasBasicForm(type) ? plain : _nullable(plain);
  }

  /// [type] or null, like the runtime makes it.
  HirConstObject _nullable(HirConstObject type) {
    if (type.target.name == 'NullableType') return type;
    if (type.target.name != 'BasicType') return _object('NullableType', [type]);
    return switch (type.fields.values.single) {
      3 => _object('BasicType', [2]),
      5 => _object('BasicType', [4]),
      _ => type,
    };
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
      case InterfaceType(isDartAsyncFutureOr: true, :final typeArguments):
        return _constantFutureOr(typeArguments.single, owner);
      case InterfaceType(:final element, :final typeArguments):
        final arguments = list(typeArguments, owner: owner);
        if (arguments == null) return null;
        return _object('InterfaceType', [numberOf(element), arguments.value]);
      case FunctionType():
        return _constantFunction(type, owner, type.formalParameters);
      case RecordType():
        final fields = list(fieldTypes(type), owner: owner);
        if (fields == null) return null;
        final names = _constants.names(fieldNames(type));
        return _object('RecordType', [fields.value, names]);
      default:
        return null;
    }
  }

  /// The object for `FutureOr` of [inner], like the runtime makes it.
  HirConstObject? _constantFutureOr(DartType inner, InterfaceElement? owner) {
    final own = constant(inner, owner: owner);
    if (own == null) return null;
    final kind = own.target.name == 'BasicType'
        ? own.fields.values.single
        : null;
    if (kind is int && kind <= 3) return own;
    if (kind == null) return _object('FutureOrType', [own]);
    final future = _scope.futureClass;
    final plain = _object('InterfaceType', [
      numberOf(future),
      _object('TypeList', [own, null]),
    ]);
    return kind == 4 ? _nullable(plain) : plain;
  }

  HirConstObject? _constantFunction(
    FunctionType type,
    InterfaceElement? owner,
    List<FormalParameterElement> parameters,
  ) {
    final binders = type.typeParameters;
    if (binders.isNotEmpty) {
      return _within(binders, () {
        final bounds = list(_boundsOf(binders), owner: owner);
        final inner = _constantPlainFunction(type, owner, parameters);
        if (bounds == null || inner == null) return null;
        return _object('GenericType', [bounds.value, inner]);
      });
    }
    return _constantPlainFunction(type, owner, parameters);
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
    List<FormalParameterElement> parameters,
  ) {
    final result = constant(type.returnType, owner: owner);
    final first = list([
      for (final p in parameters)
        if (p.isRequiredPositional) p.type,
    ], owner: owner);
    final second = list([
      for (final p in parameters)
        if (p.isOptionalPositional) p.type,
    ], owner: owner);
    if (result == null || first == null || second == null) return null;
    HirConstObject? names;
    for (final parameter in parameters.reversed.where((p) => p.isNamed)) {
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

  /// The object for [declared] where [builder] is, or null if it is generic.
  HirValue? value(FunctionBuilder builder, DartType declared) {
    final type = declared.extensionTypeErasure;
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
      case InterfaceType(isDartAsyncFutureOr: true, :final typeArguments):
        final inner = value(builder, typeArguments.single);
        if (inner == null) return null;
        return builder.call(HirCall(_scope.runtime('futureOr'), [inner]));
      case InterfaceType(:final element, :final typeArguments):
        final arguments = listValue(builder, typeArguments);
        if (arguments == null) return null;
        return _create(builder, 'InterfaceType', [
          builder.add(HirConst(numberOf(element))),
          arguments,
        ]);
      case FunctionType():
        return _functionValue(builder, type, type.formalParameters);
      case RecordType():
        final fields = listValue(builder, fieldTypes(type));
        if (fields == null) return null;
        final names = builder.add(_scope.names(fieldNames(type)));
        return _create(builder, 'RecordType', [fields, names]);
      default:
        return null;
    }
  }

  HirValue? _functionValue(
    FunctionBuilder builder,
    FunctionType type,
    List<FormalParameterElement> parameters, {
    bool instanceMethod = false,
  }) {
    HirValue? inner() => _function(builder, type, parameters, instanceMethod);
    final binders = type.typeParameters;
    if (binders.isEmpty) return inner();
    return _within(binders, () {
      final bounds = listValue(builder, _boundsOf(binders));
      final function = inner();
      if (bounds == null || function == null) return null;
      return _create(builder, 'GenericType', [bounds, function]);
    });
  }

  HirValue? _function(
    FunctionBuilder builder,
    FunctionType type,
    List<FormalParameterElement> parameters,
    bool instanceMethod,
  ) {
    DartType own(FormalParameterElement p) => instanceMethod && isUnchecked(p)
        ? builder.library.typeProvider.objectQuestionType
        : p.type;
    final result = value(builder, type.returnType);
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
    for (final parameter in parameters.reversed.where((p) => p.isNamed)) {
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

  /// A tear-off keeps its declaration's parameter order.
  HirValue? tearOffType(
    FunctionBuilder builder,
    ExecutableElement element, {
    FunctionType? asType,
    bool instanceMethod = false,
  }) {
    final type = asType ?? element.type;
    final declared = element.formalParameters;
    var parameters = declared;
    if (!identical(type, element.type)) {
      // Instantiation can change the types and puts names in alphabetical order.
      final typed = type.formalParameters;
      final byName = {
        for (final p in typed)
          if (p.isNamed) p.name: p,
      };
      parameters = [
        for (final (i, p) in declared.indexed)
          p.isNamed ? byName[p.name]! : typed[i],
      ];
    }
    if (!instanceMethod) {
      final constant = _constantFunction(type, null, parameters);
      if (constant != null) return builder.add(HirStatic(constant));
    }
    return _functionValue(
      builder,
      type,
      parameters,
      instanceMethod: instanceMethod,
    );
  }

  HirValue? _parameter(FunctionBuilder builder, TypeParameterElement element) {
    if (builder.typePlaces[element] case (final list, final index)?) {
      return _elementOf(builder, list, index);
    }
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
    return list == null
        ? null
        : _elementOf(builder, list, parameters.indexOf(element));
  }

  HirValue _elementOf(FunctionBuilder builder, HirValue list, int index) {
    var rest = list;
    for (var i = 0; i < index; i++) {
      rest = builder.add(HirLoad(_field('TypeList', 'tail'), rest));
    }
    return builder.add(HirLoad(_field('TypeList', 'head'), rest));
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
