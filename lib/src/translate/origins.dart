import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/source.dart';

/// Why functions are part of the program.
final class Origins() {
  /// What asked for a function.
  final _askedBy = <ExecutableElement, ExecutableElement?>{};

  /// What is translated now.
  ExecutableElement? get current => _current;
  ExecutableElement? _current;

  /// Does [work], which translates [element], as [by] asked.
  ///
  /// A problem in a library of the SDK tells what needs it.
  void within(
    ExecutableElement element,
    ExecutableElement? by,
    void Function() work,
  ) {
    _askedBy.putIfAbsent(element, () => by);
    final before = _current;
    _current = element;
    try {
      work();
    } on CompileFailure catch (failure) {
      if (!element.library.isInSdk) rethrow;
      throw CompileFailure([
        for (final problem in failure.problems)
          problem.because('needed by ${_chainTo(element)}'),
      ]);
    } finally {
      _current = before;
    }
  }

  /// What asked for [element], from the inside out.
  String _chainTo(ExecutableElement element) {
    final names = <String>[];
    final seen = <ExecutableElement>{};
    for (
      ExecutableElement? found = element;
      found != null && seen.add(found);
      found = _askedBy[found]
    ) {
      final owner = found.enclosingElement;
      final prefix = owner is InstanceElement ? '${owner.displayName}.' : '';
      names.add('$prefix${found.displayName}');
    }
    return names.take(8).join(', by ');
  }
}
