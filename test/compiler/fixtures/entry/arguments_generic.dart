void main<T>([List<String>? arguments]) {
  if (T != dynamic || arguments != null) {
    throw StateError('Generic main defaults.');
  }
  print('generic');
}
