import 'value.dart';

/// A value that each object of a class holds.
final class HirField(final String name, final HirType type);

/// A class whose objects hold its superclass's fields and [ownFields].
final class HirClass(
  final String name,
  final HirClass? superclass,
  Iterable<HirField> ownFields,
) {
  final List<HirField> ownFields = .unmodifiable(ownFields);

  /// Every field of an object, starting with the superclass's.
  List<HirField> get fields => [...?superclass?.fields, ...ownFields];

  bool isSubclassOf(HirClass other) {
    for (HirClass? found = this; found != null; found = found.superclass) {
      if (found == other) return true;
    }
    return false;
  }
}

/// A member that calls look up in the class of their receiver.
///
/// [parameters] excludes the receiver. Selectors are told apart by themselves.
final class HirSelector(
  final String name,
  Iterable<HirType> parameters, [

  /// The type of the result, if there is one.
  final HirType? result,
]) {
  final List<HirType> parameters = .unmodifiable(parameters);
}
