import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'chains.dart';
import 'closures.dart';
import 'conversions.dart';
import 'creators.dart';
import 'describe.dart';
import 'dynamics.dart';
import 'members.dart';
import 'operations.dart';
import 'scope.dart';
import 'types.dart';

/// Translates calls, the creation of objects and reading properties.
final class CallTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final ClosureTranslator _closures,
  final ChainTranslator _chains,
) {
  late final _conversions = Conversions(_scope, _builder);
  late final _operations = OperationTranslator(_scope, _builder, _evaluator);
  late final _dynamics = DynamicTranslator(_scope, _builder, _evaluator);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// The result of [node], if it has one.
  HirValue? invocation(MethodInvocation node) {
    final element = node.methodName.element, target = node.realTarget;
    if (target != null && target.staticType is DynamicType) {
      return _dynamicCall(node, target);
    }
    if (target?.staticType is FunctionType) {
      return _callFunction(node, target!);
    }
    if (target != null &&
        (target.staticType?.isDartCoreFunction ?? false) &&
        node.methodName.name == 'call') {
      return _dynamicCall(node, target);
    }
    if (element is! ExecutableElement) _unsupported(node, describe(node));
    if (_builder.typeOf(element.baseElement) != null) {
      return _local(node, element.baseElement);
    }
    if (!isInstanceMember(element)) return _static(node, element);
    if (element is! MethodElement) _unsupported(node, describe(node));
    if (target is SuperExpression) {
      final (positional, named) = _given(node.argumentList);
      return superMember(
        node,
        element,
        positional,
        named: named,
        types: _typeList(node, node.typeArgumentTypes),
      );
    }
    final receiver = target == null ? _this(node) : object(node, target);
    return _checked(
      node,
      element,
      method(
        node,
        receiver,
        _receiverClass(node, target),
        element,
        node.argumentList,
        types: node.typeArgumentTypes,
      ),
    );
  }

  /// [result] of [element], checked if it can be of another type than [node],
  /// as functions taking type arguments of their object can.
  HirValue? _checked(
    Expression node,
    ExecutableElement element,
    HirValue? result,
  ) {
    final base = element.baseElement;
    if (result == null ||
        !mentions(base.returnType, base.enclosingElement, isTaken: true)) {
      return result;
    }
    return _conversions.cast(
          result,
          _conversions.types.objectQuestionType,
          element.returnType,
        ) ??
        _unsupported(node, 'testing for ${element.returnType}');
  }

  HirValue? _local(MethodInvocation node, ExecutableElement element) {
    final self = _builder.read(element);
    final arguments = ordered(element, supplied(node.argumentList));
    final types = _typeList(node, node.typeArgumentTypes);
    return _direct(_builder.locals.functions[element]!, element, [
      self,
      ?types,
      ...arguments,
    ]);
  }

  /// The list of [types], if there are any.
  HirValue? _typeList(AstNode node, List<DartType>? types) {
    if (types == null || types.isEmpty) return null;
    return _scope.typeList(_builder, types) ??
        _unsupported(node, 'these type arguments');
  }

  HirValue? _dynamicCall(MethodInvocation node, Expression target) {
    final object = _evaluator.value(target);
    _chains.check(node, object);
    return _dynamics.call(
      node,
      object,
      node.methodName.name,
      node.argumentList,
      types: node.typeArguments,
    );
  }

  HirValue? _callFunction(MethodInvocation node, Expression target) {
    if (node.methodName.name != 'call') {
      final name = node.methodName.name;
      _unsupported(node, 'calling $name of the SDK');
    }
    final function = _evaluator.value(target);
    _chains.check(node, function);
    return _closures.call(
      node,
      function,
      node.argumentList,
      node.typeArgumentTypes,
    );
  }

  HirValue _this(AstNode node) =>
      _builder.receiver ?? _unsupported(node, 'this here');

  /// The object that [target] is, of which [node] uses a member.
  HirValue object(Expression node, Expression target) {
    if (classFor(target.staticType) == null) {
      _unsupported(node, describe(node));
    }
    final result = _evaluator.value(target);
    _chains.check(node, result);
    return result;
  }

  /// The class whose members values of [type] have.
  InterfaceElement? classFor(DartType? type) =>
      switch (type == null ? null : boundOf(type)) {
        FunctionType() => _scope.functionClass,
        DynamicType() || VoidType() => _conversions.types.objectElement,
        _ => classOf(type),
      };

  InterfaceElement _receiverClass(AstNode node, Expression? target) =>
      (target == null ? _builder.receiverClass : classFor(target.staticType)) ??
      _unsupported(node, describe(node));

  HirValue? _static(MethodInvocation node, ExecutableElement element) {
    final isFunction =
        element is TopLevelFunctionElement || element is MethodElement;
    if (!isFunction) _unsupported(node, describe(node));
    final arguments = node.argumentList.arguments;
    switch (_coreName(element)) {
      case 'dart:io exit':
        final code = arguments.single.argumentExpression;
        final type = _conversions.types.intType;
        _builder.end(HirExit(_evaluator.valueTo(code, type)));
        return null;
    }
    if (_scope.operationOf(element) case final name?) {
      return _operations.call(node, name);
    }
    final function = _scope.functionOf(element.baseElement);
    if (function == null) {
      _unsupported(node, 'calling ${element.displayName} of the SDK');
    }
    final given = ordered(element.baseElement, supplied(node.argumentList));
    return _direct(function, element, [
      ?_typeList(node, node.typeArgumentTypes),
      ...given,
    ]);
  }

  static String? _coreName(ExecutableElement element) =>
      element is TopLevelFunctionElement && element.library.isInSdk
      ? '${element.library.uri} ${element.name}'
      : null;

  HirValue? _direct(
    HirFunction function,
    ExecutableElement element,
    List<HirValue> arguments,
  ) {
    final result = _builder.call(
      HirCall(function, [
        for (final (i, argument) in arguments.indexed)
          _conversions.coerce(argument, function.parameters[i]),
      ]),
    );
    if (isNever(element.returnType)) _builder.end(HirUnreachable());
    return result;
  }

  /// Creates an object, or calls a factory.
  HirValue creation(InstanceCreationExpression node) {
    final element = node.constructorName.element;
    final class_ = classOf(node.staticType);
    if (element == null || class_ is! ClassElement) {
      _unsupported(node, 'objects of type ${node.staticType}');
    }
    if (node.isConst) {
      final value = node.computeConstantValue()?.value;
      return _builder.add(
        _scope.constantOf(.reference, value) ??
            _unsupported(node, 'a constant of type ${node.staticType}'),
      );
    }
    var target = element, given = supplied(node.argumentList);
    for (
      var next = redirectionOf(target);
      next != null;
      next = redirectionOf(target)
    ) {
      given = redirected(given);
      target = next;
    }
    return _create(node, target, given);
  }

  /// Creates an object with [element], giving [supplied] to its parameters.
  HirValue _create(
    Expression node,
    ConstructorElement element,
    Map<FormalParameterElement, HirValue> supplied,
  ) {
    final class_ = element.enclosingElement as ClassElement;
    if (!_scope.declares(class_)) {
      _unsupported(node, 'calling ${class_.displayName} of the SDK');
    }
    final base = element.baseElement;
    final types = element.returnType.typeArguments;
    if (element.isFactory) {
      final arguments = ordered(base, supplied);
      return _direct(_scope.factoryOf(base), element, [
        ?_typeList(node, types),
        ...arguments,
      ])!;
    }
    final created = _scope.createdClass(class_);
    final arguments = ordered(base, supplied);
    final list = _typeList(node, types);
    final object = _builder.create(created);
    _direct(_scope.initializerOf(base), element, [object, ?list, ...arguments]);
    return object;
  }

  /// The arguments of a call, evaluated in source order, by parameter.
  Map<FormalParameterElement, HirValue> supplied(ArgumentList list) {
    final values = <FormalParameterElement, HirValue>{};
    for (final argument in list.arguments) {
      final parameter = argument.correspondingParameter!;
      if (valueType(parameter.type) == null) {
        _unsupported(
          argument.argumentExpression,
          'a parameter of type ${parameter.type}',
        );
      }
      values[parameter.baseElement] = _evaluator.valueTo(
        argument.argumentExpression,
        parameter.type,
      );
    }
    return values;
  }

  /// Arguments in the order of [element]'s parameters, with its defaults.
  List<HirValue> ordered(
    ExecutableElement element,
    Map<FormalParameterElement, HirValue> supplied,
  ) => [
    for (final parameter in element.formalParameters)
      supplied[parameter] ?? _builder.add(_scope.defaultOf(parameter)),
  ];

  /// The positional and named arguments of a call.
  (List<HirValue>, Map<String, HirValue>) _given(ArgumentList list) {
    final given = supplied(list);
    return (
      [
        for (final MapEntry(:key, :value) in given.entries)
          if (key.isPositional) value,
      ],
      {
        for (final MapEntry(:key, :value) in given.entries)
          if (key.isNamed) key.name!: value,
      },
    );
  }

  /// Calls the method [element] on [receiver].
  HirValue? method(
    AstNode node,
    HirValue receiver,
    InterfaceElement class_,
    MethodElement element,
    ArgumentList list, {
    List<DartType>? types,
  }) {
    final (positional, named) = _given(list);
    final typeList = _typeList(node, types);
    return invoke(node, receiver, class_, element, positional, named, typeList);
  }

  /// Calls the instance member [element] on [receiver].
  HirValue? invoke(
    AstNode node,
    HirValue receiver,
    InterfaceElement class_,
    ExecutableElement element, [
    List<HirValue> positional = const [],
    Map<String, HirValue> named = const {},
    HirValue? types,
    bool isSome = false,
  ]) {
    _checkMember(node, element);
    final names = named.keys.toList()..sort();
    final arguments = [
      ?types,
      ...positional,
      for (final name in names) named[name]!,
    ];
    final base = element.baseElement;
    Never reject(String what) => _unsupported(node, what);
    if (receiver.type != .reference) {
      final level = _scope.levelOf(_scope.boxElement(receiver.type!));
      final function = _scope.functionAt(
        level,
        base,
        positional.length,
        names,
        reject,
        isUnboxed: true,
      );
      if (function == null) reject(describe(node));
      return _direct(function, element, [receiver, ...arguments]);
    }
    final selector = _scope.selectorOf(
      base,
      class_,
      positional.length,
      names,
      reject,
    );
    HirValue? call() => _builder.call(
      HirVirtualCall(selector, receiver, [
        for (final (i, value) in arguments.indexed)
          _conversions.coerce(value, selector.parameters[i]),
      ]),
    );
    final owner = base.enclosingElement;
    final mayBeNull =
        !isSome &&
        owner is ClassElement &&
        owner.isDartCoreObject &&
        receiver != _builder.receiver;
    if (mayBeNull && selector.result != null) {
      return _orNull(node, receiver, base, selector, arguments, call);
    }
    final result = call();
    if (isNever(element.returnType)) _builder.end(HirUnreachable());
    return result;
  }

  /// What [call] gives, or what null does for [member] if [receiver] is null.
  HirValue _orNull(
    AstNode node,
    HirValue receiver,
    ExecutableElement member,
    HirSelector selector,
    List<HirValue> arguments,
    HirValue? Function() call,
  ) {
    final type = selector.result!;
    final null_ = _conversions.types.nullType.element as ClassElement;
    final function = _scope.functionAt(
      _scope.levelOf(null_),
      member,
      arguments.length,
      const [],
      (what) => _unsupported(node, what),
    );
    return _builder.choose(
      _conversions.isNull(receiver),
      type,
      () => _conversions.coerce(
        _direct(function!, member, [receiver, ...arguments])!,
        type,
      ),
      () => call()!,
    );
  }

  void _checkMember(AstNode node, ExecutableElement element) {
    final owner = element.enclosingElement;
    if (owner is! InterfaceElement) _unsupported(node, 'extensions');
    if (!_scope.declares(owner)) {
      _unsupported(node, 'calling ${element.displayName} of the SDK');
    }
  }

  /// Uses the superclass's member [given] on `this`, giving it [values].
  HirValue? superMember(
    AstNode node,
    ExecutableElement given,
    List<HirValue> values, {
    Map<String, HirValue> named = const {},
    HirValue? types,
  }) {
    final element = given.baseElement;
    _checkMember(node, element);
    final names = named.keys.toList()..sort();
    final function = _scope.functionAt(
      _builder.level!.superLevel!,
      element,
      values.length,
      names,
      (what) => _unsupported(node, what),
    );
    if (function == null) _unsupported(node, 'this use of super');
    return _direct(function, element, [
      _this(node),
      ?types,
      ...values,
      for (final name in names) named[name]!,
    ]);
  }

  /// Gives the method [element] of [receiver].
  HirValue tearOff(
    AstNode node,
    HirValue receiver,
    InterfaceElement class_,
    MethodElement element,
  ) {
    _checkMember(node, element);

    return _builder.call(
      HirVirtualCall(
        _scope.tearOffSelector(element.baseElement, class_),
        _conversions.coerce(receiver, .reference),
        const [],
      ),
    )!;
  }

  HirValue _methodOf(Expression node, Expression? target, MethodElement found) {
    final method = found.baseElement;
    if (target is SuperExpression) {
      _checkMember(node, method);
      final found = implementationIn(_builder.level!.superLevel!, method);
      if (found == null) _unsupported(node, 'this use of super');
      return _scope.tearOff(_builder, found, _this(node));
    }
    final class_ = _receiverClass(node, target);
    if (target == null) return tearOff(node, _this(node), class_, method);
    return tearOff(node, object(node, target), class_, method);
  }

  /// Reads the property [element] of [target], or of `this` if that is null.
  HirValue property(Expression node, Expression? target, Element element) {
    if (element is MethodElement) return _methodOf(node, target, element);
    if (element is! GetterElement) _unsupported(node, describe(node));
    HirValue? result;
    if (target is SuperExpression) {
      result = superMember(node, element, const []);
    } else {
      final class_ = _receiverClass(node, target);
      final receiver = target == null ? _this(node) : object(node, target);
      final read = invoke(node, receiver, class_, element);
      result = _checked(node, element, read);
    }
    return result ?? _unsupported(node, describe(node));
  }

  /// Reads `target[index]`.
  HirValue index(IndexExpression node) {
    final element = node.element, target = node.realTarget;
    if (target.staticType is DynamicType) {
      final object = _evaluator.value(target);
      _chains.check(node, object);
      return _dynamics.operate(node, object, '[]', [
        _evaluator.value(node.index, placeholder: .reference),
      ]);
    }
    if (element == null) _unsupported(node, describe(node));
    final type = element.formalParameters.first.type;
    if (valueType(type) == null) _unsupported(node, describe(node));
    final isSuper = target is SuperExpression;
    final receiver = isSuper ? _this(node) : object(node, target);
    final position = _evaluator.valueTo(node.index, type);
    final result = isSuper
        ? superMember(node, element, [position])
        : invoke(node, receiver, _receiverClass(node, target), element, [
            position,
          ]);
    return result ?? _unsupported(node, 'using a value without a type');
  }
}
