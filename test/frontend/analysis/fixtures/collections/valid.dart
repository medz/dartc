// The SDK folds the boundary comparison and null-aware entries incorrectly.
// ignore_for_file: equal_elements_in_const_set, equal_keys_in_const_map, list_element_type_not_assignable, map_key_type_not_assignable, const_eval_throws_idbze, const_eval_throws_exception

import '../numeric_constants.dart';

const greater = integer > floating;
const equal = integer == floating;
const uniqueSet = <bool>{true, equal};
const uniqueMap = <bool, int>{true: 1, equal: 2};
const values = <int>[
  if (greater) 7 else 1 ~/ 0,
  (greater ? 8 : 'wrong') as dynamic,
  ?(greater ? null : 9),
  ?(greater ? 9 : null),
  10,
  ...(greater ? <int>[11] : <String>['wrong']) as dynamic,
  ...<dynamic>[12],
];
const mapping = <int, int>{
  ?(greater ? null : 3): 1 ~/ 0,
  1: ?(greater ? null : 2),
  2: 3,
  ...(greater ? <int, int>{4: 5} : <String, int>{'wrong': 0}) as dynamic,
};
const elements = <int>{
  ?(greater ? null : 1),
  ?(greater ? 2 : null),
  3,
  ...[4],
};
const records = <(bool,), int>{(true,): 1, (equal,): 2};

int listSum() {
  var sum = 0;
  for (final value in values) {
    sum += value;
  }
  return sum;
}

int mapSum() => mapping.length + mapping[2]! + mapping[4]!;
int setSum() {
  var sum = 0;
  for (final value in elements) {
    sum += value;
  }
  return sum;
}

int sizes() => uniqueSet.length + uniqueMap.length + records.length;
