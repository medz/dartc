import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

class UserList<E>(final List<E> values) extends ListBase<E> {
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  E operator [](int index) => values[index];
  @override
  void operator []=(int index, E value) => values[index] = value;
}

Iterable<T> chain<T>(Iterable<T> first, Iterable<T> second) =>
    first.followedBy(second);

void main() {
  for (final first in <List<int>>[
    [1, 2],
    List<int>.of([1, 2], growable: false),
    const [1, 2],
    Uint8List.fromList([1, 2]),
    UserList<int>([1, 2]),
  ]) {
    final result = chain(first, [3, 4]);
    print(jsonEncode(result.toList()));
    print(
      '${result.length}:${result.first}:${result.last}:${result.elementAt(2)}',
    );
  }
  print(jsonEncode(chain<num>(UserList<num>([1]), [2.5]).toList()));
  print(jsonEncode(chain([1, 2], [3, 4].where((_) => true)).toList()));
  print(jsonEncode(chain(Iterable<int>.generate(2), [2, 3]).toList()));
  try {
    chain<num>(UserList<int>([1]), [2.5]);
    print(false);
  } on TypeError {
    print(true);
  }
  final iterator = UserList<int>([5, 6]).followedBy([7, 8]).iterator;
  if (!iterator.moveNext() || iterator.current != 5) throw StateError('first');
  var pressure = 0;
  for (var i = 0; i < 40000; i++) {
    pressure += <Object>[i, '$i'].length;
  }
  if (pressure != 80000) throw StateError('allocation pressure');
  final rest = <int>[];
  while (iterator.moveNext()) {
    rest.add(iterator.current);
  }
  print(jsonEncode(rest));
  try {
    final dynamic incompatible = UserList<num>([2.5]);
    chain<int>([1], incompatible);
    print(false);
  } on TypeError {
    print(true);
  }
}
