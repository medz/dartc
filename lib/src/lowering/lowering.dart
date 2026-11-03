import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'checked_libraries.dart';
import 'function.dart';

/// Converts checked functions to typed SSA in the order of their declarations.
abstract final class Lowering {
  /// Throws [UnsupportedError] with a source location for a Dart construct that
  /// has no IR translation yet.
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
