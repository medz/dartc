import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

/// Finds what a value of type `dynamic` is checked to be where a pattern has to
/// match it.
final class PatternTypes(final LibraryElement _library) {
  /// What [pattern] says of the type of what it matches, if it says anything.
  DartType? of(DartPattern? pattern) => switch (pattern) {
    ParenthesizedPattern(:final pattern) => of(pattern),
    DeclaredVariablePattern(:final type) ||
    WildcardPattern(:final type) => type?.type,
    AssignedVariablePattern(:final VariableElement element) => element.type,
    NullAssertPattern(:final pattern) => switch (of(pattern)) {
      null => null,
      final type => _library.typeSystem.leastUpperBound(
        type,
        _library.typeProvider.nullType,
      ),
    },
    LogicalAndPattern(:final leftOperand, :final rightOperand) => _both(
      of(leftOperand),
      of(rightOperand),
    ),
    RecordPattern() => _record(pattern),
    ObjectPattern(:final type) => type.type,
    ListPattern() => _library.typeProvider.listType(
      pattern.typeArguments?.arguments.single.type ?? _elements(pattern),
    ),
    MapPattern() => _map(pattern),
    _ => null,
  };

  DartType? _both(DartType? a, DartType? b) => a == null
      ? b
      : b == null
      ? a
      : _library.typeSystem.greatestLowerBound(a, b);

  DartType _known(DartType? type) => type ?? _library.typeProvider.dynamicType;

  DartType _record(RecordPattern pattern) => RecordType(
    positional: [
      for (final field in pattern.fields)
        if (field.effectiveName == null) _known(of(field.pattern)),
    ],
    named: {
      for (final field in pattern.fields)
        ?field.effectiveName: _known(of(field.pattern)),
    },
    nullabilitySuffix: NullabilitySuffix.none,
  );

  DartType _elements(ListPattern pattern) {
    DartType? found;
    for (final element in pattern.elements) {
      final own = switch (element) {
        RestPatternElement(:final pattern) => switch (of(pattern)) {
          final InterfaceType type =>
            type
                .asInstanceOf(_library.typeProvider.iterableElement)
                ?.typeArguments
                .single,
          _ => null,
        },
        final DartPattern pattern => of(pattern),
        _ => null,
      };
      found = _both(found, own);
    }
    return _known(found);
  }

  DartType _map(MapPattern pattern) {
    final given = pattern.typeArguments?.arguments;
    DartType? found;
    for (final entry in pattern.elements.whereType<MapPatternEntry>()) {
      found = _both(found, of(entry.value));
    }
    return _library.typeProvider.mapType(
      _known(given?.first.type),
      _known(given?.last.type ?? found),
    );
  }
}
