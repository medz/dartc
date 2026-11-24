import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'assigned.dart';
import 'builder.dart';
import 'calls.dart';
import 'conversions.dart';
import 'late_locals.dart';
import 'scope.dart';
import 'types.dart';

/// Translates `for` loops, of statements and of literals, and declarations of
/// variables.
final class LoopTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final CallTranslator _calls,
  final LateTranslator _lates,

  /// Assigns what a pattern sets of a value of a type.
  final void Function(DartPattern pattern, HirValue value, DartType type)
  _destructure,

  /// Assigns a value of a type to what is named.
  final void Function(SimpleIdentifier name, HirValue value, DartType type)
  _assignNamed,
) {
  late final _conversions = Conversions(_scope, _builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  void declare(VariableDeclarationList list) {
    for (final declaration in list.variables) {
      final variable = declaration.declaredFragment!.element;
      if (variable.isConst) continue;
      final type =
          valueType(variable.type) ??
          _unsupported(declaration, 'a variable of type ${variable.type}');
      if (list.isLate) {
        _lates.declare(declaration, variable, type);
        continue;
      }
      final initializer = declaration.initializer;
      final value = initializer == null
          ? null
          : _evaluator.valueTo(initializer, variable.type);
      _builder.declare(variable, type);
      if (value != null) _builder.assign(variable, value);
    }
  }

  void destructure(PatternVariableDeclaration node) {
    final expression = node.expression;
    final value = _evaluator.value(expression);
    _destructure(node.pattern, value, expression.staticType!);
  }

  /// The variables that each round of a loop has of its own.
  static Iterable<Element> _ownVariables(ForParts parts) => switch (parts) {
    ForPartsWithDeclarations(:final variables) => [
      for (final variable in variables.variables)
        variable.declaredFragment!.element,
    ],
    ForPartsWithPattern(:final variables) => declaredIn(variables.pattern),
    _ => const [],
  };

  /// Does [body] as often as [parts] of [node] say.
  ///
  /// Tells [within] where the loop ends and where it goes on.
  void translate(
    AstNode node,
    ForLoopParts parts,
    void Function() body, {
    void Function(Join exit, Join next)? within,
  }) {
    switch (parts) {
      case ForParts():
        _for(node, parts, body, within);
      case ForEachParts():
        _forIn(node, parts, body, within);
    }
  }

  void _for(
    AstNode node,
    ForParts parts,
    void Function() body,
    void Function(Join exit, Join next)? within,
  ) {
    switch (parts) {
      case ForPartsWithDeclarations(:final variables):
        if (variables.isLate) _unsupported(variables, 'late loop variables');
        declare(variables);
      case ForPartsWithExpression(:final initialization):
        if (initialization != null) _evaluator.effect(initialization);
      case ForPartsWithPattern(:final variables):
        destructure(variables);
    }
    final head = _builder.join(node), exit = _builder.join(node);
    final update = _builder.join(node);
    within?.call(exit, update);
    _builder
      ..jump(head)
      ..enter(head);
    void round() {
      body();
      _builder
        ..jump(update)
        ..enter(update);
      _ownVariables(parts).forEach(_builder.renew);
      parts.updaters.forEach(_evaluator.effect);
      _builder.jump(head);
    }

    final condition = parts.condition;
    if (condition == null) {
      round();
    } else {
      final value = _evaluator.valueTo(condition, _conversions.types.boolType);
      _builder.branch(value, round, () => _builder.jump(exit));
    }
    _builder.enter(exit);
  }

  void _forIn(
    AstNode node,
    ForEachParts parts,
    void Function() body,
    void Function(Join exit, Join next)? within,
  ) {
    final iterable = parts.iterable;
    each(node, iterable, _iterable(iterable), within: within, (value) {
      _assign(parts, value);
      body();
    });
  }

  /// What [node] gives, as something to iterate over.
  HirValue _iterable(Expression node) => node.staticType is DynamicType
      ? _evaluator.valueTo(node, _conversions.types.iterableDynamicType)
      : _evaluator.valueAs(node, .reference);

  /// Does [body] for each element of [iterable], which is what [source] gives.
  void each(
    AstNode node,
    Expression source,
    HirValue iterable,
    void Function(HirValue value) body, {
    void Function(Join exit, Join next)? within,
  }) {
    final iterableClass = _conversions.types.iterableElement;
    final iterator = _use(node, iterable, iterableClass, 'iterator');
    final next = _builder.join(node), exit = _builder.join(node);
    within?.call(exit, next);
    _builder
      ..jump(next)
      ..enter(next);
    final class_ = _iteratorClass;
    final method = class_.getMethod('moveNext')!;
    final isOne = _calls.invoke(node, iterator, class_.thisType, method)!;
    _builder.branch(isOne, () {
      body(_use(node, iterator, class_, 'current'));
      _builder.jump(next);
    }, () => _builder.jump(exit));
    _builder.enter(exit);
  }

  InterfaceElement get _iteratorClass =>
      _conversions.types.iterableElement.library.getClass('Iterator')!;

  HirValue _use(
    AstNode node,
    HirValue object,
    InterfaceElement class_,
    String name,
  ) => _calls.invoke(node, object, class_.thisType, class_.getGetter(name)!)!;

  /// Assigns [value], the next of the elements of [parts], to its variable.
  void _assign(ForEachParts parts, HirValue value) {
    final VariableElement variable;
    final type = elementType(parts.iterable.staticType!);
    switch (parts) {
      case ForEachPartsWithPattern(:final pattern):
        return _destructure(pattern, value, type);
      case ForEachPartsWithDeclaration(:final loopVariable):
        variable = loopVariable.declaredFragment!.element;
        _builder.declare(
          variable,
          valueType(variable.type) ??
              _unsupported(parts, 'a variable of type ${variable.type}'),
        );
      case ForEachPartsWithIdentifier(
            identifier: SimpleIdentifier(:final VariableElement element),
          )
          when _builder.typeOf(element) != null:
        variable = element;
      case ForEachPartsWithIdentifier(:final identifier):
        return _assignNamed(identifier, value, type);
    }
    final given =
        _conversions.cast(value, type, variable.type) ??
        _unsupported(parts, 'testing for ${variable.type}');
    if (!_lates.write(variable, given)) _builder.assign(variable, given);
  }

  /// The type of the elements of something of [type].
  DartType elementType(DartType type) {
    final iterable = _conversions.types.iterableElement;
    final found = switch (boundOf(type)) {
      final InterfaceType type => type.asInstanceOf(iterable),
      _ => null,
    };
    return found?.typeArguments.single ?? _conversions.types.dynamicType;
  }
}
