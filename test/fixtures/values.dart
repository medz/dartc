int boxStrings = 0;

class Box {
  int value;
  int extra;
  Box(this.value, {this.extra = 7});
  String toString() {
    boxStrings++;
    return 'Box(' + this.value.toString() + ')';
  }

  void arguments(
    int first,
    String second,
    bool third,
    Object? fourth,
    Box fifth,
    List<int> sixth,
    num seventh, {
    required int last,
    bool flag = false,
    String tag = 'tail',
    Object? absent,
    int wide = -9223372036854775808,
  }) {
    print(<Object?>[
      value,
      first,
      second,
      third,
      fourth,
      fifth.value,
      sixth[0],
      seventh,
      last,
      flag,
      tag,
      absent,
      wide,
    ]);
  }

  int recurse(int count, {int bias = 1}) {
    if (count == 0) return value + bias;
    return recurse(count - 1, bias: bias + 1);
  }
}

class Plain {
  int value;
  Plain([this.value = 7]);
}

class UnusedType {}

class Echo {
  List<dynamic> owner;
  Echo(this.owner);
  String toString() {
    print(this.owner);
    return 'Echo';
  }
}

void objectValues() {
  dynamic value = 1;
  print(value);
  value = value + 2;
  print(value);
  print(value == 3);
  value = true;
  print(value & false);
  print(value | false);
  print(value ^ true);
  Object object = 9223372036854775807;
  print(object);
  Object? absent = null;
  print(absent);
  var mixed = [
    1,
    'hi',
    true,
    null,
    Box(5),
    <int>[7, 8],
  ];
  print(mixed);
  List<dynamic> values = <dynamic>[2, 'text', false, null, Plain(3)];
  print(values);
  List<int> ints = <int>[1, 2];
  List<Object> view = ints;
  print(view[0]);
  view.add(3);
  print(ints);
  List<Object?> nullableView = <dynamic>[1, null, '字🙂'];
  print(nullableView);
  int? number = 3;
  print(number);
  number = null;
  print(number);
  String? text = '你好🙂';
  print(text);
  text = null;
  print(text);
  dynamic maximum = 9223372036854775807;
  print(maximum);
  print(maximum + 1);
  var cycle = <dynamic>[];
  cycle.add(cycle);
  print(cycle);
  var owner = <dynamic>[];
  owner.add(Echo(owner));
  print(owner);
  print(owner);
}

var global = null;
int calls = 0;

dynamic pass(dynamic value) => value;
int integer(int value) => value + 1;
String string(String value) => value;

bool tick() {
  calls++;
  return true;
}

bool choose() => true;

void touchVoid() {
  print('void');
}

void valueVoid() => 7;

class Cell {
  dynamic value;
  Object? optional;
  Object _hidden;
  Cell(this.value, this.optional, {int this._hidden = 7});
  toString() => 'Cell(${this.value},${this.optional})';
}

void valueContexts() {
  var local = null;
  local = 7;
  global = 'global';
  print(local);
  print(global);
  print(integer(pass(8)));
  print(string(pass('你好🙂')));
  dynamic value = pass(false);
  print(!value);
  if (value) print('unreachable');
  print(value && tick());
  value = pass(true);
  print(value || tick());
  print(calls);
  print(value & false);
  print(value | false);
  print(value ^ true);
  value = 5;
  print(value++);
  print(++value);
  value += 3;
  print(value);
  print(value - 2);
  print(value * 2);
  print(value ~/ 3);
  print(value % 3);
  print(value << 2);
  print(value >> 2);
  value = -1;
  print(value >>> 1);
  print(-value);
  print(~value);
  print(value < 0);
  print(value >= 0);
  print(value != false);
  value = 'tagged';
  print('text=' + value);
  print(value.toString());
  var mixed = choose() ? 1 : 'other';
  print(mixed);
  var nullable = !choose() ? 1 : null;
  print(nullable);
  String? absent = null;
  print(absent.toString());
  absent = pass('text');
  if (absent != null) print(absent.length);
  bool? flag = false;
  print(flag);
  flag = null;
  print(flag);
  var holder = Cell(3, null);
  print(holder);
  holder.value = 'changed';
  holder.optional = true;
  print(holder);
  List<void> erased = <void>[
    1,
    's',
    null,
    true,
    holder,
    touchVoid(),
    valueVoid(),
  ];
  List<Object?> view = erased;
  print(view);
  List<Object?> repeatedVoid = List<void>.filled(2, touchVoid());
  print(repeatedVoid);
  List<Object?> repeatedValue = List<void>.filled(2, valueVoid());
  print(repeatedValue);
  var inferredVoid = [valueVoid()];
  List<Object?> inferredView = inferredVoid;
  print(inferredView);
  var inferredFilled = List.filled(1, valueVoid());
  List<Object?> inferredFilledView = inferredFilled;
  print(inferredFilledView);
  var nested = <List<Object>>[
    <int>[1],
    <String>['x'],
  ];
  print(nested);
  print(nested[0][0]);
  var optionalNumbers = [1, null, 2];
  print(optionalNumbers);
  for (int item in <dynamic>[1, 2]) print(item);
  var values = List<dynamic>.filled(1, 'ok');
  print(values[0]);
  print('interpolate=${pass(null)},${pass(false)},${pass(1)}');
}

