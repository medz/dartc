import 'dart:collection';

int _calls = 0;

class Label(final String value) {
  @override
  String toString() {
    _calls++;
    return value;
  }
}

final class ChildLabel(super.value) extends Label {
  @override
  String toString() => '<${super.toString()}>';
}

String describe(Object? value) => value.toString();
String Function() formatter(Object? value) => value.toString;

String collectionText(int mode) {
  switch (mode) {
    case 0:
      _calls = 0;
      final Object value = ChildLabel('object');
      final text = '${describe(value)}|${formatter(value)()}|${describe(null)}';
      return '$text|$_calls|${describe(12)}|${describe(1.25)}|${describe(true)}|${formatter(null)()}|${formatter(null) == formatter(null)}';
    case 1:
      final text = StringBuffer('a')
        ..write(null)
        ..writeCharCode(0x1f642)
        ..writeAll([Label('x'), Label('y')], ':')
        ..writeln();
      final before = '${text.length}:${text.toString()}';
      text.clear();
      return '$before${text.isEmpty}:${text.isNotEmpty}';
    case 2:
      final values = List.generate(5, (i) => i + 1);
      values.setRange(1, 4, values);
      values.insertAll(2, [8, 9]);
      values.replaceRange(0, 2, [7]);
      values.removeWhere((x) => x.isEven);
      values.sort();
      return '${values.reversed.join(',')}|${values.asMap()}';
    case 3:
      final values = [1, 2, 3];
      var rejected = false;
      try {
        values.addAll(values);
      } on ConcurrentModificationError {
        rejected = true;
      }
      final fixed = List.of(values, growable: false);
      fixed[0] = 9;
      fixed.sort();
      return '$rejected|$values|$fixed';
    case 4:
      final original = [1, 2];
      final copy = List<int>.unmodifiable(original);
      original[0] = 7;
      return '$copy|${_listFailures(copy)}|${_listFailures(const <int>[])}';
    case 5:
      final values = <int>{3, 1, 2}..add(1);
      values.remove(1);
      values.add(1);
      return '$values|${values.union({4, 2})}|${values.intersection({1, 3})}|${values.difference({1})}';
    case 6:
      final set = LinkedHashSet<String>(
        equals: (a, b) => a.length == b.length,
        hashCode: (value) => value.length,
        isValidKey: (value) => value is String,
      )..addAll(['first', 'other', 'no', 'a']);
      final copy = set.toSet()..add('last');
      final Object other = 5;
      return '${set.lookup('equal')}|${set.contains(other)}|$set|$copy';
    case 7:
      final set = <String?>{null, 'a'}..add(null);
      final fixed = Set.unmodifiable(set);
      set.clear();
      var failures = 0;
      for (final value in [
        fixed,
        const <String?>{null, 'a'},
        const <String?>{},
      ]) {
        try {
          value.add(null);
        } on UnsupportedError {
          failures++;
        }
        try {
          value.remove('absent');
        } on UnsupportedError {
          failures++;
        }
        try {
          value.clear();
        } on UnsupportedError {
          failures++;
        }
      }
      return '$fixed|$failures';
    case 8:
      final original = <String, int>{'a': 1, 'b': 2};
      final copy = Map<String, int>.unmodifiable(original);
      original['a'] = 5;
      var failures = 0;
      for (final value in [
        copy,
        const <String, int>{'a': 1},
        const <String, int>{},
      ]) {
        try {
          value.remove('absent');
        } on UnsupportedError {
          failures++;
        }
        try {
          value.addAll({});
        } on UnsupportedError {
          failures++;
        }
        try {
          value.clear();
        } on UnsupportedError {
          failures++;
        }
      }
      return '$copy|$failures';
    case 9:
      final map = Map.fromIterables(['b', 'a', 'b'], [1, 2, 3]);
      map.update('a', (x) => x + 4);
      map.putIfAbsent('c', () => 8);
      map.removeWhere((k, v) => v.isOdd);
      return '${map.map((k, v) => MapEntry(v, k))}|${Map.fromEntries(map.entries)}';
    case 10:
      final source = [1, 2, 3, 4, 5];
      final values = source.where((x) => x.isOdd).map((x) => x * 2);
      final taken = values.take(2).toList();
      return '$taken|${values.skip(1).join('/')}|${values.fold(0, (int a, b) => a + b)}|${values.any((x) => x == 6)}|${values.every((x) => x.isEven)}';
    case 11:
      final list = <Object?>[];
      final map = <String, Object?>{};
      list.add(list);
      map['self'] = map;
      return '$list|$map|${{1, 2}}|${MapEntry('key', [Label('value')])}';
    case 12:
      final Iterable<Object?> source = [1, 2, 3];
      final Map<Object?, Object?> map = {'a': 4};
      return '${<int>[...source as dynamic]}|${<int>{...source as dynamic}}|${<String, int>{...map as dynamic}}';
    case 13:
      final list = [1, 2, 3].cast<num>();
      final set = <int>{1, 2}.cast<num>();
      final map = <String, int>{'a': 1}.cast<Object, num>();
      var failures = 0;
      try {
        list.add(1.5);
      } on TypeError {
        failures++;
      }
      try {
        set.add(1.5);
      } on TypeError {
        failures++;
      }
      try {
        map['b'] = 1.5;
      } on TypeError {
        failures++;
      }
      return '$list|$set|$map|$failures';
    case 14:
      final one = Label('a'), two = Label('a');
      final set = Set<Label>.identity()..addAll([one, one, two]);
      final map = Map<Label, int>.identity()
        ..[one] = 1
        ..[two] = 2;
      return '${set.length}|${map.length}|${set.lookup(one) == one}';
    case 15:
      final set = HashSet<int>()..addAll([3, 1, 2, 2]);
      final values = set.toList()..sort();
      final iterator = set.iterator..moveNext();
      set.add(4);
      try {
        iterator.moveNext();
      } on ConcurrentModificationError {
        return '$values|modified';
      }
      return 'iterator failed to detect modification';
    case 16:
      return '${ArgumentError.value('line\n\t"', 'input', 'bad')}|${RangeError.range(4, 0, 2, 'index')}|${StateError('state')}|${UnsupportedError('operation')}';
    case 22:
      final receiver = Label('receiver');
      return [
        NoSuchMethodError.withInvocation(
          receiver,
          Invocation.genericMethod(#missing, [int], ['argument'], {#named: 1}),
        ),
        NoSuchMethodError.withInvocation(null, Invocation.getter(#missing)),
        NoSuchMethodError.withInvocation(
          receiver,
          Invocation.setter(#missing, 1),
        ),
      ].join('|');
    case 18:
      final text = StringBuffer();
      for (var i = 0; i < 260; i++) {
        text.write(i < 130 ? 'x' : 'abcdefghi');
      }
      for (var i = 0; i < 130; i++) {
        text.writeCharCode(i % 5 == 0 ? 0x1f642 : 0x61 + i % 26);
      }
      final snapshot = text.toString();
      text.writeAll([], '|');
      var rejected = false;
      try {
        text.writeCharCode(0x110000);
      } on RangeError {
        rejected = true;
      }
      final length = text.length;
      text
        ..clear()
        ..writeCharCode(0)
        ..writeCharCode(0xd800)
        ..writeln();
      return '$snapshot|$length|$rejected|$text';
    case 19:
      final result = StringBuffer();
      for (final values in [<int>{}, LinkedHashSet<int>(hashCode: (_) => 0)]) {
        for (var i = 0; i < 200; i++) {
          values.add(i);
        }
        for (var i = 0; i < 160; i++) {
          values.remove(i);
        }
        final copy = values.toSet();
        values
          ..clear()
          ..add(999);
        for (var i = 0; i < 80; i++) {
          copy.add(i);
        }
        final iterator = copy.iterator..moveNext();
        copy.add(201);
        var detected = false;
        try {
          iterator.moveNext();
        } on ConcurrentModificationError {
          detected = true;
        }
        result.write('$values|$copy|${copy.lookup(199)}|$detected;');
      }
      final map = {for (var i = 0; i < 100; i++) i: '$i'};
      final copy = Map<int, String>.of(map);
      map
        ..clear()
        ..[200] = 'original';
      copy.putIfAbsent(101, () {
        copy.clear();
        return 'inserted';
      });
      return '$result|$map|$copy';
    case 20:
      final fixed = List<int>.generate(130, (i) => i, growable: false);
      final slice = fixed.sublist(1, 129);
      final copy = List<int>.unmodifiable(slice);
      slice[0] = -1;
      final nullable = List<int?>.of(fixed)
        ..length = 1
        ..length = 40;
      nullable.addAll([4, null, 7]);
      final text = <Object?>[Label('label'), null, 3, '中'].join();
      var rejected = 0;
      try {
        nullable.length = -1;
      } on RangeError {
        rejected++;
      }
      try {
        fixed.addAll([]);
      } on UnsupportedError {
        rejected++;
      }
      return '${copy.length}/${copy.first}/${copy.last}|${nullable.length}/${nullable[0]}/${nullable[1]}/${nullable.last}|$text|$rejected';
    case 21:
      final outcomes = <String>[];
      for (final skip in [-1, 0, 2]) {
        final fixed = List<int>.filled(3, 0);
        try {
          fixed.setRange(0, 2, [1].where((_) => true), skip);
          outcomes.add('accepted');
        } on RangeError {
          outcomes.add('range');
        } on StateError {
          outcomes.add('short');
        }
      }
      return outcomes.join('/');
    default:
      _calls = 0;
      final first = Label('first');
      final second = ChildLabel('second');
      final result = '$first$second';
      final getter = formatter(first);
      return '$result|${getter()}|$_calls';
  }
}

int _listFailures(List<int> values) {
  var count = 0;
  try {
    values.remove(999);
  } on UnsupportedError {
    count++;
  }
  try {
    values.addAll([]);
  } on UnsupportedError {
    count++;
  }
  try {
    values.sort();
  } on UnsupportedError {
    count++;
  }
  try {
    values.removeWhere((_) => false);
  } on UnsupportedError {
    count++;
  }
  try {
    values.clear();
  } on UnsupportedError {
    count++;
  }
  return count;
}
