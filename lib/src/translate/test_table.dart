import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'classes.dart';
import 'closure.dart';
import 'types.dart';

/// The tests for classes that a program does.
final class TestTable(final ClassTable _classes) {
  final _tests = <InterfaceElement, HirTypeTest>{};

  final _extensions = <InterfaceElement, HirTypeTest>{};

  /// Whether objects are of classes that extend [class_].
  HirTypeTest extendsOf(InterfaceElement class_) =>
      _extensions[class_] ??= HirTypeTest('extends ${class_.displayName}');

  /// Whether objects are of [class_].
  HirTypeTest testOf(InterfaceElement class_) =>
      _tests[class_] ??= HirTypeTest(class_.displayName);

  HirTypeTest? _unsendable;

  /// Whether objects are of classes that the official runtime refuses to send
  /// to other isolates, as they or their supertypes are marked so.
  HirTypeTest get unsendable => _unsendable ??= HirTypeTest('unsendable');

  /// The classes that pass each test, of [classes] and of those that functions
  /// are, which are like [functionClass].
  Map<HirTypeTest, Set<HirClass>> results(
    Iterable<InterfaceElement> classes,
    Iterable<Closure> closures,
    InterfaceElement functionClass,
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
    ?_unsendable: {
      for (final class_ in classes)
        if (_isUnsendable(class_)) _classes.classOf(class_),
    },
  };

  static bool _isUnsendable(InterfaceElement class_) => [
    class_,
    for (final type in class_.allSupertypes) type.element,
  ].any(_isMarked);

  static bool _isMarked(Element element) =>
      element.metadata.annotations.any((annotation) {
        final value = annotation.computeConstantValue();
        return value?.type?.element?.name == 'pragma' &&
            value?.getField('name')?.toStringValue() == 'vm:isolate-unsendable';
      });
}