int assignmentTrace = 0;
List<Object> assignmentStorage = <int>[0];

List<Object> assignmentReceiver() {
  assignmentTrace = assignmentTrace * 10 + 1;
  return assignmentStorage;
}

int assignmentIndex() {
  assignmentTrace = assignmentTrace * 10 + 2;
  return 0;
}

int assignmentValue() {
  assignmentTrace = assignmentTrace * 10 + 3;
  return 6;
}

void assignmentValues() {
  dynamic slot;
  var localValues = [slot = 1];
  List<int> localInts = localValues;
  print(localInts[0]);
  print(slot);
  Object object = 0;
  var objectValues = [object = 2];
  List<int> objectInts = objectValues;
  print(objectInts[0]);
  print(object);
  var globalValues = [global = 3];
  List<int> globalInts = globalValues;
  print(globalInts[0]);
  var holder = Cell(0, null);
  var fieldValues = [holder.optional = 4];
  List<int> fieldInts = fieldValues;
  print(fieldInts[0]);
  var indexedValues = [
    assignmentReceiver()[assignmentIndex()] = assignmentValue(),
  ];
  List<int> indexedInts = indexedValues;
  print(indexedInts[0]);
  print(assignmentStorage);
  print(assignmentTrace);
}

int typeEvaluations = 0;

dynamic typeValue(dynamic value) {
  typeEvaluations++;
  return value;
}

void typeChecks() {
  dynamic value = 5;
  print(value is int);
  print(value is! String);
  print((value as int) + 1);
  print((value as Object) is int);
  print((value as dynamic) is int);
  print(pass(value) is int ? 'integer' : 'other');
  print(pass(1) + 2 is int);
  print(1 + 2 is! String);
  print(pass(3) is int == true);
  value = null;
  // Exercise Null and top-type operators even when an equivalent check exists.
  // ignore: type_check_with_null
  print(value is Null);
  // ignore: unnecessary_type_check
  print(value is dynamic);
  print(value is Object);
  // ignore: unnecessary_type_check
  print(value is Object?);
  print(value is int?);
  print(value as Null);
  print(value as int?);
  print(value as String?);
  value = Box(13);
  print(value is Box);
  print(value is UnusedType);
  print(value is Plain);
  print(value is Box?);
  print((value as Box).value);
  Object object = value;
  print((object as Box).value);
  value = <int>[1, 2];
  print(value is List<int>);
  print(value is List<Object>);
  print(value is! List<String>);
  print((value as List<int>)[0]);
  print(value as List<Object>);
  value = <int?>[1, null];
  print(value is List<int?>);
  print(value is! List<int>);
  print(value as List<Object?>);
  value = <List<int>>[
    <int>[3],
  ];
  print(value is List<List<int>>);
  print(value is List<List<Object>>);
  print(value is! List<List<String>>);
  print((value as List<List<Object>>)[0][0]);
  value = pass(<void>[1, 'text']);
  print(value is List<void>);
  print(value as List<Object?>);
  value = <dynamic>[1];
  print(value is! List<int>);
  print(typeValue(7) is int);
  print(typeValue(8) as int);
  print(typeValue(true) is! bool);
  print(typeValue(false) as bool);
  print(!choose() && typeValue(1) is int);
  print(choose() || typeValue(false) as bool);
  typeValue(9) is int;
  typeValue(10) as int;
  print(typeEvaluations);
}

