import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';
import 'closure.dart';
import 'conversions.dart';
import 'coroutine.dart';
import 'coroutines.dart';
import 'dynamics.dart';
import 'environment.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// Translates closures and calls of functions that are values.
final class ClosureTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,

  /// The value of what an expression uses a member of, and its type.
  final HirValue Function(Expression target, Expression node) _valueOf,
  final DartType? Function(Expression target) _typeOf,

  /// Calls a method of an object, which is of a type.
  final HirValue? Function(
    HirValue receiver,
    DartType? type,
    MethodElement element,
    FunctionExpressionInvocation node,
  )
  callMethod,
) {
  late final _conversions = Conversions(_scope, _builder);
  late final _dynamics = DynamicTranslator(_scope, _builder, _evaluator);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Creates the closure that [node] is.
  HirValue create(FunctionExpression node) =>
      _create(node, node.declaredFragment!.element, null);

  /// Creates and declares the local function [node].
  void declare(FunctionDeclaration node) {
    final element = node.declaredFragment!.element;
    _builder.declare(element, .reference);
    _builder.assign(
      element,
      _create(node.functionExpression, element, element),
    );
  }

  /// [name] is what the closure calls itself, if it has a name.
  HirValue _create(
    FunctionExpression node,
    ExecutableElement element,
    Element? name,
  ) {
    final isGeneric = element.typeParameters.isNotEmpty;
    final environment = Environment.of(
      _builder,
      node,
      _scope.capturesOf(declarationOf(node)),
      name: name,
    );
    // An open type is found where the closure is created.
    final type = isOpen(element.type)
        ? HirField('type', .reference, isFinal: true)
        : null;
    final class_ = HirClass(_describe(element), null, [
      ...environment.fields,
      ?type,
    ]);
    final function = HirFunction(
      '${_builder.function.name}.${name?.displayName ?? 'closure'}',
      [
        .reference,
        if (isGeneric) .reference,
        for (final parameter in element.formalParameters)
          valueType(parameter.type) ??
              _unsupported(node, 'a parameter of type ${parameter.type}'),
      ],
      valueType(element.returnType) ??
          _unsupported(node, 'a result of type ${element.returnType}'),
    );
    _scope.addLocalFunction(function);
    final frameName =
        '${outerName(node)}.${name?.displayName ?? '<anonymous closure>'}';
    _scope.addClosure(
      Closure(
        class_,
        element.formalParameters,
        () => function,
        (_, self) => [self],
        typeParameters: element.typeParameters,
        name: frameName,
        bind: environment.bindTypes,
        typeValue: (builder) => type == null
            ? _scope.typeValue(builder, element.type)!
            : builder.add(HirLoad(type, builder.inputs.first)),
      ),
    );
    if (name != null) _builder.locals.functions[name] = function;
    _scope.schedule(() {
      final builder = environment.build(
        function,
        element.formalParameters,
        typeOwners: [if (isGeneric) element],
        returnType: element.returnType,
      )..frameName = frameName;
      if (name != null) {
        builder.bind(name, builder.inputs.first, .reference);
      }
      if (CoroutineKind.of(node.body) case final kind?) {
        CoroutineTranslator(
          _scope,
          builder,
        ).start(node.body, kind, element.returnType, element.formalParameters);
        builder.finish();
      } else {
        _scope.translateBody(builder, node.body);
      }
    });
    final object = _builder.create(class_);
    environment.store(object);
    if (type != null) {
      final value =
          _scope.typeValue(_builder, element.type) ??
          _unsupported(node, 'a function of type ${element.type}');
      _builder.add(HirStore(type, object, value));
    }
    return object;
  }

  /// What the function around [node] is called.
  static String outerName(AstNode node) {
    final parent = node.parent;
    // A function with a name is in its declaration.
    final outer = parent is FunctionDeclaration ? parent.parent : parent;
    for (var at = outer; at != null; at = at.parent) {
      switch (at) {
        case FunctionDeclaration(:final name):
          final isLocal = at.parent is FunctionDeclarationStatement;
          return isLocal ? '${outerName(at)}.${name.lexeme}' : name.lexeme;
        case MethodDeclaration(
          :final name,
          declaredFragment: Fragment(:final element),
        ):
          return '${element.enclosingElement?.displayName}.${name.lexeme}';
        case FunctionExpression(parent: final outer)
            when outer is! FunctionDeclaration:
          return '${outerName(at)}.<anonymous closure>';
      }
    }
    return '';
  }

  static String _describe(ExecutableElement element) =>
      describeType(element.type);

  /// Calls [node], whose function is any expression.
  HirValue? invocation(FunctionExpressionInvocation node) {
    final function = node.function;
    final type = function.staticType;
    final element = node.element;
    if (element is MethodElement && isExtensionMember(element)) {
      final value = _valueOf(function, node);
      final type = _typeOf(function);
      return callMethod(value, type, element, node);
    }
    if (type is FunctionType) {
      return call(
        node,
        _evaluator.value(function),
        node.argumentList,
        node.typeArgumentTypes,
      );
    }
    if (element is MethodElement && classOf(type) != null) {
      final object = _evaluator.valueAs(function, .reference);
      return callMethod(object, type, element, node);
    }
    return _dynamics.call(
      node,
      _evaluator.value(function, placeholder: .reference),
      'call',
      node.argumentList,
      types: node.typeArguments,
    );
  }

  /// Calls the function [value].
  HirValue? call(
    Expression node,
    HirValue value,
    ArgumentList list,
    List<DartType>? types,
  ) {
    final typeList = types == null || types.isEmpty
        ? null
        : _scope.typeList(_builder, types) ??
              _unsupported(node, 'these type arguments');
    final positional = <HirValue>[];
    final named = <String, HirValue>{};
    for (final argument in list.arguments) {
      final parameter = argument.correspondingParameter!;
      final expression = argument.argumentExpression;
      if (valueType(parameter.type) == null) {
        _unsupported(expression, 'a parameter of type ${parameter.type}');
      }
      final given = _conversions.coerce(
        _evaluator.valueTo(expression, parameter.type),
        .reference,
      );
      if (parameter.isNamed) {
        named[parameter.name!] = given;
      } else {
        positional.add(given);
      }
    }
    final names = named.keys.toList()..sort();
    final selector = _scope.callSelector(
      types?.length ?? 0,
      positional.length,
      names,
    );
    final result = _builder.call(
      HirVirtualCall(selector, value, [
        ?typeList,
        ...positional,
        for (final name in names) named[name]!,
      ]),
    );
    if (isNever(node.staticType)) _builder.end(HirUnreachable());
    return result;
  }
}
