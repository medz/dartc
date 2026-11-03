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
  /// Calls to the same declaration share a target throughout the batch. Throws
  /// [UnsupportedError] at the first source construct without an IR translation.
  static List<IrFunction> lower(CheckedLibraries input) {
    final bindings = TargetBindings();
    return [
      for (final library in input.libraries)
        for (final unit in library.units)
          for (final node in unit.unit.declarations)
            if (node case ast.FunctionDeclaration(
              declaredFragment: TopLevelFunctionFragment(:final element),
              :final functionExpression,
            ))
              FunctionLowering(
                unit,
                bindings,
                element,
                functionExpression.body,
              ).run()
            else
              unsupported(unit, node, 'declaration'),
    ];
  }
}
