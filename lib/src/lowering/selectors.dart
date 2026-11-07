import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'core_member.dart';
import 'function_context.dart';
import 'operators.dart';
import 'record.dart';

/// Evaluates a selector chain, skipping the remaining selectors on a null-aware miss.
final class SelectorChain(
  final FunctionContext context,
  final ast.Expression root,
  final Value? Function(ast.Expression) evaluate, {
  final Value? cascadeReceiver,
  final dart.DartType? cascadeReceiverType,
  final bool cascadeNullAware = false,
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
    final explicitOverride = expression is ast.ExtensionOverride;
    if (expression is ast.ExtensionOverride) {
      if (expression.importPrefix?.element case final PrefixElement prefix
          when prefix.imports.any((i) => i.prefix?.isDeferred == true)) {
        unsupported(context.unit, expression, 'deferred extension override');
      }
      nullAware = nullAware || expression.isNullAware;
      expression = expression.argumentList.arguments.single.argumentExpression;
    }
    final value = cascaded
        ? cascadeReceiver
        : expression == null || expression is ast.SuperExpression
        ? context.receiver
        : explicitOverride
        ? evaluate(expression)
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
    final known = context.refined(value);
    // A type test can add a different view without subsuming the receiver's
    // original type (for example T extends a record, tested against U).
    return identical(known, value) || value.type.accepts(known.type)
        ? known
        : value;
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
      final resolved = arguments.parent;
      final application = context.extensionApplication(
        callMethod,
        resolved ?? node,
        receiver: resolved is ast.FunctionExpressionInvocation
            ? resolved.function
            : null,
      );
      // Virtual getter-call syntax reads the getter after the arguments. Other
      // receivers, including explicit overrides, are checked before arguments.
      if (getFunction == null) {
        input = context.memberReceiver(input, application);
        if (input == null) return null;
      }
      final args =
          resolved is ast.InvocationExpression &&
              resolved.staticInvokeType is dart.FunctionType
          ? context.arguments(arguments, evaluate)
          : context.dynamicArguments(arguments, evaluate);
      if (args == null) return null;
      var function = getFunction == null ? input : getFunction(input);
      if (function == null) return null;
      if (function.type is! FunctionType) {
        if (_structuralBound<FunctionType>(function.type)
            case final FunctionType bound) {
          function = context.cast(function, bound);
        }
      }
      if (application != null) {
        final receiver = context.memberReceiver(function, application);
        return receiver == null
            ? null
            : context.callExtension(application, receiver, args, typeArguments);
      }
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
      if (function.type is DynamicType ||
          function.type is! FunctionType &&
              ValueType.function.accepts(function.type)) {
        return context.dynamicMember(
          function,
          .method,
          'call',
          args.positional,
          args.named,
          typeArguments,
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
        function is ast.ExtensionOverride
            ? _receiver(function, false)
            : _visit(function),
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
        when target != null &&
                ValueType.function.accepts(
                  context.typeOf(target.staticType!, target).nonNullable,
                ) ||
            node.isCascaded &&
                cascadeReceiver != null &&
                ValueType.function.accepts(cascadeReceiver!.type.nonNullable)) {
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
      final application = context.extensionApplication(
        element,
        node,
        receiver: target,
        receiverType: cascadeReceiverType,
        unqualified: target == null && !node.isCascaded,
        nullAware: isNullAware || cascadeNullAware && node.isCascaded,
      );
      final converted = context.memberReceiver(receiver, application);
      if (converted == null) return null;
      final key = evaluate(index);
      if (key == null) return null;
      if (application == null &&
          (target?.staticType is dart.DynamicType ||
              node.isCascaded && cascadeReceiver?.type is DynamicType)) {
        return context.dynamicMember(receiver, .method, '[]', [key]);
      }
      return context.callPositionalMember(
        element,
        converted,
        [key],
        node,
        direct: target is ast.SuperExpression,
        extension: application,
      );
    }
    final (receiver, name, member, arguments, nullAware) = switch (node) {
      ast.PrefixedIdentifier(:final prefix, :final identifier)
          when prefix.staticType is dart.DynamicType ||
              prefix.staticType is dart.RecordType ||
              prefix.staticType != null &&
                  ValueType.function.accepts(
                    context.typeOf(prefix.staticType!, prefix).nonNullable,
                  ) &&
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
        target: final target,
        :final argumentList,
        :final isNullAware,
      )
          when target?.staticType is dart.DynamicType ||
              node.isCascaded && cascadeReceiver?.type is DynamicType =>
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
          when !method.isStatic &&
              (isClassLike(method.enclosingElement) ||
                  isExtensionOwner(method.enclosingElement)) =>
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
    if (member == null &&
        name == 'call' &&
        ValueType.function.accepts(known.type.nonNullable)) {
      return known;
    }
    if (member is ExecutableElement &&
        !member.isStatic &&
        isExtensionOwner(member.enclosingElement) &&
        coreEnumField(member) == null) {
      if (member is MethodElement && member.isOperator) {
        unsupported(context.unit, node, 'extension operator tear-off');
      }
      final cascaded = switch (node) {
        ast.PropertyAccess(:final isCascaded) ||
        ast.MethodInvocation(:final isCascaded) => isCascaded,
        _ => false,
      };
      final application = context.extensionApplication(
        member,
        node,
        receiver: receiver,
        receiverType: cascadeReceiverType,
        unqualified: receiver == null && !cascaded,
        nullAware: nullAware || cascadeNullAware && cascaded,
      )!;
      final converted = context.memberReceiver(known, application);
      if (converted == null) return null;
      if (member is GetterElement) {
        Value? get(Value value) => context.callPositionalMember(
          member,
          value,
          [],
          node,
          extension: application,
        );
        final invocation = getterArguments ?? arguments;
        if (invocation != null) {
          return invokeValue(get(converted), invocation, getterCall);
        }
        final value = get(converted);
        return value == null
            ? null
            : context.normal(
                context.cast(value, context.typeOf(node.staticType!, node)),
              );
      }
      if (arguments == null) {
        return context.bindExtension(application, converted, node);
      }
      final args = context.arguments(arguments, evaluate);
      if (args == null) return null;
      return context.callExtension(application, converted, args, typeArguments);
    }

    if (receiver?.staticType is dart.DynamicType ||
        known.type is DynamicType ||
        !direct &&
            member is MethodElement &&
            member.library.isDartCore &&
            member.enclosingElement?.name == 'Object' &&
            name == 'toString') {
      final invocation = getterArguments ?? arguments;
      final args = context.dynamicArguments(invocation, evaluate);
      if (args == null) return null;
      final value = context.dynamicMember(
        known,
        invocation == null ? .getter : .method,
        name,
        args.positional,
        args.named,
        typeArguments,
      );
      return value == null
          ? null
          : context.normal(
              context.cast(value, context.typeOf(node.staticType!, node)),
            );
    }
    final recordType = member == null
        ? _structuralBound<RecordType>(known.type)
        : null;
    if ((receiver?.staticType is dart.RecordType || recordType != null) &&
        member == null) {
      final owner =
          recordType ??
          context.typeOf(receiver!.staticType!, receiver).nonNullable
              as RecordType;
      final slot = owner.slots[name];
      if (slot == null) unsupported(context.unit, node, 'record member $name');
      final record = context.normal(context.cast(known, owner));
      return record == null
          ? null
          : context.normal(readRecordField(context, record, slot));
    }
    if (coreEnumField(member is ExecutableElement ? member : null)
        case final field?) {
      return context.normal(context.emit(LoadField(field, known)));
    }
    if (member is! ExecutableElement ||
        !isClassLike(member.enclosingElement) ||
        member.isStatic) {
      unsupported(context.unit, node, 'member $name');
    }
    if (coreRuntimeType(member)) {
      return context.callPositionalMember(
        member,
        known,
        [],
        node,
        direct: direct,
      );
    }
    final target = direct
        ? context.bindings.superTarget(
            context.receiver!.type,
            member,
            context.unit,
            node,
          )
        : context.bindings.target(member, context.unit, node);
    if (member.library.isDartCore &&
        (!direct || target.library.toString() == 'dart:core') &&
        member is GetterElement &&
        member.name == 'hashCode' &&
        (member.enclosingElement.name == 'Object' ||
            member.enclosingElement.name == 'Type' ||
            coreRuntimeMember(member))) {
      return context.normal(
        context.emit(ObjectHashCode(known, direct: direct)),
      );
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
    if (member is MethodElement && arguments == null) {
      return context.emit(BindMethod(target, known, direct: direct));
    }
    final args = context.arguments(arguments, evaluate);
    if (args == null) return null;
    if (member.library.isDartCore &&
        (!direct || target.library.toString() == 'dart:core') &&
        !coreRuntimeMember(member) &&
        (member is GetterElement || arguments != null)) {
      if (args.named.isEmpty) {
        final operation = lowerCoreCollectionMember(
          member,
          known,
          args.positional,
        );
        if (operation != null) return context.normal(context.emit(operation));
      }
    }
    Value? result(Instruction call) {
      final value = context.normal(context.emit(call));
      if (value == null || member is! GetterElement) return value;
      return context.normal(
        context.cast(value, context.typeOf(node.staticType!, node)),
      );
    }

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
      ClassElement() ||
      EnumElement() ||
      ExtensionElement() ||
      ExtensionTypeElement() =>
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
      final value = context.normal(read());
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
      final operatorMember = switch (site) {
        ast.MethodReferenceExpression(:final element) => element,
        _ => null,
      };
      final operation = context.extensionApplication(
        operatorMember,
        site,
        receiverType: site.readType,
      );
      final operand = context.memberReceiver(old, operation);
      if (operand == null) return null;
      final result = write(
        lowerBinary(
          context,
          site,
          operator,
          operand,
          rhs == null ? const Constant.integer(1) : evaluate(rhs),
          extension: operation,
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
    final cascaded = switch (place) {
      ast.PropertyAccess(:final isCascaded) ||
      ast.IndexExpression(:final isCascaded) => isCascaded,
      _ => false,
    };
    final receiver = _receiver(target, nullAware, cascaded: cascaded);
    if (receiver == null) return null;
    if ((target?.staticType is dart.DynamicType ||
            receiver.type is DynamicType) &&
        !(destination is ExecutableElement &&
            isExtensionOwner(destination.enclosingElement))) {
      final key = index == null ? null : evaluate(index);
      if (index != null && key == null) return null;
      final name = switch (place) {
        ast.PrefixedIdentifier(:final identifier) => identifier.name,
        ast.PropertyAccess(:final propertyName) => propertyName.name,
        ast.IndexExpression() => '[]',
        _ => unsupported(context.unit, place, 'dynamic assignment receiver'),
      };
      return apply(
        () => context.dynamicMember(
          receiver,
          index == null ? .getter : .method,
          name,
          [?key],
        ),
        (value) => context.dynamicMember(
          receiver,
          index == null ? .setter : .method,
          index == null ? name : '[]=',
          [?key, value],
        ),
      );
    }
    if (destination is! ExecutableElement ||
        destination.isStatic ||
        !(isClassLike(destination.enclosingElement) ||
            isExtensionOwner(destination.enclosingElement))) {
      unsupported(context.unit, site, 'assignment target');
    }
    ExtensionApplication? application(ExecutableElement? member) =>
        context.extensionApplication(
          member,
          site,
          receiver: target,
          receiverType: cascadeReceiverType,
          unqualified: target == null && !cascaded,
          nullAware: nullAware || cascadeNullAware && cascaded,
        );
    final writeApplication = application(destination);
    final readMember = site.readElement;
    final readApplication = application(
      readMember is ExecutableElement ? readMember : null,
    );
    final writeReceiver = context.memberReceiver(receiver, writeApplication);
    if (writeReceiver == null) return null;
    final readReceiver = context.memberReceiver(receiver, readApplication);
    if (readReceiver == null) return null;
    final inputKey = index == null ? null : evaluate(index);
    // Compound updates check the read key first. The write-key conversion
    // belongs to the setter call and is skipped entirely on a non-null ??=.
    final key = inputKey == null || operator.type != .EQ
        ? inputKey
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
        readReceiver,
        [?key],
        site,
        direct: direct,
        extension: readApplication,
      ),
      (value) => context.callPositionalMember(
        destination,
        writeReceiver,
        [?key, value],
        site,
        direct: direct,
        extension: writeApplication,
      ),
    );
  }
}

/// Finds a requested structural shape through either side of a promotion.
T? _structuralBound<T extends ValueType>(
  ValueType type, [
  Set<ValueType>? active,
]) {
  final base = type.nonNullable;
  if (base is T) return base;
  if (type is! TypeParameterType &&
      type is! PromotedTypeParameterType &&
      type is! NonNullableTypeParameterType) {
    return base == type ? null : _structuralBound<T>(base, active);
  }
  active ??= {};
  if (!active.add(type)) return null;
  try {
    return switch (type) {
      PromotedTypeParameterType(:final parameter, :final bound) =>
        _structuralBound<T>(bound, active) ??
            _structuralBound<T>(parameter, active),
      TypeParameterType(:final bound) => _structuralBound<T>(bound, active),
      NonNullableTypeParameterType(:final parameter) => _structuralBound<T>(
        parameter.bound,
        active,
      ),
      _ => null,
    };
  } finally {
    active.remove(type);
  }
}