int filledTrace = 0;

int filledLength() {
  filledTrace = filledTrace * 10 + 1;
  return 1;
}

int filledValue() {
  filledTrace = filledTrace * 10 + 2;
  return 5;
}

bool filledGrowable() {
  filledTrace = filledTrace * 10 + 3;
  return true;
}

void filledLists() {
  var values = List<int>.filled(
    filledLength(),
    filledValue(),
    growable: filledGrowable(),
  );
  values.add(7);
  print(values);
  print(filledTrace);
  var fixed = List<int>.filled(2, 4);
  fixed[0] = 9;
  print(fixed);
  var explicitFixed = List<int>.filled(1, 2, growable: false);
  explicitFixed[0] = 3;
  print(explicitFixed);
  dynamic growable = true;
  var dynamicFlag = List<bool>.filled(0, false, growable: growable);
  dynamicFlag.add(true);
  print(dynamicFlag);
}

String conditionTrace = '';

dynamic conditionOperand(int marker, bool value) {
  conditionTrace = conditionTrace + marker.toString();
  return value;
}

int conditionChoice(int marker) {
  conditionTrace = conditionTrace + marker.toString();
  return marker;
}

bool lazyCondition =
    (conditionOperand(1, false) || conditionOperand(2, true)) &&
        !conditionOperand(3, false)
    ? conditionOperand(4, true) || conditionOperand(5, false)
    : conditionOperand(6, false);

void conditionCase(int bits, bool a, bool b, bool c, bool d) {
  conditionTrace = '';
  int result = 0;
  if ((conditionOperand(1, a) || conditionOperand(2, b)) &&
      !(conditionOperand(3, c) && !conditionOperand(4, d))) {
    result = 1;
  }
  print('$bits:$result:$conditionTrace');
}

void conditionLoops(int stop) {
  conditionTrace = '';
  int index = 0, total = 0;
  while (conditionOperand(1, index < 5) &&
      (!conditionOperand(2, index == 2) || conditionOperand(3, index < 4))) {
    index++;
    if (index == 2) continue;
    total += index;
    if (index == stop) break;
  }
  print('while:$index:$total:$conditionTrace');
  conditionTrace = '';
  total = 0;
  for (
    index = 0;
    conditionOperand(1, index < 5) &&
        (conditionOperand(2, index != 2) || !conditionOperand(3, index >= 5));
    index++
  ) {
    if (index == 1) continue;
    total += index;
    if (index == stop) break;
  }
  print('for:$index:$total:$conditionTrace');
  conditionTrace = '';
  index = 0;
  total = 0;
  do {
    index++;
    if (index == 2) continue;
    total += index;
    if (index == stop) break;
  } while (conditionOperand(1, index < 5) &&
      (conditionOperand(2, index != 3) || !conditionOperand(3, index >= 5)));
  print('do:$index:$total:$conditionTrace');
}

void conditionTernary(bool a, bool b) {
  conditionTrace = '';
  var selected = conditionOperand(1, a) || !conditionOperand(2, b)
      ? conditionChoice(5)
      : conditionChoice(6);
  print('ternary:$selected:$conditionTrace');
}

void conditionComparisons(dynamic value) {
  conditionTrace = '';
  int result = 0;
  if (argumentValue(1, value) < 3) result += 1;
  if (!(argumentValue(2, value) >= 3)) result += 2;
  if (argumentValue(3, value) < 3 && argumentValue(4, value) > 0) result += 4;
  if (argumentValue(5, value) >= 3 || argumentValue(6, value) == 0) result += 8;
  dynamic boxed = argumentValue(7, value) < 3;
  bool explicit = boxed as bool;
  print(<dynamic>[boxed, !(argumentValue(8, value) < 3)]);
  print('$result:$explicit:$conditionTrace');
}

