import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'ffi.dart';

/// Includes the SDK declarations consumed by built-in List bodies.
void requireListSupport(
  LibraryElement library,
  void Function(InterfaceElement) requireClass,
) {
  final core = library.typeProvider.objectElement.library;
  for (final name in ['IndexError', 'RangeError', 'UnsupportedError']) {
    requireClass(core.getClass(name)!);
  }
  final internal = core.fragments
      .expand((fragment) => fragment.importedLibraries)
      .firstWhere((library) => library.uri == Uri.parse('dart:_internal'));
  requireClass(internal.getClass('ListIterator')!);
}

/// Supplies bodies and SDK dependencies for compiler-owned declarations.
Value Function(FunctionTarget, Block)? intrinsicFor(
  ExecutableElement element,
  void Function(InterfaceElement) requireClass,
) {
  if (element.library.isDartCore &&
      element.baseElement == element.library.getTopLevelFunction('identical')) {
    return (target, entry) =>
        entry.emit(Identical(entry.parameters[0], entry.parameters[1]));
  }
  if (isPointerCast(element)) {
    return (target, entry) => lowerFfi(
      element,
      entry.parameters,
      entry.emit,
      result: target.returnType,
    )!;
  }
  if (element.library.isDartCore) {
    final list = element.library.getClass('List')!;
    if (element == list.getNamedConstructor('filled') ||
        element == list.getNamedConstructor('empty')) {
      requireListSupport(element.library, requireClass);
      return (target, entry) => entry.emit(
        element == list.getNamedConstructor('empty')
            ? NewCollection(
                target.returnType as ClassType,
                growable: entry.parameters.single,
              )
            : ListFilled(
                target.returnType as ClassType,
                entry.parameters[0],
                entry.parameters[1],
                entry.parameters[2],
              ),
      );
    }
    final string = element.library.getClass('String')!;
    if (element == string.getNamedConstructor('fromCharCode')) {
      requireClass(element.library.getClass('RangeError')!);
      return (target, entry) =>
          entry.emit(StringFromCharCode(entry.parameters.single));
    }
    if (element == string.getMethod('[]')) {
      requireClass(element.library.getClass('IndexError')!);
      requireClass(element.library.getClass('RangeError')!);
      return (target, entry) => entry.emit(
        StringFromCharCode(
          entry.emit(
            StringCodeUnitAt(entry.parameters[0], entry.parameters[1]),
          ),
        ),
      );
    }
    if (element == string.getMethod('+')) {
      return (target, entry) =>
          entry.emit(StringConcat(entry.parameters[0], entry.parameters[1]));
    }
    if (element == string.getMethod('==')) {
      return (target, entry) =>
          entry.emit(Equals(entry.parameters[0], entry.parameters[1]));
    }
    if (element == string.getGetter('hashCode')) {
      return (target, entry) =>
          entry.emit(ObjectHashCode(entry.parameters.single));
    }
    if (element == string.getGetter('length')) {
      return (target, entry) =>
          entry.emit(StringLength(entry.parameters.single));
    }
    if (element == string.getMethod('codeUnitAt')) {
      requireClass(element.library.getClass('IndexError')!);
      return (target, entry) => entry.emit(
        StringCodeUnitAt(entry.parameters[0], entry.parameters[1]),
      );
    }
  }
  return null;
}
