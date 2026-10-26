class Box {
  int value;
  Box(this.value);
  String toString() => 'Box(' + this.value.toString() + ')';
}

class Plain {
  int value;
  Plain(this.value);
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
  Cell(this.value, this.optional);
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
  listGrowth(args);
}
