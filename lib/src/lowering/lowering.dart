import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'checked_libraries.dart';
import 'class_declaration.dart';
import 'function.dart';

/// The translation from resolved Dart declarations to executable IR operations.
abstract final class Lowering() {
  /// Returns class declarations and verified function bodies from [input].
  ///
  /// Calls to the same declaration share a target throughout the batch.
  /// Constants appear as operands at their uses. Throws
  /// [UnsupportedError] at the first source construct without an IR translation.
  static IrProgram lower(CheckedLibraries input) {
    final bindings = Bindings();
    final functions = <IrFunction>[];
    final classes = <IrClass>[];
    for (final unit in input.libraries.expand((library) => library.units)) {
      for (final node in unit.unit.declarations) {
        switch (node) {
          case ast.TypeAlias():
            break;
          case ast.ClassDeclaration():
            classes.add(lowerClass(unit, bindings, node, functions));
          case ast.FunctionDeclaration(
            declaredFragment: TopLevelFunctionFragment(:final element),
            :final functionExpression,
          ):
            functions.add(
              FunctionLowering(
                unit,
                bindings,
                element,
                node,
                functionExpression.body,
              ).run(),
            );
          case ast.TopLevelVariableDeclaration(variables: final declarations)
              when declarations.isConst:
            for (final variable in declarations.variables) {
              bindings.constantOf(
                variable.declaredFragment!.element,
                unit,
                variable,
              );
            }
          default:
            unsupported(unit, node, 'declaration');
        }
      }
    }
    return IrProgram(classes, functions);
  }
}
