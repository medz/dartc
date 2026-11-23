import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builtin_error.dart';
import 'classes.dart';
import 'types.dart';

/// The errors that programs throw by themselves, and tests for what is caught.
final class ErrorTable(
  final ClassTable _classes,
  final LibraryElement _core,

  /// Tells that there are objects of a class.
  final void Function(ClassElement class_) _instantiate,
) {
  final _throwers = <BuiltinError, HirFunction>{};
  final _tests = <ClassElement, HirTypeTest>{};

  /// The names of the variables that [BuiltinError.late] can be about.
  final List<String> lateNames = [];

  /// The functions that throw errors.
  Iterable<HirFunction> get functions => _throwers.values;

  /// The class of stack traces.
  HirClass get trace => _created(_class('StackTrace'));

  ClassElement _class(String name) => _core.getClass(name)!;

  HirClass _created(ClassElement element) {
    _instantiate(element);
    return _classes.classOf(element);
  }

  /// The error thrown here that objects of [class_] are, if any.
  BuiltinError? builtin(ClassElement class_) {
    for (final error in _throwers.keys) {
      if (_class(error.className) == class_) return error;
    }
    return null;
  }

  /// Whether objects are of [class_].
  HirTypeTest testOf(ClassElement class_) =>
      _tests[class_] ??= HirTypeTest(class_.displayName);

  /// The classes that pass each test, of [classes].
  Map<HirTypeTest, Set<HirClass>> results(Iterable<ClassElement> classes) => {
    for (final MapEntry(key: tested, value: test) in _tests.entries)
      test: {
        for (final class_ in classes)
          if (isSubclass(class_, tested)) _classes.classOf(class_),
      },
  };

  /// A number for the variable called [name].
  int lateNumber(String name) {
    if (!lateNames.contains(name)) lateNames.add(name);
    return lateNames.indexOf(name);
  }

  HirFunction? throwerIfMade(BuiltinError error) => _throwers[error];

  /// A function that throws [error], given its number if it has one.
  HirFunction throwerOf(BuiltinError error) =>
      _throwers[error] ??= _makeThrower(error);

  HirFunction _makeThrower(BuiltinError error) {
    final class_ = _created(_class(error.className));
    final number = class_.fields.single;
    final parameters = [if (error.hasNumber) HirType.integer];
    final block = HirBlock(parameters);
    final HirValue object;
    if (error.isConstant) {
      object = block.add(HirStatic(HirConstObject(class_, {number: 0})));
    } else {
      object = block.add(HirNew(class_));
      final HirValue value = error.hasNumber
          ? block.parameters.single
          : block.add(HirConst(0));
      block.add(HirStore(number, object, value));
    }
    final HirValue stack = error.isExhaustion
        ? block.add(HirStatic(HirConstObject(trace, const {})))
        : block.add(HirNew(trace));
    block.end(HirThrow(object, stack));
    return HirFunction('throw ${error.name}', parameters, null, false)
      ..define([block]);
  }
}
