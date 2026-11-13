import '../../frontend/lowering/fixtures/records.dart' as records;

class Item(final int value) {
  @override
  Type get runtimeType => String;

  @override
  bool operator ==(Object other) => other is Item && value == other.value;

  @override
  int get hashCode => value;

  @override
  String toString() => 'item $value';
}

(Object?, {Object? value}) widen(Object? first, Object? value) =>
    (first, value: value);

void main() {
  print(
    '${records.fieldOrder(1)},${records.constantRecord()},'
    '${records.unusualNames(2)},${records.castRecord(4)}',
  );
  final record = widen(3.5, Item(7));
  print(
    '${record is (double, {Item value})},'
    '${record is (double, {String value})},'
    '${record.runtimeType == (3.5, value: Item(0)).runtimeType}',
  );
  print(record);
  const (Object, {Object name}) constant = (42, name: '中文🙂');
  final actual = widen(null, constant);
  print('${constant.runtimeType},${actual.$1},${actual.value}');
  final a = (Item(7), flag: true), b = (Item(7), flag: true);
  final Object differentShape = (Item(7), other: true);
  print(
    '${a == b},${a.hashCode == b.hashCode},'
    '${a == (Item(8), flag: true)},${a == differentShape}',
  );
  print(
    '${records.emptyOrSingleton(true)},${records.emptyOrSingleton(false)},'
    '${records.equalFields(1, 1)},${records.equalFields(1, 2)}',
  );
  Object? nullable;
  print('${(nullable,) == (null,)},${(double.nan,) == (1.0,)}');
  final nanPair = ('a', double.nan);
  print('nan record: ${nanPair == nanPair}');
  dynamic selected = (named: 'n', 12, apply: (int x) => x + 2);
  print(
    '${selected.$1},${selected.named},${selected.apply(3)},'
    '${selected.apply.call(4)}',
  );
  selected = (99, 10, named: 'second');
  print('${selected.named},${selected.$2}');
  selected = (missing: 1);
  for (final run in <void Function()>[
    () => selected.named,
    () => selected.apply(4),
    () => selected.$1,
    () => selected.named = 'invalid',
  ]) {
    try {
      run();
      throw StateError('Missing record member accepted');
    } on NoSuchMethodError {
      print('missing');
    }
  }
  final retained = (Item(42), label: 'kept 中文🙂', nested: (1, 2));
  var sum = 0;
  for (var i = 0; i < 40000; i++) {
    final current = (Item(i), label: '$i');
    sum += current.$1.value;
  }
  print('$sum,$retained');
}
