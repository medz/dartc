import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';
import 'closure.dart';
import 'conversions.dart';
import 'scope.dart';
import 'types.dart';

/// Translates closures and calls of functions that are values.
final class ClosureTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,

  /// Calls a method of an object.
  final HirValue? Function(
    Expression node,
    HirValue receiver,
    ClassElement class_,
    MethodElement element,
    ArgumentList list,
  )
  callMethod,
) {
  late final _conversions = Conversions(_scope, _builder);

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
    if (isGeneric && name == null) {
      _unsupported(node, 'generic functions as values');
    }
    if (node.body.isAsynchronous || node.body.isGenerator) {
      _unsupported(node.body, 'async and generator functions');
    }
    final captures = _scope.capturesOf(declarationOf(node));
    final used = [
      for (final used in captures.usedBy(node))
        if (used != name) used,
    ];
    final receiver = _builder.receiver;
    final fields = [for (final used in used) _field(used)];
    final self = HirField('this', .reference);
    final lists = {
      for (final owner in _builder.typeLists.keys)
        owner: HirField('types', .reference),
    };
    // An open type is found where the closure is created.
    final type = isOpen(element.type) && !isGeneric
        ? HirField('type', .reference)
        : null;
    final class_ = HirClass(_describe(element), null, [
      if (receiver != null) self,
      ...fields,
      ...lists.values,
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
      hasNoResult(element.returnType)
          ? null
          : valueType(element.returnType) ??
                _unsupported(node, 'a result of type ${element.returnType}'),
    );
    final closure = Closure(
      class_,
      element.type,
      element.formalParameters,
      () => function,
      (_, self) => [self],
      typeValue: (builder) => type == null
          ? _scope.typeValue(builder, element.type)!
          : builder.add(HirLoad(type, builder.inputs.first)),
    );
    _scope.addClosure(closure, function, isValue: !isGeneric);
    if (name != null) _scope.setLocalFunction(name, function);
    final outer = _builder;
    _scope.schedule(() {
      final builder = FunctionBuilder(
        outer.unit,
        function,
        element.formalParameters,
        receiverClass: outer.receiverClass,
        receiverField: receiver == null ? null : self,
        isClosure: true,
        typeOwner: isGeneric ? element : null,
        returnType: element.returnType,
        captures: captures,
        cellClass: _scope.cellClass,
      );
      lists.forEach((owner, field) {
        builder.bindTypes(
          owner,
          builder.add(HirLoad(field, builder.inputs.first)),
        );
      });
      for (final (i, used) in used.indexed) {
        builder.bind(
          used,
          builder.add(HirLoad(fields[i], builder.inputs.first)),
          outer.typeOf(used)!,
        );
      }
      if (name != null) {
        builder.bind(name, builder.inputs.first, .reference);
      }
      _scope.translateBody(builder, node.body);
    });
    final object = _builder.create(class_);
    if (receiver != null) {
      _builder.add(HirStore(self, object, receiver));
    }
    for (final (i, used) in used.indexed) {
      _builder.add(HirStore(fields[i], object, _builder.raw(used)));
    }
    lists.forEach((owner, field) {
      _builder.add(HirStore(field, object, _builder.typeLists[owner]!));
    });
    if (type != null) {
      final value =
          _scope.typeValue(_builder, element.type) ??
          _unsupported(node, 'a function of type ${element.type}');
      _builder.add(HirStore(type, object, value));
    }
    return object;
  }

  HirField _field(Element used) =>
      HirField(used.displayName, _builder.rawTypeOf(used)!);

  static String _describe(ExecutableElement element) =>
      describeType(element.type);

  /// Calls [node], whose function is any expression.
  HirValue? invocation(FunctionExpressionInvocation node) {
    final function = node.function;
    final type = function.staticType;
    if (type is FunctionType) {
      return call(node, _evaluator.value(function), node.argumentList);
    }
    final element = node.element;
    final class_ = classOf(type);
    if (element is MethodElement && class_ != null) {
      return callMethod(
        node,
        _evaluator.valueAs(function, .reference),
        class_,
        element,
        node.argumentList,
      );
    }
    _unsupported(function, 'using a dynamic value');
  }

  /// Calls the function [value].
  HirValue? call(Expression node, HirValue value, ArgumentList list) {
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
    final selector = _scope.callSelector(positional.length, names);
    final result = _builder.call(
      HirVirtualCall(selector, value, [
        ...positional,
        for (final name in names) named[name]!,
      ]),
    );
    if (isNever(node.staticType)) _builder.end(HirUnreachable());
    return result;
  }
}
