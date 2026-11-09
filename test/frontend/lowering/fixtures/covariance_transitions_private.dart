class Real() {
  Object? _f([num x = 10]) => x;
}

abstract class Contract() {
  // The private obligation is implemented from another library without a call.
  // ignore: unused_element, unused_element_parameter
  Object? _f([covariant num x = 20]);
}

String inspectPrivate(Real value) {
  final Object call = value._f;
  return '${value._f()}:${call is Object? Function([Object?])}';
}