void conditionContexts() {
  for (int bits = 0; bits < 16; bits++) {
    conditionCase(
      bits,
      (bits & 1) != 0,
      (bits & 2) != 0,
      (bits & 4) != 0,
      (bits & 8) != 0,
    );
  }
  conditionLoops(3);
  conditionLoops(9);
  conditionTernary(true, true);
  conditionTernary(false, true);
  conditionTernary(false, false);
  dynamic invalid = pass(1);
  if (choose() || invalid) print('short circuit');
  if (!choose() && invalid) print('unreachable');
  conditionTrace = '';
  var first = lazyCondition;
  var second = lazyCondition;
  print('lazy:$first:$second:$conditionTrace');
  conditionComparisons(pass(1));
  conditionComparisons(pass(4));
  conditionComparisons(pass(0));
}

class BindingProbe {
  int value;
  BindingProbe(this.value) {
    value += 1;
  }

  int get doubled => value * 2;
  int parameter(int value) => value + this.value;

  int localGetter() {
    int doubled = 3;
    return doubled + this.doubled;
  }

  int localField() {
    int value = 4;
    {
      value += 1;
    }
    return value + this.value;
  }
}

int bindingParameter(int value) {
  int value = 9;
  return value;
}

int bindingCalls = 0;
int _ = 11;

int bindingMark() {
  bindingCalls++;
  return bindingCalls;
}

void localBindings() {
  int value = 1;
  {
    int value = 2;
    {
      int value = 3;
      print(value);
    }
    print(value);
  }
  {
    value += 4;
  }
  print(value);
  for (int value = 0; value < 2; value++) print(value);
  print(value);
  var rows = <int>[6, 7];
  for (var rows in rows) print(rows);
  print(rows);
  for (int value = 0; value < 1; value++) {
    int value = 8;
    print(value);
  }
  switch (2) {
    case 1:
      int branch = 1;
      print(branch);
      break;
    case 2:
      int branch = 2;
      print(branch);
      break;
  }
  // A label does not introduce a declaration scope.
  // ignore: unused_label
  mark:
  int marked = 10;
  print(marked);
  var probe = BindingProbe(5);
  print(probe.value);
  print(probe.parameter(2));
  print(probe.localGetter());
  print(probe.localField());
  print(bindingParameter(2));
  for (int shadow = 0; shadow < 2; shadow++)
    // ignore: unused_local_variable
    int shadow = bindingMark();
  if (choose())
    // ignore: unused_local_variable
    int value = bindingMark();
  print(value);
  int _ = bindingMark();
  int _ = bindingMark();
  print(bindingCalls);
  print(_);
}

void flowBranches(Object? value, int? number) {
  print(value is Box && value.value > 0);
  print(value is! Box || value.value > 0);
  var selected = value is Box ? value.value : -1;
  print(selected);
  if (value is Box) {
    var inferred = [value];
    List<Box> boxes = inferred;
    print(boxes[0].value);
  } else if (value is String) {
    print(value.length);
  }
  if (number is! int) {
    var inferred = [number];
    List<Null> absent = inferred;
    print(absent);
  } else {
    var inferred = [number];
    List<int> numbers = inferred;
    print(numbers);
  }
  if (number == null) number = 4;
  var present = [number];
  List<int> presentNumbers = present;
  print(presentNumbers[0] + 1);
  if (value != null && value is! Box) {
    var inferred = [value];
    List<Object> objects = inferred;
    print(objects);
  }
}

void flowExit(Object? value) {
  if (value is! int) return;
  var inferred = [value];
  List<int> numbers = inferred;
  print(numbers);
}

void flowAssignments(Object value, dynamic other) {
  if (value is int) {
    var inferred = [value++, ++value, value += 2];
    List<int> numbers = inferred;
    print(numbers);
    value = 8;
    var retained = [value];
    List<int> retainedNumbers = retained;
    print(retainedNumbers);
    value = 'changed';
    print([value] is List<String>);
  }
  if (other is int) {
    other = 9;
    var inferred = [other];
    List<int> numbers = inferred;
    print(numbers);
    other = 'dynamic';
    print([other] is List<String>);
  }
}

