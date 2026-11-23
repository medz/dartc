import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'chains.dart';
import 'checks.dart';
import 'closures.dart';
import 'constant.dart';
import 'conversions.dart';
import 'creators.dart';
import 'describe.dart';
import 'dynamics.dart';
import 'members.dart';
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
    if (target != null && isNumber(_withoutNull(target.staticType))) {
      final result = _numberMember(node, element, target);
      if (result != null) return result;
    }
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
    return _closures.call(node, function, node.argumentList);
  }

  /// The result of a conversion of the number [target], if it is one.
  HirValue? _numberMember(
    MethodInvocation node,
    MethodElement element,
    Expression target,
  ) {
    final name = element.displayName;
    if (name != 'toInt' && name != 'toDouble') return null;
    final value = _evaluator.value(target);
    _chains.check(node, value);
    if (value.type == .reference) {
      final helper = name == 'toInt' ? 'numToInt' : 'numToDouble';
      return _builder.call(HirCall(_scope.runtime(helper), [value]));
    }
    if (name == 'toInt') {
      return CheckedOperations(_scope, _builder).toInt(value);
    }
    return value.type == .float
        ? value
        : _builder.add(HirUnary(.intToFloat, value));
  }

  DartType? _withoutNull(DartType? type) =>
      type == null ? null : _builder.library.typeSystem.promoteToNonNull(type);

  HirValue _this(AstNode node) =>
      _builder.receiver ?? _unsupported(node, 'this here');

  /// The object that [target] is, of which [node] uses a member.
  HirValue object(Expression node, Expression target) {
    if (classOf(target.staticType) == null) {
      _unsupported(node, describe(node));
    }
    final result = _evaluator.valueAs(target, .reference);
    _chains.check(node, result);
    return result;
  }

  InterfaceElement _receiverClass(AstNode node, Expression? target) =>
      (target == null ? _builder.receiverClass : classOf(target.staticType)) ??
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
      case 'dart:core print':
        _print(arguments.single.argumentExpression);
        return null;
      case 'dart:core identical':
        final [left, right] = [
          for (final argument in arguments) argument.argumentExpression,
        ];
        return _identical(left, right);
    }
    if (_scope.machineOpOf(element) case final op?) {
      return _machine(op, arguments);
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

  HirValue _identical(Expression left, Expression right) {
    final a = _evaluator.value(left), b = _evaluator.value(right);
    if (a.type == b.type && a.type != .float && a.type != .reference) {
      return _builder.add(HirCompare(.equal, a, b));
    }
    final objects = [
      for (final value in [a, b]) _conversions.coerce(value, .reference),
    ];
    return canBeNumber(left.staticType!) && canBeNumber(right.staticType!)
        ? _builder.call(HirCall(_scope.runtime('sameObjects'), objects))!
        : _builder.add(HirCompare(.equal, objects[0], objects[1]));
  }

  HirValue? _machine(HirMachineOp op, List<Argument> arguments) {
    final call = _builder.add(
      HirMachine(op, [
        for (final (i, argument) in arguments.indexed)
          _evaluator.valueAs(argument.argumentExpression, op.parameters[i]),
      ]),
    );
    if (op == .trap || op == .resume) _builder.end(HirUnreachable());
    return call.type == null ? null : call;
  }

  static String? _coreName(ExecutableElement element) =>
      element is TopLevelFunctionElement && element.library.isInSdk
      ? '${element.library.uri} ${element.name}'
      : null;

  void _print(Expression argument) {
    final text = constantText(argument.unParenthesized);
    if (text == null) {
      _unsupported(argument, 'printing anything but a constant string');
    }
    _builder.add(HirPrint(text));
  }

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
    if (element.library.isInSdk) {
      _unsupported(node, 'calling ${class_.displayName} of the SDK');
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
    if (class_.library.isInSdk) {
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
  ]) {
    _checkMember(node, element);
    final names = named.keys.toList()..sort();
    final selector = _scope.selectorOf(
      element.baseElement,
      class_,
      positional.length,
      names,
      (what) => _unsupported(node, what),
    );
    final result = _builder.call(
      HirVirtualCall(selector, receiver, [
        for (final (i, value) in [
          ?types,
          ...positional,
          for (final name in names) named[name]!,
        ].indexed)
          _conversions.coerce(value, selector.parameters[i]),
      ]),
    );
    if (isNever(element.returnType)) _builder.end(HirUnreachable());
    return result;
  }

  void _checkMember(AstNode node, ExecutableElement element) {
    final owner = element.enclosingElement;
    if (owner is! InterfaceElement) _unsupported(node, 'extensions');
    if (owner.library.isInSdk && element.displayName != '==') {
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
    if (element.typeParameters.isNotEmpty) {
      _unsupported(node, 'tear-offs of generic methods');
    }
    return _builder.call(
      HirVirtualCall(
        _scope.tearOffSelector(element.baseElement, class_),
        receiver,
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
