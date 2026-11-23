import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'function.dart';

/// Translates the program whose `main` is in [library].
///
/// Throws [CompileFailure] at the first construct not supported yet.
HirModule translateProgram(SourceLibrary library) {
  final entry = library.element.entryPoint;
  if (entry == null) {
    throw CompileFailure([
      library.units.first.problemAt(0, 'The program has no main function.'),
    ]);
  }
  for (final unit in library.units) {
    for (final declaration in unit.ast.declarations) {
      if (declaration is FunctionDeclaration &&
          declaration.declaredFragment?.element == entry) {
        return HirModule(FunctionTranslator(unit).translate(declaration));
      }
    }
  }
  throw CompileFailure([
    library.units.first.problemAt(
      0,
      'Not supported yet: main from another library.',
    ),
  ]);
}