void flowContexts() {
  Object object = 1;
  Object? optional = 2;
  dynamic unknown = 3;
  print([object] is List<int>);
  print([optional] is List<int>);
  print([unknown] is List<int>);
  int? number = 1;
  var updates = [number++, ++number, number += 2];
  List<int> updatedNumbers = updates;
  print(updatedNumbers);
  Object cast = pass(Box(12));
  cast as Box;
  print(cast.value);
  unknown as int;
  var castValues = [unknown];
  List<int> castNumbers = castValues;
  print(castNumbers);
  Object joined = pass(7);
  if (choose()) {
    joined as int;
  } else {
    joined as int;
  }
  var joinedValues = [joined];
  List<int> joinedNumbers = joinedValues;
  print(joinedNumbers);
  flowBranches(Box(6), 2);
  flowBranches('text', null);
  flowExit(10);
  flowExit(null);
  flowAssignments(1, 2);
  int? loopValue;
  do {
    loopValue = 4;
  } while (!choose());
  var doValues = [loopValue];
  List<int> doNumbers = doValues;
  print(doNumbers);
  loopValue = null;
  for (loopValue = 5; !choose();) {}
  var forValues = [loopValue];
  List<int> forNumbers = forValues;
  print(forNumbers);
  loopValue = null;
  while (loopValue == null) loopValue = 6;
  var whileValues = [loopValue];
  List<int> whileNumbers = whileValues;
  print(whileNumbers);
  Object countdown = 2;
  while (countdown is int && countdown > 0) {
    print(countdown + 1);
    countdown = 0;
  }
  Object? last;
  for (var item in <int>[8]) last = item;
  print([last] is List<int>);
  int switched;
  switch (choose()) {
    case true:
      switched = 11;
      break;
    case false:
      switched = 12;
      break;
  }
  print(switched);
  int carried;
  int turn = 0;
  do {
    carried = ++turn;
    if (turn == 1) continue;
    break;
  } while (turn < 3);
  print([carried, turn]);
}

int staticReturn(dynamic value) => value;

void staticContexts(Object? left, Object? right) {
  dynamic rhs = pass(2);
  var sums = [1 + rhs];
  List<num> numbers = sums;
  dynamic reified = numbers;
  print(numbers);
  print(reified is List<num>);
  print(reified is List<int>);
  print([rhs + 1] is List<num>);
  var comparisons = [rhs < 1];
  print(comparisons);
  print(comparisons is List<bool>);
  var integers = [7 ~/ rhs, 7 & rhs];
  List<int> typedIntegers = integers;
  print(typedIntegers);
  var flags = [true & pass(false), !pass(true), 1 < rhs];
  List<bool> typedFlags = flags;
  print(typedFlags);
  var words = ['s' + pass('t')];
  List<String> typedWords = words;
  print(typedWords);
  Object compound = 1;
  if (compound is int) {
    var changes = [compound += rhs];
    List<num> changedNumbers = changes;
    dynamic changedType = changedNumbers;
    print(changedNumbers);
    print(changedType is List<int>);
  }
  num number = 4;
  var plain = [number, -number, number + 2];
  List<num> plainNumbers = plain;
  print(plainNumbers);
  print(plain is List<int>);
  int quotient = number ~/ 2;
  print(quotient);
  if (number is int) print(number & 1);
  List<num> owned = <num>[1, 9223372036854775807];
  List<Object> objects = owned;
  objects[0] = 3;
  objects.add(5);
  print(owned);
  print(owned[1]);
  List<num> view = <int>[6];
  view[0] = 7;
  view.add(8);
  print(view);
  print(view[0]);
  print(pass(1) is num);
  print(pass(9223372036854775807) is num);
  print(pass('text') is num);
  print(staticReturn(pass(9)));
  print(left == right);
  print(left != null);
  print(null == right);
  print(right.toString());
}

const int argumentDefault = 4;

dynamic argumentValue(int marker, dynamic value) {
  conditionTrace = conditionTrace + marker.toString();
  return value;
}

String namedArguments(
  int first,
  int second, {
  required String label,
  int count = argumentDefault,
  Object? value,
  bool flag = true,
}) {
  print(<Object?>[first, second, label, count, value, flag]);
  return label;
}

