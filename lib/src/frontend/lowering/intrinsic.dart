import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'ffi.dart';

/// Supplies ordinary IR bodies for SDK declarations with compiler-owned semantics.
IrFunction? intrinsicBody(ExecutableElement element, FunctionTarget target) {
  final entry = Block(target.parameterTypes);
  final Value result;
  if (element.library.isDartCore &&
      element.baseElement == element.library.getTopLevelFunction('identical')) {
    result = entry.emit(Identical(entry.parameters[0], entry.parameters[1]));
  } else if (isPointerCast(element)) {
    result = lowerFfi(
      element,
      entry.parameters,
      entry.emit,
      result: target.returnType,
    )!;
  } else {
    return null;
  }
  entry.finish(Return(result));
  return IrFunction(target, [entry]);
}
