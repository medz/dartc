import 'effects.dart';

enum const E() {
  a,
  b,
}

String sdkJoin(List<String> values) => values.join(',');
List<int> sdkTake(List<int> values) => values.take(2).toList();
int enumCompare() => Enum.compareByIndex(E.a, E.b);
int enumCompareNames() => Enum.compareByName(E.a, E.b);
E enumByName() => E.values.byName('a');
Map<String, E> enumNames() => E.values.asNameMap();
Duration duration() => const Duration(seconds: 2);

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
