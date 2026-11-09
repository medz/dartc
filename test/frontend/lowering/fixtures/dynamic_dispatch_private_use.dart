import 'dynamic_dispatch_private.dart';

int privateLibraries() {
  dynamic value = PrivateBox();
  final int external = value._value();
  return callPrivate(value) * 100 + external;
}
