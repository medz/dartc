void unsupportedCollection() async {
  await for (final value in const Stream<int>.empty()) {
    if (value == 0) break;
  }
}
