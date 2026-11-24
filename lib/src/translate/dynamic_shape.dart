import 'package:analyzer/dart/element/element.dart';

/// How a member is used whose object can be anything.
enum DynamicUse() {
  call,
  get,
  set,
}

/// A use of a member by its name.
final class DynamicShape(
  final DynamicUse use,

  /// The name by which members are looked up; `unary-` and `[]=` are some.
  final String name,

  /// Where a private name belongs.
  final LibraryElement? library,
  final int positional,
  final List<String> named,
  final Never Function(String what) reject, {

  /// The type arguments given first.
  final int types = 0,
}) {
  DynamicShape withTypes(int types) =>
      DynamicShape(use, name, library, positional, named, reject, types: types);
}
