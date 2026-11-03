import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'operators.dart';
import 'record.dart';

/// Evaluates a selector chain, skipping the remaining selectors on a null-aware miss.
final class SelectorChain(
  final FunctionContext context,
  final ast.Expression root,
  final Value? Function(ast.Expression) evaluate,
) {
  JumpTarget? _skipped;

  /// Returns the selected value, or null when evaluation cannot continue.
  Value? lower() {
    final node = root;
    final result = switch (node) {
      ast.AssignmentExpression() => _update(node),
      ast.PostfixExpression(
        operator: Token(type: .PLUS_PLUS || .MINUS_MINUS),
      ) ||
      ast.PrefixExpression(
        operator: Token(type: .PLUS_PLUS || .MINUS_MINUS),
      ) => _update(node as ast.CompoundAssignmentExpression),
      _ => _visit(node),
    };
    final exit = _skipped;
    if (exit == null || !exit.hasIncoming) return result;
    if (result != null) exit.jump([result]);
    return exit.enter()!.parameters.first;
  }

  Value? _receiver(ast.Expression? expression, bool nullAware) {
    final value = expression == null || expression is ast.SuperExpression
        ? context.receiver
        : _visit(expression);
    if (value == null) return null;
    if (nullAware) {
      _skipped ??= JumpTarget(context, [
        context.typeOf(root.staticType!, root),
      ]);
      context.guard(
        context.testType(value, .nullType, negated: true),
        _skipped!,
        [const Constant.nullValue()],
      );
      if (context.current == null) return null;
    }
    return context.refined(value);
  }

  Value? _visit(ast.Expression node) {
    if (node case ast.PostfixExpression(
      operator: Token(type: .BANG),
      :final operand,
    )) {
      final value = _visit(operand);
      return value == null ? null : context.normal(context.checkNotNull(value));
    }
    if (node case ast.IndexExpression(
      isCascaded: false,
      :final target,
      :final index,
      :final isNullAware,
      :final element,
    )) {
      final receiver = _receiver(target, isNullAware);
      if (receiver == null) return null;
      final key = evaluate(index);
      return key == null
          ? null
          : context.callPositionalMember(
              element,
              receiver,
              [key],
              node,
              direct: target is ast.SuperExpression,
            );
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
    final known = _receiver(receiver, nullAware);
    if (known == null) return null;
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

  Value? _update(ast.CompoundAssignmentExpression site) {
    final (place, operator, rhs) = switch (site) {
      ast.AssignmentExpression(
        :final leftHandSide,
        :final operator,
        :final rightHandSide,
      ) =>
        (leftHandSide, operator, rightHandSide),
      ast.PrefixExpression(:final operand, :final operator) ||
      ast.PostfixExpression(
        :final operand,
        :final operator,
      ) => (operand, operator, null),
      _ => unsupported(context.unit, site, 'assignment'),
    };
    Value? apply(Value? Function() read, void Function(Value) store) {
      Value? write(Value? result) {
        if (result == null) return null;
        store(result);
        return context.current == null ? null : result;
      }

      if (operator.type == .EQ) return write(evaluate(rhs!));
      final value = read();
      if (value == null) return null;
      final old = context.normal(
        context.cast(value, context.typeOf(site.readType!, site)),
      );
      if (old == null) return null;
      if (operator.type == .QUESTION_QUESTION_EQ) {
        return context.ifNull(
          old,
          context.typeOf(site.staticType!, site),
          () => write(evaluate(rhs!)),
        );
      }
      final result = write(
        lowerBinary(
          context,
          site,
          operator,
          old,
          rhs == null ? const Constant.integer(1) : evaluate(rhs),
        ),
      );
      return result != null && site is ast.PostfixExpression ? old : result;
    }

    final destination = site.writeElement;
    if (destination is VariableElement &&
        context.locals.containsKey(destination)) {
      return apply(() => context.locals[destination], (value) {
        if (!context.typeOf(destination.type, site).accepts(value.type)) {
          unsupported(context.unit, site, 'implicit conversion');
        }
        context.locals[destination] = value;
      });
    }
    if (destination is! ExecutableElement ||
        destination.isStatic ||
        destination.enclosingElement is! ClassElement) {
      unsupported(context.unit, site, 'assignment target');
    }
    final (target, nullAware, index) = switch (place) {
      ast.SimpleIdentifier() => (null, false, null),
      ast.PrefixedIdentifier(:final prefix) => (prefix, false, null),
      ast.PropertyAccess(
        :final target,
        :final isNullAware,
        isCascaded: false,
      ) =>
        (target, isNullAware, null),
      ast.IndexExpression(
        :final target,
        :final isNullAware,
        :final index,
        isCascaded: false,
      ) =>
        (target, isNullAware, index),
      _ => unsupported(context.unit, place, 'assignment receiver'),
    };
    final receiver = _receiver(target, nullAware);
    if (receiver == null) return null;
    final key = index == null ? null : evaluate(index);
    if (index != null && key == null) return null;
    final direct = target is ast.SuperExpression;
    return apply(
      () => context.callPositionalMember(
        site.readElement as ExecutableElement?,
        receiver,
        [?key],
        site,
        direct: direct,
      ),
      (value) => context.callPositionalMember(
        destination,
        receiver,
        [?key, value],
        site,
        direct: direct,
      ),
    );
  }
}
