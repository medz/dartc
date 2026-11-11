import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'ffi.dart';

/// Supplies bodies and SDK dependencies for compiler-owned declarations.
IrFunction Function(FunctionTarget)? intrinsicFor(
  ExecutableElement element,
  void Function(InterfaceElement) requireClass,
) {
  if (element.library.isDartCore &&
      element.baseElement == element.library.getTopLevelFunction('identical')) {
    return (target) => _body(
      target,
      (entry) =>
          entry.emit(Identical(entry.parameters[0], entry.parameters[1])),
    );
  }
  if (isPointerCast(element)) {
    return (target) => _body(
      target,
      (entry) => lowerFfi(
        element,
        entry.parameters,
        entry.emit,
        result: target.returnType,
      )!,
    );
  }
  if (element.library.isDartCore) {
    final string = element.library.getClass('String')!;
    if (element == string.getNamedConstructor('fromCharCode')) {
      requireClass(element.library.getClass('RangeError')!);
      return (target) => _body(
        target,
        (entry) => entry.emit(StringFromCharCode(entry.parameters.single)),
      );
    }
    if (element == string.getMethod('[]')) {
      requireClass(element.library.getClass('IndexError')!);
      requireClass(element.library.getClass('RangeError')!);
      return (target) => _body(
        target,
        (entry) => entry.emit(
          StringFromCharCode(
            entry.emit(
              StringCodeUnitAt(entry.parameters[0], entry.parameters[1]),
            ),
          ),
        ),
      );
    }
    if (element == string.getMethod('+')) {
      return (target) => _body(
        target,
        (entry) =>
            entry.emit(StringConcat(entry.parameters[0], entry.parameters[1])),
      );
    }
    if (element == string.getMethod('==')) {
      return (target) => _body(
        target,
        (entry) => entry.emit(Equals(entry.parameters[0], entry.parameters[1])),
      );
    }
    if (element == string.getGetter('hashCode')) {
      return (target) => _body(
        target,
        (entry) => entry.emit(ObjectHashCode(entry.parameters.single)),
      );
    }
    if (element == string.getGetter('length')) {
      return (target) => _body(
        target,
        (entry) => entry.emit(StringLength(entry.parameters.single)),
      );
    }
    if (element == string.getMethod('codeUnitAt')) {
      requireClass(element.library.getClass('IndexError')!);
      return (target) => _body(
        target,
        (entry) => entry.emit(
          StringCodeUnitAt(entry.parameters[0], entry.parameters[1]),
        ),
      );
    }
  }
  return null;
}

IrFunction _body(FunctionTarget target, Value Function(Block) result) {
  final entry = Block(target.parameterTypes);
  entry.finish(Return(result(entry)));
  return IrFunction(target, [entry]);
}
