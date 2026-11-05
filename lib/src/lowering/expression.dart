import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'collection.dart';
import 'function_context.dart';
import 'operators.dart';
import 'pattern.dart';
import 'record.dart';
import 'selectors.dart';

/// Returns the emitted operand, or `null` when [expression] cannot complete normally.
Value? lowerExpression(FunctionContext context, ast.Expression expression) =>
    context.normal(_lower(context, expression));

Value? _lower(FunctionContext context, ast.Expression expression) {
  final unit = context.unit;
  switch (expression) {
    case ast.TypeLiteral():
      final prefix = expression.type.importPrefix?.element;
      if (prefix is PrefixElement &&
          prefix.imports.any((i) => i.prefix?.isDeferred == true)) {
        unsupported(unit, expression, 'deferred type literal');
      }
      final type = context.typeOf(expression.type.type!, expression);
      return typeParametersIn(type).isEmpty
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
              member.enclosingElement is ClassElement ||
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
          member.enclosingElement is ClassElement) {
        final target = context.bindings.target(member, unit, expression);
        return context.emit(DirectCall(target, []));
      }
      unsupported(unit, expression, 'dot shorthand property');
    case ast.FunctionReference(:final function, :final typeArgumentTypes):
      final value = lowerExpression(context, function);
      return value == null
          ? null
          : context.instantiateFunction(value, typeArgumentTypes, expression);
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
      :final expression,
      :final element,
      :final typeArgumentTypes,
    ):
      final receiver = lowerExpression(context, expression);
      if (receiver == null) return null;
      if (element == null || element.enclosingElement is! ClassElement) {
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
      if (constructorName.type.importPrefix?.element
          case final PrefixElement prefix
          when prefix.imports.any((i) => i.prefix?.isDeferred == true)) {
        unsupported(unit, expression, 'deferred constructor tear-off');
      }
      final target = context.bindings.target(
        constructorName.element!,
        unit,
        expression,
      );
      final resolved = expression.staticType! as dart.FunctionType;
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
      if (expression is ast.PrefixedIdentifier && expression.isDeferred) {
        unsupported(unit, expression, 'deferred function tear-off');
      }
      return FunctionConstant(
        context.bindings.target(callee, unit, expression),
      );
    case ast.PropertyAccess(
          propertyName: ast.SimpleIdentifier(
            element: final MethodElement method,
          ),
          target: final target?,
        )
        when method.isStatic &&
            target is ast.PrefixedIdentifier &&
            !target.isDeferred:
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
        return context.bindings.constantValue(
          expression.computeConstantValue()?.value,
          unit,
          expression,
        );
      }
      if (ctor is! ConstructorElement) {
        unsupported(unit, expression, 'dot shorthand constructor');
      }
      final prefix = expression is ast.InstanceCreationExpression
          ? expression.constructorName.type.importPrefix?.element
          : null;
      if (prefix is PrefixElement &&
          prefix.imports.any((i) => i.prefix?.isDeferred == true)) {
        unsupported(unit, expression, 'deferred constructor');
      }
      final source = context.bindings.target(ctor, unit, expression);
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
      final value = direct
          ? context.receiver
          : lowerExpression(context, operand);
      if (value == null) return null;
      if (operator.type == .BANG) {
        final condition = context.normal(context.cast(value, .boolean));
        return condition == null
            ? null
            : context.emit(Equals(condition, const Constant.boolean(false)));
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
      if (exception != null) context.raise(exception);
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
      return context.cast(
        context.readLocal(variable),
        context.typeOf(expression.staticType!, expression),
      );
    case ast.Identifier(
          element: GetterElement(
            variable: final TopLevelVariableElement variable,
          ),
        )
        when variable.isConst:
      if (expression is ast.PrefixedIdentifier && expression.isDeferred) {
        unsupported(unit, expression, 'deferred constant');
      }
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
                callee.enclosingElement is ClassElement ||
            expression is ast.MethodInvocation &&
                callee is TopLevelFunctionElement:
      if (expression case ast.MethodInvocation(target: final receiver?)) {
        final prefix = receiver is ast.SimpleIdentifier
            ? receiver.element
            : null;
        final valid = switch (receiver) {
          _ when prefix is PrefixElement => !prefix.imports.any(
            (i) => i.prefix?.isDeferred == true,
          ),
          ast.Identifier(element: ClassElement())
              when callee is MethodElement =>
            receiver is! ast.PrefixedIdentifier || !receiver.isDeferred,
          _ => false,
        };
        if (!valid) {
          unsupported(unit, expression, 'call receiver');
        }
      }
      final target = context.bindings.target(callee, unit, expression);
      final args = context.arguments(
        argumentList,
        (e) => lowerExpression(context, e),
      );
      return args == null
          ? null
          : context.emit(
              DirectCall(
                target,
                context.bindings.bind(target, args),
                typeArguments: context.typeArguments(
                  typeArgumentTypes,
                  expression,
                ),
              ),
            );
    case ast.DotShorthandInvocation():
      unsupported(unit, expression, 'dot shorthand invocation');
    case ast.BinaryExpression(
      :final leftOperand,
      :final rightOperand,
      :final operator,
    ):
      final left = leftOperand is ast.SuperExpression
          ? context.receiver
          : lowerExpression(context, leftOperand);
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
