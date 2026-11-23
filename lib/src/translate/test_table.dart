import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'classes.dart';
import 'closure.dart';
import 'types.dart';

/// The tests for classes that a program does.
final class TestTable(final ClassTable _classes) {
  final _tests = <InterfaceElement, HirTypeTest>{};

  final _extensions = <ClassElement, HirTypeTest>{};

  /// Whether objects are of classes that extend [class_].
  HirTypeTest extendsOf(ClassElement class_) =>
      _extensions[class_] ??= HirTypeTest('extends ${class_.displayName}');

  /// Whether objects are of [class_].
  HirTypeTest testOf(InterfaceElement class_) =>
      _tests[class_] ??= HirTypeTest(class_.displayName);

  /// The classes that pass each test, of [classes] and of those that functions
  /// are, which are like [functionClass].
  Map<HirTypeTest, Set<HirClass>> results(
    Iterable<ClassElement> classes,
    Iterable<Closure> closures,
    ClassElement functionClass,
  ) => {
    for (final MapEntry(key: tested, value: test) in _tests.entries)
      test: {
        for (final class_ in classes)
          if (isSubclass(class_, tested)) _classes.classOf(class_),
        if (isSubclass(functionClass, tested))
          for (final closure in closures) closure.class_,
      },
    for (final MapEntry(key: tested, value: test) in _extensions.entries)
      test: {
        for (final class_ in classes)
          if (_classes.levels.of(class_).chain.any((l) => l.element == tested))
            _classes.classOf(class_),
      },
  };
}
