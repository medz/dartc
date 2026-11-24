import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';
import 'classes.dart';
import 'constructor.dart';
import 'coroutine.dart';
import 'coroutines.dart';
import 'extension_constructor.dart';
import 'levels.dart';
import 'members.dart';
import 'origins.dart';
import 'runtime_links.dart';
import 'scope.dart';
import 'statement.dart';
import 'types.dart';

/// The functions that sources declare, each translated once.
final class FunctionTable(
  final ProgramScope _scope,
  final Declarations _declarations,
) {
  final _functions = <(ExecutableElement, Level?), HirFunction>{};
  final _origins = Origins();

  Iterable<HirFunction> get all => _functions.values;

  /// Whether [element] is part of the program.
  bool contains(ExecutableElement element) =>
      _functions.containsKey((element, null));

  /// The function of [element], which can be a member of a level.
  ///
  /// Members of a mixin have one for each class that they are mixed in.
  HirFunction of(ExecutableElement element, [Level? given]) {
    final level = given ?? _ownLevel(element);
    return _functions.putIfAbsent((element, level), () {
      final by = _origins.current;
      _scope.schedule(() => _translate(element, level, by));
      final owner = element.enclosingElement;
      final result = element.returnType;
      final isInitializer = isInitializerElement(element);
      return HirFunction(
        owner is InstanceElement
            ? '${owner.displayName}.${element.lookupName}'
            : element.displayName,
        [
          if (level != null) plainType(level.element) ?? .reference,
          if (isExtensionMember(element))
            valueType(extendedType(element)!) ??
                (throw _declarations.unsupported(
                  element,
                  'extending ${extendedType(element)}',
                )),
          if (takesExtensionTypes(element) != null) .reference,
          if (takesTypes(element) != null) .reference,
          for (final parameter in element.formalParameters)
            valueType(parameter.type) ??
                (throw _declarations.unsupported(
                  element,
                  'a parameter of type ${parameter.type}',
                )),
        ],
        isInitializer ||
                hasNoResult(result) ||
                result is VoidType && RuntimeLinks.isRuntime(element.library)
            ? null
            : valueType(result) ??
                  (throw _declarations.unsupported(
                    element,
                    'a result of type $result',
                  )),
        !RuntimeLinks.isRuntime(element.library),
      );
    });
  }

  /// The level that a function works on objects of, if it is not a mixin's.
  Level? _ownLevel(ExecutableElement element) => hasReceiver(element)
      ? _scope.levelOf(element.enclosingElement as InterfaceElement)
      : null;

  void _translate(
    ExecutableElement element,
    Level? level,
    ExecutableElement? by,
  ) => _origins.within(element, by, () => _translateDeclared(element, level));

  void _translateDeclared(ExecutableElement element, Level? level) {
    final declared = _declarations[element];
    final owner = element.enclosingElement;
    final (unit, node) = declared ?? _declarations[owner as InterfaceElement]!;
    final builder = FunctionBuilder(
      unit,
      _functions[(element, level)]!,
      element.formalParameters,
      ownLevel: level,
      returnType: element.returnType,
      thisType: isExtensionMember(element) ? extendedType(element) : null,
      typeOwners: [?takesExtensionTypes(element), ?takesTypes(element)],
      captures: _scope.capturesOf(declarationOf(node)),
      cellClass: _scope.cellClass,
    );
    final statements = StatementTranslator(_scope, builder);
    if (isInitializerElement(element)) {
      ConstructorTranslator(
        _scope,
        _declarations,
        builder,
        statements,
      ).initializer(element as ConstructorElement);
    } else if (owner is ExtensionTypeElement &&
        element is ConstructorElement &&
        !element.isFactory) {
      ExtensionConstructorTranslator(
        _scope,
        builder,
        statements,
      ).translate(owner, node);
    } else {
      final body = switch (node) {
        FunctionDeclaration(
          functionExpression: FunctionExpression(:final body),
        ) ||
        MethodDeclaration(:final body) ||
        ConstructorDeclaration(:final body) => body,
        _ => throw StateError('Unexpected declaration $node.'),
      };
      final isNative =
          element.isExternal && _scope.natives.define(builder, element);
      if (isNative) {
        // It does only what the function of C does.
      } else if (CoroutineKind.of(body) case final kind?) {
        CoroutineTranslator(
          _scope,
          builder,
        ).start(body, kind, element.returnType, element.formalParameters);
      } else {
        statements.body(body);
      }
    }
    builder.finish();
  }
}