void positionalArguments([
  int argumentDefault = argumentDefault,
  String label = 'positional',
  bool flag = true,
  Object? value,
  int? nullable = 9,
  num wide = 9223372036854775807,
  int left = 1 << 64,
  int unsigned = -1 >>> 64,
]) {
  print(<Object?>[
    argumentDefault,
    label,
    flag,
    value,
    nullable,
    wide,
    left,
    unsigned,
  ]);
}

void nullableArguments({required Object? value, Object? fallback = 'default'}) {
  print(<Object?>[value, fallback]);
}

int recursiveArguments(int count, {int total = 1}) {
  if (count == 0) return total;
  return recursiveArguments(count - 1, total: total + count);
}

void argumentCalls() {
  conditionTrace = '';
  print(
    namedArguments(
      count: argumentValue(1, 5),
      argumentValue(2, 2),
      label: argumentValue(3, 'named'),
      argumentValue(4, 4),
      value: argumentValue(5, Box(6)),
      flag: argumentValue(6, false),
    ),
  );
  print(conditionTrace);
  namedArguments(2, 4, label: 'omitted');
  positionalArguments();
  positionalArguments(2, 'explicit', false, Box(3), null, -9223372036854775808);
  nullableArguments(value: null);
  nullableArguments(fallback: null, value: 9223372036854775807);
  var box = Box(9, extra: 11);
  print(Box(9).extra);
  print(box.extra);
  print(Plain().value);
  print(Plain(3).value);
  print(Cell(1, null)._hidden);
  print(Cell(1, null, hidden: pass(9))._hidden);
  var values = <int>[7];
  conditionTrace = '';
  (argumentValue(0, box) as Box).arguments(
    wide: argumentValue(1, 9223372036854775807),
    argumentValue(2, 1),
    tag: argumentValue(3, 'tag'),
    argumentValue(4, '字🙂'),
    flag: argumentValue(5, false),
    argumentValue(6, true),
    argumentValue(7, 9223372036854775807),
    last: argumentValue(8, 8),
    argumentValue(9, Box(12)),
    absent: argumentValue(10, null),
    argumentValue(11, values),
    argumentValue(12, 9223372036854775807),
  );
  print(conditionTrace);
  print(<Object?>[box.value, box.extra, values[0]]);
  box.arguments(1, 'short', false, null, Box(2), values, 3, last: 8);
  print(recursiveArguments(3));
  print(box.recurse(2));
}

void literalShifts(int value) {
  print(<int>[
    value << 0,
    value >> 0,
    value >>> 0,
    value << 1,
    value >> 1,
    value >>> 1,
    value << 31,
    value >> 31,
    value >>> 31,
    value << 32,
    value >> 32,
    value >>> 32,
    value << 63,
    value >> 63,
    value >>> 63,
  ]);
}

void shiftContexts() {
  for (int count in <int>[0, 63, 64, 65, 9223372036854775807]) {
    print(<int>[1 << count, -1 >> count, -1 >>> count]);
    print(<int>[-1 << count, 1 >> count, 1 >>> count]);
  }
  literalShifts(-9223372036854775808);
  literalShifts(9223372036854775807);
  literalShifts(-1);
}

const Object constantObject = 1;
const num constantNumber = 1;
const List<num> constantNumbers = [
  1,
  9223372036854775807,
  -9223372036854775808,
];
const constantMatrix = [
  [1],
  [1],
];
const constantIdentity = identical(const <int>[1], const <int>[1]);

void constantDefaults([
  List<int> empty = const [],
  List<List<int>> nested = const [[]],
]) {
  print(identical(empty, const <int>[]));
  print(identical(nested[0], const <int>[]));
  print(nested);
}

