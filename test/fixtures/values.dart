int boxStrings = 0;

class Box {
  int value;
  int extra;
  int? cached;
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
    int wide = -9_223_372_036_854_775_808,
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

  int get access {
    conditionTrace = conditionTrace + '2';
    return value;
  }

  set access(int next) {
    conditionTrace = conditionTrace + '4';
    value = next;
  }

  int? get conditionalAccess {
    conditionTrace = conditionTrace + '2';
    return cached;
  }

  set conditionalAccess(int next) {
    conditionTrace = conditionTrace + '4';
    cached = next;
  }

  int? get opaqueAccess => cached;
  set opaqueAccess(void next) {
    print(<void>[next]);
  }

  int get textLength => value;
  set textLength(String text) {
    value = text.length;
  }

  int get number => value;
  set number(num next) {
    value = next as int;
  }

  set writeOnly(int next) {
    value = next;
  }

  void updateAccess(int next) {
    access = next;
    access += 1;
  }
}

class Plain {
  final int value;
  final bool enabled = true;
  int assigned = 0;
  Plain([this.value = 7]);
  set value(int next) {
    assigned = next;
  }
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
void opaqueValue(dynamic value) => value;

class Cell {
  dynamic value;
  Object? optional;
  final Object _hidden;
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
  conditionTrace = '';
  print(<Object?>[
    opaqueValue(argumentValue(1, 9223372036854775807)) as int,
    opaqueValue(-9223372036854775808) as int,
    opaqueValue(false) as bool,
    opaqueValue(null) as Null,
    opaqueValue('字🙂') as String,
    (opaqueValue(<int>[8]) as List<int>)[0],
    (opaqueValue(holder) as Cell).value,
  ]);
  print(conditionTrace);
  var payload = <int>[9];
  print(identical(payload, opaqueValue(payload) as List<Object>));
  var dynamicValues = [opaqueValue(1) as dynamic];
  print(dynamicValues is List<int>);
  var objectValues = [opaqueValue(1) as Object];
  print(objectValues is List<int>);
  var numValues = [opaqueValue(9223372036854775807) as num];
  print(numValues is List<int>);
  void castLocal = 3;
  castLocal as int;
  var localValues = [castLocal];
  List<int> localInts = localValues;
  print(localInts);
  void nullableLocal = null;
  nullableLocal as int?;
  var nullValues = [nullableLocal];
  List<int?> nullableInts = nullValues;
  print(nullableInts);
  print(nullValues is List<int>);
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

void accessorValues() {
  var box = Box(4);
  conditionTrace = '';
  print((argumentValue(1, box) as Box).access = conditionChoice(3));
  print(conditionTrace);
  conditionTrace = '';
  print((argumentValue(1, box) as Box).access += conditionChoice(3));
  print(conditionTrace);
  conditionTrace = '';
  print((argumentValue(1, box) as Box).access++);
  print(conditionTrace);
  conditionTrace = '';
  print(++(argumentValue(1, box) as Box).access);
  print(conditionTrace);
  conditionTrace = '';
  box.updateAccess(9);
  print(<Object>[box.value, conditionTrace]);
  print(box.textLength = '字🙂');
  print(box.textLength);
  var combined = [box.number += pass(2)];
  List<num> numbers = combined;
  print(combined is List<int>);
  print(numbers);
  var assigned = [box.writeOnly = pass(9223372036854775807)];
  print(assigned is List<int>);
  print(assigned);
  print(box.value);
  var plain = Plain(8);
  print(<int>[plain.value, plain.assigned]);
  plain.value = 9;
  print(<int>[plain.value, plain.assigned]);
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

int topStorage = 4;
int get topAccess {
  conditionTrace = conditionTrace + '1';
  return topStorage;
}

set topAccess(int next) {
  conditionTrace = conditionTrace + '3';
  topStorage = next;
}

int get topLength => topStorage;
set topLength(String text) {
  topStorage = text.length;
}

int get topNumber => topStorage;
set topNumber(num next) {
  topStorage = next as int;
}

set topOnly(int next) {
  topStorage = next;
}

get topUntyped => global;
set topUntyped(next) {
  global = next;
}

final int topFinal = 7;
set topFinal(int next) {
  topStorage = next;
}

const int topConstant = 8;
set topConstant(int next) {
  topStorage = next;
}

void topAccessorValues() {
  conditionTrace = '';
  print(topAccess = conditionChoice(2));
  print(conditionTrace);
  conditionTrace = '';
  print(topAccess += conditionChoice(2));
  print(conditionTrace);
  conditionTrace = '';
  print(topAccess++);
  print(conditionTrace);
  conditionTrace = '';
  print(++topAccess);
  print(conditionTrace);
  print(topLength = '字🙂');
  print(topLength);
  var combined = [topNumber += pass(2)];
  List<num> numbers = combined;
  print(combined is List<int>);
  print(numbers);
  var assigned = [topOnly = pass(9223372036854775807)];
  print(assigned is List<int>);
  print(assigned);
  print(topStorage);
  topUntyped = 'untyped';
  print([topUntyped] is List<String>);
  print(topUntyped);
  topFinal = 9;
  print(<int>[topFinal, topStorage]);
  topConstant = 10;
  print(<int>[topConstant, topStorage]);
}

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

List<Object>? coalescingStorage;
List<Object>? get coalescingTop {
  conditionTrace = conditionTrace + '1';
  return coalescingStorage;
}

set coalescingTop(List<int> next) {
  conditionTrace = conditionTrace + '3';
  coalescingStorage = next;
}

void coalescingAssignmentFlow(
  int? number,
  List<Object>? lists,
  Object? object,
) {
  var inferred = [number ??= nonCompletingWhile()];
  List<int> numbers = inferred;
  print(<Object>[numbers, number + 1]);
  object ??= 7;
  var retained = [object];
  List<Object> objects = retained;
  print(retained is List<int>);
  print(objects);
  if (lists is List<int>?) {
    var assigned = [lists ??= []];
    List<List<int>> integers = assigned;
    print(integers);
  }
}

void coalescingAssignmentValues() {
  int? local = pass(null);
  var assigned = [local ??= 6];
  List<int> integers = assigned;
  print(<Object>[integers, local + 1]);
  global = null;
  conditionTrace = '';
  print([global ??= conditionChoice(5), global ??= conditionChoice(6)]);
  print(conditionTrace);
  var cell = Cell(0, null);
  conditionTrace = '';
  print((argumentValue(1, cell) as Cell).optional ??= conditionChoice(3));
  print(conditionTrace);
  var indexed = <int?>[null];
  for (var attempt = 0; attempt < 2; attempt++) {
    conditionTrace = '';
    print(
      (argumentValue(1, indexed) as List<int?>)[conditionChoice(2) - 2] ??=
          conditionChoice(3),
    );
    print(conditionTrace);
  }
  var box = Box(0);
  for (var attempt = 0; attempt < 2; attempt++) {
    conditionTrace = '';
    print(
      (argumentValue(1, box) as Box).conditionalAccess ??= conditionChoice(3),
    );
    print(conditionTrace);
  }
  box.cached = null;
  var dynamicResult = [box.conditionalAccess ??= pass(9223372036854775807)];
  print(dynamicResult is List<int>);
  print(dynamicResult);
  conditionTrace = '';
  var lists = [coalescingTop ??= []];
  List<List<Object>> objects = lists;
  print(lists[0] is List<int>);
  print(lists is List<List<int>>);
  print(objects);
  print(conditionTrace);
  conditionTrace = '';
  print(coalescingTop ??= <int>[conditionChoice(2)]);
  print(conditionTrace);
  conditionTrace = '';
  // ignore: dead_code, dead_null_aware_expression
  var finalValue = topFinal ??= conditionChoice(1);
  // ignore: dead_code, dead_null_aware_expression
  var constantValue = topConstant ??= conditionChoice(2);
  print(<int>[finalValue, constantValue]);
  print(conditionTrace);
  // A nonnull getter still contributes the unexecuted RHS type to the result.
  // ignore: dead_code, dead_null_aware_expression
  var wide = [box.textLength ??= 'unused'];
  List<Object> joined = wide;
  print(wide is List<int>);
  print(joined);
  var present = Box(0);
  present.cached = 1;
  box.cached = null;
  List<Object?> payload = <void>[
    present.opaqueAccess ??= valueVoid(),
    box.opaqueAccess ??= valueVoid(),
  ];
  print(payload);
  Null absent;
  var nullResult = [absent ??= null];
  List<Null> nulls = nullResult;
  print(nulls);
  Object? knownNull = pass(null);
  knownNull as Null;
  int definitelyAssigned;
  knownNull ??= (definitelyAssigned = 8);
  print(definitelyAssigned);
  int nonnull = 1;
  final int writtenLater;
  // ignore: dead_code, dead_null_aware_expression
  nonnull ??= (writtenLater = 2);
  writtenLater = 3;
  print(writtenLater);
  coalescingAssignmentFlow(4, null, null);
}

const coalescingNested = <List<int>>[
  null ?? <int>[3],
];

void coalescingDefaults([
  // ignore: dead_code, dead_null_aware_expression
  int number = null ?? (1 ?? (1 ~/ 0)),
  List<List<int>> nested = const <List<int>>[
    null ?? <int>[3],
  ],
]) {
  print(number);
  print(identical(nested, coalescingNested));
}

void coalescingValues(
  int? number,
  bool? flag,
  String? text,
  List<List<int>>? lists,
) {
  int selected = number ?? 4;
  bool enabled = flag ?? true;
  String label = text ?? 'fallback';
  List<List<int>> nested = lists ?? [[]];
  nested[0].add(9);
  print(<Object>[selected, enabled, label, nested]);
  print(flag ?? false || true);
  print(flag ?? false ? 1 : 2);
  number ?? (number = 5);
  print(number + 1);
  // ignore: dead_code, dead_null_aware_expression
  number ?? touchVoid();
  // ignore: dead_code, dead_null_aware_expression
  List<Object?> payload = <void>[number ?? touchVoid()];
  print(payload);
}

void coalescingContexts() {
  conditionTrace = '';
  print(<dynamic>[
    argumentValue(1, 0) ?? argumentValue(2, 7),
    argumentValue(3, false) ?? argumentValue(4, true),
    argumentValue(5, null) ?? argumentValue(6, 'right'),
    argumentValue(7, Box(8)) ?? argumentValue(8, Box(9)),
  ]);
  print(conditionTrace);
  conditionTrace = '';
  print(
    argumentValue(1, null) ??
        argumentValue(2, 0) ??
        argumentValue(3, 'unreachable'),
  );
  print(conditionTrace);
  print((pass('字🙂') as String?) ?? 'cast fallback');
  var exact = [null ?? 5];
  List<int> integers = exact;
  print(integers);
  var unknown = [pass(6) ?? 7];
  print(unknown is List<int>);
  print(unknown);
  // ignore: dead_code, dead_null_aware_expression
  var joined = [1 ?? 'other'];
  List<Object> objects = joined;
  print(joined is List<int>);
  print(objects);
  coalescingValues(null, null, null, null);
  coalescingValues(-9223372036854775808, false, 'present', <List<int>>[[]]);
  int? absent = pass(null);
  absent ?? touchVoid();
  List<Object?> missing = <void>[absent ?? touchVoid()];
  print(missing);
  dynamic dynamicValue = pass(9223372036854775807);
  var dynamicPayload = [dynamicValue ?? touchVoid()];
  List<Object?> dynamicView = dynamicPayload;
  print(dynamicView);
  var conditionalPayload = [choose() ? dynamicValue : valueVoid()];
  List<Object?> conditionalView = conditionalPayload;
  print(conditionalView);
  coalescingDefaults();
  coalescingAssignmentValues();
}

void nullAssertionValues() {
  int? number = pass(0);
  bool? flag = pass(false);
  String? text = pass('字🙂');
  List<int>? list = pass(<int>[7]);
  Object? object = pass(9);
  print(<Object>[
    number! + 1,
    !flag!,
    text!.length,
    identical(list, list!),
    object!,
  ]);
  print(<Object>[number + 1, flag && true, text.length, list[0]]);
  var inferred = [object];
  List<Object> objects = inferred;
  print(inferred is List<int>);
  print(objects);
  dynamic unknown = pass(9223372036854775807);
  var dynamicValues = [unknown!];
  print(dynamicValues is List<int>);
  print(dynamicValues);
  for (dynamic value in <dynamic>[0, false, '', const <int>[]]) print(value!);
  // ignore: unnecessary_non_null_assertion
  List<int> contextual = []!;
  contextual.add(1);
  // ignore: unnecessary_non_null_assertion
  List<List<int>> nested = (null ?? [[]])!;
  nested[0].add(2);
  print([contextual, nested]);
  var box = Box(0);
  box.cached = 0;
  conditionTrace = '';
  print((argumentValue(1, box) as Box).conditionalAccess!);
  print(conditionTrace);
  print((opaqueValue(7) as dynamic)!);
  // ignore: unnecessary_non_null_assertion
  print(number!!);
}

final int lazyFinalValue = conditionChoice(9);

void finalAssignments(bool flag) {
  final int initialized = 3;
  final int deferred;
  final bool? nullable;
  if (flag) {
    deferred = 4;
    nullable = null;
  } else {
    deferred = 5;
    nullable = false;
  }
  print(<Object?>[initialized, deferred, nullable]);
  final values = <int>[1];
  values.add(2);
  values[0]++;
  print(values);
  for (final item in <int>[1, 2]) {
    final int copy;
    copy = item + 1;
    print(copy);
  }
}

int completeReturn(bool flag) {
  if (flag) return 6;
  return 7;
}

Never nonCompletingWhile() {
  while (true) {}
}

int neverWrapper() {
  nonCompletingWhile();
}

int nonCompletingFor() {
  for (;;) {}
}

int nonCompletingDo() {
  do {} while (true);
}

// ignore: body_might_complete_normally_nullable
int? fallthroughInt() {}
// ignore: body_might_complete_normally_nullable
bool? fallthroughBool() {}
dynamic fallthroughDynamic() {}
void fallthroughVoid() {}

void finalContexts() {
  conditionTrace = '';
  print('final:$conditionTrace');
  print(lazyFinalValue);
  print(lazyFinalValue);
  print(conditionTrace);
  finalAssignments(true);
  finalAssignments(false);
  print(Plain(8).value);
  print(Plain().enabled);
  print(<Object?>[completeReturn(true), completeReturn(false)]);
  print(<Object?>[fallthroughInt(), fallthroughBool(), fallthroughDynamic()]);
  List<Object?> erased = <void>[fallthroughVoid()];
  print(erased);
}

void neverContexts() {
  var empty = <Never>[];
  List<String> texts = empty;
  List<int> numbers = empty;
  print(<Object>[texts, numbers]);
  dynamic bottom = pass(empty);
  print(bottom is List<String>);
  print(bottom is List<int>);
  dynamic value = pass(null);
  print(value is Never);
  // ignore: type_check_with_null
  print(value is Never?);
  value = 1;
  // ignore: type_check_with_null
  print(value is Never?);
  Never? nullable = null;
  print(nullable);
  print(identical(const <Never?>[], const <Null>[]));
  final int unreachable;
  return;
  // ignore: dead_code
  if (false) unreachable = 1;
  unreachable = 2;
  print(unreachable);
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
  print(1__000 + 0XF__F);
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
  List<num> owned = <num>[1, 0x7FFF_FFFF_FFFF_FFFF];
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
  var large = String.fromCharCodes(List<int>.filled(65536, 65));
  print(large);
  print(codes);
  print('tail🙂');
  print('');
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

@metadataTag
class MetadataProbe {
  @metadataList
  int metadataTag;
  @metadataList
  MetadataProbe(@metadataList this.metadataTag);
  @metadataList
  int read(@metadataList int metadataList) {
    const localNote = true;
    @localNote
    int value = metadataList + this.metadataTag;
    return value;
  }
}

@metadataNull
const metadataTag = 1;
const metadataList = <Object?>[null, '注🙂'];
const metadataNull = null;

@metadataTag
@metadataList
@metadataNull
void metadataValues() {
  print(MetadataProbe(3).read(4));
  const localNote = 'local';
  @metadataList
  int first = 1, second = 2;
  @localNote
  int zero = 0;
  for (@localNote int i = 0; i < 1; i++) first += i;
  for (@localNote final element in <int>[3]) second += element;
  print(<int>[first + zero, second]);
}

void main(List<String> args) {
  metadataValues();
  objectValues();
  valueContexts();
  assignmentValues();
  accessorValues();
  topAccessorValues();
  typeChecks();
  filledLists();
  conditionContexts();
  coalescingContexts();
  nullAssertionValues();
  finalContexts();
  neverContexts();
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
