import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'constant.dart';
import 'describe.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// Translates calls, the creation of objects and reading properties.
final class CallTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// The result of [node], if it has one and [isUsed].
  HirValue? invocation(MethodInvocation node, {required bool isUsed}) {
    final element = node.methodName.element, target = node.realTarget;
    if (element is! ExecutableElement) _unsupported(node, describe(node));
    if (!isInstanceMember(element)) return _static(node, element);
    if (element is! MethodElement) _unsupported(node, describe(node));
    if (target is SuperExpression) {
      return superMember(
        node,
        element,
        ordered(element, supplied(node.argumentList)),
      );
    }
    HirValue? call(HirValue receiver) => _invoke(
      node,
      receiver,
      _receiverClass(node, target),
      element,
      node.argumentList,
    );
    if (target == null) return call(_this(node));
    final receiver = object(target, isNullAware: node.isNullAware);
    return node.isNullAware
        ? _unlessNull(node, receiver, () => call(receiver), isUsed: isUsed)
        : call(receiver);
  }

  HirValue _this(AstNode node) =>
      _builder.receiver ?? _unsupported(node, 'this here');

  /// The object that [target] is, on which a member is used.
  ///
  /// Where a null-aware target is null, a use that [isNullAware] itself is
  /// skipped anyway; others would have to be skipped with it.
  HirValue object(Expression target, {bool isNullAware = false}) {
    if (_isNullAware(target) && !isNullAware) {
      _unsupported(target.parent!, 'null-aware chains');
    }
    if (classOf(target.staticType) == null) {
      _unsupported(target.parent!, describe(target.parent!));
    }
    return _evaluator.valueAs(target, .reference);
  }

  static bool _isNullAware(Expression target) => switch (target) {
    MethodInvocation(:final isNullAware) ||
    PropertyAccess(:final isNullAware) ||
    IndexExpression(:final isNullAware) => isNullAware,
    _ => false,
  };

  ClassElement _receiverClass(AstNode node, Expression? target) =>
      (target == null ? _builder.receiverClass : classOf(target.staticType)) ??
      _unsupported(node, describe(node));

  /// Runs [call] unless [receiver] is null, which is then the result.
  HirValue? _unlessNull(
    Expression node,
    HirValue receiver,
    HirValue? Function() call, {
    required bool isUsed,
  }) {
    final type = valueType(node.staticType!);
    if (isUsed && type == null) {
      _unsupported(node, 'a value of type ${node.staticType}');
    }
    final exit = _builder.join(node, isUsed ? type : null);
    final isNull = _builder.add(
      HirCompare(.equal, receiver, _builder.add(HirNull())),
    );
    _builder.branch(
      isNull,
      () => _builder.jump(exit, isUsed ? _builder.add(HirNull()) : null),
      () {
        final result = call();
        _builder.jump(exit, isUsed ? result : null);
      },
    );
    return _builder.enter(exit);
  }

  HirValue? _static(MethodInvocation node, ExecutableElement element) {
    final isFunction =
        element is TopLevelFunctionElement || element is MethodElement;
    if (!isFunction) _unsupported(node, describe(node));
    final arguments = node.argumentList.arguments;
    switch (_coreName(element)) {
      case 'dart:io exit':
        final code = arguments.single.argumentExpression;
        _builder.end(HirExit(_evaluator.valueAs(code, .integer)));
        return null;
      case 'dart:core print':
        _print(arguments.single.argumentExpression);
        return null;
      case 'dart:core identical':
        final [left, right] = [
          for (final argument in arguments)
            _evaluator.valueAs(argument.argumentExpression, .reference),
        ];
        return _builder.add(HirCompare(.equal, left, right));
    }
    if (_scope.machineOpOf(element) case final op?) {
      return _machine(op, arguments);
    }
    final function = _scope.functionOf(element);
    if (function == null) {
      _unsupported(node, 'calling ${element.displayName} of the SDK');
    }
    return _direct(function, element, [
      ...ordered(element, supplied(node.argumentList)),
    ]);
  }

  HirValue? _machine(HirMachineOp op, List<Argument> arguments) {
    final call = _builder.add(
      HirMachine(op, [
        for (final argument in arguments)
          _evaluator.valueAs(argument.argumentExpression, .integer),
      ]),
    );
    if (op == .trap) _builder.end(HirUnreachable());
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
    final call = _builder.add(HirCall(function, arguments));
    if (element.returnType is NeverType) _builder.end(HirUnreachable());
    return call.type == null ? null : call;
  }

  /// Creates an object, or calls a factory.
  HirValue creation(InstanceCreationExpression node) {
    final element = node.constructorName.element;
    final class_ = classOf(node.staticType);
    if (element == null || class_ == null) {
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
    if (element.isFactory) {
      final factory = _scope.factoryOf(element);
      return _builder.add(
        HirCall(factory, ordered(element, supplied(node.argumentList))),
      );
    }
    final created = _scope.createdClass(class_);
    final arguments = ordered(element, supplied(node.argumentList));
    final object = _builder.add(HirNew(created));
    _builder.add(
      HirCall(_scope.initializerOf(element), [object, ...arguments]),
    );
    return object;
  }

  /// The arguments of a call, evaluated in source order, by parameter.
  Map<FormalParameterElement, HirValue> supplied(ArgumentList list) {
    final values = <FormalParameterElement, HirValue>{};
    for (final argument in list.arguments) {
      final parameter = argument.correspondingParameter!;
      final type =
          valueType(parameter.type) ??
          _unsupported(
            argument.argumentExpression,
            'a parameter of type ${parameter.type}',
          );
      values[parameter] = _evaluator.valueAs(argument.argumentExpression, type);
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

  HirValue? _invoke(
    AstNode node,
    HirValue receiver,
    ClassElement class_,
    MethodElement element,
    ArgumentList list,
  ) {
    final given = supplied(list);
    final positional = [
      for (final MapEntry(:key, :value) in given.entries)
        if (key.isPositional) value,
    ];
    final named = {
      for (final MapEntry(:key, :value) in given.entries)
        if (key.isNamed) key.name!: value,
    };
    return invoke(node, receiver, class_, element, positional, named);
  }

  /// Calls the instance member [element] on [receiver].
  HirValue? invoke(
    AstNode node,
    HirValue receiver,
    ClassElement class_,
    ExecutableElement element, [
    List<HirValue> positional = const [],
    Map<String, HirValue> named = const {},
  ]) {
    _checkMember(node, element);
    final names = named.keys.toList()..sort();
    final selector = _scope.selectorOf(
      element,
      class_,
      positional.length,
      names,
      (what) => _unsupported(node, what),
    );
    final call = _builder.add(
      HirVirtualCall(selector, receiver, [
        ...positional,
        for (final name in names) named[name]!,
      ]),
    );
    if (element.returnType is NeverType) _builder.end(HirUnreachable());
    return call.type == null ? null : call;
  }

  void _checkMember(AstNode node, ExecutableElement element) {
    final owner = element.enclosingElement;
    if (owner is! ClassElement) _unsupported(node, 'extensions and mixins');
    if (element is MethodElement && element.typeParameters.isNotEmpty) {
      _unsupported(node, 'generic methods');
    }
    if (owner.library.isInSdk && element.displayName != '==') {
      _unsupported(node, 'calling ${element.displayName} of the SDK');
    }
  }

  /// Uses the superclass's member [element] on `this`, giving [values].
  HirValue? superMember(
    AstNode node,
    ExecutableElement element,
    List<HirValue> values,
  ) {
    _checkMember(node, element);
    final parent = _builder.receiverClass!.supertype!.element as ClassElement;
    if (implementationIn(parent, element) != element) {
      _unsupported(node, 'this use of super');
    }
    final receiver = _this(node);
    if (fieldOfAccessor(element) case final field?) {
      final found = _scope.fieldOf(field);
      if (element is GetterElement) {
        return _builder.add(HirLoad(found, receiver));
      }
      _builder.add(HirStore(found, receiver, values.single));
      return null;
    }
    if (element.library.isInSdk) {
      // Only the equality of Object, which is identity.
      return _builder.add(HirCompare(.equal, receiver, values.single));
    }
    return _direct(_scope.memberOf(element), element, [receiver, ...values]);
  }

  /// Reads the property [element] of [target], or of `this` if that is null.
  HirValue property(Expression node, Expression? target, Element element) {
    if (element is MethodElement) _unsupported(node, 'method tear-offs');
    if (element is! GetterElement) _unsupported(node, describe(node));
    HirValue? result;
    if (target is SuperExpression) {
      result = superMember(node, element, const []);
    } else {
      final class_ = _receiverClass(node, target);
      HirValue? read(HirValue receiver) =>
          invoke(node, receiver, class_, element);
      if (target == null) {
        result = read(_this(node));
      } else {
        final isNullAware = node is PropertyAccess && node.isNullAware;
        final receiver = object(target, isNullAware: isNullAware);
        result = isNullAware
            ? _unlessNull(node, receiver, () => read(receiver), isUsed: true)
            : read(receiver);
      }
    }
    return result ?? _unsupported(node, describe(node));
  }

  /// Reads `target[index]`.
  HirValue index(IndexExpression node) {
    final element = node.element, target = node.realTarget;
    if (element == null || node.isNullAware) {
      _unsupported(node, describe(node));
    }
    final type =
        valueType(element.formalParameters.first.type) ??
        _unsupported(node, describe(node));
    final isSuper = target is SuperExpression;
    final receiver = isSuper ? _this(node) : object(target);
    final position = _evaluator.valueAs(node.index, type);
    final result = isSuper
        ? superMember(node, element, [position])
        : invoke(node, receiver, _receiverClass(node, target), element, [
            position,
          ]);
    return result ?? _unsupported(node, 'using a value without a type');
  }
}