void constantLists() {
  const words = <int>[-9223372036854775808, 9223372036854775807];
  const flags = <bool>[false, true];
  const texts = <String?>[null, '字🙂'];
  const optional = <int?>[null, 0, -9223372036854775808];
  const tagged = <dynamic>[
    0,
    false,
    '轻🙂',
    null,
    <int>[13],
  ];
  const deep = <List<List<String?>>?>[
    null,
    <List<String?>>[
      <String?>['深🙂', null],
    ],
  ];
  print(words);
  print(flags);
  print(texts);
  print(optional);
  print(tagged);
  print(deep);
  const first = <Object?>[constantObject, '好🙂', null, true];
  const second = <Object?>[constantNumber, '好🙂', null, true];
  print(first);
  print(identical(first, second));
  print(first == second);
  print(constantIdentity);
  print(identical(const <Object>[1], const <num>[1]));
  print(identical(const <num>[1], const <int>[1]));
  print(identical(constantMatrix[0], constantMatrix[1]));
  print(identical(constantMatrix[0], const <int>[1]));
  const widened = <List<Object>>[
    <int>[1],
  ];
  print(identical(widened[0], constantMatrix[0]));
  print(
    identical(widened, const <List<Object>>[
      <Object>[1],
    ]),
  );
  const empty = [];
  print(empty is List<int>);
  print(identical(empty, const <dynamic>[]));
  const List<int> contextual = [];
  print(identical(contextual, const <int>[]));
  const token = 2;
  const local = [token];
  print(identical(local, const <int>[2]));
  const Object promoted = 1;
  if (promoted is int) {
    const typed = <int>[promoted];
    print(identical(typed, constantMatrix[0]));
  }
  const int? nullable = 1;
  const present = <int>[nullable];
  print(identical(present, constantMatrix[0]));
  List<Object> view = constantNumbers;
  print(view);
  print(view[1]);
  print(identical(view, constantNumbers));
  constantDefaults();
}

void bufferValues() {
  boxStrings = 0;
  var buffer = StringBuffer(7);
  buffer.write(null);
  buffer.writeln();
  buffer.writeln(Box(4));
  print(buffer.toString());
  print(boxStrings);
  print(buffer.toString());
  print(boxStrings);
  var initial = StringBuffer(Box(5));
  print(initial.toString());
  print(boxStrings);
}

int stringEvaluations = 0;

String stringReceiver() {
  stringEvaluations++;
  return 'a🙂b';
}

void stringBoundaries() {
  print(stringReceiver().substring(1));
  print(stringReceiver().lastIndexOf(''));
  print(stringEvaluations);
  var text = 'a🙂b';
  for (int start = 0; start <= text.length; start++) {
    print(text.substring(start, start));
    print(text.indexOf('', start));
    print(text.lastIndexOf('', start));
    print(text.startsWith('', start));
  }
  print(text.codeUnitAt(3));
  var codes = String.fromCharCodes(<int>[0, 55296, 120, 57343, 1114111]);
  print(codes.length);
  print(codes.codeUnitAt(1));
  print(codes.codeUnitAt(3));
  print(codes.substring(4));
}

void listGrowth(List<String> args) {
  var values = <int>[];
  values.clear();
  print(values.length);
  int i = 0;
  while (i < 80) {
    values.add(i);
    i = i + 1;
  }
  print(values.length);
  print(values[0]);
  print(values[79]);
  print(values.removeLast());
  print(values.length);
  values.clear();
  print(values.length);
  values.add(91);
  print(values[0]);
  var texts = <String>[];
  i = 0;
  while (i < 80) {
    texts.add(i.toString() + ':好');
    i = i + 1;
  }
  print(texts[0]);
  print(texts[79]);
  print(texts.removeLast());
  texts.clear();
  texts.add('🙂');
  print(texts[0]);
  var empty = List<int>.filled(0, 0, growable: true);
  empty.clear();
  empty.add(7);
  print(empty[0]);
  var filled = List<int>.filled(3, 6, growable: true);
  filled.add(8);
  print(filled[0]);
  print(filled[3]);
  var flags = List<bool>.filled(3, true);
  print(flags[0]);
  var entries = List<Box>.filled(2, Box(17));
  entries[0].value = 19;
  print(entries[1].value);
  var nested = List<List<int>>.filled(2, <int>[5]);
  nested[0][0] = 21;
  print(nested[1][0]);
  var words = List<String>.filled(2, '中文');
  print(words[1]);
  print(args.length);
  print(args[0]);
}

void main(List<String> args) {
  objectValues();
  valueContexts();
  assignmentValues();
  typeChecks();
  filledLists();
  conditionContexts();
  localBindings();
  flowContexts();
  staticContexts(1, null);
  argumentCalls();
  shiftContexts();
  constantLists();
  bufferValues();
  stringBoundaries();
  listGrowth(args);
}
