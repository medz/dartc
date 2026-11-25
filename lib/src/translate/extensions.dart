// Some imports here alone tell the type arguments of the extensions used.
// ignore_for_file: implementation_imports
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/member.dart'
    show SubstitutedElementImpl;
import 'package:analyzer/src/dart/resolver/applicable_extensions.dart'
    show ExtensionsExtensions;
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'members.dart';
import 'native_members.dart';
import 'native_types.dart';
import 'scope.dart';
import 'types.dart';

/// Translates uses of members that extensions and extension types declare,
/// which are functions taking the value that they are used on.
final class ExtensionTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  late final _conversions = Conversions(_scope, _builder);
  late final _natives = NativeMembers(_scope, _builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// The type arguments that [owner] has where [node] uses [element] on a value
  /// of [type].
  List<DartType> _typesOf(
    AstNode node,
    ExecutableElement element,
    InstanceElement owner,
    DartType type,
  ) {
    if (owner is ExtensionTypeElement) {
      var found = type;
      while (found is TypeParameterType) {
        found = found.bound;
      }
      return (found as InterfaceType).asInstanceOf(owner)!.typeArguments;
    }
    // Elements whose types need no type arguments do not tell them.
    if (_override(node, element)?.typeArgumentTypes case final types?) {
      return types;
    }
    final substitution = switch (element) {
      SubstitutedElementImpl(:final substitution) => substitution,
      _ =>
        [owner as ExtensionElement]
            .applicableTo(targetLibrary: _builder.library, targetType: type)
            .single
            .substitution,
    };
    return [
      for (final parameter in owner.typeParameters)
        substitution.map[parameter]!,
    ];
  }

  /// Whether [node] uses [element] without naming a receiver.
  static bool _omitsReceiver(AstNode node, ExecutableElement element) =>
      switch (node) {
        SimpleIdentifier() => true,
        MethodInvocation(:final realTarget) => realTarget == null,
        AssignmentExpression(leftHandSide: final place) ||
        PostfixExpression(operand: final place) ||
        PrefixExpression(operand: final place) =>
          // Operators are used on the value that is there.
          place is SimpleIdentifier && element is! MethodElement,
        _ => false,
      };

  /// What [node] uses [element] on, if it names the extension.
  static ExtensionOverride? _override(AstNode node, ExecutableElement element) {
    final isPlace = element is! MethodElement || element.name!.startsWith('[');
    final on = switch (node) {
      AssignmentExpression(leftHandSide: final place) ||
      PostfixExpression(operand: final place) ||
      PrefixExpression(
        operator: Token(type: TokenType.PLUS_PLUS || TokenType.MINUS_MINUS),
        operand: final place,
      ) => isPlace ? _target(place) : null,
      BinaryExpression(:final leftOperand) => leftOperand,
      _ => _target(node),
    };
    return switch (on?.unParenthesized) {
      final ExtensionOverride override => override,
      _ => null,
    };
  }

  static Expression? _target(AstNode node) => switch (node) {
    MethodInvocation(:final target) ||
    PropertyAccess(:final target) ||
    IndexExpression(:final target) => target,
    PrefixExpression(:final operand) => operand,
    FunctionExpressionInvocation(:final function) => function,
    _ => null,
  };

  HirValue? _types(AstNode node, ExecutableElement element, DartType? type) {
    final owner = takesExtensionTypes(element.baseElement);
    if (owner == null) return null;
    if (owner is ExtensionElement &&
        element is! SubstitutedElementImpl &&
        _omitsReceiver(node, element)) {
      // A bare reference in a class can also resolve to an extension member.
      if (_builder.typesOf(owner) case final types?) return types;
    }
    final types = _typesOf(node, element, owner, type!);
    return _scope.typeList(_builder, types) ??
        _unsupported(node, 'these type arguments');
  }

  /// What members like [element] take first.
  HirValue _receiver(ExecutableElement element, HirValue value) => _conversions
      .coerce(value, valueType(extendedType(element.baseElement)!)!);

  /// Uses [element] on [receiver], giving its own [types] after those of the
  /// extension.
  HirValue? use(
    AstNode node,
    (HirValue, DartType?) receiver,
    ExecutableElement element,
    List<HirValue> positional,
    Map<String, HirValue> named,
    HirValue? types,
  ) {
    final (value, type) = receiver;
    final base = element.baseElement;
    if (NativeTypes.isFfi(base) && type != null) {
      final found = _natives.use(node, (value, type), base, positional);
      if (found != null) return found.result;
    }
    if (fieldOfAccessor(base) != null) return value;
    final function =
        _scope.functionOf(base) ??
        _unsupported(node, 'calling ${element.displayName} of the SDK');
    var position = 0;
    final arguments = [
      _receiver(element, value),
      ?_types(node, element, type),
      ?types,
      for (final parameter in base.formalParameters)
        if (parameter.isNamed)
          named[parameter.name] ?? _builder.add(_scope.defaultOf(parameter))
        else if (position < positional.length)
          positional[position++]
        else
          _builder.add(_scope.defaultOf(parameter)),
    ];
    final result = _builder.call(
      HirCall(function, [
        for (final (i, argument) in arguments.indexed)
          _conversions.coerce(argument, function.parameters[i]),
      ]),
    );
    if (isNever(element.returnType)) _builder.end(HirUnreachable());
    return result;
  }

  /// Gives the method [element] of [receiver] as a function.
  HirValue tearOff(
    AstNode node,
    (HirValue, DartType?) receiver,
    MethodElement element,
  ) {
    final (value, type) = receiver;
    return _scope.extensionTearOff(
      _builder,
      element.baseElement,
      _receiver(element, value),
      _types(node, element, type),
    );
  }
}
