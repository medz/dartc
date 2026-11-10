import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'ffi.dart';
import 'collection.dart';
import 'function_context.dart';
import 'operators.dart';
import 'pattern.dart';
import 'record.dart';
import 'selectors.dart';

/// Returns the emitted operand, or `null` when [expression] cannot complete normally.
Value? lowerExpression(FunctionContext context, ast.Expression expression) =>
    context.normal(_lower(context, expression));

/// Operator overrides are receiver syntax, not first-class expression values.
Value? _operatorReceiver(FunctionContext context, ast.Expression expression) {
  if (expression is ast.ExtensionOverride) {
    if (expression.isNullAware) {
      unsupported(context.unit, expression, 'null-aware operator override');
    }
    expression = expression.argumentList.arguments.single.argumentExpression;
  }
  return expression is ast.SuperExpression
      ? context.receiver
      : lowerExpression(context, expression);
}

Value? _lower(FunctionContext context, ast.Expression expression) {
  final unit = context.unit;
  switch (expression) {
    case ast.AwaitExpression(expression: final operand):
      final value = lowerExpression(context, operand);
      return value == null
          ? null
          : context.awaitValue(
              value,
              context.typeOf(expression.staticType!, expression),
            );
    case ast.TypeLiteral():
      context.checkDeferred(expression.type);
      final type = context.typeOf(expression.type.type!, expression);
      return type.freeTypeParameters.isEmpty
          ? TypeConstant(type)
          : context.emit(ReifyType(type));
    case ast.ListLiteral() || ast.SetOrMapLiteral():
      return lowerCollection(
        context,
        expression as ast.TypedLiteral,
        (e) => lowerExpression(context, e),
      );
    case ast.CascadeExpression():
      final receiver = lowerExpression(context, expression.target);
      if (receiver == null) return null;
      Value? sections() {
        for (final section in expression.cascadeSections) {
          SelectorChain(
            context,
            section,
            (e) => lowerExpression(context, e),
            cascadeReceiver: context.refined(receiver),
            cascadeReceiverType: expression.target.staticType,
            cascadeNullAware: expression.isNullAware,
          ).lower();
          if (context.current == null) return null;
        }
        return receiver;
      }

      return expression.isNullAware
          ? context.branch(
              context.testType(receiver, .nullType, negated: true),
              sections,
              () => const Constant.nullValue(),
              context.typeOf(expression.staticType!, expression),
            )
          : sections();
    case ast.DotShorthandPropertyAccess():
      final member = expression.propertyName.element;
      if (member is MethodElement &&
              member.isStatic &&
              (isClassLike(member.enclosingElement) ||
                  isExtensionOwner(member.enclosingElement)) ||
          member is ConstructorElement) {
        return FunctionConstant(
          context.bindings.target(
            member as ExecutableElement,
            unit,
            expression,
          ),
        );
      }
      if (member is GetterElement && member.variable.isConst) {
        return context.bindings.constantOf(member.variable, unit, expression);
      }
      if (member is GetterElement &&
          member.isStatic &&
          (isClassLike(member.enclosingElement) ||
              isExtensionOwner(member.enclosingElement))) {
        final target = context.bindings.target(member, unit, expression);
        return context.emit(DirectCall(target, []));
      }
      unsupported(unit, expression, 'dot shorthand property');
    case ast.FunctionReference(:final function, :final typeArgumentTypes):
      final value = lowerExpression(context, function);
      if (value == null) return null;
      return context.bindings.tryConstantExpression(unit, expression) ??
          context.instantiateFunction(value, typeArgumentTypes, expression);
    case ast.FunctionExpression():
      return context.close(expression);
    case ast.SimpleIdentifier(element: final LocalFunctionElement local):
      return context.readLocal(local);
    case ast.MethodInvocation(
      methodName: ast.SimpleIdentifier(
        element: final LocalFunctionElement local,
      ),
      target: null,
      :final argumentList,
    ):
      final function = context.readLocal(local);
      final args = context.arguments(
        argumentList,
        (e) => lowerExpression(context, e),
      );
      return args == null
          ? null
          : context.emit(
              FunctionCall(
                function,
                args.positional,
                args.named,
                context.typeArguments(expression.typeArgumentTypes, expression),
              ),
            );
    case ast.ThisExpression():
      return context.receiver!;
    case ast.ImplicitCallReference(
      expression: final operand,
      :final element,
      :final typeArgumentTypes,
    ):
      final receiver = lowerExpression(context, operand);
      if (receiver == null) return null;
      final application = context.extensionApplication(
        element,
        expression,
        receiver: operand,
      );
      if (application != null) {
        final checked = context.memberReceiver(receiver, application);
        return checked == null
            ? null
            : context.instantiateFunction(
                context.bindExtension(application, checked, expression),
                typeArgumentTypes,
                expression,
              );
      }
      if (element == null || !isClassLike(element.enclosingElement)) {
        unsupported(unit, expression, 'implicit call tear-off');
      }
      return context.instantiateFunction(
        context.emit(
          BindMethod(
            context.bindings.target(element, unit, expression),
            receiver,
          ),
        ),
        typeArgumentTypes,
        expression,
      );
    case ast.ConstructorReference(:final constructorName):
      context.checkDeferred(constructorName.type);
      final target = context.bindings.target(
        constructorName.element!,
        unit,
        expression,
      );
      final resolved = expression.staticType! as dart.FunctionType;
      final arguments = resolved.typeParameters.isNotEmpty
          ? const <ValueType>[]
          : context.typeArguments(
              (resolved.returnType as dart.InterfaceType).typeArguments,
              expression,
            );
      if (resolved.typeParameters.isEmpty &&
          arguments.isNotEmpty &&
          (arguments.any((type) => type.freeTypeParameters.isNotEmpty) ||
              context
                  .typeArguments(
                    constructorName.type.typeArguments?.arguments.map(
                      (type) => type.type!,
                    ),
                    expression,
                  )
                  .any((type) => type.freeTypeParameters.isNotEmpty))) {
        return context.emit(
          InstantiateFunction(FunctionConstant(target), arguments),
        );
      }
      if (constructorName.element!.enclosingElement is ExtensionTypeElement) {
        if (constructorName.type.element case final TypeAliasElement alias
            when resolved.typeParameters.isNotEmpty) {
          return context.bindings.constructorAliasConstant(
            alias,
            target,
            unit,
            expression,
          );
        }
        return FunctionConstant(
          target,
          typeArguments: resolved.typeParameters.isNotEmpty ? null : arguments,
        );
      }
      final signature = context.typeOf(resolved, expression) as FunctionType;
      final generic = signature.typeParameters.isNotEmpty;
      final alias = constructorName.type.element;
      final original = target.tearOffSignature();
      final distinctAlias =
          generic &&
          alias is TypeAliasElement &&
          !(signature.accepts(original) && original.accepts(signature));
      return FunctionConstant(
        target,
        ownerType: generic ? null : signature.result as ClassType,
        constructorSignature: generic ? signature : null,
        constructorAlias: distinctAlias
            ? (alias.library.uri, alias.name!)
            : null,
      );
    case ast.Identifier(element: final ExecutableElement callee)
        when callee is TopLevelFunctionElement ||
            callee is MethodElement && callee.isStatic:
      if (callee is TopLevelFunctionElement && callee.isOriginLoadLibrary) {
        return FunctionConstant(
          context.bindings.deferredImport(expression)!.loader.target,
        );
      }
      context.checkDeferred(expression);
      return FunctionConstant(
        context.bindings.target(callee, unit, expression),
      );
    case ast.PropertyAccess(
          propertyName: ast.SimpleIdentifier(
            element: final MethodElement method,
          ),
          target: final target?,
        )
        when method.isStatic && target is ast.PrefixedIdentifier:
      context.checkDeferred(target);
      return FunctionConstant(
        context.bindings.target(method, unit, expression),
      );
    case ast.DotShorthandConstructorInvocation(
          :final isConst,
          :final argumentList,
          element: final ctor,
        ) ||
        ast.InstanceCreationExpression(
          :final isConst,
          :final argumentList,
          constructorName: ast.ConstructorName(element: final ctor),
        ):
      if (isConst) {
        return context.bindings.constantExpression(unit, expression);
      }
      if (ctor is! ConstructorElement) {
        unsupported(unit, expression, 'dot shorthand constructor');
      }
      if (expression is ast.InstanceCreationExpression) {
        context.checkDeferred(expression.constructorName.type);
      }
      if (ffiClass(ctor.enclosingElement) == FfiTypes.pointer) {
        final args = context.arguments(
          argumentList,
          (e) => lowerExpression(context, e),
        );
        if (args == null) return null;
        final value = lowerFfi(
          ctor,
          args.positional,
          context.emit,
          result: context.typeOf(expression.staticType!, expression),
        );
        if (value != null) return value;
        unsupported(unit, expression, 'native pointer construction');
      }
      final source = context.bindings.target(ctor, unit, expression);
      if (ctor.enclosingElement is ExtensionTypeElement) {
        final args = context.arguments(
          argumentList,
          (e) => lowerExpression(context, e),
        );
        return args == null
            ? null
            : context.emit(
                DirectCall(
                  source,
                  context.bindings.bind(source, args),
                  typeArguments: context.typeArguments(
                    (expression.staticType! as dart.InterfaceType)
                        .typeArguments,
                    expression,
                  ),
                ),
              );
      }
      final construction = source.resolveConstruction(
        context.typeOf(expression.staticType!, expression) as ClassType,
      );
      final target = construction.target;
      final args = context.arguments(
        argumentList,
        (e) => lowerExpression(context, e),
      );
      if (args == null) return null;
      final bound = context.bindings.bind(target, args);
      final instanceType = construction.ownerType;
      return context.emit(
        target.kind == .factory
            ? DirectCall(target, bound, ownerType: instanceType)
            : Construct(target, bound, instantiatedType: instanceType),
      );
    case ast.SymbolLiteral():
      return context.bindings.constantExpression(unit, expression);
    case ast.BooleanLiteral(:final value):
      return Constant.boolean(value);
    case ast.IntegerLiteral():
      return _integerLiteral(context, expression, expression, negated: false);
    case ast.PrefixExpression(
      operator: Token(type: .MINUS),
      operand: final ast.IntegerLiteral literal,
    ):
      return _integerLiteral(context, expression, literal, negated: true);
    case ast.DoubleLiteral(:final value):
      return Constant.floating(value);
    case ast.PrefixExpression(
      operator: Token(type: .MINUS),
      operand: ast.DoubleLiteral(:final value),
    ):
      return Constant.floating(-value);
    case ast.PrefixExpression(:final operand, :final operator, :final element)
        when operator.type == .MINUS ||
            operator.type == .TILDE ||
            operator.type == .BANG:
      final direct = operand is ast.SuperExpression;
      final input = _operatorReceiver(context, operand);
      if (input == null) return null;
      final application = context.extensionApplication(
        element,
        expression,
        receiver: operand,
      );
      final value = context.memberReceiver(input, application);
      if (value == null) return null;
      if (operator.type == .BANG) {
        final condition = context.normal(context.cast(value, .boolean));
        return condition == null
            ? null
            : context.emit(Equals(condition, const Constant.boolean(false)));
      }
      if (application == null && operand.staticType is dart.DynamicType) {
        return context.dynamicMember(
          value,
          .method,
          operator.type == .MINUS ? 'unary-' : '~',
          [],
        );
      }
      if (value.type == .integer && element?.library.isDartCore == true) {
        return context.emit(
          operator.type == .TILDE
              ? IntBinary(.bitXor, value, const Constant.integer(-1))
              : IntBinary(.subtract, const Constant.integer(0), value),
        );
      }
      if (operator.type == .MINUS &&
          ValueType.number.accepts(value.type) &&
          element?.library.isDartCore == true) {
        return context.emit(NumericNegate(value));
      }
      return context.callPositionalMember(
        element,
        value,
        [],
        expression,
        direct: direct,
        extension: application,
      );
    case ast.NullLiteral():
      return const Constant.nullValue();
    case ast.RecordLiteral():
      return lowerRecord(
        context,
        expression,
        (e) => lowerExpression(context, e),
      );
    case ast.PatternAssignment(:final pattern, :final expression):
      return assignPattern(
        context,
        pattern,
        lowerExpression(context, expression),
      );
    case ast.StringLiteral(stringValue: final value?):
      return Constant.string(value);
    case ast.StringLiteral():
      final parts = <Value>[];
      bool append(ast.StringLiteral literal) {
        switch (literal) {
          case ast.AdjacentStrings(:final strings):
            for (final string in strings) {
              if (!append(string)) return false;
            }
          case ast.StringInterpolation(:final elements):
            for (final element in elements) {
              switch (element) {
                case ast.InterpolationString(:final value):
                  parts.add(Constant.string(value));
                case ast.InterpolationExpression(:final expression):
                  var nested = expression;
                  while (nested is ast.ParenthesizedExpression) {
                    nested = nested.expression;
                  }
                  if (nested is ast.StringLiteral) {
                    if (!append(nested)) return false;
                    continue;
                  }
                  final value = lowerExpression(context, expression);
                  if (value == null) return false;
                  parts.add(value);
              }
            }
          case ast.SimpleStringLiteral(:final value):
            parts.add(Constant.string(value));
        }
        return true;
      }
      return append(expression) ? context.emit(Interpolate(parts)) : null;
    case ast.ParenthesizedExpression(:final expression):
      return lowerExpression(context, expression);
    case ast.IsExpression(:final expression, :final type, :final notOperator):
      final input = lowerExpression(context, expression);
      return input == null
          ? null
          : context.testType(
              input,
              context.typeOf(type.type!, type),
              negated: notOperator != null,
            );
    case ast.AsExpression(:final expression, :final type):
      final input = lowerExpression(context, expression);
      return input == null
          ? null
          : context.cast(input, context.typeOf(type.type!, type));
    case ast.ThrowExpression(:final expression):
      final exception = lowerExpression(context, expression);
      if (exception != null) {
        context.raise(context.convert(exception, .object));
      }
      return null;
    case ast.RethrowExpression():
      final (exception, trace) = context.caught!;
      context.raise(exception, trace);
      return null;
    case ast.ConditionalExpression(
      :final condition,
      :final thenExpression,
      :final elseExpression,
    ):
      final test = lowerExpression(context, condition);
      if (test == null) return null;
      return context.branch(
        test,
        () => lowerExpression(context, thenExpression),
        () => lowerExpression(context, elseExpression),
        context.typeOf(expression.staticType!, expression),
      );
    case ast.SwitchExpression():
      final subject = lowerExpression(context, expression.expression);
      if (subject == null) return null;
      final done = JumpTarget(context, [
        context.typeOf(expression.staticType!, expression),
      ]);
      final cache = PatternCache(
        context,
        expression.cases.map((arm) => arm.guardedPattern.pattern),
      );
      for (final arm in expression.cases) {
        final next = JumpTarget(context);
        context.inScope(() {
          matchGuarded(
            context,
            arm.guardedPattern,
            subject,
            next,
            (e) => lowerExpression(context, e),
            cache,
          );
          if (context.current == null) return;
          final result = lowerExpression(context, arm.expression);
          if (result != null) done.jump([result]);
        });
        if (next.enter() == null) break;
      }
      context.exhaustivenessFailure();
      return done.enter()?.parameters.first;
    case ast.SimpleIdentifier(element: final VariableElement variable)
        when context.hasLocal(variable):
      final value = context.normal(context.readLocal(variable));
      return value == null
          ? null
          : context.cast(
              value,
              context.typeOf(expression.staticType!, expression),
            );
    case ast.Identifier(
          element: GetterElement(
            variable: final TopLevelVariableElement variable,
          ),
        )
        when variable.isConst:
      context.checkDeferred(expression);
      return context.bindings.constantOf(variable, unit, expression);
    case ast.PrefixedIdentifier() ||
        ast.PropertyAccess() ||
        ast.SimpleIdentifier(element: GetterElement()) ||
        ast.SimpleIdentifier(element: MethodElement(isStatic: false)) ||
        ast.FunctionExpressionInvocation() ||
        ast.MethodInvocation(
          methodName: ast.SimpleIdentifier(element: null || GetterElement()),
        ) ||
        ast.MethodInvocation(
          methodName: ast.SimpleIdentifier(
            element: MethodElement(isStatic: false),
          ),
        ) ||
        ast.IndexExpression() ||
        ast.CompoundAssignmentExpression():
      return SelectorChain(
        context,
        expression,
        (e) => lowerExpression(context, e),
      ).lower();
    case ast.DotShorthandInvocation(
              memberName: ast.SimpleIdentifier(
                element: final ExecutableElement callee,
              ),
              :final argumentList,
              :final typeArgumentTypes,
            ) ||
            ast.MethodInvocation(
              methodName: ast.SimpleIdentifier(
                element: final ExecutableElement callee,
              ),
              :final argumentList,
              :final typeArgumentTypes,
            )
        when callee is MethodElement &&
                callee.isStatic &&
                (isClassLike(callee.enclosingElement) ||
                    isExtensionOwner(callee.enclosingElement)) ||
            expression is ast.MethodInvocation &&
                callee is TopLevelFunctionElement:
      FunctionTarget? loadLibrary;
      if (expression case ast.MethodInvocation(target: final receiver?)) {
        final prefix = receiver is ast.SimpleIdentifier
            ? receiver.element
            : null;
        final valid = switch (receiver) {
          _ when prefix is PrefixElement => true,
          ast.Identifier(
            element: ClassElement() ||
                EnumElement() ||
                ExtensionElement() ||
                ExtensionTypeElement(),
          )
              when callee is MethodElement =>
            true,
          _ => false,
        };
        if (!valid) {
          unsupported(unit, expression, 'call receiver');
        }
        if (callee is TopLevelFunctionElement && callee.isOriginLoadLibrary) {
          loadLibrary = context.bindings
              .deferredImport(receiver)!
              .loader
              .target;
        } else {
          context.checkDeferred(receiver);
        }
      }
      final target =
          loadLibrary ?? context.bindings.target(callee, unit, expression);
      final args = context.arguments(
        argumentList,
        (e) => lowerExpression(context, e),
      );
      if (args == null) return null;
      if (callee.library.uri == Uri.parse('dart:math') &&
          callee.baseElement == callee.library.getTopLevelFunction('sqrt')) {
        return context.emit(NumericSquareRoot(args.positional.single));
      }
      return context.emit(
        DirectCall(
          target,
          context.bindings.bind(target, args),
          typeArguments: context.typeArguments(typeArgumentTypes, expression),
        ),
      );
    case ast.DotShorthandInvocation():
      unsupported(unit, expression, 'dot shorthand invocation');
    case ast.BinaryExpression(
      :final leftOperand,
      :final rightOperand,
      :final operator,
    ):
      final input = _operatorReceiver(context, leftOperand);
      if (input == null) return null;
      final application = context.extensionApplication(
        expression.element,
        expression,
        receiver: leftOperand,
      );
      final left = context.memberReceiver(input, application);
      if (left == null) return null;
      if (operator.type == .QUESTION_QUESTION) {
        return context.ifNull(
          left,
          context.typeOf(expression.staticType!, expression),
          () => lowerExpression(context, rightOperand),
        );
      }
      if (operator.type == .AMPERSAND_AMPERSAND || operator.type == .BAR_BAR) {
        final and = operator.type == .AMPERSAND_AMPERSAND;
        if (left case ScalarConstant(value: final bool value)) {
          if (value != and) return left;
          final right = lowerExpression(context, rightOperand);
          return right == null ? null : context.convert(right, .boolean);
        }
        return context.shortCircuit(
          left,
          evaluateWhen: and,
          skipped: left,
          resultType: .boolean,
          right: () => lowerExpression(context, rightOperand),
        );
      }
      return lowerBinary(
        context,
        expression,
        operator,
        left,
        lowerExpression(context, rightOperand),
        extension: application,
      );
    default:
      unsupported(
        unit,
        expression,
        'expression starting with ${expression.beginToken.lexeme}',
      );
  }
}

Constant _integerLiteral(
  FunctionContext context,
  ast.Expression site,
  ast.IntegerLiteral literal, {
  required bool negated,
}) {
  if (site.staticType!.isDartCoreDouble) {
    if (literal.parseDoubleValue(negated: negated) case final d?) {
      return .floating(d);
    }
  } else if (literal.parseIntValue(negated: negated) case final i?) {
    return .integer(i);
  }
  unsupported(context.unit, site, 'numeric literal');
}
