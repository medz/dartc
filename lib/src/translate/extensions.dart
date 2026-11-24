import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
// Only this tells the type arguments of the extensions used.
// ignore: implementation_imports
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

  /// The type arguments that [owner] has where a value of [type] is used.
  List<DartType> _typesOf(AstNode node, InstanceElement owner, DartType type) {
    if (owner is ExtensionTypeElement) {
      final found = switch (type) {
        TypeParameterType(:final bound) => bound,
        _ => type,
      };
      return (found as InterfaceType).asInstanceOf(owner)!.typeArguments;
    }
    owner as ExtensionElement;
    final found = [owner]
        .applicableTo(targetLibrary: _builder.library, targetType: type)
        .single;
    return [
      for (final parameter in owner.typeParameters)
        if (_mentions(owner.extendedType, parameter))
          found.substitution.map[parameter]!
        else
          _unsupported(
            node,
            'an extension that does not use its ${parameter.name}',
          ),
    ];
  }

  static bool _mentions(DartType type, TypeParameterElement parameter) =>
      switch (type) {
        TypeParameterType(:final element) => element == parameter,
        InterfaceType(:final typeArguments) => typeArguments.any(
          (argument) => _mentions(argument, parameter),
        ),
        FunctionType(:final returnType, :final formalParameters) =>
          _mentions(returnType, parameter) ||
              formalParameters.any((p) => _mentions(p.type, parameter)),
        RecordType() => fieldsOf(
          type,
        ).any((field) => _mentions(field, parameter)),
        _ => false,
      };

  HirValue? _types(AstNode node, ExecutableElement element, DartType? type) {
    final owner = takesExtensionTypes(element.baseElement);
    if (owner == null) return null;
    final types = _typesOf(node, owner, type!);
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
