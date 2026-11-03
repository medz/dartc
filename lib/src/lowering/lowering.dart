import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'checked_libraries.dart';
import 'function.dart';

/// The translation from resolved Dart declarations to executable IR operations.
abstract final class Lowering() {
  /// Returns verified functions in the declaration order of [input].
  ///
  /// Calls to the same declaration share a target throughout the batch.
  /// Constants appear as operands at their uses. Throws
  /// [UnsupportedError] at the first source construct without an IR translation.
  static List<IrFunction> lower(CheckedLibraries input) {
    final bindings = TargetBindings();
    final functions = <IrFunction>[];
    for (final unit in input.libraries.expand((library) => library.units)) {
      for (final node in unit.unit.declarations) {
        switch (node) {
          case ast.FunctionDeclaration(
            declaredFragment: TopLevelFunctionFragment(:final element),
            :final functionExpression,
          ):
            functions.add(
              FunctionLowering(
                unit,
                bindings,
                element,
                functionExpression.body,
              ).run(),
            );
          case ast.TopLevelVariableDeclaration(variables: final declarations)
              when declarations.isConst:
            for (final variable in declarations.variables) {
              constantOf(variable.declaredFragment!.element, unit, variable);
            }
          default:
            unsupported(unit, node, 'declaration');
        }
      }
    }
    return functions;
  }
}
