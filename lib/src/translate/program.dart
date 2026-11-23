import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'classes.dart';
import 'constructor.dart';
import 'dispatch.dart';
import 'scope.dart';
import 'statement.dart';
import 'types.dart';

/// Translates everything the program's `main` can reach.
///
/// Throws [CompileFailure] at the first construct not supported yet.
HirModule translateProgram(SourceProgram program) =>
    ProgramTranslator(program).translate();

/// Finds the functions a program needs and translates each once.
///
/// Functions, classes and selectors only grow and are bounded by the source.
final class ProgramTranslator(final SourceProgram program)
    implements ProgramScope {
  late final _declarations = Declarations(program);
  late final _classes = ClassTable(_declarations);
  late final _dispatch = DispatchBuilder(_declarations, memberOf, fieldOf);
  final _functions = <ExecutableElement, HirFunction>{};
  final _pending = <ExecutableElement>[];

  HirModule translate() {
    final start = program.main.units.first;
    final entry = program.main.element.entryPoint;
    if (entry == null) {
      throw CompileFailure([
        start.problemAt(0, 'The program has no main function.'),
      ]);
    }
    if (entry.formalParameters.isNotEmpty) {
      throw _declarations.unsupported(entry, 'parameters of main');
    }
    final main = HirFunction(entry.displayName, const []);
    _functions[entry] = main;
    _pending.add(entry);
    do {
      while (_pending.isNotEmpty) {
        _translate(_pending.removeLast());
      }
    } while (_dispatch.update() || _pending.isNotEmpty);
    return HirModule(
      main,
      [..._functions.values, ..._dispatch.made],
      classes: _dispatch.classes.map(_classes.classOf),
      dispatch: _dispatch.result(_classes.classOf),
    );
  }

  @override
  HirFunction? functionOf(ExecutableElement element) =>
      _declarations[element] == null ? null : _declare(element);

  @override
  HirFunction memberOf(ExecutableElement element) => _declare(element);

  @override
  HirFunction initializerOf(ConstructorElement element) => _declare(element);

  @override
  HirFunction factoryOf(ConstructorElement element) {
    if (element.redirectedConstructor != null) {
      throw _declarations.unsupported(element, 'redirecting factories');
    }
    return _declare(element);
  }

  @override
  HirClass createdClass(ClassElement element) {
    final class_ = _classes.classOf(element);
    _dispatch.instantiate(element);
    return class_;
  }

  @override
  HirField fieldOf(FieldElement element) => _classes.fieldOf(element);

  @override
  HirSelector selectorOf(
    ExecutableElement member,
    ClassElement receiver,
    int positional,
    List<String> named,
    Reject reject,
  ) => _dispatch.selectorOf(member, receiver, positional, named, reject);

  HirFunction _declare(ExecutableElement element) =>
      _functions.putIfAbsent(element, () {
        _pending.add(element);
        final owner = element.enclosingElement;
        final result = element.returnType;
        final isInitializer = isInitializerElement(element);
        return HirFunction(
          owner is InstanceElement
              ? '${owner.displayName}.${element.lookupName}'
              : element.displayName,
          [
            if (hasReceiver(element)) .reference,
            for (final parameter in element.formalParameters)
              valueType(parameter.type) ??
                  (throw _declarations.unsupported(
                    element,
                    'a parameter of type ${parameter.type}',
                  )),
          ],
          isInitializer || hasNoResult(result)
              ? null
              : valueType(result) ??
                    (throw _declarations.unsupported(
                      element,
                      'a result of type $result',
                    )),
        );
      });

  void _translate(ExecutableElement element) {
    final declared = _declarations[element];
    final owner = element.enclosingElement;
    final (unit, node) = declared ?? _declarations[owner as ClassElement]!;
    final builder = FunctionBuilder(
      unit,
      _functions[element]!,
      element.formalParameters,
      receiverClass: hasReceiver(element) ? owner as ClassElement : null,
    );
    final statements = StatementTranslator(this, builder);
    if (isInitializerElement(element)) {
      ConstructorTranslator(
        this,
        _declarations,
        builder,
        statements,
      ).initializer(element as ConstructorElement);
    } else {
      final (parameters, body) = switch (node) {
        FunctionDeclaration(
          functionExpression: FunctionExpression(
            :final typeParameters,
            :final body,
          ),
        ) ||
        MethodDeclaration(
          :final typeParameters,
          :final body,
        ) => (typeParameters, body),
        ConstructorDeclaration(:final body) => (null, body),
        _ => throw StateError('Unexpected declaration $node.'),
      };
      if (parameters != null) {
        throw unit.unsupported(parameters, 'type parameters');
      }
      if (body.isAsynchronous || body.isGenerator) {
        throw unit.unsupported(body, 'async and generator functions');
      }
      statements.body(body);
    }
    builder.finish();
  }
}
