import '../effects.dart';
import 'first.dart' as first;
import 'first.dart' as again;
import 'barrel.dart' as exposed;
import 'second.dart' as second;

String libraryIdentity() {
  final original = first.shared;
  again.shared += tick(1);
  final private = first.updatePrivate();
  first.SharedName.value += tick(2);
  return observe([
    original,
    first.shared,
    again.shared,
    exposed.shared,
    private,
    second.readPrivate(),
    exposed.readPrivate(),
    exposed.readPart(),
    first.partValue,
    first.SharedName.value,
    second.SharedName.value,
  ]);
}

String observe(List<Object?> values) => '$values';
