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
  for (final name in ['List', 'IndexError', 'RangeError', 'UnsupportedError']) {
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
  requireClass(core.getClass('Map')!);
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
  Constant Function(ClassType, Iterable<(Constant, Constant)>) mapConstant,
) {
  if (element.library.isDartCore &&
      element.baseElement == element.library.getTopLevelFunction('identical')) {
    return (target, entry) =>
        entry.emit(Identical(entry.parameters[0], entry.parameters[1]));
  }
  if (element.isExternal &&
      element.library.uri == Uri.parse('dart:math') &&
      element.baseElement == element.library.getTopLevelFunction('_sqrt')) {
    return (target, entry) =>
        entry.emit(NumericSquareRoot(entry.parameters.single));
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
    if (element == element.library.getClass('int')!.getMethod('~')) {
      return (target, entry) => entry.emit(
        IntBinary(.bitXor, entry.parameters.single, const Constant.integer(-1)),
      );
    }
    if (element is ConstructorElement) {
      final helper = switch (element.name) {
        'fromEnvironment' when owner == element.library.getClass('String') =>
          '_stringFromEnvironment',
        'fromEnvironment' when owner == element.library.getClass('int') =>
          '_intFromEnvironment',
        'fromEnvironment' when owner == element.library.getClass('bool') =>
          '_boolFromEnvironment',
        'hasEnvironment' when owner == element.library.getClass('bool') =>
          '_hasEnvironment',
        _ => null,
      };
      if (helper != null) {
        final implementation = element.library.getTopLevelFunction(helper);
        if (implementation == null) return null;
        requireMapSupport(element.library, requireClass);
        final variables = element.library.session.declaredVariables;
        final values = mapConstant(CoreTypes.mapOf(.string, .string), [
          for (final name in variables.variableNames)
            (Constant.string(name), Constant.string(variables.get(name)!)),
        ]);
        final body = bind(implementation);
        return (target, entry) =>
            entry.emit(DirectCall(body, [values, ...entry.parameters]));
      }
    }
    if (element.isExternal &&
        (owner == element.library.getClass('Object') ||
            owner == element.library.getClass('Null'))) {
      switch (element.name) {
        case '==':
          return (target, entry) =>
              entry.emit(Identical(entry.parameters[0], entry.parameters[1]));
        case 'hashCode':
        case '_identityHashCode':
          return (target, entry) =>
              entry.emit(ObjectHashCode(entry.parameters.single, direct: true));
        case 'runtimeType':
          return (target, entry) => entry.emit(
            ObjectRuntimeType(entry.parameters.single, direct: true),
          );
      }
    }
    if (element.isExternal && owner == element.library.getClass('_Double')) {
      final operator = switch (element.name) {
        '_add' => NumericOperator.add,
        '_sub' => NumericOperator.subtract,
        '_mul' => NumericOperator.multiply,
        '_div' => NumericOperator.divide,
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
        case '_greaterThanFromInteger':
          return (target, entry) => entry.emit(
            NumericBinary(
              .greaterThan,
              entry.parameters[1],
              entry.parameters[0],
            ),
          );
        case '-':
          return (target, entry) =>
              entry.emit(NumericNegate(entry.parameters.single));
        case 'fromInteger':
          return (target, entry) =>
              entry.emit(NumericToDouble(entry.parameters.single));
        case 'hashCode':
          return (target, entry) =>
              entry.emit(ObjectHashCode(entry.parameters.single));
        case '_equal':
        case '_equalToInteger':
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
    if (element.isExternal &&
        owner == element.library.getClass('_IntegerImplementation')) {
      final operator = switch (element.name) {
        '_bitAndFromInteger' => IntOperator.bitAnd,
        '_bitOrFromInteger' => IntOperator.bitOr,
        '_bitXorFromInteger' => IntOperator.bitXor,
        '_shrFromInteger' => IntOperator.shiftRight,
        '_ushrFromInteger' => IntOperator.unsignedShiftRight,
        '_shlFromInteger' => IntOperator.shiftLeft,
        '_addFromInteger' => IntOperator.add,
        '_subFromInteger' => IntOperator.subtract,
        '_mulFromInteger' => IntOperator.multiply,
        '_truncDivFromInteger' => IntOperator.truncateDivide,
        '_moduloFromInteger' => IntOperator.modulo,
        _ => null,
      };
      if (operator != null) {
        return (target, entry) => entry.emit(
          IntBinary(operator, entry.parameters[1], entry.parameters[0]),
        );
      }
      if (element.name == '_equalToInteger') {
        return (target, entry) =>
            entry.emit(Equals(entry.parameters[0], entry.parameters[1]));
      }
      if (element.name == '_greaterThanFromInteger') {
        return (target, entry) => entry.emit(
          NumericBinary(.greaterThan, entry.parameters[1], entry.parameters[0]),
        );
      }
      if (element.name == 'hashCode') {
        return (target, entry) =>
            entry.emit(ObjectHashCode(entry.parameters.single));
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
    final string = element.library.getClass('String')!;
    if (element == string.getGetter('codeUnits')) {
      final units = _internal(element.library).getClass('CodeUnits')!;
      requireClass(units);
      return (target, entry) => entry.emit(
        Construct(bind(units.unnamedConstructor!), entry.parameters),
      );
    }
    if (element == string.getGetter('length') ||
        element ==
            element.library.getClass('_StringBase')?.getGetter('length')) {
      return (target, entry) =>
          entry.emit(StringLength(entry.parameters.single));
    }
  }
  return null;
}
