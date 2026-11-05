import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function.dart';
import 'global_declaration.dart';

/// Emits extension bodies as static targets with explicit receiver parameters.
void lowerExtension(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.ExtensionDeclaration declaration,
  List<IrFunction> functions,
) {
  for (final member in declaration.body.members) {
    switch (member) {
      case ast.MethodDeclaration(:final body):
        FunctionLowering.append(
          functions,
          unit,
          bindings,
          member.declaredFragment!.element,
          member,
          body,
        );
      case ast.FieldDeclaration(isStatic: true, :final fields):
        for (final variable in fields.variables) {
          lowerGlobal(unit, bindings, variable, functions);
        }
      default:
        unsupported(unit, member, 'extension member declaration');
    }
  }
}
