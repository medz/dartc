import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'ffi.dart';

LibraryElement _internal(LibraryElement library) => library
    .typeProvider
    .objectElement
    .library
    .fragments
    .expand((fragment) => fragment.importedLibraries)
    .firstWhere((library) => library.uri == Uri.parse('dart:_internal'));

/// Includes the SDK declarations consumed by built-in List bodies.
void requireListSupport(
  LibraryElement library,
  void Function(InterfaceElement) requireClass,
) {
  final core = library.typeProvider.objectElement.library;
  for (final name in ['IndexError', 'RangeError', 'UnsupportedError']) {
    requireClass(core.getClass(name)!);
  }
  final collection = core.fragments
      .expand((fragment) => fragment.importedLibraries)
      .firstWhere((library) => library.uri == Uri.parse('dart:collection'));
  requireClass(collection.getClass('ListBase')!);
}

/// Includes ordinary Map algorithms and the key iteration contract.
void requireMapSupport(
  LibraryElement library,
  void Function(InterfaceElement) requireClass,
) {
  final core = library.typeProvider.objectElement.library;
  requireClass(core.getClass('ConcurrentModificationError')!);
  requireClass(core.getClass('Iterable')!);
  final collection = core.fragments
      .expand((fragment) => fragment.importedLibraries)
      .firstWhere((library) => library.uri == Uri.parse('dart:collection'));
  requireClass(collection.getClass('MapBase')!);
  requireClass(collection.getClass('LinkedHashMap')!);
}

/// Supplies bodies and SDK dependencies for compiler-owned declarations.
Value? Function(FunctionTarget, Block)? intrinsicFor(
  ExecutableElement element,
  void Function(InterfaceElement) requireClass,
  FunctionTarget Function(ExecutableElement) bind,
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
    final owner = element.enclosingElement;
    if (element.isExternal && owner == element.library.getClass('_Double')) {
      final operator = switch (element.name) {
        '_add' => NumericOperator.add,
        '_sub' => NumericOperator.subtract,
        '_mul' => NumericOperator.multiply,
        '_div' => NumericOperator.divide,
        '_modulo' => NumericOperator.modulo,
        '_remainder' => NumericOperator.remainder,
        '_greaterThan' => NumericOperator.greaterThan,
        _ => null,
      };
      if (operator != null) {
        return (target, entry) => entry.emit(
          NumericBinary(operator, entry.parameters[0], entry.parameters[1]),
        );
      }
      final rounding = switch (element.name) {
        'roundToDouble' => IntegerRounding.round,
        'floorToDouble' => IntegerRounding.floor,
        'ceilToDouble' => IntegerRounding.ceil,
        'truncateToDouble' || 'toInt' => IntegerRounding.truncate,
        _ => null,
      };
      if (rounding != null) {
        if (element.name == 'toInt') {
          requireClass(element.library.getClass('UnsupportedError')!);
        }
        return (target, entry) => entry.emit(
          element.name == 'toInt'
              ? NumericToInt(entry.parameters.single, rounding)
              : NumericRoundToDouble(entry.parameters.single, rounding),
        );
      }
      switch (element.name) {
        case 'fromInteger':
          return (target, entry) =>
              entry.emit(NumericToDouble(entry.parameters.single));
        case 'hashCode':
          return (target, entry) =>
              entry.emit(ObjectHashCode(entry.parameters.single));
        case '_equal':
          return (target, entry) =>
              entry.emit(Equals(entry.parameters[0], entry.parameters[1]));
        case 'isNaN':
          return (target, entry) => entry.emit(
            Equals(
              entry.emit(
                Equals(entry.parameters.single, entry.parameters.single),
              ),
              const Constant.boolean(false),
            ),
          );
        case 'isNegative':
        case 'isInfinite':
          return (target, entry) {
            final value = entry.parameters.single;
            final yes = Block(), no = Block();
            final negative = element.name == 'isNegative';
            entry.finish(
              Branch(
                entry.emit(
                  negative
                      ? NumericBinary(
                          .lessThan,
                          value,
                          const Constant.floating(0),
                        )
                      : Equals(value, const Constant.floating(double.infinity)),
                ),
                Jump(yes),
                Jump(no),
              ),
            );
            yes.finish(const Return(Constant.boolean(true)));
            no.finish(
              Return(
                no.emit(
                  negative
                      ? Identical(value, const Constant.floating(-0.0))
                      : Equals(
                          value,
                          const Constant.floating(double.negativeInfinity),
                        ),
                ),
              ),
            );
            return null;
          };
      }
    }
    if (element == element.library.getClass('Error')!.getMethod('_throw')) {
      return (target, entry) {
        entry.finish(
          Throw(entry.parameters[0], stackTrace: entry.parameters[1]),
        );
        return null;
      };
    }
    if (element.baseElement ==
        element.library.getTopLevelFunction('identityHashCode')) {
      return (target, entry) =>
          entry.emit(ObjectHashCode(entry.parameters.single, direct: true));
    }
    if (element == element.library.getClass('Map')!.unnamedConstructor) {
      requireMapSupport(element.library, requireClass);
      return (target, entry) =>
          entry.emit(NewCollection(target.returnType as ClassType));
    }
    final list = element.library.getClass('List')!;
    if (element == list.getNamedConstructor('of') ||
        element == list.getNamedConstructor('from')) {
      requireListSupport(element.library, requireClass);
      return (target, entry) => entry.emit(
        ListFrom(
          target.returnType as ClassType,
          entry.parameters[0],
          entry.parameters[1],
        ),
      );
    }
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
    if (element == string.getNamedConstructor('fromCharCodes')) {
      requireListSupport(element.library, requireClass);
      return (target, entry) => entry.emit(
        StringFromCharCodes(
          entry.parameters[0],
          entry.parameters[1],
          entry.parameters[2],
        ),
      );
    }
    if (element == string.getGetter('codeUnits')) {
      final units = _internal(element.library).getClass('CodeUnits')!;
      requireClass(units);
      return (target, entry) => entry.emit(
        Construct(bind(units.unnamedConstructor!), entry.parameters),
      );
    }
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
