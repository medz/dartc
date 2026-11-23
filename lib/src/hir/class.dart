import 'value.dart';

/// A value that each object of a class holds.
final class HirField(final String name, final HirType type);

/// How an array holds one of its elements.
enum HirElement(
  final HirType type,

  /// The bytes it takes.
  final int size,
) {
  reference(.reference, 8),
  int8(.integer, 1),
  uint8(.integer, 1),
  int16(.integer, 2),
  uint16(.integer, 2),
  int32(.integer, 4),
  uint32(.integer, 4),
  int64(.integer, 8),
  float32(.float, 4),
  float64(.float, 8),
}

/// What objects hold besides their fields, as many as each of them says.
enum HirElements() {
  references,

  /// Bytes, which hold numbers of any kind.
  bytes,
}

/// A class whose objects hold its superclass's fields and [ownFields].
///
/// If it has [elements], its objects are arrays. It then has no subclasses and
/// at most one field.
final class HirClass(
  final String name,
  final HirClass? superclass,
  Iterable<HirField> ownFields, [
  final HirElements? elements,
]) {
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

/// A question about the class of an object, told apart by itself.
final class HirTypeTest(final String name);

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
