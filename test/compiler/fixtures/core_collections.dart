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

final class LinkedItem(final int value) extends LinkedListEntry<LinkedItem> {
  @override
  bool operator ==(Object other) => other is LinkedItem && value == other.value;

  @override
  int get hashCode => value;
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
    case 23:
      final map = SplayTreeMap<int, String>()
        ..addAll({5: 'five', 1: 'one', 3: 'three', 2: 'two'})
        ..[3] = 'THREE';
      final keys = map.keys;
      final bounds = [
        map.firstKey(),
        map.lastKey(),
        map.lastKeyBefore(3),
        map.firstKeyAfter(3),
        map.lastKeyBefore(1),
        map.firstKeyAfter(5),
      ];
      map.remove(2);
      map.addEntries([const MapEntry(4, 'four')]);
      final from = SplayTreeMap<int, String>.of(map, (a, b) => b.compareTo(a));
      return '${keys.join(',')}|${map.values.join(',')}|$bounds|${from.keys.join(',')}';
    case 24:
      var compared = 0;
      final set = SplayTreeSet<String>((a, b) {
        compared++;
        return a.length.compareTo(b.length);
      }, (key) => key is String)..addAll(['ccc', 'bb', 'a', 'zz']);
      final canonical = set.lookup('??');
      final before = compared;
      // ignore: collection_methods_unrelated_type
      final rejected = !set.contains(7) && set.lookup(null) == null;
      final unchanged = compared == before;
      final copy = set.toSet()..add('long');
      final union = set.union({'zz', 'dddd'});
      final intersection = set.intersection({'a', 'bb'});
      final difference = set.difference({'a'});
      set.retainAll(['z', 'zz']);
      return '$canonical|$rejected/$unchanged|$set|$copy|$union|$intersection|$difference';
    case 25:
      final map = SplayTreeMap<int, int>.of({3: 30, 1: 10, 2: 20});
      final values = <int>[];
      final iterator = map.keys.iterator;
      while (iterator.moveNext()) {
        values.add(iterator.current);
        map[3];
        map[1];
        map[iterator.current] = -iterator.current;
      }
      final modified = map.entries.iterator..moveNext();
      map[4] = 40;
      var detected = 0;
      try {
        modified.moveNext();
      } on ConcurrentModificationError {
        detected++;
      }
      final set = SplayTreeSet<int>.of([3, 1, 2]);
      final keys = <int>[];
      final setIterator = set.iterator;
      while (setIterator.moveNext()) {
        keys.add(setIterator.current);
        set.add(setIterator.current);
        set.contains(3);
      }
      final setModified = set.iterator..moveNext();
      set.remove(2);
      try {
        setModified.moveNext();
      } on ConcurrentModificationError {
        detected++;
      }
      return '$values|$keys|$map|$detected';
    case 26:
      final from = SplayTreeMap<int, String>.from({2: 'b', 1: 'a'});
      final iterable = SplayTreeMap<int, int>.fromIterable(
        [3, 1, 3, 2],
        key: (value) => value as int,
        value: (value) => (value as int) * 10,
      );
      final constructor = SplayTreeMap<int, int>.fromIterables;
      final paired = constructor([2, 1, 2], [20, 10, 21]);
      final set = SplayTreeSet<int>.from(<Object>[3, 1, 2, 2]);
      final Map<Object?, Object?> cast = paired.cast<Object?, Object?>();
      cast[3] = 30;
      var rejected = 0;
      try {
        constructor([1, 2], [1]);
      } on ArgumentError {
        rejected++;
      }
      try {
        SplayTreeMap<int, String>.from(<Object, Object>{'bad': 1});
      } on TypeError {
        rejected++;
      }
      try {
        SplayTreeSet<int>.from(<Object>[1, 'bad']);
      } on TypeError {
        rejected++;
      }
      try {
        cast[4] = 'bad';
      } on TypeError {
        rejected++;
      }
      return '$from|$iterable|$paired|$set|$rejected';
    case 27:
      final map = SplayTreeMap<int, int>.of({1: 10, 3: 30});
      var calls = 0;
      final existing = map.putIfAbsent(1, () {
        calls++;
        return -1;
      });
      final inserted = map.putIfAbsent(2, () {
        map
          ..clear()
          ..[2] = 200
          ..[4] = 40;
        return 20;
      });
      map.update(4, (value) {
        map[2];
        return value + 1;
      });
      map.update(5, (value) => value, ifAbsent: () => 50);
      map.updateAll((key, value) {
        map.firstKey();
        return value + key;
      });
      final snapshot = '$map';
      var detected = false;
      try {
        map.update(2, (value) {
          map.remove(2);
          return value;
        });
      } on ConcurrentModificationError {
        detected = true;
      }
      return '$existing/$inserted/$calls|$snapshot|$map|$detected';
    case 28:
      final map = SplayTreeMap<int, List<int>>();
      final set = SplayTreeSet<int>();
      for (var i = 0; i < 401; i++) {
        final key = i * 31 % 401;
        map[key] = [key, key + 1];
        set.add(key);
      }
      final iterator = map.keys.iterator..moveNext();
      var allocations = 0;
      for (var i = 0; i < 5000; i++) {
        allocations += List<int>.filled(64, i).last;
      }
      var keys = iterator.current;
      while (iterator.moveNext()) {
        keys += iterator.current;
        map.lastKey();
      }
      final copy = set.toSet();
      var sum = 0;
      for (final key in copy) {
        sum += map.remove(key)!.first;
        set.remove(key);
      }
      return '$allocations|$keys/$sum|${map.length}/${set.length}|${copy.length}/${copy.first}/${copy.last}';
    case 29:
      final results = <String>[];
      for (final queue in <Queue<int?>>[
        ListQueue<int?>(8),
        DoubleLinkedQueue<int?>(),
      ]) {
        queue.addAll(List.generate(7, (i) => i));
        for (var i = 0; i < 5; i++) {
          queue.removeFirst();
        }
        queue.addAll([7, 8, 9, 10]);
        queue.addFirst(4);
        queue.addAll(List.generate(30, (i) => i + 11));
        for (var i = 3; i >= 0; i--) {
          queue.addFirst(i);
        }
        queue.add(null);
        final removed = queue.removeLast();
        final first = queue.removeFirst();
        final last = queue.removeLast();
        final found = queue.remove(20);
        final missing = queue.remove(99);
        queue.removeWhere((value) => value!.isEven);
        queue.retainWhere((value) => value! % 3 != 0);
        final copy = queue.toList(growable: false);
        queue
          ..clear()
          ..addAll([null, 7, null]);
        results.add(
          '$removed/$first/$last/$found/$missing|$copy|'
          '${queue.length}/${queue.first}/${queue.last}/${queue.elementAt(1)}',
        );
      }
      return results.join(';');
    case 30:
      final results = <String>[];
      for (final construct in <Queue<int> Function(Iterable<dynamic>)>[
        Queue<int>.from,
        ListQueue<int>.from,
        DoubleLinkedQueue<int>.from,
      ]) {
        final queue = construct(<Object>[1, 2, 2].map((value) => value));
        final view = queue.cast<Object?>();
        view.addFirst(0);
        view.addLast(3);
        var rejected = 0;
        try {
          construct(<Object>[1, 'bad']);
        } on TypeError {
          rejected++;
        }
        try {
          view.addLast('bad');
        } on TypeError {
          rejected++;
        }
        final source = Queue<Object?>.of([1, 'bad', null]);
        final narrowed = Queue.castFrom<Object?, int>(source);
        try {
          narrowed.elementAt(1);
        } on TypeError {
          rejected++;
        }
        // Queue.castFrom passes Object? arguments through without a cast.
        // ignore: collection_methods_unrelated_type
        final removed = narrowed.remove('bad');
        try {
          narrowed.last;
        } on TypeError {
          rejected++;
        }
        source.remove(null);
        results.add('${queue.join(',')}|$rejected/$removed/${narrowed.single}');
      }
      return results.join(';');
    case 31:
      final results = <String>[];
      for (final queue in <Queue<int>>[
        ListQueue<int>(),
        DoubleLinkedQueue<int>(),
      ]) {
        var rejected = 0;
        for (final read in <int Function()>[
          () => queue.first,
          () => queue.last,
          () => queue.single,
          queue.removeFirst,
          queue.removeLast,
        ]) {
          try {
            read();
          } on StateError {
            rejected++;
          }
        }
        queue.addAll([1, 2, 3]);
        final iterator = queue.iterator..moveNext();
        queue.remove(2);
        try {
          iterator.moveNext();
        } on ConcurrentModificationError {
          rejected++;
        }
        try {
          queue.single;
        } on StateError {
          rejected++;
        }
        for (final index in [-1, queue.length]) {
          try {
            queue.elementAt(index);
          } on RangeError {
            rejected++;
          }
        }
        queue.removeLast();
        results.add('$rejected/${queue.single}/${queue.length}');
      }
      return results.join('|');
    case 32:
      final queue = DoubleLinkedQueue<int>.of([1, 3]);
      final first = queue.firstEntry()!;
      first
        ..append(2)
        ..prepend(0)
        ..element = 11;
      queue.lastEntry()!.append(4);
      final boundaries =
          '${queue.firstEntry()!.previousEntry()}/'
          '${queue.lastEntry()!.nextEntry()}/'
          '${first.previousEntry()!.element}/${first.nextEntry()!.element}';
      final visited = <int>[];
      queue.forEachEntry((entry) {
        visited.add(entry.element);
        if (entry.element == 0) {
          entry
            ..prepend(-1)
            ..append(5)
            ..remove();
        } else if (entry.element == 11) {
          entry.append(12);
        } else if (entry.element == 3) {
          entry.remove();
        }
      });
      final result = '$boundaries|$visited|${queue.toList()}/${queue.length}';
      queue.clear();
      final empty = '${queue.firstEntry()}/${queue.lastEntry()}';
      queue.add(7);
      return '$result|$empty/${queue.single}';
    case 33:
      final first = LinkedItem(1);
      final equal = LinkedItem(1);
      final list = LinkedList<LinkedItem>()..addAll([first, equal]);
      first.insertBefore(LinkedItem(0));
      equal
        ..insertAfter(LinkedItem(3))
        ..insertAfter(LinkedItem(2));
      final before =
          '${list.map((entry) => entry.value).toList()}|'
          '${list.first.previous}/${list.last.next}/'
          '${first.previous!.value}/${equal.next!.value}';
      final identity =
          '${first == equal}/${list.contains(LinkedItem(1))}/'
          '${list.remove(LinkedItem(1))}/${list.contains(equal)}';
      final other = LinkedList<LinkedItem>();
      var rejected = false;
      try {
        other.add(equal);
      } on StateError {
        rejected = true;
      }
      equal.unlink();
      final detached = '${equal.list}/${equal.previous}/${equal.next}';
      other.addFirst(equal);
      final moved = '${identical(equal.list, other)}/${other.single.value}';
      final entries = list.toList();
      list.clear();
      final cleared = entries.every(
        (entry) =>
            entry.list == null && entry.next == null && entry.previous == null,
      );
      list.addAll(entries.reversed);
      return '$before|$identity|$rejected/$detached/$moved/$cleared|'
          '${list.map((entry) => entry.value).toList()}';
    case 34:
      final list = LinkedList<LinkedItem>();
      var rejected = 0;
      for (final read in <LinkedItem Function()>[
        () => list.first,
        () => list.last,
        () => list.single,
      ]) {
        try {
          read();
        } on StateError {
          rejected++;
        }
      }
      list.addAll([LinkedItem(1), LinkedItem(2), LinkedItem(3)]);
      final iterator = list.iterator..moveNext();
      list.last.unlink();
      try {
        iterator.moveNext();
      } on ConcurrentModificationError {
        rejected++;
      }
      try {
        // Exercise the callback modification check of LinkedList.forEach.
        // ignore: avoid_function_literals_in_foreach_calls
        list.forEach((entry) => entry.unlink());
      } on ConcurrentModificationError {
        rejected++;
      }
      final value = list.single.value;
      final removed = list.remove(list.single);
      final empty = list.iterator;
      return '$rejected/$value/$removed/${list.isEmpty}/'
          '${empty.moveNext()}/${empty.moveNext()}';
    case 35:
      final queue = ListQueue<List<int>>();
      final linked = DoubleLinkedQueue<List<int>>();
      final list = LinkedList<LinkedItem>();
      for (var i = 0; i < 129; i++) {
        queue.add([i]);
        linked.add([i]);
        list.add(LinkedItem(i));
      }
      final iterator = list.iterator..moveNext();
      final entry = linked.firstEntry()!;
      var allocations = 0;
      for (var i = 0; i < 5000; i++) {
        allocations += List<int>.filled(64, i).last;
      }
      var sum = iterator.current.value;
      while (iterator.moveNext()) {
        sum += iterator.current.value;
      }
      final first = entry.remove().single;
      final last = list.last;
      list.clear();
      list.add(last);
      return '$allocations|$sum/$first/${list.single.value}|'
          '${queue.removeFirst().single}/${queue.removeLast().single}/'
          '${linked.first.single}/${linked.last.single}';
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
