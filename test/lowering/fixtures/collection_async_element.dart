void unsupportedCollection() async {
  final values = <int>[
    await for (final value in const Stream<int>.empty()) value,
  ];
  if (values.isNotEmpty) throw 99;
}
