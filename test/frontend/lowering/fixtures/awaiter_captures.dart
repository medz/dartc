import 'dart:async';

const awaiter = pragma('vm:awaiter-link', false);

class const Marker(final String name);

(String, Object) Function() local(Object value) {
  @awaiter
  final link = value;
  final label = value.toString();
  return () => (label, link);
}

(String, Object) Function() parameter(
  String label,
  @pragma('vm:awaiter-link') Object link,
) =>
    () => (label, link);

Object Function() Function() nested(@pragma('vm:awaiter-link') Object link) =>
    () =>
        () => link;

Object Function(Object) boxed(Object value) {
  @pragma('vm:awaiter-link')
  var link = value;
  return (Object next) {
    final previous = link;
    link = next;
    return previous;
  };
}

Object Function(Object) boxedParameter(
  @pragma('vm:awaiter-link') Object link,
) => (Object next) {
  final previous = link;
  link = next;
  return previous;
};

Object Function() lazyCapture(@pragma('vm:awaiter-link') Object link) {
  late final value = link;
  return () => value;
}

(String, Object) Function() multiple(
  @pragma('vm:awaiter-link') Object first,
  @pragma('vm:awaiter-link') String second,
) =>
    () => (second, first);

Object Function() unused(@pragma('vm:awaiter-link') Object link) =>
    () => 'unused';

Object Function() unmarked(Object link) =>
    () => link;

Object Function() unrelated(@pragma('vm:prefer-inline') Object link) =>
    () => link;

Object Function() impostor(@Marker('vm:awaiter-link') Object link) =>
    () => link;

Future<List<int>> sdkWait(List<Future<int>> inputs) => Future.wait(inputs);

Future<List<int>> sdkIterableWait(List<Future<int>> inputs) => inputs.wait;
