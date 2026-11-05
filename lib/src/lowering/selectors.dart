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
  final Value? Function(ast.Expression) evaluate, {
  final Value? cascadeReceiver,
}) {
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

  Value? _receiver(
    ast.Expression? expression,
    bool nullAware, {
    bool cascaded = false,
  }) {
    final value = cascaded
        ? cascadeReceiver
        : expression == null || expression is ast.SuperExpression
        ? context.receiver
        : _visit(expression);
    if (value == null) return null;
    if (value.type is DynamicType) {
      unsupported(context.unit, root, 'dynamic member dispatch');
    }
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

  Value? _visit(
    ast.Expression node, {
    ast.ArgumentList? getterArguments,
    MethodElement? getterCall,
    List<ValueType> getterTypeArguments = const [],
  }) {
    final typeArguments = node is ast.InvocationExpression
        ? context.typeArguments(node.typeArgumentTypes, node)
        : getterTypeArguments;
    Value? invokeValue(
      Value? input,
      ast.ArgumentList arguments, [
      MethodElement? callMethod,
      Value? Function(Value)? getFunction,
    ]) {
      if (input == null) return null;
      if (input.type is DynamicType) {
        unsupported(context.unit, node, 'dynamic function invocation');
      }
      final args = context.arguments(arguments, evaluate);
      if (args == null) return null;
      final function = getFunction == null ? input : getFunction(input);
      if (function == null) return null;
      if (callMethod != null) {
        final method = context.bindings.target(callMethod, context.unit, node);
        return context.normal(
          context.emit(
            InstanceCall(
              method,
              function,
              args.positional,
              args.named,
              null,
              typeArguments,
            ),
          ),
        );
      }
      if (function.type is! FunctionType) {
        unsupported(context.unit, node, 'untyped function invocation');
      }
      return context.normal(
        context.emit(
          FunctionCall(function, args.positional, args.named, typeArguments),
        ),
      );
    }

    // Static accessors have no runtime receiver. Validate their namespace without
    // evaluating it, then retain the ordinary call/assignment evaluation order.
    final (staticMember, staticReceiver, staticArguments) = switch (node) {
      ast.Identifier(element: final GetterElement getter)
          when getter.isStatic =>
        (getter, node is ast.PrefixedIdentifier ? node.prefix : null, null),
      ast.PropertyAccess(
        propertyName: ast.SimpleIdentifier(element: final GetterElement getter),
        :final target,
      )
          when getter.isStatic =>
        (getter, target, null),
      ast.MethodInvocation(
        methodName: ast.SimpleIdentifier(element: final GetterElement getter),
        :final target,
        :final argumentList,
      )
          when getter.isStatic =>
        (getter, target, argumentList),
      _ => (null, null, null),
    };
    if (staticMember != null) {
      _checkStaticReceiver(staticReceiver, node);
      Value? get() {
        if (staticMember.variable.isConst) {
          return context.bindings.constantOf(
            staticMember.variable,
            context.unit,
            node,
          );
        }
        final target = context.bindings.target(
          staticMember,
          context.unit,
          node,
        );
        return context.normal(context.emit(DirectCall(target, [])));
      }

      final invocation = getterArguments ?? staticArguments;
      return invocation == null
          ? get()
          : invokeValue(get(), invocation, getterCall);
    }

    if (node case ast.FunctionExpressionInvocation(
      :final function,
      :final argumentList,
      :final element,
    )) {
      if (function
          case ast.Identifier(element: GetterElement()) ||
              ast.PropertyAccess(
                propertyName: ast.SimpleIdentifier(element: GetterElement()),
              )) {
        return _visit(
          function,
          getterArguments: argumentList,
          getterCall: element is MethodElement ? element : null,
          getterTypeArguments: typeArguments,
        );
      }
      return invokeValue(
        _visit(function),
        argumentList,
        element is MethodElement ? element : null,
      );
    }
    if (node
        case ast.MethodInvocation(
          methodName: ast.SimpleIdentifier(name: 'call', element: null),
          target: final target,
          :final isNullAware,
          :final argumentList,
        )
        when target?.staticType is dart.FunctionType ||
            node.isCascaded &&
                cascadeReceiver?.type.nonNullable is FunctionType) {
      return invokeValue(
        _receiver(target, isNullAware, cascaded: node.isCascaded),
        argumentList,
      );
    }
    if (node case ast.PostfixExpression(
      operator: Token(type: .BANG),
      :final operand,
    )) {
      final value = _visit(operand);
      return value == null ? null : context.normal(context.checkNotNull(value));
    }
    if (node case ast.IndexExpression(
      :final target,
      :final index,
      :final isNullAware,
      :final element,
    )) {
      final receiver = _receiver(
        target,
        isNullAware,
        cascaded: node.isCascaded,
      );
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
          when prefix.staticType is dart.DynamicType ||
              prefix.staticType is dart.RecordType ||
              prefix.staticType is dart.FunctionType &&
                  identifier.name == 'call' ||
              identifier.element is ExecutableElement &&
                  !(identifier.element as ExecutableElement).isStatic =>
        (prefix, identifier.name, identifier.element, null, false),
      ast.PropertyAccess(
        target: final target,
        :final propertyName,
        :final isNullAware,
      ) =>
        (target, propertyName.name, propertyName.element, null, isNullAware),
      ast.SimpleIdentifier(element: final GetterElement getter)
          when !getter.isStatic =>
        (null, node.name, getter, null, false),
      ast.SimpleIdentifier(element: final MethodElement method)
          when !method.isStatic =>
        (null, node.name, method, null, false),
      ast.MethodInvocation(
        methodName: ast.SimpleIdentifier(element: null, :final name),
        target: final target?,
        :final argumentList,
        :final isNullAware,
      )
          when target.staticType is dart.DynamicType =>
        (target, name, null, argumentList, isNullAware),
      ast.MethodInvocation(
        methodName: ast.SimpleIdentifier(element: final GetterElement getter),
        :final target,
        :final argumentList,
        :final isNullAware,
      )
          when !getter.isStatic =>
        (target, getter.name!, getter, argumentList, isNullAware),
      ast.MethodInvocation(
        methodName: ast.SimpleIdentifier(element: final MethodElement method),
        :final target,
        :final argumentList,
        :final isNullAware,
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
    final known = _receiver(
      receiver,
      nullAware,
      cascaded: switch (node) {
        ast.PropertyAccess(:final isCascaded) ||
        ast.MethodInvocation(:final isCascaded) => isCascaded,
        _ => false,
      },
    );
    if (known == null) return null;
    if (known.type.nonNullable is FunctionType &&
        member == null &&
        name == 'call') {
      return known;
    }
    if ((receiver?.staticType is dart.RecordType ||
            known.type.nonNullable is RecordType) &&
        member == null) {
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
    if (member.library.uri.toString() == 'dart:core' &&
        (member is GetterElement || arguments != null)) {
      if (member is GetterElement &&
          member.name == 'hashCode' &&
          (member.enclosingElement.name == 'Object' ||
              member.enclosingElement.name == 'Type')) {
        return context.normal(context.emit(ObjectHashCode(known)));
      }
      final args = context.arguments(arguments, evaluate);
      if (args == null) return null;
      if (args.named.isEmpty) {
        final operation = coreCollectionOperation(
          member.name!,
          known,
          args.positional,
        );
        if (operation != null) return context.normal(context.emit(operation));
      }
      unsupported(context.unit, node, 'core collection member $name');
    }
    final target = context.bindings.target(member, context.unit, node);
    if (member is MethodElement && arguments == null) {
      return context.emit(BindMethod(target, known, direct: direct));
    }
    final invocation = getterArguments ?? arguments;
    if (member is GetterElement && invocation != null) {
      Value? get(Value receiver) => context.callPositionalMember(
        member,
        receiver,
        [],
        node,
        direct: direct,
      );
      return direct
          ? invokeValue(get(known), invocation, getterCall)
          : invokeValue(known, invocation, getterCall, get);
    }
    Value? result(Instruction call) {
      final value = context.normal(context.emit(call));
      if (value == null || member is! GetterElement) return value;
      return context.normal(
        context.cast(value, context.typeOf(node.staticType!, node)),
      );
    }

    final args = context.arguments(arguments, evaluate);
    if (args == null) return null;
    return result(
      direct
          ? DirectCall(
              target,
              [known, ...context.bindings.bind(target, args)],
              ownerType: (known.type.nonNullable as ClassType).asInstanceOf(
                target.owner!,
              ),
              typeArguments: typeArguments,
            )
          : InstanceCall(
              target,
              known,
              args.positional,
              args.named,
              null,
              typeArguments,
            ),
    );
  }

  void _checkStaticReceiver(ast.Expression? receiver, ast.AstNode site) {
    if (receiver == null) return;
    final element = receiver is ast.Identifier ? receiver.element : null;
    final valid = switch (element) {
      PrefixElement() => !element.imports.any(
        (i) => i.prefix?.isDeferred == true,
      ),
      ClassElement() =>
        receiver is! ast.PrefixedIdentifier || !receiver.isDeferred,
      _ => false,
    };
    if (!valid) unsupported(context.unit, site, 'static accessor receiver');
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
        result = context.normal(
          context.convert(result, context.typeOf(site.writeType!, site)),
        );
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
    if (destination is VariableElement && context.hasLocal(destination)) {
      return apply(() => context.readLocal(destination), (value) {
        context.writeLocal(destination, value);
      });
    }
    if (destination is SetterElement && destination.isStatic) {
      final receiver = switch (place) {
        ast.SimpleIdentifier() => null,
        ast.PrefixedIdentifier(:final prefix) => prefix,
        ast.PropertyAccess(:final target) => target,
        _ => unsupported(context.unit, place, 'static assignment target'),
      };
      _checkStaticReceiver(receiver, site);
      final setter = context.bindings.target(destination, context.unit, site);
      return apply(() {
        final getter = site.readElement;
        if (getter is! GetterElement || !getter.isStatic) {
          unsupported(context.unit, site, 'static assignment getter');
        }
        return context.normal(
          context.emit(
            DirectCall(context.bindings.target(getter, context.unit, site), []),
          ),
        );
      }, (value) => context.emit(DirectCall(setter, [value])));
    }
    if (destination is! ExecutableElement ||
        destination.isStatic ||
        destination.enclosingElement is! ClassElement) {
      unsupported(context.unit, site, 'assignment target');
    }
    final (target, nullAware, index) = switch (place) {
      ast.SimpleIdentifier() => (null, false, null),
      ast.PrefixedIdentifier(:final prefix) => (prefix, false, null),
      ast.PropertyAccess(:final target, :final isNullAware) => (
        target,
        isNullAware,
        null,
      ),
      ast.IndexExpression(:final target, :final isNullAware, :final index) => (
        target,
        isNullAware,
        index,
      ),
      _ => unsupported(context.unit, place, 'assignment receiver'),
    };
    final receiver = _receiver(
      target,
      nullAware,
      cascaded: switch (place) {
        ast.PropertyAccess(:final isCascaded) ||
        ast.IndexExpression(:final isCascaded) => isCascaded,
        _ => false,
      },
    );
    if (receiver == null) return null;
    final inputKey = index == null ? null : evaluate(index);
    final key = inputKey == null
        ? null
        : context.normal(
            context.convert(
              inputKey,
              context.typeOf(destination.formalParameters.first.type, site),
            ),
          );
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
