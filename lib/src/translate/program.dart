import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'statement.dart';
import 'types.dart';

/// Translates everything the program's `main` can reach.
///
/// Throws [CompileFailure] at the first construct not supported yet.
HirModule translateProgram(SourceProgram program) =>
    ProgramTranslator(program).translate();

/// Finds the functions a program needs and translates each once.
final class ProgramTranslator(final SourceProgram program) {
  final _declarations =
      <TopLevelFunctionElement, (SourceUnit, FunctionDeclaration)>{};
  final _functions = <TopLevelFunctionElement, HirFunction>{};
  final _pending = <TopLevelFunctionElement>[];

  HirModule translate() {
    for (final library in program.libraries) {
      for (final unit in library.units) {
        for (final declaration in unit.ast.declarations) {
          if (declaration is! FunctionDeclaration) continue;
          final element = declaration.declaredFragment?.element;
          if (element is TopLevelFunctionElement) {
            _declarations[element] = (unit, declaration);
          }
        }
      }
    }
    final start = program.main.units.first;
    final entry = program.main.element.entryPoint;
    if (entry == null) {
      throw CompileFailure([
        start.problemAt(0, 'The program has no main function.'),
      ]);
    }
    if (entry.formalParameters.isNotEmpty) {
      throw _unsupported(entry, 'parameters of main');
    }
    final main = HirFunction(entry.displayName, const []);
    _functions[entry] = main;
    _pending.add(entry);
    while (_pending.isNotEmpty) {
      _translate(_pending.removeLast());
    }
    return HirModule(main, _functions.values);
  }

  /// The function of [element], or null if it is not part of the program.
  HirFunction? _functionFor(TopLevelFunctionElement element) {
    if (!_declarations.containsKey(element)) return null;
    return _functions.putIfAbsent(element, () {
      _pending.add(element);
      final result = element.returnType;
      return HirFunction(
        element.displayName,
        [
          for (final parameter in element.formalParameters)
            valueType(parameter.type) ??
                (throw _unsupported(
                  element,
                  'a parameter of type ${parameter.type}',
                )),
        ],
        hasNoResult(result)
            ? null
            : valueType(result) ??
                  (throw _unsupported(element, 'a result of type $result')),
      );
    });
  }

  CompileFailure _unsupported(TopLevelFunctionElement element, String what) {
    final (unit, declaration) = _declarations[element]!;
    return CompileFailure([
      unit.problemAt(declaration.name.offset, 'Not supported yet: $what.'),
    ]);
  }

  void _translate(TopLevelFunctionElement element) {
    final (unit, declaration) = _declarations[element]!;
    final expression = declaration.functionExpression;
    if (expression.typeParameters case final parameters?) {
      throw unit.unsupported(parameters, 'type parameters');
    }
    final body = expression.body;
    if (body.isAsynchronous || body.isGenerator) {
      throw unit.unsupported(body, 'async and generator functions');
    }
    final builder = FunctionBuilder(
      unit,
      _functions[element]!,
      element.formalParameters,
    );
    StatementTranslator(_functionFor, builder).body(body);
    builder.finish();
  }
}
