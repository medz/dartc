import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function.dart';

/// Lowers shared storage through the same static accessor calls as properties.
void lowerGlobal(
  ResolvedUnitResult unit,
  Bindings bindings,
  ast.VariableDeclaration declaration,
  List<IrCallable> functions,
) {
  final element =
      declaration.declaredFragment!.element as PropertyInducingElement;
  if (element.isConst) {
    bindings.constantOf(element, unit, declaration);
    return;
  }
  final getter = bindings.target(element.getter!, unit, declaration);
  if (functions.any((function) => function.target == getter)) return;
  if (element
      case FieldElement(isExternal: true) ||
          TopLevelVariableElement(isExternal: true)) {
    for (final accessor in [element.getter, element.setter].nonNulls) {
      functions.add(IrExternal(bindings.target(accessor, unit, declaration)));
    }
    return;
  }
  if (element.isLate || element.isFinal) {
    bindings.requireLateError(element.library, unit, declaration);
  }
  final slot = bindings.global(element, unit, declaration);
  if (declaration.initializer case final expression?) {
    FunctionLowering.appendExpression(
      functions,
      unit,
      bindings,
      slot.initializer!,
      expression,
    );
  }
  for (final accessor in [element.getter, element.setter].nonNulls) {
    final target = bindings.target(accessor, unit, declaration);
    final entry = Block(target.parameterTypes);
    if (accessor is GetterElement) {
      final value = entry.emit(LoadGlobal(slot));
      entry.finish(value.type == .never ? Unreachable(value) : Return(value));
    } else {
      entry.emit(StoreGlobal(slot, entry.parameters.single));
      entry.finish(const Return());
    }
    functions.add(IrFunction(target, [entry]));
  }
}
