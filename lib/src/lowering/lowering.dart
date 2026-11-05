import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'checked_libraries.dart';
import 'class_declaration.dart';
import 'function.dart';
import 'global_declaration.dart';

/// The translation from resolved Dart declarations to executable IR operations.
abstract final class Lowering() {
  /// Returns class declarations and verified function bodies from [input].
  ///
  /// Assertions are omitted by default. Set [enableAssertions] to evaluate
  /// assertion conditions and raise assertion errors on failures.
  ///
  /// Calls to the same declaration share a target throughout the batch.
  /// Constants appear as operands at their uses. Throws
  /// [UnsupportedError] at the first source construct without an IR translation.
  static IrProgram lower(
    CheckedLibraries input, {
    bool enableAssertions = false,
  }) {
    final bindings = Bindings(enableAssertions: enableAssertions);
    for (final unit in input.libraries.expand((library) => library.units)) {
      for (final node in unit.unit.declarations) {
        switch (node) {
          case ast.ClassDeclaration():
            bindings.registerClass(node.declaredFragment!.element, unit, node);
          case ast.EnumDeclaration():
            bindings.registerClass(node.declaredFragment!.element, unit, node);
          default:
            break;
        }
      }
    }
    final functions = <IrFunction>[];
    final classes = <IrClass>[];
    for (final unit in input.libraries.expand((library) => library.units)) {
      for (final node in unit.unit.declarations) {
        switch (node) {
          case ast.TypeAlias():
            break;
          case ast.ClassDeclaration():
            classes.add(lowerClass(unit, bindings, node, functions));
          case ast.EnumDeclaration():
            classes.add(lowerEnum(unit, bindings, node, functions));
          case ast.FunctionDeclaration(
            declaredFragment: final fragment?,
            :final functionExpression,
          ):
            FunctionLowering.append(
              functions,
              unit,
              bindings,
              fragment.element,
              node,
              functionExpression.body,
            );
          case ast.TopLevelVariableDeclaration(variables: final declarations):
            for (final variable in declarations.variables) {
              lowerGlobal(unit, bindings, variable, functions);
            }
          default:
            unsupported(unit, node, 'declaration');
        }
      }
    }
    return IrProgram(classes, functions, globals: bindings.globals);
  }
}
