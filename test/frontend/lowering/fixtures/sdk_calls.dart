import 'dart:async';

import 'effects.dart';

String sdkJoin(List<String> values) => values.join(',');
Duration duration() => const Duration(seconds: 2);

Future<(int, String)> waitRecord((Future<int>, Future<String>) values) =>
    values.wait;

class Strings() implements List<String> {
  @override
  String join([String separator = '']) {
    tick(2);
    return 'joined:$separator';
  }

  @override
  Iterable<String> get reversed {
    tick(3);
    return const ['reversed'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String virtualCalls() {
  final List<String> values = Strings();
  final joined = values.join('${tick(1)}');
  final first = switch (values) {
    List<String>(reversed: [final value]) => value,
    _ => 'missing',
  };
  return '$joined:$first';
}
