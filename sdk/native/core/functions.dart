import 'dart:_heap/objects.dart' show applyFunction;

@patch
class Function {
  @patch
  static _apply(List<dynamic> arguments, List<dynamic> names) =>
      applyFunction(arguments[0], arguments, names, null);
}

/// Whether a function takes [arguments], of which the first is itself and the
/// last have [names].
bool _applyFits(
  List arguments,
  List names,
  int required,
  int positional,
  List allNames,
  List requiredNames,
) {
  final count = arguments.length - names.length - 1;
  if (count < required || count > positional) return false;
  for (var i = 0; i < names.length; i++) {
    if (!allNames.contains(names[i])) return false;
  }
  for (var i = 0; i < requiredNames.length; i++) {
    if (!names.contains(requiredNames[i])) return false;
  }
  return true;
}

int _applyPositional(List arguments, List names, int index) =>
    index < arguments.length - names.length - 1 ? index : -1;

int _applyNamed(List arguments, List names, String name) {
  final index = names.indexOf(name);
  return index < 0 ? -1 : arguments.length - names.length - 1 + index;
}

Object? _applyArgument(List arguments, int index) => arguments[index + 1];

Object? _applyMissing(
  Object function,
  List arguments,
  List names,
  String name,
) => _missing(function, 0, name, null, arguments.sublist(1), names, null);
