import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'record.dart';

/// Evaluates a selector chain, skipping the remaining selectors on a null-aware miss.
Value? lowerSelectors(
  FunctionContext context,
  ast.Expression root,
  Value? Function(ast.Expression) evaluate,
) {
  JumpTarget? skipped;
  Value? visit(ast.Expression node) {
    if (node case ast.PostfixExpression(
      operator: Token(type: .BANG),
      :final operand,
    )) {
      final value = visit(operand);
      return value == null ? null : context.normal(context.checkNotNull(value));
    }
    final (receiver, name, member, arguments, nullAware) = switch (node) {
      ast.PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.staticType is dart.RecordType ||
              identifier.element is GetterElement &&
                  !(identifier.element as GetterElement).isStatic =>
        (prefix, identifier.name, identifier.element, null, false),
      ast.PropertyAccess(
        target: final target?,
        :final propertyName,
        :final isNullAware,
        isCascaded: false,
      ) =>
        (target, propertyName.name, propertyName.element, null, isNullAware),
      ast.SimpleIdentifier(element: final GetterElement getter)
          when !getter.isStatic =>
        (null, node.name, getter, null, false),
      ast.MethodInvocation(
        methodName: ast.SimpleIdentifier(element: final MethodElement method),
        :final target,
        :final argumentList,
        :final isNullAware,
        isCascaded: false,
      )
          when !method.isStatic && method.enclosingElement is ClassElement =>
        (target, method.name!, method, argumentList, isNullAware),
      _ => (null, null, null, null, false),
    };
    if (name == null) {
      if (identical(node, root)) {
        unsupported(context.unit, node, 'member access');
      }
      return evaluate(node);
    }
    final direct = receiver is ast.SuperExpression;
    final value = receiver == null || direct
        ? context.receiver
        : visit(receiver);
    if (value == null) return null;
    if (nullAware) {
      skipped ??= JumpTarget(context, [context.typeOf(root.staticType!, root)]);
      context.guard(
        context.testType(value, .nullType, negated: true),
        skipped!,
        [const Constant.nullValue()],
      );
      if (context.current == null) return null;
    }
    final known = context.refined(value);
    if (receiver?.staticType is dart.RecordType && member == null) {
      final owner = known.type.nonNullable is RecordType
          ? known.type.nonNullable as RecordType
          : context.typeOf(receiver!.staticType!, receiver).nonNullable
                as RecordType;
      final slot = owner.slots[name];
      if (slot == null) unsupported(context.unit, node, 'record member $name');
      final record = context.normal(context.cast(known, owner));
      return record == null
          ? null
          : context.normal(readRecordField(context, record, slot));
    }
    if (member is! ExecutableElement ||
        member.enclosingElement is! ClassElement ||
        member.isStatic) {
      unsupported(context.unit, node, 'member $name');
    }
    final target = context.bindings.target(member, context.unit, node);
    Value? result(Instruction call) {
      final value = context.normal(context.emit(call));
      if (value == null || member is! GetterElement) return value;
      return context.normal(
        context.cast(value, context.typeOf(node.staticType!, node)),
      );
    }

    if (direct) {
      final args = context.bindings.arguments(
        member,
        arguments,
        context.unit,
        evaluate,
      );
      return args == null ? null : result(DirectCall(target, [known, ...args]));
    }
    final positional = <Value>[], named = <String, Value>{};
    for (final argument in arguments?.arguments ?? const <ast.Argument>[]) {
      final value = evaluate(argument.argumentExpression);
      if (value == null) return null;
      if (argument is ast.NamedArgument) {
        named[argument.name.lexeme] = value;
      } else {
        positional.add(value);
      }
    }
    return result(InstanceCall(target, known, positional, named));
  }

  final result = visit(root);
  final exit = skipped;
  if (exit == null || !exit.hasIncoming) return result;
  if (result != null) exit.jump([result]);
  return exit.enter()!.parameters.first;
}
