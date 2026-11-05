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
  List<ast.ClassMember> members,
  List<IrFunction> functions,
) {
  for (final member in members) {
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

/// Erased representation construction and access are ordinary identity bodies.
void lowerExtensionType(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.ExtensionTypeDeclaration declaration,
  List<IrFunction> functions,
) {
  final element = declaration.declaredFragment!.element;
  for (final executable in [
    element.primaryConstructor,
    element.representation.getter!,
  ]) {
    final target = bindings.target(executable, unit, declaration);
    final entry = Block(target.parameterTypes);
    final value = entry.parameters.single;
    entry.finish(value.type == .never ? Unreachable(value) : Return(value));
    functions.add(IrFunction(target, [entry]));
  }
  lowerExtension(unit, bindings, declaration.body.members, functions);
}
