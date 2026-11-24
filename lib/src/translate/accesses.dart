import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// What tells the member that [field] reads apart from others.
String accessKey(PatternField field) {
  final owner = field.element?.enclosingElement, name = field.effectiveName;
  if (owner is! ExtensionElement && owner is! ExtensionTypeElement) {
    return '.$name';
  }
  final isGeneric = (owner as InstanceElement).typeParameters.isNotEmpty;
  final pattern = field.parent;
  // They can do different things for different types.
  final type = isGeneric && pattern is ObjectPattern ? pattern.type.type : null;
  return '.${owner.hashCode} ${type ?? ''} $name';
}

/// Whether [pattern] matches anything without looking at it.
bool ignoresValue(DartPattern pattern) => switch (pattern.unParenthesized) {
  WildcardPattern(:final type) => type == null,
  LogicalAndPattern(:final leftOperand, :final rightOperand) =>
    ignoresValue(leftOperand) && ignoresValue(rightOperand),
  LogicalOrPattern(:final leftOperand) => ignoresValue(leftOperand),
  _ => false,
};

/// Whether a property that [pattern] is for is not read. Unlike elements of
/// lists, properties are read where nothing but any value is allowed.
bool ignoresField(DartPattern pattern) =>
    ignoresValue(pattern) && _hasOr(pattern);

bool _hasOr(DartPattern pattern) => switch (pattern.unParenthesized) {
  LogicalOrPattern() => true,
  LogicalAndPattern(:final leftOperand, :final rightOperand) =>
    _hasOr(leftOperand) && _hasOr(rightOperand),
  _ => false,
};

/// What more than one of [patterns], or of their parts, get from the same
/// value, as keys made of how they get there.
Set<String> repeatedIn(Iterable<DartPattern> patterns) {
  final seen = <String>{}, repeated = <String>{};
  void add(String key) {
    if (!seen.add(key)) repeated.add(key);
  }

  for (final pattern in patterns) {
    _collect(pattern, '', add);
  }
  return repeated;
}

void _collect(DartPattern pattern, String path, void Function(String) add) {
  void read(DartPattern? inner, String key) {
    add(key);
    if (inner != null) _collect(inner, key, add);
  }

  switch (pattern) {
    case ParenthesizedPattern(:final pattern) ||
        NullCheckPattern(:final pattern) ||
        NullAssertPattern(:final pattern) ||
        CastPattern(:final pattern):
      _collect(pattern, path, add);
    case LogicalAndPattern(:final leftOperand, :final rightOperand) ||
        LogicalOrPattern(:final leftOperand, :final rightOperand):
      _collect(leftOperand, path, add);
      _collect(rightOperand, path, add);
    case RecordPattern(:final fields):
      var position = 0;
      for (final field in fields) {
        final name = field.effectiveName ?? '\$${++position}';
        _collect(field.pattern, '$path.$name', add);
      }
    case ObjectPattern(:final fields):
      for (final field in fields) {
        read(field.pattern, '$path${accessKey(field)}');
      }
    case ListPattern(:final elements):
      final rest = elements.indexWhere((e) => e is RestPatternElement);
      if (rest < 0 || elements.length > 1) add('$path.length');
      for (final (i, element) in elements.indexed) {
        final key = listKey(elements, i, rest);
        switch (element) {
          case RestPatternElement(:final pattern?):
            read(pattern, '$path$key');
          case final DartPattern element:
            read(element, '$path$key');
          case _:
            break;
        }
      }
    case MapPattern(:final elements):
      for (final entry in elements.whereType<MapPatternEntry>()) {
        read(entry.value, '$path${mapKey(entry)}');
        add('$path${mapKey(entry)}?');
      }
    case _:
      break;
  }
}

/// What tells the element at [index] apart, where a rest element is at [rest]
/// if there is one.
String listKey(List<ListPatternElement> elements, int index, int rest) =>
    index == rest
    ? '[$index..-${elements.length - index - 1}]'
    : rest >= 0 && index > rest
    ? '[-${elements.length - index}]'
    : '[$index]';

String mapKey(MapPatternEntry entry) => '[${entry.key}]';
