import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'classes.dart';
import 'conversions.dart';
import 'levels.dart';
import 'members.dart';
import 'scope.dart';
import 'statement.dart';
import 'types.dart';

/// Translates generative constructors.
final class ConstructorTranslator(
  final ProgramScope _scope,
  final Declarations _declarations,
  final FunctionBuilder _builder,
  final StatementTranslator _statements,
) {
  /// Sets fields, then runs the superclass's constructor, then the body.
  void initializer(ConstructorElement element) {
    final class_ = element.enclosingElement;
    final node = _declarations[element]?.$2 as ConstructorDeclaration?;
    if (element.isExternal) {
      throw _declarations.unsupported(element, 'external constructors');
    }
    final initializers = node?.initializers ?? const <ConstructorInitializer>[];
    for (final redirect
        in initializers.whereType<RedirectingConstructorInvocation>()) {
      _run(redirect.element!, redirect.argumentList, element);
      return;
    }
    final level = _builder.level!;
    if (_scope.argumentsOf(level) case final field?) {
      final list = _builder.typesOf(class_)!;
      _builder.add(HirStore(field, _builder.receiver!, list));
    }
    _setFields(level);
    for (final parameter in element.formalParameters) {
      if (parameter case FieldFormalParameterElement(:final field?)) {
        _store(field, _builder.read(parameter));
      }
    }
    SuperConstructorInvocation? explicit;
    for (final initializer in initializers) {
      switch (initializer) {
        case ConstructorFieldInitializer(
          fieldName: SimpleIdentifier(element: final FieldElement field),
        ):
          _store(
            field,
            _statements.expressions.valueTo(initializer.expression, field.type),
          );
        case SuperConstructorInvocation():
          explicit = initializer;
        case AssertInitializer():
          break;
        default:
          throw _builder.unit.unsupported(initializer, 'this initializer');
      }
    }
    final parent = explicit?.element ?? element.superConstructor;
    if (parent != null && !_isObject(parent)) {
      _run(
        parent,
        explicit?.argumentList,
        element,
        before: () => _setMixinFields(level),
      );
    } else {
      _setMixinFields(level);
    }
    if (node != null && node.body is! EmptyFunctionBody) {
      _statements.body(node.body);
    }
  }

  static bool _isObject(ConstructorElement element) =>
      switch (element.enclosingElement) {
        ClassElement(:final isDartCoreObject) => isDartCoreObject,
        _ => false,
      };

  void _setMixinFields(Level level) {
    for (final below in level.chain.skip(1).takeWhile((l) => l.isMixin)) {
      _builder.at(below, () => _setFields(below));
    }
  }

  /// Evaluates the initializers that the fields of [level] are declared with.
  void _setFields(Level level) {
    for (final field in ClassTable.instanceFields(level.element)) {
      if (_scope.fieldOf(level, field).isSet case final isSet?) {
        final no = _builder.add(HirConst(false));
        _builder.add(HirStore(isSet, _builder.receiver!, no));
        continue;
      }
      final declaration = _declarations[field]!.$2 as VariableDeclaration;
      final initializer = declaration.initializer;
      if (initializer == null) continue;
      _store(field, _statements.expressions.valueTo(initializer, field.type));
    }
  }

  void _store(FieldElement field, HirValue value) {
    final (value: place, :isSet) = _scope.fieldOf(_builder.level!, field);
    final given = Conversions(_scope, _builder).coerce(value, place.type);
    final object = _builder.receiver!;
    _builder.add(HirStore(place, object, given));
    if (isSet == null) return;
    _builder.add(HirStore(isSet, object, _builder.add(HirConst(true))));
  }

  /// The type arguments that [target] takes from [element].
  HirValue? _types(ConstructorElement target, ConstructorElement element) {
    final class_ = element.enclosingElement;
    final owner = takesTypes(target.baseElement);
    if (owner == null) return null;
    final own = _builder.typesOf(class_);
    if (owner == class_) return own;
    final given = class_.supertype!.typeArguments;
    final isSame =
        own != null &&
        given.length == class_.typeParameters.length &&
        given.indexed.every((e) => e.$2 == class_.thisType.typeArguments[e.$1]);
    if (isSame) return own;
    return _scope.typeList(_builder, class_.supertype!.typeArguments) ??
        (throw _declarations.unsupported(class_, 'these type arguments'));
  }

  /// Runs constructor [target] on the same object, passing on the super
  /// parameters of [element]. Does [before] after evaluating arguments.
  void _run(
    ConstructorElement target,
    ArgumentList? arguments,
    ConstructorElement element, {
    void Function()? before,
  }) {
    final supplied = arguments == null
        ? <FormalParameterElement, HirValue>{}
        : _statements.expressions.calls.supplied(arguments);
    final class_ = element.enclosingElement;
    if (class_ is ClassElement && class_.isMixinApplication) {
      // Its constructors take what those of its superclass do.
      for (final (i, parameter) in element.formalParameters.indexed) {
        supplied[target.baseElement.formalParameters[i]] = _builder.read(
          parameter,
        );
      }
    }
    for (final parameter in element.formalParameters) {
      if (parameter case SuperFormalParameterElement(
        :final superConstructorParameter?,
      )) {
        // A parameter passed on may be wider where it takes a number.
        supplied[superConstructorParameter.baseElement] =
            Conversions(_scope, _builder).coerce(
              _builder.read(parameter),
              valueType(superConstructorParameter.baseElement.type)!,
            );
      }
    }
    final function = _scope.initializerOf(target.baseElement);
    final given = [
      _builder.receiver!,
      ?_types(target, element),
      ..._statements.expressions.calls.ordered(target.baseElement, supplied),
    ];
    before?.call();
    final conversions = Conversions(_scope, _builder);
    _builder.call(
      HirCall(function, [
        for (final (i, value) in given.indexed)
          conversions.coerce(value, function.parameters[i]),
      ]),
    );
  }
}
