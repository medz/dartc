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

abstract class ConstantTypeFactory {
  const factory ConstantTypeFactory(Object? value) = ConstantTypeInitializer;
}

class ConstantTypeInitializer implements ConstantTypeFactory {
  final int number;
  final bool integer;
  final bool other;
  const ConstantTypeInitializer(Object? value)
    : number = value as int,
      integer = value is int,
      other = value is! int;
}

class CastInferredFields {
  var number = (null as int?) ?? 4;
  var integer = 1 is int;
  var widened = 1 as num;
}

typedef ConstantVoid = void;

void constantTypeDefaults([num value = 1 as num, bool integer = 1 is int]) {
  print([value, integer]);
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
  const num wide = 1;
  const Object? missing = null;
  const number = wide as num;
  const nullable = missing as int?;
  const checks = [
    wide is int,
    wide is! double,
    missing is Null,
    missing is int,
    missing is Object?,
  ];
  print([number, nullable, checks]);
  print([number] is List<num>);
  print([number] is List<int>);
  const List<num> source = <int>[1, 2];
  const actualList = source is List<int>;
  const recoveredList = source as List<int>;
  const widenedList = <int>[1, 2] as List<num>;
  print(actualList);
  print(identical(source, recoveredList));
  print(identical(source, widenedList));
  print([widenedList] is List<List<num>>);
  print([widenedList] is List<List<int>>);
  const factory = ConstantTypeFactory(3);
  const actualClass = factory is ConstantTypeInitializer;
  const recoveredClass = factory as ConstantTypeInitializer;
  print([
    actualClass,
    identical(factory, recoveredClass),
    recoveredClass.number,
    recoveredClass.integer,
    recoveredClass.other,
  ]);
  print(ConstantTypeInitializer(5).number);
  const Object function = functionFromObject;
  const callback = function as int Function(Object?);
  const matches = function is int Function(int);
  const mismatch = function is String Function();
  print([matches, mismatch, identical(function, callback)]);
  print(callback(6));
  const deadCast = true ? 3 : ('wrong' as int);
  const coalesced = (1 as Object?) ?? ('wrong' as int);
  const and = false && (('wrong' as int) == 0);
  const or = true || (null as bool);
  const bottom = true ? 2 : (1 as Never);
  print([deadCast, coalesced, and, or, bottom]);
  const void hidden = 7;
  const visible = hidden as int;
  const discarded = 1 as ConstantVoid;
  const top = 1 is ConstantVoid;
  print(visible);
  print(<void>[discarded]);
  print(top);
  constantTypeDefaults();
  final inferred = CastInferredFields();
  print([inferred.number, inferred.integer, inferred.widened]);
  print([inferred.number] is List<int>);
  print([inferred.widened] is List<num>);
  print([inferred.widened] is List<int>);
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
  var values = new List<int>.filled(
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

int initialZero = 0;
bool initialFalse = false;
double initialPositiveZero = 0.0;
double initialNegativeZero = -0.0;
Object? initialTaggedZero = 0;
Object? initialTaggedFalse = false;
int? initialNull;
var initialInferredNull = null;
late int initialLateZero = 0;
late final int initialLateFinalZero = 0;
final int initialFinalZero = 0;
set initialFinalZero(int value) => initialZero = value;
int initialCalls = 0;
int initialEffect() {
  initialCalls++;
  return 0;
}

int initialLazyZero = initialEffect();
int initialSkippedZero = initialEffect();

class InitialStatics {
  static int value = 0;
  static bool flag = false;
  static double positiveZero = 0.0;
  static Object? nullable;
}

void topAccessorValues() {
  print(<Object?>[
    initialZero,
    initialFalse,
    1.0 / initialPositiveZero,
    1.0 / initialNegativeZero,
    initialTaggedZero,
    initialTaggedFalse,
    initialNull,
    initialInferredNull,
    initialLateFinalZero,
    InitialStatics.flag,
    1.0 / InitialStatics.positiveZero,
    InitialStatics.nullable,
  ]);
  initialLateZero = 12;
  InitialStatics.value = 13;
  initialNull ??= 14;
  initialInferredNull = 15;
  initialFinalZero = 16;
  print(<Object?>[
    initialLateZero,
    InitialStatics.value,
    initialNull,
    initialInferredNull,
    initialFinalZero,
    initialZero,
  ]);
  initialSkippedZero = 17;
  print(initialCalls);
  print(initialLazyZero);
  print(initialLazyZero);
  print(initialSkippedZero);
  print(initialCalls);
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
  // These declarations reserve storage; they do not evaluate a Never value.
  // ignore: unused_local_variable
  Never unassigned;
  // ignore: unused_local_variable
  late Never delayed;
  // ignore: unused_local_variable
  late final inferred = nonCompletingWhile();
  nullElement() {
    [?null];
  }

  emptySpread() {
    [...<Never>[]];
  }

  // ignore: unnecessary_type_check
  print(nullElement is Null Function());
  print(nullElement is Never Function());
  // ignore: unnecessary_type_check
  print(emptySpread is Null Function());
  print(emptySpread is Never Function());
  print(nullElement());
  print(emptySpread());
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
  int certain;
  // Sound flow uses the non-null type for definite assignment since Dart 3.9.
  // ignore: unnecessary_null_comparison
  if (turn != null) certain = turn;
  print(certain);
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

int firstArgument(int value, int unused) => value;
int twiceArgument(int value) => value + value;
double scaledArgument(double value) => value * 0.5 + 1.0;
String sameArgument(String value) => value;
int failedArgument() => throw 'argument failed';

void argumentCalls() {
  functionTrace = 0;
  print(firstArgument(functionMark(1), functionMark(2)));
  print(twiceArgument(functionMark(3)));
  twiceArgument(functionMark(4));
  print(functionTrace);
  print(firstArgument(firstArgument(5, 6), twiceArgument(7)));
  print(scaledArgument(3.5));
  print(sameArgument(sameArgument('reference')));
  try {
    print(firstArgument(twiceArgument(functionMark(5)), failedArgument()));
  } catch (value) {
    print(value);
  } finally {
    print(functionTrace);
  }
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

void integerDivisions() {
  int operand() {
    print('division operand');
    return -17;
  }

  print(operand() ~/ 1);
  print(operand() % 1);
  const boundaries = <int>[
    -9223372036854775808,
    -9223372036854775807,
    -17,
    -16,
    -15,
    -7,
    -2,
    -1,
    0,
    1,
    2,
    7,
    15,
    16,
    17,
    9223372036854775807,
  ];
  for (final left in boundaries) {
    print(<int>[
      left ~/ 1,
      left % 1,
      left ~/ 2,
      left % 2,
      left ~/ 16,
      left % 16,
      left ~/ 2147483648,
      left % 2147483648,
      left ~/ 4294967296,
      left % 4294967296,
      left ~/ 4611686018427387904,
      left % 4611686018427387904,
      left << 64,
      left >> 64,
      left >>> 64,
    ]);
    try {
      print(left ~/ 16);
      print(left % 16);
    } finally {
      print(left);
    }
    for (final right in boundaries) {
      if (right == 0) continue;
      dynamic boxed = left;
      print([
        left,
        right,
        left ~/ right,
        left % right,
        boxed ~/ right,
        boxed % right,
      ]);
    }
  }
}

void shiftContexts() {
  const boundaries = <int>[
    (-9_223_372_036_854_775_808),
    - -9223372036854775808,
    -(-9223372036854775808),
    -0009223372036854775808,
    0x8000000000000000,
    -0x8000000000000000,
    0x0000FFFFFFFFFFFFFFFF,
    -(0xffffffffffffffff),
    0009223372036854775807,
  ];
  print(boundaries);
  print(<int>[
    (-9_223_372_036_854_775_808),
    - -9223372036854775808,
    -(-9223372036854775808),
    -0009223372036854775808,
    0x8000000000000000,
    -0x8000000000000000,
    0x0000FFFFFFFFFFFFFFFF,
    -(0xffffffffffffffff),
    0009223372036854775807,
  ]);
  for (int count in <int>[0, 63, 64, 65, 9223372036854775807]) {
    print(<int>[1 << count, -1 >> count, -1 >>> count]);
    print(<int>[-1 << count, 1 >> count, 1 >>> count]);
  }
  literalShifts(-9223372036854775808);
  literalShifts(9223372036854775807);
  literalShifts(-1);
  integerDivisions();
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

int constObjectCalls = 0;

class ConstAtom {
  final int number;
  const ConstAtom(this.number, [int unused = 0]);
  String toString() => 'Atom(' + number.toString() + ')';
}

class ConstOtherAtom {
  final int number;
  const ConstOtherAtom(this.number);
}

class ConstRecord {
  final Object? payload;
  final ConstAtom? child;
  final List<Object?> items;
  final bool enabled = true;
  final String label = 'fixed🙂';
  const ConstRecord({this.payload, this.child, this.items = const []});
}

class ConstChain {
  final ConstChain? next;
  const ConstChain(this.next);
}

const constantAtom = ConstAtom(7);
const constantRecord = ConstRecord(
  payload: -9223372036854775808,
  child: ConstAtom(7),
  items: <Object?>[
    ConstAtom(7),
    <int>[1],
    false,
    null,
    'nested🙂',
  ],
);

int constObjectValue() {
  constObjectCalls++;
  return 7;
}

void constObjectDefault([ConstAtom value = const ConstAtom(7)]) {
  print(identical(value, constantAtom));
}

void constObjects() {
  const first = ConstAtom(7);
  const sameFields = ConstAtom(7, 99);
  const Object widened = ConstAtom(7);
  const different = ConstOtherAtom(7);
  const same = first == sameFields;
  print(<bool>[
    identical(first, constantAtom),
    identical(first, sameFields),
    identical(first, widened),
    identical(first, different),
    same,
  ]);
  var one = ConstAtom(constObjectValue());
  var two = ConstAtom(constObjectValue());
  print(<bool>[identical(one, two), identical(one, first)]);
  print(constObjectCalls);
  print(<int>[
    const ConstAtom(-9223372036854775808).number,
    const ConstAtom(9223372036854775807).number,
  ]);
  const objects = <ConstAtom>[ConstAtom(7)];
  const equivalent = <ConstAtom>[ConstAtom(7, 99)];
  print(identical(objects, equivalent));
  print(objects);
  print(identical(constantRecord.child, first));
  print(constantRecord.items);
  print(<Object?>[
    constantRecord.payload,
    constantRecord.child!.number,
    constantRecord.enabled,
    constantRecord.label,
  ]);
  var dynamicRecord = pass(constantRecord);
  print(dynamicRecord is ConstRecord);
  print((dynamicRecord as ConstRecord).payload);
  const empty = ConstRecord();
  print(<Object?>[empty.child, empty.payload, empty.items]);
  const chain = ConstChain(ConstChain(null));
  print(chain.next!.next);
  print(identical(chain.next, const ConstChain(null)));
  constObjectDefault();
}

void operatorIndexing() {
  final grid = OpGrid();
  grid[1] = 7;
  grid[2] = grid[1] + 1;
  grid[3] += 5;
  grid[0]++;
  grid[0]--;
  grid[1] -= 2;
  print(grid.cells);
  print(grid.reads);
  print(grid[2] = 9);
  OpCounter c = OpCounter(1);
  c += 4;
  c++;
  c -= 2;
  --c;
  print(c.n);
  OpScale scale = OpBox(2);
  scale = scale * 3;
  print(scale.size);
  scale = OpBigBox(2) * 3;
  print(scale.size);
  OpBox box = OpBigBox(1) * 5;
  print(box.size);
  final keyed = OpKeyed();
  print(keyed[2] + keyed[0]);
  print(keyed.self(opA));
  dynamic d = opA;
  print(d is OpVec);

  final contracts = OpIndexContracts();
  opIndexTrace = '';
  opIndexReceiver(contracts)[opIndexKey()] += opIndexValue();
  print(opIndexTrace);
  print(contracts[3]++);
  print(++contracts[4]);
  contracts.value = 7;
  opAliasValue = 8;
  OpListIndex()[[]] += 2;
  OpDoubleIndex()[1] += 2;
  final callable = OpCallableIndex();
  OpFunctionIndex()[callable] += 2;
  OpCallableWriteIndex()[callable] ??= 9;
  dynamic key = 'key';
  final present = OpNullableIndex(5);
  opIndexTrace = '';
  present[key] ??= opIndexValue();
  print(present[key] ??= opIndexValue());
  print(opIndexTrace);
  final absent = OpNullableIndex(null);
  absent[1] ??= opIndexValue();
  print(absent[2] ??= opIndexValue());

  final updateSuper = OpSuperIndexLeaf().exercise();
  opIndexTrace = '';
  print(updateSuper());
  print(opIndexTrace);
  OpSuperNullableIndex(5).exercise('key');
  OpSuperNullableIndex(null).exercise(2);
  OpSuperListIndex().exercise();
  OpSuperFunctionIndex().exercise();
  print(OpSuperWriteOnly().exercise());
}

String opIndexTrace = '';

OpIndexContracts opIndexReceiver(OpIndexContracts value) {
  opIndexTrace += 'r';
  return value;
}

int opIndexKey() {
  opIndexTrace += 'i';
  return 2;
}

int opIndexValue() {
  opIndexTrace += 'v';
  return 3;
}

typedef OpWriteResult = void;

OpWriteResult set opAliasValue(int value) => print(value);

class OpIndexContracts {
  int operator [](int key) {
    opIndexTrace += 'g';
    return key + 10;
  }

  OpWriteResult operator []=(Object key, int value) {
    opIndexTrace += 'w';
    print([key, value]);
  }

  OpWriteResult set value(int value) => print(value);
}

class OpListIndex {
  int operator [](List<int> key) => key.length;
  void operator []=(Object key, int value) {
    print(key is List<int>);
    print(value);
  }
}

class OpDoubleIndex {
  int operator [](double key) {
    print(key);
    return 4;
  }

  void operator []=(Object key, int value) {
    print(key is double);
    print(value);
  }
}

class OpCallableIndex {
  int call() => 4;
}

class OpFunctionIndex {
  int operator [](int Function() key) => key();
  void operator []=(Object key, int value) {
    print(key is OpCallableIndex);
    print(value);
  }
}

class OpCallableWriteIndex {
  int? operator [](Object key) {
    print(key is OpCallableIndex);
    return null;
  }

  void operator []=(int Function() key, int value) {
    print(key());
    print(value);
  }
}

class OpNullableIndex(final int? value) {
  int? operator [](Object key) {
    opIndexTrace += 'g';
    return value;
  }

  void operator []=(int key, int value) => print([key, value]);
}

class OpSuperIndexMiddle extends OpIndexContracts {
  int operator [](int key) => super[key] + 1;
}

class OpSuperIndex extends OpSuperIndexMiddle {
  int operator [](int key) => -1;
  void operator []=(Object key, int value) {
    print('override');
  }

  int Function() exercise() {
    opIndexTrace = '';
    print(super[opIndexKey()] = opIndexValue());
    print(opIndexTrace);
    opIndexTrace = '';
    print(super[opIndexKey()] += opIndexValue());
    print(opIndexTrace);
    print(super[3]++);
    print(++super[4]);
    print(super[3]--);
    print(--super[4]);
    super[2] -= 3;
    return () => super[opIndexKey()] += opIndexValue();
  }
}

class OpSuperIndexLeaf extends OpSuperIndex {}

class OpSuperNullableIndex extends OpNullableIndex {
  OpSuperNullableIndex(super.value);
  int operator [](Object key) => -1;
  void operator []=(int key, int value) {
    print('override');
  }

  void exercise(dynamic key) {
    opIndexTrace = '';
    print(super[key] ??= opIndexValue());
    super[key] ??= opIndexValue();
    print(opIndexTrace);
  }
}

class OpSuperListIndex extends OpListIndex {
  void exercise() {
    super[[]] += 2;
  }
}

class OpSuperFunctionIndex extends OpFunctionIndex {
  void exercise() {
    super[OpCallableIndex()] += 2;
  }
}

class OpWriteOnly {
  void operator []=(int key, Object value) {
    print([key, value]);
  }
}

class OpSuperWriteOnly extends OpWriteOnly {
  List<int> exercise() {
    final result = [super[2] = 9];
    return result;
  }
}

int opPick<T extends OpBase>(T t) => t[2];
OpBase opBump<T extends OpBase>(T t) => t + 1;
OpBase opFlip<T extends OpBase>(T t) => -t;

void operatorInheritance() {
  const d = OpDerived(3);
  print(d + 1);
  print(-d);
  print(~d);
  print(d[4]);
  print(d < const OpBase(9));
  print(opPick(d));
  print(opPick(const OpBase(1)));
  print(opBump(d));
  print(opBump(const OpBase(5)));
  print(opFlip(d));
}

void operatorValues() {
  operatorVectors();
  operatorIndexing();
  operatorInheritance();
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
  var codes = StringBuffer();
  print(<Object>[codes.length, codes.isEmpty, codes.isNotEmpty]);
  for (var code in <int>[65, 0, 0x1f642, 0xd800, 0x10ffff]) {
    codes.writeCharCode(code);
  }
  var value = codes.toString();
  var units = <int>[];
  for (var i = 0; i < value.length; i++) units.add(value.codeUnitAt(i));
  print(units);
  print(<Object>[codes.length, codes.isEmpty, codes.isNotEmpty]);
  codes.clear();
  print(<Object>[codes.length, codes.isEmpty, codes.isNotEmpty]);
}

StackTrace stackTraceRead() => StackTrace.current;

StackTrace stackTraceMiddle() => stackTraceRead();

int stackTraceVisits = 0;

StackTrace stackTraceRecursive(int depth) {
  if (depth == 0) return stackTraceRead();
  final trace = stackTraceRecursive(depth - 1);
  stackTraceVisits++;
  return trace;
}

class StackTraceSource {
  final int marker;
  StackTraceSource(this.marker);

  StackTrace read() {
    final trace = StackTrace.current;
    print(marker);
    return trace;
  }
}

StackTrace stackTraceMany(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
  Object object,
  double value,
) {
  final trace = stackTraceRead();
  print(a + b + c + d + e + f + g + h + i);
  print(object);
  print(value);
  return trace;
}

StackTrace Function() stackTraceClosure(int marker) => () {
  final trace = StackTrace.current;
  print(marker);
  return trace;
};

void stackTraceValues() {
  final text = 'arbitrary\ntrace\u0000🙂\ud800';
  final stored = StackTrace.fromString(text);
  print(identical(stored.toString(), text));
  print(StackTrace.empty.toString() == '');
  print(identical(StackTrace.empty, StackTrace.empty));
  const empty = StackTrace.empty;
  print(identical(empty, StackTrace.empty));
  Object value = stored;
  print(value is StackTrace);
  print((value as StackTrace).toString() == text);

  final trace = stackTraceMiddle();
  final rendered = trace.toString();
  final leaf = rendered.indexOf('stackTraceRead');
  final middle = rendered.indexOf('stackTraceMiddle');
  final caller = rendered.indexOf('stackTraceValues');
  print(leaf >= 0 && middle > leaf && caller > middle);
  print(rendered.indexOf('StackTrace.current') == -1);
  print(trace.toString() == rendered);

  final recursive = stackTraceRecursive(48).toString();
  var frames = 0;
  var offset = recursive.indexOf('stackTraceRecursive');
  while (offset >= 0) {
    frames++;
    offset = recursive.indexOf('stackTraceRecursive', offset + 1);
  }
  print(frames == 49);
  print(stackTraceVisits == 48);
  print(recursive.indexOf('stackTraceValues') >= 0);

  final direct = StackTraceSource(71).read().toString();
  print(direct.indexOf('StackTraceSource.read') >= 0);
  final read = StackTraceSource(72).read;
  final indirect = read().toString();
  print(indirect.indexOf('StackTraceSource.read') >= 0);
  print(indirect.indexOf('stackTraceValues') >= 0);
  final closure = stackTraceClosure(73)().toString();
  print(closure.indexOf('<anonymous closure>') >= 0);
  print(closure.indexOf('stackTraceValues') >= 0);

  final many = stackTraceMany(
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    'retained',
    1.25,
  ).toString();
  print(many.indexOf('stackTraceRead') >= 0);
  print(many.indexOf('stackTraceMany') > many.indexOf('stackTraceRead'));
  print(many.indexOf('stackTraceValues') > many.indexOf('stackTraceMany'));
}

int exceptionVisits = 0;

int exceptionStep(int value) {
  exceptionVisits = exceptionVisits * 10 + value;
  return value;
}

Never exceptionLeaf(Object value, int depth) {
  if (depth > 0) exceptionLeaf(value, depth - 1);
  throw value;
}

int exceptionMany(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
  int j,
  int k,
  Object value,
  double floating,
  bool fail,
) {
  if (fail) exceptionLeaf(value, 12);
  return a + b + c + d + e + f + g + h + i + j + k + floating.toInt();
}

int exceptionPressure(int seed, bool fail) {
  final a = seed + 1, b = seed + 2, c = seed + 3, d = seed + 4;
  final e = seed + 5, f = seed + 6, g = seed + 7, h = seed + 8;
  final i = seed + 9, j = seed + 10, k = seed + 11;
  final object = Box(seed);
  final text = 'retained/$seed🙂';
  final floating = seed + 0.25;
  var result = seed;
  try {
    result = exceptionMany(
      a,
      b,
      c,
      d,
      e,
      f,
      g,
      h,
      i,
      j,
      k,
      object,
      floating,
      fail,
    );
  } on Box catch (caught, trace) {
    print(identical(caught, object));
    print(trace.toString().indexOf('exceptionLeaf') >= 0);
    print(trace.toString().indexOf('exceptionPressure') >= 0);
    print(text);
    print(floating);
    print(result);
  }
  return result + a + b + c + d + e + f + g + h + i + j + k + object.value;
}

T exceptionGeneric<T>(Object value, T fallback) {
  try {
    throw value;
  } on T catch (caught) {
    return caught;
  } catch (_) {
    return fallback;
  }
}

int exceptionInitializer() {
  exceptionVisits++;
  if (exceptionVisits == 1) throw 'retry';
  return exceptionVisits;
}

final int exceptionGlobal = exceptionInitializer();

class ExceptionFields {
  late final int value = exceptionInitializer();
  int get fail => throw 'getter';
  set fail(int value) => throw value;
  void method() => throw this;
}

int exceptionReturn(bool fail) {
  try {
    return fail ? throw 'return' : 23;
  } on String {
    return 24;
  }
}

class ErrorMessage {
  String toString() => throw 'safeToString must not invoke this';
}

class ImplementedError implements Error {
  StackTrace? get stackTrace => null;
}

void exceptionValues() {
  print(Error.safeToString(null));
  print(Error.safeToString(7));
  print(Error.safeToString(1.5));
  print(Error.safeToString(true));
  print(Error.safeToString('a\n"\t\\\u0000\ud800🙂'));
  print(Error.safeToString(ErrorMessage()));
  print(Error.safeToString(<int>[1]).indexOf('Instance(length:1)') == 0);
  print(Error.safeToString(() => 1).indexOf('Closure') == 0);
  for (final error in <Object>[
    Error(),
    AssertionError(),
    AssertionError('message'),
    TypeError(),
    ArgumentError(),
    ArgumentError('message', 'value'),
    ArgumentError.value('bad', 'value', 'message'),
    ArgumentError.notNull('value'),
    RangeError('message'),
    RangeError.value(1.5, 'value'),
    RangeError.range(7, 1, 3),
    RangeError.range(7, null, 3),
    RangeError.range(7, 3, null),
    RangeError.range(7, 3, 3),
    RangeError.range(7, 3, 1),
    IndexError.withLength(-1, 3),
    IndexError.withLength(0, 0),
    IndexError.withLength(4, 3),
    UnsupportedError('operation'),
    UnimplementedError(),
    UnimplementedError('operation'),
    StateError('state'),
    ConcurrentModificationError(),
    ConcurrentModificationError(ErrorMessage()),
    Exception(),
    Exception('message'),
    const FormatException(),
    const FormatException('format', 'abc', 1),
    const FormatException('format', 'a\r\nb\nc', 4),
    const FormatException('format', 'abc', -1),
    const FormatException('format', 'abc', 4),
    const FormatException('format', 42, 3),
    const IntegerDivisionByZeroException(),
  ])
    print(error);
  final longSource = String.fromCharCodes(List<int>.filled(180, 120));
  for (final position in <int?>[null, 5, 90, 175, 180])
    print(FormatException('format', longSource, position));
  final argument = ArgumentError.value(7, 'value', 'message');
  print(argument.invalidValue);
  print(argument.name);
  print(argument.message);
  print(argument.stackTrace == null);
  final range = RangeError.range(7, 1, 3, 'value', 'message');
  print(range.invalidValue);
  print(range.start);
  print(range.end);
  final indexable = <int>[1, 2];
  final index = IndexError.withLength(7, 2, indexable: indexable);
  print(index.invalidValue);
  print(index.start);
  print(index.end);
  print(index.length);
  print(identical(index.indexable, indexable));
  print(index is RangeError);
  print(range is ArgumentError);
  print(argument is Error);
  print((argument as Object) is Exception);
  print(const FormatException() is Exception);
  print(const IntegerDivisionByZeroException() is UnsupportedError);
  print(ArgumentError.checkNotNull<int>(7));
  print(RangeError.checkValueInInterval(2, 1, 3));
  print(RangeError.checkNotNegative(0));
  print(RangeError.checkValidRange(1, null, 3));
  print(RangeError.checkValidRange(1, 2, 3));
  print(IndexError.check(1, 3));
  for (final operation in <void Function()>[
    () {
      ArgumentError.checkNotNull<int>(null);
    },
    () {
      RangeError.checkValueInInterval(4, 1, 3);
    },
    () {
      RangeError.checkNotNegative(-1);
    },
    () {
      RangeError.checkValidRange(-1, null, 3);
    },
    () {
      RangeError.checkValidRange(1, 4, 3);
    },
    () {
      IndexError.check(4, 3, name: null);
    },
  ]) {
    try {
      operation();
    } on ArgumentError catch (error) {
      print(error);
    } finally {
      print('error finally');
    }
  }
  final supplied = StackTrace.fromString('supplied trace');
  try {
    Error.throwWithStackTrace(range, supplied);
  } on RangeError catch (error, trace) {
    print(identical(error, range));
    print(trace.toString());
  } finally {
    print('trace finally');
  }
  final implemented = ImplementedError();
  try {
    throw implemented;
  } on Error catch (error) {
    print(identical(error, implemented));
    print(error.stackTrace == null);
  }
  for (var value in <Object>[
    0,
    9223372036854775807,
    1.25,
    false,
    '',
    <int>[1],
    Box(3),
    () => 3,
  ]) {
    dynamic thrown = value;
    try {
      throw thrown;
    } catch (caught) {
      print(identical(value, caught));
    }
  }
  print(exceptionPressure(3, false));
  print(exceptionPressure(4, true));
  print(exceptionReturn(false));
  print(exceptionReturn(true));
  print(exceptionGeneric<int>(31, 1));
  print(exceptionGeneric<int>('no', 2));
  print(exceptionGeneric<List<int>>(<int>[7], <int>[]));
  final closures = <Object Function()>[];
  StackTrace? original;
  final object = Box(73);
  try {
    try {
      exceptionLeaf(object, 3);
    } on String {
      print('wrong handler');
    } catch (value, trace) {
      closures.add(() => value);
      closures.add(() => trace);
      original = trace;
      try {
        throw 'nested';
      } catch (other) {
        print(other);
      }
      rethrow;
    }
  } on Box catch (value, trace) {
    print(identical(value, object));
    print(identical(original, trace));
    print(identical(closures[0](), object));
    print(identical(closures[1](), trace));
  }
  try {
    try {
      throw 81;
    } on String {}
  } on int? catch (value) {
    print(value! + 1);
  }
  try {
    throw true;
  } on bool {
    try {
      rethrow;
    } catch (value) {
      final value = 'shadow';
      print(value);
    }
  }
  exceptionVisits = 0;
  try {
    print([exceptionStep(1), throw exceptionStep(2), exceptionStep(3)]);
  } catch (value) {
    print(value);
    print(exceptionVisits);
  }
  int? missing;
  try {
    print(missing ?? (throw 'fallback'));
  } catch (value) {
    print(value);
  }
  final fields = ExceptionFields();
  try {
    fields.fail;
  } catch (value) {
    print(value);
  }
  try {
    fields.fail = 4;
  } catch (value) {
    print(value);
  }
  final method = fields.method;
  try {
    method();
  } catch (value) {
    print(identical(value, fields));
  }
  final int assigned;
  try {
    throw 1;
  } catch (_) {
    assigned = 6;
  }
  print(assigned);
  outer:
  for (var i = 0; i < 4; i++) {
    try {
      if (i == 0) continue outer;
      throw i;
    } on int catch (value) {
      if (value == 1) continue outer;
      print(value);
      break outer;
    }
  }
  try {
    try {
      throw 'replace';
    } catch (_) {
      throw 91;
    }
  } on int catch (value) {
    print(value);
  }
  exceptionVisits = 0;
  try {
    print(exceptionGlobal);
  } catch (value) {
    print(value);
  }
  print(exceptionGlobal);
  exceptionVisits = 0;
  try {
    print(fields.value);
  } catch (value) {
    print(value);
  }
  print(fields.value);
  exceptionVisits = 0;
  late final local = exceptionInitializer();
  final read = () => local;
  try {
    print(read());
  } catch (value) {
    print(value);
  }
  print(read());
}

int finallyCompletion(int body, int cleanup, List<int> events) {
  var i = 0;
  while (i < 2) {
    i++;
    try {
      events.add(10 + i);
      if (body == 1) return i;
      if (body == 2) throw i;
      if (body == 3) break;
      if (body == 4) continue;
      events.add(20 + i);
    } finally {
      events.add(30 + i);
      if (cleanup == 1) return 100 + i;
      if (cleanup == 2) throw 100 + i;
      if (cleanup == 3) break;
      if (cleanup == 4) continue;
      events.add(40 + i);
    }
    events.add(50 + i);
  }
  return 200 + i;
}

T finallyResult<T>(T value) {
  try {
    return value;
  } finally {
    print('generic finally');
  }
}

double finallyDouble(double value) {
  try {
    return value + 0.25;
  } finally {
    value = 10.5;
    print(value);
  }
}

Box finallyObject(Box value) {
  try {
    return value;
  } finally {
    value.value++;
  }
}

void finallyVoid() {
  try {
    return print('void return');
  } finally {
    print('void cleanup');
  }
}

int finallyAlwaysReturns() {
  try {} finally {
    return 17;
  }
}

class FinallyConstructor {
  int value = 1;
  FinallyConstructor() {
    try {
      return;
    } finally {
      value = 7;
    }
  }
}

int finallyCatch(int mode) {
  try {
    if (mode == 0) return 1;
    return throw mode;
  } on int catch (value) {
    if (value == 1) return 2;
    if (value == 2) throw value + 10;
  } finally {
    print('caught cleanup $mode');
  }
  return 3;
}

void finallyFlow(Object value) {
  int assignedByTry;
  final int assignedByFinally;
  try {
    assignedByTry = 3;
    if (value is! int) return;
  } finally {
    assignedByFinally = 4;
    if (false) value = 'unreachable write';
  }
  print(value + assignedByTry + assignedByFinally);
  Object next = value;
  try {
    next = 'changed';
  } finally {
    if (next is! String) return;
  }
  print(next.length);
  Object untouched = value;
  try {
    if (untouched is! int) return;
  } finally {
    try {} finally {
      if (false) untouched = 'unreachable nested write';
    }
  }
  print(untouched + 1);
  int onBreak;
  do {
    try {
      onBreak = 5;
      break;
    } finally {
      print('assigned before break');
    }
  } while (false);
  print(onBreak);
}

void finallyValues() {
  for (var body = 0; body < 5; body++) {
    for (var cleanup = 0; cleanup < 5; cleanup++) {
      final events = <int>[];
      try {
        print(finallyCompletion(body, cleanup, events));
      } catch (value) {
        print(value);
      }
      print(events);
    }
  }
  final object = Box(81);
  print(identical(finallyObject(object), object));
  print(object.value);
  print(finallyDouble(-0.5));
  print(finallyResult<int>(9223372036854775807));
  print(finallyResult<double>(-0.0));
  print(finallyResult<bool>(false));
  print(finallyResult<String?>('kept'));
  print(finallyResult<String?>(null));
  print(identical(finallyResult<Box>(object), object));
  finallyVoid();
  print(finallyAlwaysReturns());
  print(FinallyConstructor().value);
  for (var i = 0; i < 4; i++) {
    try {
      print(finallyCatch(i));
    } catch (value) {
      print(value);
    }
  }
  finallyFlow(9);
  finallyFlow('early return');

  final captured = <int Function()>[];
  outer:
  for (var i = 0; i < 3; i++) {
    try {
      for (var j = 0; j < 2; j++) {
        try {
          if (i == 0) continue outer;
          if (i == 1) break outer;
        } finally {
          print('inner $i $j');
        }
      }
    } finally {
      final kept = i;
      int read() => kept;
      captured.add(read);
      print('outer $i');
    }
  }
  for (var read in captured) print(read());
  for (var value in <int>[0, 1, 2]) {
    try {
      if (value == 0) continue;
      break;
    } finally {
      print('for-in cleanup $value');
    }
  }
  var round = 0;
  do {
    try {
      round++;
      continue;
    } finally {
      print('do cleanup $round');
    }
  } while (round < 2);
  try {
    for (var i = 0; i < 3; i++) {
      if (i == 0) continue;
      break;
    }
    switch (1) {
      case 1:
        try {
          continue next;
        } finally {
          print('case cleanup');
        }
      next:
      case 2:
        print('continued case');
    }
    print('inside outer try');
  } finally {
    print('after inner jumps');
  }
  finish:
  {
    try {
      try {
        break finish;
      } finally {
        print('inner block');
      }
    } finally {
      print('outer block');
    }
  }
  StackTrace? original;
  try {
    try {
      try {
        throw object;
      } catch (value, trace) {
        original = trace;
        rethrow;
      }
    } finally {
      try {
        throw 'cleanup exception';
      } catch (value) {
        print(value);
      }
    }
  } catch (value, trace) {
    print(identical(value, object));
    print(identical(trace, original));
    try {
      try {
        throw 'replaced';
      } finally {
        rethrow;
      }
    } catch (value, trace) {
      print(identical(value, object));
      print(identical(trace, original));
    }
  }
  Object inferred() {
    local() {
      try {
        return 1;
      } finally {
        return 'inferred Object';
      }
    }

    return local();
  }

  print(inferred());
  int Function() returnedClosure() {
    var value = 5;
    try {
      return () => value;
    } finally {
      value++;
    }
  }

  print(returnedClosure()());
}

int stringEvaluations = 0;

String stringReceiver() {
  stringEvaluations++;
  return 'a🙂b';
}

class OpGrid {
  final List<int> cells = [0, 0, 0, 0];
  int reads = 0;
  int operator [](int i) {
    reads++;
    return cells[i];
  }

  void operator []=(int i, int v) {
    cells[i] = v;
  }
}

class OpCounter {
  final int n;
  OpCounter(this.n);
  OpCounter operator +(int k) => OpCounter(n + k);
  OpCounter operator -(int k) => OpCounter(n - k);
}

abstract class OpScale {
  OpScale operator *(int k);
  int get size;
}

class OpBox implements OpScale {
  final int size;
  OpBox(this.size);
  OpBox operator *(int k) => OpBox(size * k);
}

class OpBigBox extends OpBox {
  OpBigBox(int size) : super(size);
  OpBox operator *(int k) => OpBigBox(size * k + 1);
}

class OpBase {
  final int v;
  const OpBase(this.v);
  OpBase operator +(int k) => OpBase(v + k);
  OpBase operator -() => OpBase(-v);
  OpBase operator ~() => OpBase(v + 100);
  int operator [](int i) => v * 10 + i;
  bool operator <(OpBase o) => v < o.v;
  String toString() => 'OpBase($v)';
}

class OpDerived extends OpBase {
  const OpDerived(int v) : super(v);
  OpBase operator +(int k) => super + (k * 2);
  OpBase operator -() => -super;
  OpBase operator ~() => ~super;
  int operator [](int i) => super[i] + 1;
  bool operator <(OpBase o) => super < o;
  String toString() => 'OpDerived($v)';
}

class OpKeyed {
  final List<String> names = ['a', 'b', 'c'];
  String operator [](int i) => names[i];
  OpVec twice(OpVec v) => v + v;
  OpVec self(OpVec v) => this.twice(v) - v;
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
  var codes = new String.fromCharCodes(<int>[0, 55296, 120, 57343, 1114111]);
  print(codes.length);
  print(codes.codeUnitAt(1));
  print(codes.codeUnitAt(3));
  print(codes.substring(4));
  final units = <int>[0, 65, 255, 256, 0xd800, 0xdc00, 0xdfff, 0xffff, 0x4f60];
  for (final length in <int>[
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    15,
    16,
    17,
    31,
    32,
    33,
    63,
    64,
    65,
    4095,
    4096,
    4097,
  ]) {
    final data = <int>[];
    for (var i = 0; i < length; i++) data.add(units[i % units.length]);
    final left = String.fromCharCodes(data);
    final same = String.fromCharCodes(data);
    print(left.substring(0) == same);
    print(left.substring(0, length) == same);
    print(left.substring(length).isEmpty);
    if (length > 1) {
      print(
        left.substring(1, length - 1) ==
            String.fromCharCodes(data.sublist(1, length - 1)),
      );
    }
    print(left == same);
    print(left == left);
    print(left == same + '!');
    for (var offset = 0; offset < 4; offset++) {
      final enclosed = 'abcd'.substring(0, offset) + left;
      print(enclosed.startsWith(same, offset));
      print(enclosed.endsWith(same));
      print(enclosed.indexOf(same, offset));
      print(enclosed.lastIndexOf(same));
      print(enclosed.substring(offset) == same);
    }
    if (length == 0) continue;
    final positions = length <= 17
        ? <int>[for (var i = 0; i < length; i++) i]
        : <int>[0, 1, 3, 4, length ~/ 2, length - 4, length - 2, length - 1];
    for (final position in positions) {
      data[position] ^= 1;
      final other = String.fromCharCodes(data);
      data[position] ^= 1;
      print(left == other);
      print(left != other);
      for (var offset = 0; offset < 4; offset++) {
        final enclosed = 'abcd'.substring(0, offset) + left;
        print(enclosed.startsWith(other, offset));
        print(enclosed.endsWith(other));
        print(enclosed.indexOf(other));
        print(enclosed.lastIndexOf(other));
      }
    }
  }
  print('Am\u00e9lie' == 'Ame\u0301lie');
  print('\ud800\udc00' == String.fromCharCodes(<int>[0x10000]));
  print(
    '\ud800x\udfff\uffff' ==
        String.fromCharCodes(<int>[0xd800, 120, 0xdfff, 0xffff]),
  );
  var large = String.fromCharCodes(List<int>.filled(65536, 65));
  print(large);
  print(codes);
  print('tail🙂');
  print('');
}

void operatorVectors() {
  print(opA + opB);
  print(opB - opA);
  print(-opA);
  print(~opB);
  print(opA * 4);
  print(opA << 3);
  print(opB >>> 1);
  print(opB ~/ 2);
  print(opA < opB);
  print(opA >= opB);
  print(opA + opB * 2);
  print(opA + -opB);
  print(opA + opB - opA);
  print(opA[0] + opB[1]);
  print((opA + opB)[1]);
  print(-(-opA));
  if (opA < opB && !(opB < opA)) print('ordered');
  var count = 0;
  for (var v = opA; v < opB; v = v + const OpVec(1, 1)) count++;
  print(count);
  print('${opA + opB} ${opA[1]}');
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
  var positions = <int>[0, 1, 2, 3, 4];
  print(positions.removeAt(0));
  print(positions.removeAt(1));
  print(positions.removeAt(positions.length - 1));
  print(positions);
  var nullable = <int?>[null, -9223372036854775808, 9223372036854775807];
  print(nullable.removeAt(1));
  print(nullable.removeAt(0));
  print(nullable);
  var references = <String?>['字🙂', null, 'tail'];
  print(references.removeAt(1));
  print(references.removeAt(0));
  print(references);
  var booleans = <bool>[false, true, false];
  print(booleans.removeAt(1));
  print(booleans);
  var boxes = <Box>[Box(3), Box(5)];
  print(boxes.removeAt(0).value);
  print(boxes[0].value);
  List<Object?> widened = <int>[-9223372036854775808, 0, 9223372036854775807];
  print(widened.removeAt(2));
  print(widened);
  var mixed = <Object?>[false, 9223372036854775807, '字🙂', null];
  print(mixed.removeAt(1));
  print(mixed);
  assignmentStorage = <int>[-9223372036854775808, 5];
  assignmentTrace = 0;
  print(assignmentReceiver().removeAt(assignmentIndex()));
  print(assignmentTrace);
  print(assignmentStorage);
  var inserted = <int>[];
  inserted.insert(0, 2);
  inserted.insert(0, 1);
  inserted.insert(inserted.length, 4);
  inserted.insert(2, 3);
  print(inserted);
  i = 0;
  while (i < 40) {
    inserted.insert(1, i);
    i++;
  }
  print(<int>[inserted.length, inserted[1], inserted[41], inserted[43]]);
  var insertedNullable = <int?>[null];
  insertedNullable.insert(0, -9223372036854775808);
  insertedNullable.insert(1, null);
  print(insertedNullable);
  var insertedRefs = <String?>[];
  insertedRefs.insert(0, '字🙂');
  insertedRefs.insert(1, null);
  print(insertedRefs);
  var insertedFlags = <bool>[];
  insertedFlags.insert(0, false);
  insertedFlags.insert(0, true);
  print(insertedFlags);
  var insertedBoxes = <Box>[];
  insertedBoxes.insert(0, Box(9));
  print(insertedBoxes[0].value);
  var insertedObjects = <Object?>[false, null];
  insertedObjects.insert(1, 9223372036854775807);
  insertedObjects.insert(0, '字🙂');
  print(insertedObjects);
  List<Object?> insertedWords = <int>[];
  insertedWords.insert(0, 9223372036854775807);
  insertedWords.insert(0, -9223372036854775808);
  print(insertedWords);
  assignmentStorage = <int>[0];
  assignmentTrace = 0;
  assignmentReceiver().insert(assignmentIndex(), assignmentValue());
  print(assignmentTrace);
  print(assignmentStorage);
  print(<void>[inserted.insert(0, 9)]);
  print(inserted[0]);
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

class MetadataValue<T> {
  final T value;
  const MetadataValue(this.value);
  const MetadataValue.named(T value) : this(value);
  static T identity<T>(T value) => value;
}

class MetadataBound<T extends num> {
  final T value;
  const MetadataBound(this.value);
}

typedef MetadataAlias<T> = MetadataValue<List<T>>;
const inferredMetadata = MetadataValue(3);
const MetadataValue<num> contextualMetadata = MetadataValue(3);
const genericMetadata = MetadataValue<int>.named(3);

@MetadataBound<int>(4)
@MetadataAlias([1, 2])
@genericMetadata
void unusedGenericMetadata() {}

@metadataTag
@metadataList
@metadataNull
void metadataValues() {
  print(MetadataValue.identity<int>(6));
  const inferred = identical(inferredMetadata, MetadataValue<int>(3));
  const contextual = identical(contextualMetadata, MetadataValue<num>(3));
  const redirected = identical(genericMetadata, MetadataValue<int>(3));
  const different = identical(MetadataValue<int>(3), MetadataValue<num>(3));
  const subtype = MetadataValue<int>(3) is MetadataValue<num>;
  const merged =
      [MetadataValue(1), MetadataValue(2.0)] is List<MetadataValue<num>>;
  const notSubtype = MetadataValue<int>(3) is MetadataValue<String>;
  const alias = identical(
    MetadataAlias([1, 2]),
    MetadataValue<List<int>>([1, 2]),
  );
  print(<bool>[
    inferred,
    contextual,
    redirected,
    different,
    subtype,
    merged,
    notSubtype,
    alias,
  ]);
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

typedef GenericIdentity<T> = T;
typedef GenericTransform<T> = T Function(T);
typedef GenericCallbacks<T> = List<GenericTransform<T>?>;
typedef GenericNested<T extends num> = List<List<T?>>;
typedef GenericNullableNested<T extends num> = GenericNested<T>?;
typedef GenericNumbers<T extends num> = List<T>;
typedef GenericRecursive<T extends List<T>> = T;
typedef GenericReverse<T extends void Function(T)> = T;
typedef GenericShadow<int> = List<int>;
typedef GenericIgnored<_, _> = int;

class GenericMark {
  const GenericMark();
}

typedef GenericPhantom<T> = GenericMark;
typedef GenericAnnotated<@GenericPhantom<T>() T> = List<T>;

typedef LegacyUntyped(int);
typedef int LegacyInteger(int value);
typedef T LegacyNumeric<@metadataTag T extends num>(T value);
typedef int LegacyHigher(int callback(int value));
typedef LegacyNested(callback(value));

dynamic legacyEcho(dynamic value) => value;
int legacyApply(int Function(int) callback) => callback(6);
dynamic legacyNested(dynamic Function(dynamic) callback) => callback('nested');

void legacyAliases() {
  LegacyUntyped untyped = legacyEcho;
  print(untyped('text'));
  LegacyInteger integer = functionPlus;
  print(integer(3));
  LegacyNumeric<int> numeric = functionPlus;
  print(numeric(4));
  LegacyHigher higher = legacyApply;
  print(higher(functionPlus));
  LegacyNested nested = legacyNested;
  print(nested(legacyEcho));
}

void genericAliases() {
  GenericTransform<int> callback = functionPlus;
  print(callback(7));
  GenericCallbacks<int> callbacks = [callback, null];
  print(callbacks[0]!(6));
  print(callbacks[1]);
  GenericNullableNested<int> nested = [
    [null, 7],
  ];
  print(nested);
  GenericIdentity identity = 7;
  print(pass([identity]) is List<int>);
  GenericNumbers numbers = [];
  print(pass(numbers) is List<num>);
  GenericRecursive recursive = [];
  print(pass([recursive]) is List<List<dynamic>>);
  GenericReverse reverse = opaqueValue;
  print(pass([reverse]) is List<void Function(Never)>);
  GenericShadow<String> shadow = ['s'];
  print(shadow);
  GenericIgnored<int, String> ignored = 9;
  print(ignored);
  GenericAnnotated<bool> annotated = [true];
  print(annotated);
}

typedef IntCallback = int Function(int);
typedef PackedCallback = Object? Function(
  int,
  String,
  bool,
  Object?,
  List<int>,
  int,
  String,
  bool,
  int,
);

int functionTrace = 0;
int functionIdentity(int value) => value;
int functionPlus(int value) => value + 1;
int functionOther(int value) => value - 1;
int functionFromObject(Object? value) => value as int;
bool functionFlag(bool value) => value;
String functionText(String value) => value;
int functionNumber() => 7;
IntCallback functionReturn() => functionPlus;
int functionApply(IntCallback callback, int value) => callback(value);
int functionDefault([IntCallback callback = functionIdentity]) => callback(11);
int functionNullable(IntCallback? callback) {
  if (callback == null) return -1;
  return callback(7);
}

int functionStep(int value) {
  functionTrace = functionTrace * 10 + 4;
  return value + 1;
}

class CallbackSlot {
  IntCallback callback;
  CallbackSlot(this.callback);
  IntCallback get selected {
    functionTrace = functionTrace * 10 + 2;
    return callback;
  }
}

CallbackSlot functionReceiver() {
  functionTrace = functionTrace * 10 + 1;
  return CallbackSlot(functionStep);
}

int functionArgument() {
  functionTrace = functionTrace * 10 + 3;
  return 4;
}

class CallbackRecord {
  final IntCallback callback;
  const CallbackRecord(this.callback);
  int apply(int value) => callback(value);
}

class MethodReceiver {
  int value;
  MethodReceiver(this.value);
  int add(int next) {
    functionTrace = functionTrace * 10 + 4;
    return value += next;
  }

  int read(int next) => value + next;
  int call(int next) => add(next);
  int other(int next) => value + next;
  int fromObject(Object? next) => next as int;
  String text(String next) => next + value.toString();
  void discard() => value;
  IntCallback implicit() => add;
  IntCallback explicit() => this.add;
  IntCallback nested() {
    IntCallback select() => add;
    return select();
  }

  Object? packed(
    int first,
    String second,
    bool third,
    Object? fourth,
    List<int> fifth,
    int sixth,
    String seventh,
    bool eighth,
    int ninth,
  ) => functionPacked(
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
    eighth,
    ninth + value,
  );
}

MethodReceiver methodReceiver(MethodReceiver value) {
  functionTrace = functionTrace * 10 + 1;
  return value;
}

MethodReceiver? methodMaybe(bool present, MethodReceiver value) =>
    present ? value : null;
IntCallback methodSelected = MethodReceiver(8).add;
IntCallback callableSelected = MethodReceiver(11);
IntCallback callableReturn(MethodReceiver value) => value;
IntCallback callableFallback(MethodReceiver? value) =>
    value ?? MethodReceiver(6);
IntCallback callableAssert(MethodReceiver? value) => value!;

class OptionalCallable {
  int call(int first, [int second = 7]) => first + second;
}

class ConstantCallable {
  final int value;
  const ConstantCallable(this.value);
  int call(int next) => value + next;
}

class ConvertedCallable {
  final IntCallback callback;
  // ignore: invalid_constant
  const ConvertedCallable(ConstantCallable source) : callback = source;
}

class NamedCallable {
  int call({required int first, int second = 5}) {
    functionTrace = functionTrace * 10 + 4;
    return first * 10 + second;
  }
}

class CallableSlot {
  MethodReceiver value;
  CallableSlot(this.value);
  MethodReceiver get selected {
    functionTrace = functionTrace * 10 + 2;
    return value;
  }

  NamedCallable get named {
    functionTrace = functionTrace * 10 + 2;
    return NamedCallable();
  }
}

int callableReplace(CallableSlot slot) {
  slot.value = MethodReceiver(9);
  return 2;
}

const functionSaved = functionIdentity;
const functionCallbacks = <IntCallback>[functionIdentity];
const functionRecord = CallbackRecord(functionIdentity);
IntCallback functionSelected = functionPlus;

Object? functionPacked(
  int first,
  String second,
  bool third,
  Object? fourth,
  List<int> fifth,
  int sixth,
  String seventh,
  bool eighth,
  int ninth,
) {
  print(<Object?>[
    first,
    second,
    third,
    fourth,
    fifth[0],
    sixth,
    seventh,
    eighth,
    ninth,
  ]);
  return ninth;
}

typedef OptionalFunction = int Function(int, [int, int?]);
typedef NamedFunction = int Function(int, {int z, required int a});
typedef LegacyNamedFunction(int value, {required int a, int z});

int optionalFunction(int x, [int y = 4, int? z]) => x + y + (z ?? 7);
int namedFunction(int x, {int z = 13, required int a}) => x + z + a;
num wideNamedFunction(num x, {num extra = 2, num z = 5, required num a}) =>
    x + extra + z + a;
int functionMark(int value) {
  functionTrace = functionTrace * 10 + value;
  return value;
}

int defaultCallback([int x = 11]) => x;
int defaultFunction({
  int Function() callback = defaultCallback,
  List<int> values = const [3, 5],
}) => callback() + values[1];
const savedNamedFunction = namedFunction;
const savedDefaultFunctions =
    <int Function({int Function() callback, List<int> values})>[
      defaultFunction,
    ];

class ParameterFunctionBase {
  int method(int x, {int y = 1}) => x + y;
  NamedFunction get callback {
    functionTrace = functionTrace * 10 + 4;
    return namedFunction;
  }

  static int staticMethod([int x = 6]) => x;
}

class ParameterFunctionChild extends ParameterFunctionBase {
  int method(int x, {int y = 8}) => x + y;
}

T Function({required T value, T? fallback}) parameterClosure<T>(T x) =>
    ({required T value, T? fallback}) {
      print(x);
      return fallback ?? value;
    };

T inferNamedParameter<T>(T Function({required T value}) callback, T value) =>
    callback(value: value);

void functionParameterValues() {
  OptionalFunction positional = optionalFunction;
  print(positional(1));
  print(positional(1, 2));
  print(positional(1, 2, 3));
  int Function(int) narrowed = positional;
  print(narrowed(9));
  NamedFunction named = namedFunction;
  functionTrace = 0;
  print(named(a: functionMark(2), functionMark(1), z: functionMark(3)));
  print(functionTrace);
  print(named(2, a: 4));
  print(savedNamedFunction == named);
  print(savedDefaultFunctions[0]());
  print(savedDefaultFunctions[0](callback: () => 17, values: [2, 4]));
  LegacyNamedFunction legacy = named;
  print(legacy(3, a: 4));
  num Function(int, {required int a, int z}) wider = wideNamedFunction;
  print(wider(3, a: 7));
  ParameterFunctionBase object = ParameterFunctionChild();
  var bound = object.method;
  print(bound(2));
  print(bound == object.method);
  functionTrace = 0;
  print(object.callback(a: functionMark(2), functionMark(1)));
  print(functionTrace);
  functionTrace = 0;
  print((object.callback)(functionMark(1), a: functionMark(2)));
  print(functionTrace);
  var staticCallback = ParameterFunctionBase.staticMethod;
  print(staticCallback());
  var accumulated = 3;
  const initial = 5;
  int local(int x, {int y = initial}) {
    accumulated += x + y;
    return accumulated;
  }

  var captured = local;
  print(captured(1));
  print(captured(1, y: 9));
  int Function({required int x, String text}) anonymous =
      ({text = 'ok', required x}) {
        print(text);
        return x + 1;
      };
  print(anonymous(x: 4));
  var closure = parameterClosure<int>(42);
  print(closure(value: 8));
  print(closure(fallback: 3, value: 9));
  final inferred = inferNamedParameter(({required int value}) => value + 1, 5);
  print(inferred);
  Object erased = named;
  print(erased is NamedFunction);
  print(erased is int Function(int, {int a, int z}));
  print(erased is int Function(int, {required int a, int z, int extra}));
  print(positional is int Function(int));
  print(named is int Function(int));
  dynamic checked = wideNamedFunction;
  num Function(int, {required int a, int z}) checkedNamed = checked;
  print(checkedNamed(2, a: 3));
  final joined = accumulated > 0
      ? ({int a = 5, int b = 3}) => a + b
      : ({int a = 9, String c = 'c'}) => a;
  print(joined());
  print(joined(a: 10));
  int recursive({int count = 3}) =>
      count == 0 ? 1 : recursive(count: count - 1) + 1;
  var recurse = recursive;
  print(recurse());
  void Function([int]) noResult = ([int value = 6]) {
    print(value);
  };
  noResult();
  int Function({int value}) throwing = ({int value = 7}) {
    try {
      throw value;
    } finally {
      print('function finally');
    }
  };
  try {
    throwing();
  } catch (value) {
    print(value);
  }
}

void functionValues() {
  constructorValues();
  functionParameterValues();
  var callableObject = MethodReceiver(1);
  print(callableObject(2));
  functionTrace = 0;
  print(methodReceiver(callableObject)(functionArgument()));
  print(functionTrace);
  IntCallback converted = callableObject;
  print(converted == callableObject.call);
  print(converted(1));
  print(functionApply(callableObject, 2));
  print(callableReturn(callableObject)(1));
  print(callableSelected(2));
  Function bareCallable = callableObject;
  IntCallback? nullableCallable = callableObject;
  print(bareCallable == callableObject.call);
  print(nullableCallable == callableObject.call);
  Object objectCallable = callableObject;
  dynamic dynamicCallable = callableObject;
  print(objectCallable is MethodReceiver);
  print(dynamicCallable is MethodReceiver);
  print(callableObject is Function);
  var assignment = (converted = callableObject);
  print(assignment is MethodReceiver);
  print(assignment == callableObject.call);
  nullableCallable = null;
  print((nullableCallable ??= callableObject)(1));
  // ignore: invalid_null_aware_operator
  print(<IntCallback>[callableObject, ?callableObject][1](1));
  for (IntCallback value in <MethodReceiver>[callableObject]) print(value(1));
  for (converted in <MethodReceiver>[callableObject]) print(converted(1));
  print([
    for (IntCallback value in <MethodReceiver>[callableObject]) value(1),
  ]);
  print(CallbackSlot(callableObject).callback(1));
  var storedCallable = CallbackSlot(functionIdentity);
  storedCallable.callback = callableObject;
  print(storedCallable.callback(1));
  IntCallback Function() factory = () => callableObject;
  print(factory()(1));
  IntCallback conditional = callableObject.value > 0
      ? callableObject
      : MethodReceiver(99);
  print(conditional == callableObject.call);
  IntCallback cascade = MethodReceiver(1)..value = 3;
  print(cascade(2));
  print(callableFallback(null)(2));
  print(callableFallback(callableObject)(2));
  print(callableAssert(callableObject)(2));
  IntCallback constantCallable = const ConstantCallable(7);
  print(constantCallable(2));
  // ignore: non_constant_list_element, dead_code
  const skippedCallables = <IntCallback>[if (false) ConstantCallable(7)];
  const skippedArguments = <CallbackRecord>[
    // ignore: const_with_non_constant_argument
    if (false) CallbackRecord(ConstantCallable(7)),
  ];
  print(skippedCallables.length);
  print(skippedArguments.length);
  print(ConvertedCallable(const ConstantCallable(7)).callback(3));
  print(OptionalCallable()(2));
  print(OptionalCallable()(2, 3));
  print(NamedCallable()(first: 2));
  var callableSlot = CallableSlot(callableObject);
  functionTrace = 0;
  print(callableSlot.selected(functionArgument()));
  print(functionTrace);
  functionTrace = 0;
  print((callableSlot.selected)(functionArgument()));
  print(functionTrace);
  functionTrace = 0;
  print(callableSlot.named(second: functionArgument(), first: 2));
  print(functionTrace);
  callableSlot.value = MethodReceiver(1);
  print(callableSlot.value(callableReplace(callableSlot)));
  callableSlot.value = MethodReceiver(1);
  print((callableSlot.value)(callableReplace(callableSlot)));
  var receiver = MethodReceiver(1), otherReceiver = MethodReceiver(1);
  functionTrace = 0;
  var method = methodReceiver(receiver).add;
  print(functionTrace);
  print(method(2));
  print(receiver.value);
  print(method == receiver.add);
  print(method != otherReceiver.add);
  print(receiver.read != receiver.other);
  print(method == receiver.implicit());
  print(method == receiver.explicit());
  print(method == receiver.nested());
  IntCallback wrapping = (value) => receiver.add(value);
  print(method == wrapping);
  Function broadMethod = method;
  Function repeatedMethod = receiver.add;
  print(broadMethod == repeatedMethod);
  Object objectMethod = method;
  print(objectMethod == receiver.add);
  IntCallback? nullableMethod = methodMaybe(true, receiver)?.add;
  print(nullableMethod == method);
  print(methodMaybe(false, receiver)?.add);
  print(nullableMethod!(1));
  dynamic dynamicMethod = receiver.read;
  IntCallback checkedMethod = dynamicMethod;
  print(checkedMethod(2));
  print(dynamicMethod is IntCallback);
  print(dynamicMethod is String Function(int));
  Object? Function(int) widened = receiver.read;
  print(widened(3));
  IntCallback acceptsObject = receiver.fromObject;
  print(acceptsObject(-9223372036854775808));
  String Function(String) textMethod = receiver.text;
  print(textMethod('接收者🙂'));
  void Function() discardedMethod = receiver.discard;
  print(<void>[discardedMethod()]);
  print(methodSelected(3));
  var methodList = <IntCallback>[receiver.add, otherReceiver.add];
  print(methodList[0] == method);
  print(methodList[1].call(4));
  functionTrace = 0;
  print((methodReceiver(receiver).add)(functionArgument()));
  print(functionTrace);
  print(functionRecord.apply == const CallbackRecord(functionIdentity).apply);
  print(functionRecord.apply(12));
  PackedCallback packedMethod = MethodReceiver(2).packed;
  print(
    packedMethod(
      -9223372036854775808,
      '方法栈🙂',
      true,
      null,
      [17],
      31,
      '尾',
      false,
      40,
    ),
  );
  print(functionApply(functionPlus, 2));
  print(functionReturn()(4));
  print(functionSelected(3));
  functionSelected = functionOther;
  print(functionSelected(3));
  var callbacks = <IntCallback>[functionPlus, functionOther];
  print(<int>[callbacks[0](5), callbacks[1](5)]);
  print(identical(functionSaved, functionCallbacks[0]));
  print(identical(functionRecord.callback, functionIdentity));
  print(functionRecord.callback(10));
  print(functionDefault());
  print(functionNullable(functionPlus));
  print(functionNullable(null));
  IntCallback broad = functionFromObject;
  print(broad(9223372036854775807));
  Object? Function(int) producer = functionIdentity;
  print(producer(-9223372036854775808));
  bool Function(bool) flag = functionFlag;
  print(flag(false));
  String Function(String) text = functionText;
  print(text('回调🙂'));
  void Function() discard = functionNumber;
  print(<void>[discard()]);
  dynamic source = functionIdentity;
  IntCallback checked = source;
  print(checked(0));
  Object callable = functionPlus;
  print(callable is Function);
  if (callable is IntCallback) print(callable(6));
  IntCallback local = functionPlus;
  print(local((local = functionOther)(10)));
  print(local(10));
  var slot = CallbackSlot(functionPlus);
  print(slot.callback((slot.callback = functionOther)(10)));
  slot.callback = functionPlus;
  print((slot.callback)((slot.callback = functionOther)(10)));
  functionTrace = 0;
  print(functionReceiver().selected(functionArgument()));
  print(functionTrace);
  functionTrace = 0;
  print((functionReceiver().selected)(functionArgument()));
  print(functionTrace);
  PackedCallback packed = functionPacked;
  print(
    packed(
      -9223372036854775808,
      '栈🙂',
      true,
      null,
      <int>[17],
      31,
      '尾',
      false,
      9223372036854775807,
    ),
  );
}

int initializerTrace = 0;
int initializerMark(int tag, int value) {
  initializerTrace = initializerTrace * 10 + tag;
  return value;
}

class InitializerOrder {
  int first = initializerMark(1, 10);
  int second = initializerMark(2, 20);
  int formal;
  final int copy;
  final int assigned;
  InitializerOrder(this.formal, int input)
    : copy = initializerMark(3, formal),
      assigned = initializerMark(4, input = input + 1),
      this.second = initializerMark(5, input) {
    formal += 10;
    print(<int>[formal, copy, assigned, first, second, input]);
    initializerMark(6, 0);
  }
  set copy(int next) {
    initializerMark(9, next);
  }
}

const int initializerOuter = 7;

class InitializerConstant {
  final int declared = initializerOuter;
  final int input;
  final int sum;
  final Object? boxed;
  final Object? absent;
  final List<int> list;
  const InitializerConstant(
    int initializerOuter, [
    this.input = initializerOuter,
  ]) : sum = initializerOuter + input,
       boxed = initializerOuter,
       absent = null,
       list = const [9];
}

class InitializerPrivate {
  final int _value;
  final int next;
  const InitializerPrivate({this._value = 3}) : next = _value + 1;
}

void constructorInitializers() {
  initializerTrace = 0;
  InitializerOrder(initializerMark(7, 4), initializerMark(8, 7));
  print(initializerTrace);
  const first = InitializerConstant(2);
  const again = InitializerConstant(2, 7);
  const different = InitializerConstant(3);
  print(<Object?>[
    first.declared,
    first.input,
    first.sum,
    first.boxed,
    first.absent,
    first.list,
  ]);
  print(different.sum);
  print(identical(first, again));
  print(identical(first, different));
  print(identical(first, InitializerConstant(2)));
  const wide = InitializerConstant(-9223372036854775808, 0);
  print(<Object?>[wide.sum, wide.boxed]);
  var ordinary = InitializerConstant(-9223372036854775808, 0);
  print(<Object?>[ordinary.sum, ordinary.boxed]);
  const private = InitializerPrivate(value: 8);
  print(<int>[private._value, private.next]);
}

class NamedChoice {
  final int value;
  const NamedChoice(this.value);
  const NamedChoice.named([int value = 4]) : value = value;
  const NamedChoice.other({int value = 4}) : value = value;
  const NamedChoice.forward([int value = 3]) : this.named(value + 1);
  const NamedChoice.chain({int value = 3}) : this.forward(value);
  int named(int extra) => value + extra;
}

typedef ChoiceAlias = NamedChoice;
typedef ChainedChoice = ChoiceAlias;
typedef NullableChoice = NamedChoice?;

RedirectOrder? redirectSeen;

class RedirectOrder {
  int declared = initializerMark(4, 40);
  final int first;
  final int second;
  RedirectOrder.new(this.first, this.second) {
    redirectSeen = this;
    initializerMark(5, 0);
  }
  RedirectOrder.forward(int value)
    : this._middle(
        initializerMark(2, value = value + 1),
        second: initializerMark(3, value + 1),
      );
  RedirectOrder._middle(int value, {int second = 6}) : this.new(value, second);
}

class NamedOnly {
  final int value;
  NamedOnly.pick(this.value);
}

class NewAlias {
  final int value;
  const NewAlias.new([this.value = 5]);
}

typedef NewChoiceAlias = NewAlias;

void namedConstructors() {
  const first = ChoiceAlias.named();
  const same = NamedChoice.other();
  print(<bool>[
    pass([NullableChoice(4)]) is List<NamedChoice>,
    pass([NullableChoice.named(4)]) is List<NamedChoice>,
    pass([NullableChoice.new(4)]) is List<NamedChoice>,
    pass([new NullableChoice.named(4)]) is List<NamedChoice>,
    pass([const NullableChoice.named(4)]) is List<NamedChoice>,
  ]);
  print(identical(first, same));
  print(identical(first, ChainedChoice.named()));
  print(ChoiceAlias(7).named(1));
  print(ChainedChoice.other(value: 9).value);
  print(NamedOnly.pick(6).value);
  print(identical(const NewAlias(), const NewAlias.new()));
  print(identical(NewAlias(), NewAlias.new()));
  print(NewChoiceAlias.new(8).value);
  print(new ChoiceAlias.named(9).named(1));
  print(new NewAlias(6).value);
  print(identical(new NewAlias.new(), const NewAlias()));
  print(identical(first, const ChainedChoice.chain()));
  print(identical(first, NamedChoice.chain()));
  print(NamedChoice.forward().value);
  print(NamedChoice.chain(value: 8).value);
  initializerTrace = 0;
  var redirected = RedirectOrder.forward(initializerMark(1, 7));
  print(initializerTrace);
  print(identical(redirectSeen, redirected));
  print(<int>[redirected.first, redirected.second, redirected.declared]);
}

class StaticBox {
  final int instanceValue;
  const StaticBox(this.instanceValue);
  static int value = initializerMark(1, 3);
  static final int frozen = initializerMark(2, 7);
  static int skipped = initializerMark(9, 99);
  static int unused = initializerMark(8, 88);
  static int? absent;
  static dynamic unspecified;
  static var inferred = value + 1;
  static const int seed = 4;
  static const StaticBox object = StaticBox(seed);
  static int get total => value + frozen;
  static set total(int next) {
    value = next - frozen;
  }

  static int get split => value;
  static set split(String next) {
    value = next.length;
  }

  static set frozen(String next) {
    value = next.length;
  }

  static set seed(int next) {
    value = next;
  }

  static int twice(int value) => value * 2;
  static int shadow(int value) => value;
  static IntCallback get callback {
    functionTrace = functionTrace * 10 + 2;
    return functionStep;
  }

  int read() => twice(instanceValue) + value;
  int static() => instanceValue;
}

typedef StaticAlias = StaticBox?;

void staticMembers() {
  initializerTrace = 0;
  print(initializerTrace);
  StaticBox.skipped = 5;
  print(initializerTrace);
  print(StaticBox.total);
  print(initializerTrace);
  StaticAlias.total += 2;
  print(StaticAlias.total);
  print(initializerTrace);
  print(StaticBox.skipped);
  print(StaticBox.absent);
  print(StaticBox.unspecified);
  print(StaticBox.split = 'text');
  StaticBox.frozen = 'abcdef';
  print(StaticBox.frozen);
  StaticBox.seed = 9;
  print(StaticBox.seed);
  print(StaticBox.value);
  print(StaticBox.inferred);
  print(StaticBox(3).read());
  print(StaticBox(5).static());
  print(StaticAlias.shadow(20));
  print(StaticAlias.object.instanceValue);
  const callback = StaticAlias.twice;
  int Function(int) typed = callback;
  print(typed(8));
  print(identical(callback, StaticBox.twice));
  functionTrace = 0;
  print(StaticBox.callback(functionArgument()));
  print(functionTrace);
}

class CascadeBox {
  int value = 0;
  List<int> values = <int>[];
  CascadeBox? child;
  int Function() callback = () => 0;
  CascadeBox Function() factory = () => CascadeBox();

  CascadeBox();

  CascadeBox update(int input) {
    value = input;
    return CascadeBox();
  }

  set written(int input) {
    value = input;
  }

  int get read => value;
  void get discarded {}
}

int cascadeTrace = 0;
int cascadeStep(int value) {
  cascadeTrace = cascadeTrace * 10 + value;
  return value;
}

CascadeBox cascadeTarget() {
  cascadeStep(1);
  return CascadeBox();
}

CascadeBox? cascadeOptional(bool present) => present ? CascadeBox() : null;

void cascadeValues() {
  var object = cascadeTarget()
    ..value = cascadeStep(2)
    ..values.add(cascadeStep(3))
    ..update(cascadeStep(4)).value = cascadeStep(5)
    ..value += cascadeStep(6)
    ..discarded;
  print(cascadeTrace);
  print(object.value);
  print(object.values);
  List<int> items = []
    ..add(1)
    ..add(2)
    ..[0] += 3;
  print(items);
  // ignore: unnecessary_type_check
  print(items is List<int>);
  var nested = CascadeBox()
    ..child = (CascadeBox()..value = 9)
    ..value = 7;
  print(nested.child!.value);
  print(nested.value);
  var first = CascadeBox(), second = CascadeBox();
  // ignore: dead_code
  var chosen = true ? first : second
    ..value = 3;
  print(first.value);
  print(second.value);
  print(identical(first, chosen));
  var factory = () => CascadeBox()..value = 8;
  print(factory().value);
  var callbacks = CascadeBox()
    ..callback = (() => 7)
    ..value = 9;
  print(callbacks.callback());
  print(callbacks.value);
  var arrow = CascadeBox()..factory = () => CascadeBox()..value = 8;
  print(arrow.value);
  print(arrow.factory().value);
  var right = 0;
  var assigned = CascadeBox()
    ..value = right = 5
    ..written = 6;
  print(right);
  print(assigned.read);
  var value = cascadeOptional(true);
  var same = value
    ?..value = value.value + 3
    ..values.add(8);
  print(identical(value, same));
  print(value!.value);
  cascadeTrace = 0;
  var missing = cascadeOptional(false)
    ?..values[cascadeStep(1)] = cascadeStep(2)
    ..value = cascadeStep(3);
  print(missing);
  print(cascadeTrace);
  Null absent = null;
  // ignore: dead_code
  print(absent?..missing(absent.member));
  final int initialized;
  // ignore: invalid_null_aware_operator
  CascadeBox()?..value = initialized = 7;
  print(initialized);
  var original = CascadeBox();
  var receiver = original;
  var result = receiver
    ..value = (receiver = CascadeBox()).value + 5
    ..written = 8;
  print(identical(original, result));
  print(original.value);
  print(receiver.value);
}

typedef NullAwareList<A, B> = List<A>;
typedef NullAwareAlias<A, B> = NullAwareBox;
int nullAwareTrace = 0;
int nullAwareStep(int value) {
  nullAwareTrace = nullAwareTrace * 10 + value;
  return value;
}

class NullAwareBox {
  int value = 7;
  int? cached;
  NullAwareBox? child;
  List<int> values = <int>[10, 20];
  NullAwareBox();
  NullAwareBox setValue(int input) {
    value = input;
    return this;
  }

  int get read {
    nullAwareStep(2);
    return value;
  }

  set write(int input) {
    nullAwareStep(3);
    value = input;
  }

  int Function(int) get callback {
    nullAwareStep(2);
    return (input) => value + input;
  }

  static int staticValue = 3;
  static int twice(int input) => input * 2;
  static const answer = 42;
}

NullAwareBox? nullAwareBox(bool present) {
  nullAwareStep(1);
  return present ? NullAwareBox() : null;
}

List<int>? nullAwareNumbers(bool present) => present ? <int>[1, 2] : null;

class NullAwareLength {
  final int? value;
  const NullAwareLength(String? input) : value = input?.length;
}

void nullAwareValues() {
  var absent = nullAwareBox(false);
  print(absent?.setValue(nullAwareStep(4)).read);
  print(nullAwareTrace);
  nullAwareTrace = 0;
  var target = nullAwareBox(true);
  print(target?.setValue(nullAwareStep(4)).read);
  print(nullAwareTrace);
  print(target?.value++);
  print(++target?.value);
  print(target?.write = nullAwareStep(4));
  print(target!.value);
  nullAwareTrace = 0;
  print(absent?.values[nullAwareStep(4)] = nullAwareStep(5));
  print(nullAwareTrace);
  // ignore: invalid_null_aware_operator
  print(target?.values[0] += 3);
  // ignore: invalid_null_aware_operator
  print(target?.values[0]);
  nullAwareTrace = 0;
  print(absent?.cached ??= nullAwareStep(4));
  print(nullAwareTrace);
  // ignore: invalid_null_aware_operator
  print(target?.cached ??= 8);
  // ignore: invalid_null_aware_operator
  print(target?.cached ??= 9);
  nullAwareTrace = 0;
  print(absent?.callback(nullAwareStep(4)));
  print(nullAwareTrace);
  nullAwareTrace = 0;
  // ignore: invalid_null_aware_operator
  print(target?.callback(nullAwareStep(4)));
  print(nullAwareTrace);
  // ignore: invalid_null_aware_operator
  print(target?.child?.setValue(nullAwareStep(5)).read);
  print(nullAwareTrace);
  print(absent?.child!.value);
  var cascade = NullAwareBox()
    ..child?.value = nullAwareStep(6)
    ..value = 9;
  print(cascade.value);
  cascade.child = NullAwareBox();
  cascade..child?.value = 8;
  print(cascade.child!.value);
  print(nullAwareNumbers(false)?[nullAwareStep(4)]);
  print(nullAwareNumbers(true)?[0] += 5);
  print(nullAwareNumbers(false)?[nullAwareStep(7)]);
  // ignore: dead_code
  print(true ? [1].length : [2].length);
  // ignore: dead_code
  print(true ? [1] as List<int>? ?? [] : [2]);
  // ignore: dead_code
  print(true ? [1] as NullAwareList<int?, String> : [2]);
  // ignore: dead_code
  print(true ? [1].length + NullAwareAlias<int, String>().value : 2);
  // ignore: dead_code
  print(true ? (nullAwareNumbers(false)?[0]) : 1);
  // ignore: invalid_null_aware_operator
  print((target?.values)?[0]);
  Null empty = null;
  // ignore: dead_code
  print(empty?.missing(empty.member));
  // ignore: dead_code
  print(empty?[true]);
  // ignore: invalid_null_aware_operator
  int staticResult = NullAwareBox?.twice(3);
  print(staticResult);
  // ignore: invalid_null_aware_operator
  print(NullAwareBox?.staticValue += 1);
  NullAwareBox constructed = NullAwareBox?.new();
  print(constructed.value);
  // ignore: invalid_null_aware_operator
  const staticConstant = NullAwareBox?.answer;
  const String? missing = null;
  const len = missing?.length;
  const String text = 'abc';
  // ignore: invalid_null_aware_operator
  const length = text?.length;
  const List<int>? list = null;
  const n = list?.length;
  const dynamic unknown = null;
  // CFE accepts these skipped constants; analyzer rejects them.
  // ignore: const_initialized_with_non_constant_value
  const indexed = unknown?[true];
  // ignore: const_eval_property_access, dead_code
  const bottom = null?.whatever;
  // ignore: const_initialized_with_non_constant_value, dead_code
  const subscript = null?[0];
  print(staticConstant);
  print(len);
  print(length);
  print(n);
  print(indexed);
  print(bottom);
  print(subscript);
  print(const NullAwareLength(null).value);
  print(const NullAwareLength('ab').value);
  final int initialized;
  // ignore: invalid_null_aware_operator
  NullAwareBox()?.value = initialized = 8;
  print(initialized);
}

int collectionTrace = 0;
int collectionStep(int n) {
  collectionTrace = collectionTrace * 10 + n;
  return n;
}

bool collectionCondition(int n, bool b) {
  collectionStep(n);
  return b;
}

List<int> collectionSequence(int n) {
  collectionStep(n);
  return <int>[n, n + 1];
}

List<int>? collectionMaybe(bool b) => b ? <int>[8, 9] : null;
int? collectionNullable(int value) {
  collectionStep(value);
  return value == 0 ? null : value;
}

var collectionGlobals = [for (var i = 0; i < 3; i++) () => i];

class CollectionFields {
  List<int> field = [for (var i = 1; i <= 2; i++) i * 2];
  List<int Function()> callbacks = [
    for (var i in [3, 4]) () => i,
  ];
  List<int> initialized;
  CollectionFields(int n) : initialized = [for (var i = 0; i < n; i++) i];
  CollectionFields.named()
    : initialized = [
        for (var i in [5, 6]) i,
      ];
  static var values = [
    for (var i in [1, 2]) i + 10,
  ];
}

void collectionValues() {
  collectionTrace = 0;
  print(<int>[
    ?collectionNullable(0),
    ?collectionNullable(2),
    if (true) ?collectionNullable(3),
    for (var i in [0, 4]) ?collectionNullable(i),
  ]);
  print(collectionTrace);
  var nonNull = [?collectionNullable(5)];
  // ignore: unnecessary_type_check
  print(nonNull is List<int>);
  var nothing = [?null];
  // ignore: unnecessary_type_check
  print(nothing is List<Never>);
  final emptyNever = <Never>[];
  print([...emptyNever]);
  print([1, ...emptyNever, 2]);
  // ignore: invalid_null_aware_operator
  var nullableContext = <List<int>>[?[]];
  // ignore: unnecessary_type_check
  print(nullableContext[0] is List<int>);
  dynamic nullable = null;
  print(<int>[?nullable]);
  nullable = 7;
  print(<int>[?nullable]);
  print([?nullable] is List<int>);
  final int? assignedNull;
  print([?(assignedNull = collectionNullable(0))]);
  print(assignedNull);
  print([?collectionCondition(6, false) ? 1 : null]);
  const noValues = [?null];
  print(identical(noValues, const <Never>[]));
  const int? maybeConstant = null;
  const retained = <int>[?maybeConstant, 2];
  print(identical(retained, const [2]));
  const dynamic absentConstant = null;
  const fromDynamic = <int>[?absentConstant];
  print(identical(fromDynamic, const <int>[]));
  const dynamic invalidConstant = 'wrong';
  // ignore: dead_code, non_constant_list_element
  const unselected = <int>[if (false) ?invalidConstant];
  print(unselected);
  const void opaqueConstant = 9;
  // ignore: use_of_void_result
  const opaqueValues = [?opaqueConstant];
  print(identical(opaqueValues, const <void>[9]));
  void opaqueNull = null;
  void opaqueValue = 10;
  // ignore: use_of_void_result
  print(<void>[?opaqueNull, ?opaqueValue]);
  collectionTrace = 0;
  print([
    collectionStep(1),
    if (collectionCondition(2, true)) collectionStep(3) else collectionStep(4),
    ...collectionSequence(5),
    collectionStep(7),
  ]);
  print(collectionTrace);
  // ignore: dead_code
  print([if (false) 1]);
  print([
    if (true)
      // ignore: dead_code
      if (false) 1 else 2,
  ]);
  print([
    for (var i = 0; i < 4; i++)
      if (i % 2 == 0) i,
  ]);
  print([
    for (var i in [1, 2])
      for (var j in [3, 4]) i * 10 + j,
  ]);
  print([
    ...[1, 2],
    ...?collectionMaybe(false),
    ...?collectionMaybe(true),
  ]);
  var callbacks = [for (var i = 0; i < 3; i++) () => i];
  print(callbacks[0]());
  print(callbacks[2]());
  var closures = [
    for (var i in [4, 5, 6]) () => i,
  ];
  print(closures[0]());
  print(closures[2]());
  print(collectionGlobals[0]());
  print(collectionGlobals[2]());
  var c = CollectionFields(3);
  print(c.field);
  print(c.initialized);
  print(c.callbacks[0]());
  print(c.callbacks[1]());
  print(CollectionFields.named().field);
  print(CollectionFields.named().initialized);
  print(CollectionFields.values);
  var i = 0;
  print([
    for (i in [2, 3]) i,
  ]);
  print(i);
  for (i in [4, 5]) print(i);
  print(i);
  Object? value = 1;
  print([if (value is int) value + 1]);
  final int assigned;
  print([if (collectionCondition(1, true)) assigned = 2 else assigned = 3]);
  print(assigned);
  dynamic dyn = <Object>[1, 2];
  print([for (int value in dyn) value + 1]);
  var reused = 0;
  print([for (reused in dyn) reused]);
  print(<int>[...dyn]);
  // ignore: unnecessary_type_check
  print([...dyn] is List<dynamic>);
  // ignore: dead_code
  var mixed = [if (false) 1 else 's'];
  // ignore: unnecessary_type_check
  print(mixed is List<Object>);
  print(mixed is List<String>);
  var nested = <List<int>>[
    if (true) [],
    // ignore: unused_local_variable
    for (var i in [1]) [],
  ];
  // ignore: unnecessary_type_check
  print(nested[0] is List<int>);
  var empty = [...?null];
  // ignore: unnecessary_type_check
  print(empty is List<Never>);
  // ignore: unnecessary_type_check
  print([1, ...?null] is List<int>);
  const base = [1, 2];
  // ignore: dead_code
  const c1 = [0, ...base, if (false) 3 else 4, ...?null];
  const c2 = [0, 1, 2, 4];
  print(identical(c1, c2));
  const dynamic dc = <Object>[1, 2];
  const cd = <int>[...dc];
  print(cd);
  const cb = [
    // ignore: non_constant_list_element, dead_code
    if (false) <int>[1][9] else 2,
  ];
  print(cb);
}

int listPatternLengths(List<int> value) => switch (value) {
  [] => 0,
  [_, _] => 2,
  [_, _, _, ...] => 3,
  [_] => 1,
};

int listPatternIntersection(List<int> value) => switch (value) {
  [] || [_] => 0,
  [_, ...] && [_, _, ...] => 1,
  _ => -1,
};

int listPatternUnion(List<int>? value) {
  if (value case [] || [_, ...]) return value.length;
  return -1;
}

String listPatternShape(Object? value) => switch (value) {
  [] => 'empty',
  <int>[var a] => 'typed/$a',
  [int a, String b] => '$a/$b',
  [var first, ...var middle, var last] => '$first/$middle/$last',
  [...var rest] => '$rest',
  _ => 'other',
};

void listPatterns() {
  for (var value in <Object?>[
    <int>[],
    <int>[1],
    <dynamic>[1],
    <Object>[2, 'two'],
    <int>[1, 2, 3, 4],
    null,
    'text',
  ])
    print(listPatternShape(value));
  for (var value in <List<int>>[
    [],
    [1],
    [1, 2],
    [1, 2, 3],
    [1, 2, 3, 4],
  ]) {
    print(listPatternLengths(value));
    print(listPatternIntersection(value));
    print(listPatternUnion(value));
  }
  print(listPatternUnion(null));
  if (<List<int>>[
        [1],
        [2, 3],
      ]
      case [[var first], [var second, var third]])
    print(first + second + third);
  var node = PatternNode(1, null, 'list', [3, 4]);
  if (node case PatternNode(values: [var first, var second]))
    print(first + second);
  if (node.values case List(length: var n) && [var first, ...])
    print(n + first);
  var cached = [1, 2, 3];
  bool clear() {
    cached.clear();
    return false;
  }

  print(switch (cached) {
    [var first, _, ...] when clear() => first,
    [var first, ...] => first,
    _ => -1,
  });
  var sliceSource = [1, 2, 3];
  List<int>? saved;
  bool save(List<int> slice) {
    saved = slice;
    sliceSource.add(4);
    return false;
  }

  print(switch (sliceSource) {
    [_, ...var rest] when save(rest) => 0,
    [_, ...var rest] => identical(rest, saved) ? rest.length : -1,
    _ => -2,
  });
  print(saved);
  var tail = [1, 2];
  bool changeTail() {
    tail[1] = 8;
    return false;
  }

  print(switch (tail) {
    [_, var last] when changeTail() => last,
    [..., var last] => last,
    _ => -1,
  });
  var sameTail = [1, 2, 3];
  bool changeSameTail() {
    sameTail[2] = 8;
    return false;
  }

  print(switch (sameTail) {
    [_, ..., var last] when changeSameTail() => last,
    [..., var last] => last,
    _ => -1,
  });
  var differentSlices = [1, 2, 3];
  List<int>? head;
  bool saveHead(List<int> slice) {
    head = slice;
    return false;
  }

  print(switch (differentSlices) {
    [...var rest, _] when saveHead(rest) => rest,
    [...var rest] => rest,
  });
  print(head);
  var callbacks = <int Function()>[];
  for (var i in [1, 2]) {
    if ([i, i + 1] case [var first, ...var rest]) {
      callbacks.add(() => ++first + rest[0]);
    }
  }
  print([callbacks[0](), callbacks[1](), callbacks[0]()]);
  print([
    for (var value in <Object?>[
      [1],
      null,
      [2, 3],
    ])
      if (value case [int first, ...]) first,
  ]);
  if (<Null>[null] case [var inferred]) print([inferred] is List<Null>);
  if (null case var inferred) print([inferred] is List<Null>);
  print(switch (null) {
    var inferred => [inferred] is List<Null>,
  });
  if (<Null>[null] case [Null explicit]) {
    // ignore: unnecessary_type_check
    print([explicit] is List<Null>);
  }
  var wildcard = [1];
  bool clearWildcard() {
    wildcard.clear();
    return false;
  }

  print(switch (wildcard) {
    [_] when clearWildcard() => 0,
    [var _] => 1,
    _ => 2,
  });
}

void sublistValues() {
  List<num> view = <int>[1, 2, 3, 4];
  var middle = view.sublist(1, 3);
  print(middle);
  print(middle is List<int>);
  middle.add(5);
  middle[0] = 9;
  print(middle);
  print(view);
  print(view.sublist(2));
  print(view.sublist(4, null));
  print(view.sublist(0, 0));
  var fromConstant = const <String>['a', 'b'].sublist(0);
  fromConstant.add('c');
  print(fromConstant);
  var fromFixed = List<int>.filled(2, 7).sublist(1);
  fromFixed.add(8);
  print(fromFixed);
  var wide = <Object?>[null, Box(4), 'word', 9223372036854775807];
  var copied = wide.sublist(1);
  print(copied[0]);
  print(copied[1]);
  print(copied[2]);
  print(identical(copied[0], wide[1]));
  var trace = '';
  var source = [1, 2, 3];
  List<int> receiver() {
    trace += 'r';
    return source;
  }

  int start() {
    trace += 's';
    source.add(4);
    return 1;
  }

  int? end() {
    trace += 'e';
    source.add(5);
    return null;
  }

  print(receiver().sublist(start(), end()));
  print(trace);
  if (source case [_, ...var rest, _]) print(rest);
  if (source case [...var all]) print(identical(all, source));
  if (view case [_, ...var rest]) print(rest is List<int>);
  if (view case [...List<int> rest]) print(rest);
}

var objectPatternTrace = <String>[];

class PatternNode {
  int tag;
  PatternNode? child;
  String text;
  List<int> values;
  PatternNode(this.tag, this.child, this.text, this.values);

  int get number {
    objectPatternTrace.add('number');
    return tag;
  }

  PatternNode? get next {
    objectPatternTrace.add('next');
    return child;
  }

  String get word {
    objectPatternTrace.add('word');
    return text;
  }

  int read() => tag;
}

class PatternVoidGetter {
  void get value => 1;
}

int objectPatternVoid(PatternVoidGetter value) => switch (value) {
  PatternVoidGetter(value: 2) => 2,
  PatternVoidGetter(value: 1) => 1,
  _ => 0,
};

class PatternPair {
  PatternNode left;
  PatternNode right;
  PatternPair(this.left, this.right);
}

typedef PatternItems<T> = List<T>;
typedef PatternNestedItems<T> = List<List<T>>;
typedef PatternBoundItems<T extends num> = List<T>;
typedef PatternCallback<T> = T Function(T);
typedef PatternNull = Null;
typedef PatternVoid = void;
typedef PatternDependent<T, U extends T> = T Function(U);
typedef PatternNullable = int?;

int patternNested(Object? value, PatternNode root) {
  bool change() {
    objectPatternTrace.add('guard');
    root.child!.tag = 50;
    root.child = PatternNode(60, null, 'new', []);
    return false;
  }

  return switch (value) {
    PatternNode(next: PatternNode(number: 0)) => -1,
    PatternNode(next: PatternNode(number: var n)) when change() => n,
    PatternNode(next: PatternNode(number: var n), read: var read) => n + read(),
    _ => -2,
  };
}

String patternFields(Object? value) => switch (value) {
  PatternNode(number: 0, word: _) => 'zero',
  PatternNode(word: String(length: 2), number: var n) => n.toString(),
  PatternNode(:var tag, :final text, :List<int> values) => '$tag/$text/$values',
  String(:var length) => 'string/$length',
  _ => 'other',
};

String objectPatternLists(Object value) => switch (value) {
  List<int>(first: var first) when first == 99 => 'int/$first',
  List<Object>(first: var first) => 'object/$first',
  _ => 'other',
};

void objectPatterns() {
  print(objectPatternVoid(PatternVoidGetter()));
  var child = PatternNode(2, null, 'cc', [3]);
  var root = PatternNode(10, child, 'rr', [4]);
  print(patternNested(root, root));
  print(objectPatternTrace);
  objectPatternTrace.clear();
  print(patternFields(root));
  print(objectPatternTrace);
  print(patternFields('abc'));
  print(patternFields(null));
  objectPatternTrace.clear();
  if (root case PatternNode(number: _) && PatternNode(number: var n)) print(n);
  print(objectPatternTrace);
  objectPatternTrace.clear();
  if (PatternPair(child, child) case PatternPair(
    left: PatternNode(number: var left),
    right: PatternNode(number: var right),
  ))
    print(left + right);
  print(objectPatternTrace);
  if (root
      case PatternNode(number: 1, word: var text) ||
          PatternNode(word: var text))
    print(text);
  if (root case PatternNode(:final child?)) print(child.tag);
  if (root case PatternNode(:var child as PatternNode)) print(child.tag);
  if (root case PatternNode(:var child!)) print(child.tag);
  var reads = <int Function()>[];
  for (var i = 0; i < 3; i++) {
    root.tag = i;
    if (root case PatternNode(number: var n) && PatternNode(number: int _)) {
      reads.add(() => ++n);
    }
  }
  print([reads[0](), reads[1](), reads[2](), reads[0]()]);
  int Function()? saved;
  bool save(int Function() read) {
    saved = read;
    return false;
  }

  var method = switch (root) {
    PatternNode(read: var read) when save(read) => read,
    PatternNode(read: var read) => read,
  };
  print(method == saved);
  print(method());
  var objects = <Object?>[root, null, 'abc'];
  print([
    for (var object in objects)
      if (object case PatternNode(:var tag)) tag,
  ]);
  print(objectPatternLists(<int>[7]));
  print(objectPatternLists(<String>['text']));
  var values = <int>[3, 4];
  if (values case List(:var first, :var last, :var length)) {
    int sum = first + last + length;
    print(sum);
  }
  if (values case PatternItems(:var first)) {
    int n = first;
    print(n);
    // ignore: unnecessary_type_check
    print([first] is List<int>);
  }
  if (<List<String>>[
        ['nested'],
      ]
      case PatternNestedItems(:var first)) {
    List<String> strings = first;
    print(strings);
  }
  if (<Object>[1] case PatternBoundItems(:var first)) {
    num n = first;
    print(n);
  }
  if (<Null>[null] case List(:var first)) print([first] is List<Null>);
  if (<Null>[null] case PatternItems(:var first)) print([first] is List<Null>);
  print(switch (1) {
    PatternVoid() => 1,
  });
  Object? maybe = null;
  print(switch (maybe) {
    PatternNull() => 1,
    _ => 0,
  });
  print(switch (maybe) {
    PatternNullable() => 1,
    _ => 0,
  });
  print(switch (maybe) {
    dynamic() => 1,
  });
  int callback(int n) => n + 1;
  if (callback case PatternCallback(call: var read)) {
    int Function(int) typed = read;
    print(typed(4));
  }
  if (callback case PatternDependent(call: var read)) {
    int Function(int) typed = read;
    print(typed(5));
  }
  if (callback case Function()) print('function');
  if (callback case Function(int) read) print(read(5));
}

var ifCaseGlobal = [if (3 case int value) value + 1];

class IfCaseBox {
  final List<int> values = [if (4 case int value) value + 1];
  final List<int> initialized;
  IfCaseBox(Object? value) : initialized = [if (value case int n) n else 0];
}

int ifCaseRefuted(int? value) {
  if (value case null) return 0;
  return value + 1;
}

void ifCaseValues() {
  var trace = <int>[];
  int step(int n) {
    trace.add(n);
    return n;
  }

  bool guard(int n) {
    step(n);
    return n == 3;
  }

  if (step(1) case 2 when guard(3))
    step(4);
  else
    step(5);
  if (step(1) case var value when guard(2))
    step(value + 3);
  else
    step(6);
  if (step(1) case var value when guard(3)) step(value + 6);
  print(trace);
  for (var source in <Object?>[1, 'abc', null, true]) {
    if (source case int value && > 0) {
      value++;
      print(value + source);
    } else if (source case String value) {
      print(value.length);
    } else if (source case null) {
      print('null');
    } else {
      print('other');
    }
  }
  print(ifCaseRefuted(null));
  print(ifCaseRefuted(4));
  int assigned;
  if (step(8) case int value) assigned = value;
  print(assigned);
  var outer = 9;
  if (outer case var outer) {
    outer++;
    print(outer);
  }
  print(outer);
  // ignore: unused_local_variable
  if (1 case var value) {
    var value = 11;
    print(value);
  }
  Object changed = 7;
  if (changed case int value when (changed = 'changed') == 'again')
    print(value);
  else
    print(changed);
  var saved = <int Function()>[];
  bool save(int Function() function) {
    saved.add(function);
    return true;
  }

  for (var i = 0; i < 3; i++) {
    if (i case var value when save(() => value)) {
      value += 10;
      saved.add(() => ++value);
    }
  }
  for (var read in saved) print(read());
  for (var read in saved) print(read());
  if (1 case var value
      when (() {
        var value = 0;
        value++;
        return value == 1;
      })()) {
    for (value in [12, 13]) print(value);
  }
  var collected = [
    for (var source in <Object?>[1, null, 'x', 2])
      if (source case int value when value > 0) ++value else 0,
  ];
  print(collected);
  var nested = <List<int>>[
    // ignore: dead_code
    if (null case var value?) [value as int] else [],
    if (2 case int value) [if (value case > 1) value],
  ];
  print(nested);
  print([
    for (var i = 0; i < 2; i++)
      if (i case var value when save(() => value)) ++value,
  ]);
  print(saved[6]());
  print(saved[7]());
  if ([] case List<int> _)
    print('typed');
  else
    print('dynamic');
  // ignore: use_of_void_result
  if (switchOpaque() case int value) print(value);
  print(ifCaseGlobal);
  var box = IfCaseBox(14);
  print(box.values);
  print(box.initialized);
  print(IfCaseBox(null).initialized);
}

int switchTrace = 0;
int switchStep(int n) {
  switchTrace = switchTrace * 10 + n;
  return n;
}

abstract class PatternOrder {
  bool operator <(num other);
}

class RelationalPatternValue implements PatternOrder {
  final int value;
  const RelationalPatternValue(this.value);
  static const limit = 5;
  bool operator <(num other) {
    switchStep(2);
    return value < other;
  }

  bool operator <=(int other) {
    switchStep(3);
    return value <= other;
  }

  dynamic operator >(int other) {
    switchStep(4);
    return value > other;
  }

  bool operator >=(int other) {
    switchStep(5);
    return value >= other;
  }
}

class ReversedPatternValue extends RelationalPatternValue {
  const ReversedPatternValue(super.value);
  bool operator <(num other) {
    switchStep(6);
    return value > other;
  }
}

class FloatPatternValue {
  bool operator <(double other) => other == 1.0;
}

class FunctionPatternValue {
  bool operator <(int Function(int) other) => other(2) == 3;
}

class NeverPatternValue {
  Never operator <(int other) => throw 'relation';
}

class SelfPatternValue {
  const SelfPatternValue();
  static const dynamic limit = SelfPatternValue();
  bool operator <(SelfPatternValue other) => true;
}

RelationalPatternValue relationalReceiver() {
  switchStep(1);
  return RelationalPatternValue(4);
}

int relationalDispatch(RelationalPatternValue value) => switch (value) {
  < 5 => 1,
  _ => 0,
};
int relationalInterface(PatternOrder value) => switch (value) {
  < 5 => 1,
  _ => 0,
};
int relationalGeneric<T extends RelationalPatternValue>(T value) =>
    switch (value) {
      < 5 => 1,
      _ => 0,
    };
int relationalIncrement(int value) => value + 1;

void relationalPatterns() {
  switchTrace = 0;
  if (relationalReceiver() case >= 3 && < .limit) print('range');
  print(switchTrace);
  switchTrace = 0;
  if (RelationalPatternValue(0) case >= 3 && < 5) print('skipped');
  print(switchTrace);
  switchTrace = 0;
  if (RelationalPatternValue(1) case > 5 || <= 2) print('alternative');
  print(switchTrace);
  switchTrace = 0;
  switch (RelationalPatternValue(2)) {
    case <= 3 when switchStep(7) == 7:
      print('guarded');
    default:
      print('default');
  }
  print(switchTrace);
  print(relationalDispatch(RelationalPatternValue(2)));
  print(relationalDispatch(ReversedPatternValue(8)));
  print(relationalDispatch(ReversedPatternValue(2)));
  print(relationalInterface(ReversedPatternValue(8)));
  print(relationalGeneric(ReversedPatternValue(8)));
  const dynamic limit = 5;
  if (RelationalPatternValue(2) case < limit) print('dynamic constant');
  if (SelfPatternValue() case < .limit) print('dynamic shorthand');
  if (<RelationalPatternValue>[RelationalPatternValue(2)] case [< 3])
    print('nested');
  print(switch (FloatPatternValue()) {
    < 1 => 1,
    _ => 0,
  });
  print(switch (FunctionPatternValue()) {
    < relationalIncrement => 1,
    _ => 0,
  });
  try {
    if (NeverPatternValue() case < 1) print('unreachable');
  } catch (error) {
    print(error);
  }
}

bool switchGuard(int n) {
  switchStep(n);
  return n == 2;
}

int switchChoose(int n) => switch (n) {
  -1 || 0 => 1,
  >= 1 && < 5 => 2,
  var v when switchGuard(v) => v,
  _ => 3,
};
int switchTyped(Object? n) => switch (n) {
  int value && > 0 => value + 1,
  String value => value.length,
  List<int> values => values[0],
  IntCallback callback => callback(3),
  null => 0,
  _ => -1,
};
int switchOrBound(int n) => switch (n) {
  >= 0 && var value || < 0 && var value => value + 1,
  _ => 0,
};
int switchNullable(bool? n) => switch (n) {
  true || false => 1,
  null => 2,
};
int switchNonNull(int? n) => switch (n) {
  var value? => value + 2,
  null => 0,
};
int switchAsserted(int? n) => switch (n) {
  var value! => value + 3,
};
int switchCasted(Object? n) => switch (n) {
  var value as int => value + 4,
};
int switchPromote(Object n) => switch (n) {
  int _ => n + 1,
  _ => 0,
};
int switchMaybe(Object? n) => switch (n) {
  null => 0,
  var v => v is int ? 1 : 2,
};
const switchSaved = <int>[1, 2];
int switchConstants(Object n) => switch (n) {
  const (1 + 2) => 1,
  switchSaved => 2,
  const ([3, 4]) => 4,
  const (ConstAtom(9)) => 5,
  _ => 3,
};
int switchConstantCast(Object n) => switch (n) {
  topConstant as int => 6,
  _ => 0,
};
int switchOperatorText(String n) => switch (n) {
  '==' || '!=' => 1,
  '<' || '<=' || '>' || '>=' => 2,
  'when' || 'as' || 'switch' => 3,
  _ => 4,
};
void switchOpaque() => 4;
// ignore: use_of_void_result
List<void> switchVoidMatch() => switch (switchOpaque()) {
  var v => [v],
};
const void switchVoidConstant = 1;
int switchVoidRelation(int n) => switch (n) {
  // ignore: use_of_void_result
  == switchVoidConstant => 1,
  _ => 2,
};
var switchEscaped = <int Function()>[];
bool switchCapture(int Function() f) {
  switchEscaped.add(f);
  return false;
}

int switchCapturePattern(Object n) => switch (n) {
  int value when switchCapture(() => value) => 0,
  _ => 1,
};
Never switchEmpty(Never n) => switch (n) {};
void switchExpressions() {
  for (var n in [-1, 0, 1, 4, 5, 9]) print(switchChoose(n));
  for (var n in <Object?>[
    2,
    -1,
    'abc',
    null,
    true,
    <int>[13],
    functionPlus,
  ])
    print(switchTyped(n));
  print(switchOrBound(3));
  print(switchOrBound(-3));
  print(switchNullable(null));
  print(switchNullable(true));
  print(switchNonNull(4));
  print(switchNonNull(null));
  print(switchAsserted(3));
  print(switchCasted(3));
  print(switchPromote(3));
  print(switchMaybe(3));
  print(switchConstants(3));
  print(switchConstants(switchSaved));
  print(switchConstants([1, 2]));
  print(switchConstants(const [3, 4]));
  print(switchConstants(const ConstAtom(9)));
  print(switchConstantCast(topConstant));
  for (var text in ['==', '!=', '<', '<=', '>', '>=', 'when', 'as', 'switch'])
    print(switchOperatorText(text));
  print(switchVoidMatch());
  print(switchVoidRelation(1));
  IntCallback fn = switch (1) {
    1 => (x) => x + 1,
    _ => (x) => x + 2,
  };
  print(fn(4));
  switchTrace = 0;
  print(switch (switchStep(1)) {
    2 when switchGuard(2) => switchStep(3),
    1 when switchGuard(2) => switchStep(4),
    _ => switchStep(5),
  });
  print(switchTrace);
  Object original = 7;
  print(switch (original) {
    int _ when (original = 'changed') == 'again' => -1,
    int value => value,
    _ => 0,
  });
  print(original);
  int assigned;
  print(switch (true) {
    true => assigned = 1,
    false => assigned = 2,
  });
  print(assigned);
  print(switchCapturePattern(7));
  print(switchEscaped[0]());
  for (var i = 0; i < 3; i++)
    print(switch (i) {
      var n when switchCapture(() => n) => 0,
      _ => 1,
    });
  print(switchEscaped[1]());
  print(switchEscaped[2]());
  print(switchEscaped[3]());
  var cls = switch (2) {
    1 => [1],
    _ => [2],
  };
  print(cls[0]);
  print(
    (switch (1) {
          _ => 1,
        }) +
        1,
  );
}

class DestructurePair {
  String Function() observe;
  DestructurePair(this.observe);
  int get a {
    print('a/' + observe());
    return 1;
  }

  int get b {
    print('b/' + observe());
    return 2;
  }
}

class DestructureValue {
  int number;
  List<int> values;
  DestructureValue(this.number, this.values);
}

void destructuringValues([bool choose = true]) {
  var [a, int b, ...rest] = [1, 2, 3, 4];
  print([a, b, rest]);
  a = 3;
  [a, b] = [b, a];
  print([a, b]);
  var old = [a, b];
  var same = ([a, b] = old);
  print(identical(old, same));
  var x = 10, y = 20;
  var pair = DestructurePair(() => '$x,$y');
  print(identical((DestructurePair(a: x, b: y) = pair), pair));
  print([x, y]);
  final DestructureValue(number: n, values: [head, ...tail]) = DestructureValue(
    7,
    [8, 9],
  );
  print([n, head, tail]);
  var (both && int typed) = 4;
  print([both, typed]);
  dynamic dynamicList = [5];
  var [int checked] = dynamicList;
  print(checked);
  Object any = 6;
  var (cast as int) = any;
  print(cast);
  int? optional = 7;
  // ignore: unnecessary_null_assert_pattern
  var (nonnull!) = optional;
  print(nonnull);
  List<int> empty;
  // ignore: unnecessary_type_check
  print(([empty] = [[]]) is List<List<int>>);
  print(empty);
  var [[nested], Object wider] = [
    [1],
    [2],
  ];
  // ignore: unnecessary_type_check
  print([nested] is List<int>);
  print(wider);
  var [[nullable]!, ...remaining] = [
    [2],
    null,
  ];
  print(nullable);
  print(remaining);
  var [List<int> fromConstant] = const [[]];
  // ignore: unnecessary_type_check
  print([fromConstant] is List<List<int>>);
  var [[fromFill]] = List.filled(1, [3]);
  // ignore: unnecessary_type_check
  print([fromFill] is List<int>);
  var [fromSpread] = [
    ...[
      [4],
    ],
  ];
  // ignore: unnecessary_type_check
  print([fromSpread] is List<List<int>>);
  var functions = <int Function()>[];
  for (var [i, j] = [0, 10]; i < 3; i++, j++) {
    functions.add(() => i + j);
  }
  print([for (var f in functions) f()]);
  functions.clear();
  for (var [i, ...r] in [
    [1, 2],
    [3, 4],
  ]) {
    functions.add(() => ++i + r[0]);
  }
  print([for (var f in functions) f()]);
  print([for (var f in functions) f()]);
  print([
    for (final [i, j] in [
      [1, 2],
      [3, 4],
    ])
      i + j,
  ]);
  print([
    for (var [i, j] = [0, 2]; i < 2; i++) i + j,
  ]);
  final int once;
  [once] = [8];
  print(once);
  num promoted = 0;
  [promoted] = <int>[9];
  // ignore: unnecessary_type_check
  print([promoted] is List<num>);
  Object changed = 'old';
  void update() {
    [changed] = [10];
  }

  update();
  print(changed);
  var numList = <int>[1];
  numList[0] = 11;
  print(numList);
  int chained = 0;
  print(([a] = [chained] = [12])[0]);
  print([a, chained]);
  if (1 case var guarded when ([guarded] = [2])[0] == 2) print(guarded);
  if (1 case var guarded
      when (() {
        [guarded] = [3];
        return true;
      })())
    print(guarded);
  var [List<int> conditional] = choose ? [[]] : [[]];
  // ignore: unnecessary_type_check
  print([conditional] is List<List<int>>);
  // CFE infers the shared List<int> context; analyzer uses List<dynamic>.
  // ignore: pattern_type_mismatch_in_irrefutable_context
  var ([inferred] && [List<int> constrained]) = [[]];
  // ignore: unnecessary_type_check
  print([inferred] is List<List<int>>);
  print(constrained);
  functions.clear();
  for (var [i, j] = [0, 10]; i < 3; i++, j++) {
    if (i == 1) continue;
    functions.add(() => i + j);
  }
  for (final [i, j] in [
    [0, 10],
    [1, 20],
    [2, 30],
  ]) {
    if (i == 1) continue;
    functions.add(() => i + j);
  }
  print([for (var f in functions) f()]);
}

int statementPatternResult(Object? value) {
  switch (value) {
    case null:
      return 0;
    case int n && > 0 when n < 3:
      return n;
    case [int n] || [int n, _]:
      return n;
    case String(length: var length):
      return length;
    default:
      return -1;
  }
}

int statementBoolean(bool? value) {
  final int result;
  switch (value) {
    case true:
      result = 1;
    case false:
      result = 2;
    case null:
      result = 3;
  }
  return result;
}

bool statementCapture(List<int Function()> functions, int Function() read) {
  functions.add(read);
  return true;
}

void statementSharedPromotion(Object value) {
  switch (value) {
    case List<Object> items when items is List<int> && items.length == 1:
    case List<Object> items when items is List<int>:
      int n = items[0];
      print(n);
  }
}

void patternSwitchStatements() {
  for (var value in <Object?>[
    null,
    2,
    [3],
    [4, 5],
    'abc',
    true,
  ])
    print(statementPatternResult(value));
  print([
    statementBoolean(true),
    statementBoolean(false),
    statementBoolean(null),
  ]);
  statementSharedPromotion([8]);
  statementSharedPromotion([9, 10]);
  var functions = <int Function()>[];
  for (Object value in [1, 2]) {
    switch (value) {
      case int n when statementCapture(functions, () => n):
      case [int n]:
        functions.add(() => ++n);
    }
  }
  print([for (var read in functions) read()]);
  print([for (var read in functions) read()]);
  functions.clear();
  switch (1) {
    case int n when statementCapture(functions, () => n):
      n = 4;
      functions.add(() => n);
  }
  print([for (var read in functions) read()]);
  functions.clear();
  var owner = PatternNode(3, null, 'first', [1, 2]);
  bool change() {
    owner.tag = 9;
    objectPatternTrace.add('guard');
    return false;
  }

  objectPatternTrace.clear();
  switch (owner) {
    case PatternNode(number: 0):
      print(0);
    case PatternNode(number: var n) when change():
      print(n);
    case PatternNode(number: var n, word: var text):
      print('$n/$text');
  }
  print(objectPatternTrace);
  Object source = 1;
  switch (source) {
    case int n when (source = 'changed') == 'again':
      print(n);
    case int n:
      print(n);
      print(source);
  }
  var repeated = 0;
  switch (1) {
    again:
    alias:
    case 1:
      print(repeated++);
      if (repeated == 1) continue alias;
      switch (2) {
        case 2:
          if (repeated < 3) continue again;
      }
    case 2:
      print(-1);
  }
  switch (1) {
    case 1:
      continue next;
    next:
    case 2 when false:
    case 3:
      print(3);
  }
  outer:
  for (var i = 0; i < 4; i++) {
    switch (i) {
      case 0:
        continue;
      case 1:
        print(1);
        break;
      case 2:
        continue outer;
      default:
        break outer;
    }
    print(9);
  }
  finish:
  switch (1) {
    case int n:
      print(n);
      break finish;
  }
  switch (1) {
    case int n when ([n] = [2])[0] == 2:
      print(n);
  }
  switch (1) {
    // An unused label still prevents the pattern binding from entering the body.
    // ignore: unused_label
    label:
    // ignore: unused_local_variable
    case int n:
      var n = 5;
      print(n);
  }
}

T genericIdentity<T>(T value) => value;
List<T> genericSingle<T>(T value) => [value];
List<T> genericEmpty<T>() => [];
List<T> genericNullable<T>(T? value) => [];
List<T> genericBounded<T extends num>() => [];
List<T> genericFilled<T>(T value) => List<T>.filled(2, value, growable: true);
T genericCast<T>(Object? value) => value as T;
bool genericMatches<T>(Object? value) => value is T;
bool genericCallbackMatches<T>(Object? value) => value is T Function(T);
T genericApply<T>(T Function(T) fn, T value) => fn(value);
List<T> genericRelay<T>(T value) => genericSingle(value);
T genericChoose<T>(T value, [T? fallback]) => fallback ?? value;
T genericNamed<T>(T first, {required T second}) => second;
T genericFirst<T, U extends List<T>>(U values) => values[0];
List<T> genericDependent<T, U extends List<T>>(U values) => [];
T genericLargest<T extends num>(T a, T b) => a > b ? a : b;
num genericJoin<T extends num, U extends num>(bool select, T a, U b) =>
    select ? a : b;
int genericNegate<T extends int>(T value) => -value;
int genericInvoke<T extends int Function(int)>(T callback) => callback(6);
T genericWrite<T extends List<int>>(T values) {
  values.add(3);
  values[0]++;
  return values;
}

int genericCount<T extends List<int>>(T values) => values.length;
int genericHead<T extends List<int>>(T values) {
  for (var value in values) return value;
  return 0;
}

List<T> genericCopy<T>(List<T> values) => [for (var value in values) value];
T genericPattern<T>(List<T> values) {
  if (values case [T first, ...]) return first;
  return values[0];
}

List<T> genericRest<T>(List<T> values) {
  if (values case [_, ...var tail]) return tail;
  return <T>[];
}

dynamic genericNest<T>(int depth, T value) {
  if (depth == 0) return value;
  return genericNest<List<T>>(depth - 1, [value]);
}

int genericIncrement(int value) => value + 1;
String genericTrace = '';
int genericNext(int value) {
  genericTrace = genericTrace + value.toString();
  return value;
}

class GenericCalls {
  static T take<T>(T value) => value;
  static T Function() keepStatic<T>(T value) =>
      () => value;
  T pick<T>(T value, {T? other}) => other ?? value;
  T call<T>(T value, {T? other}) => other ?? value;

  T Function() keep<T>(T value) =>
      () => pick<T>(value);
}

class GenericHolder {
  GenericCalls get value {
    genericTrace = genericTrace + 'getter';
    return GenericCalls();
  }
}

U Function(T) genericSecondClosure<T, U>(U result) =>
    (value) => result;

T Function(T) genericIdentityClosure<T>() =>
    (value) => value;
List<T> Function(T) genericListClosure<T>() =>
    (value) => [value];
T Function(Object?) genericCastClosure<T>() =>
    (value) => value as T;
bool Function(Object?) genericTestClosure<T>() =>
    (value) => value is T;
T Function() Function() genericNestedClosure<T>(T value) =>
    () =>
        () => value;

List<T Function(T)> genericSharedClosures<T>(T value) {
  T read(T ignored) => value;
  T write(T next) {
    value = next;
    return read(next);
  }

  return [read, write];
}

List<T Function()> genericLoopClosures<T>(List<T> values) => [
  for (final value in values) () => value,
];

T Function(int) genericRecursiveClosure<T>(T value) {
  T visit(int depth) => depth == 0 ? value : visit(depth - 1);
  return visit;
}

List<List<T>> Function(T) genericRelayClosure<T>() =>
    (value) => genericSingle<List<T>>(genericSingle<T>(value));

List<T> genericLocalFunctions<T>(T value) {
  T forward(T next) => next;
  List<T> make() => [forward(value)];
  final List<T> Function() inferred = () {
    return [value];
  };
  final List<T> Function() filled = () => List<T>.filled(2, value);
  return [...make(), ...inferred(), ...filled()];
}

List<T> Function() genericEmptyClosure<T>() =>
    () => [];
List<T?> Function() genericNullableClosure<T>() =>
    () => [null];

void genericClosures() {
  final number = genericIdentityClosure<int>();
  final text = genericIdentityClosure<String>();
  Object value = number;
  print(number(42));
  print(text('closure'));
  print(value is int Function(int));
  print(value is String Function(String));
  print(value is num Function(int));
  print(value is int Function(num));
  final nullable = genericIdentityClosure<int?>();
  print(nullable(null));
  print(nullable(7));
  print(genericListClosure<String>()('typed'));
  print(genericCastClosure<int>()(8));
  print(genericTestClosure<List<int>>()([1]));
  print(genericTestClosure<List<int>>()(['wrong']));
  print(genericNestedClosure<String>('nested')()());
  final shared = genericSharedClosures<String>('before');
  print(shared[0]('ignored'));
  print(shared[1]('after'));
  print(shared[0]('ignored'));
  final numbers = genericSharedClosures<int>(0x7fffffffffffffff);
  print(numbers[0](0));
  print(numbers[1](-0x8000000000000000));
  print(numbers[0](0));
  final loops = genericLoopClosures<int>([1, 2, 3]);
  print([for (final read in loops) read()]);
  print(genericRecursiveClosure<bool>(true)(4));
  print(genericRelayClosure<String>()('relay'));
  print(genericLocalFunctions<int>(9));
  print(GenericCalls().keep<String>('receiver')());
  print(GenericCalls.keepStatic<int>(17)());
  final second = genericSecondClosure<int, String>('second parameter');
  print(second(18));
  value = second;
  print(value is String Function(int));
  print(value is int Function(String));
  value = genericEmptyClosure<int>()();
  print(value is List<int>);
  print(value is List<String>);
  value = genericNullableClosure<int>()();
  print(value is List<int?>);
  print(value is List<int>);
  final void Function(void) ignored = genericIdentityClosure<void>();
  ignored(print('void closure argument'));
}

void genericFunctions() {
  genericClosures();
  print(genericIdentity<int>(42));
  print(genericIdentity(true));
  print(genericIdentity('generic'));
  print(genericIdentity<int?>(null));
  // ignore: unnecessary_type_check
  print(genericSingle(5) is List<int>);
  // ignore: unnecessary_type_check
  print(genericSingle(null) is List<Null>);
  List<num> numbers = genericSingle(2);
  print(numbers is List<int>);
  print(genericEmpty() is List<Never>);
  // ignore: unnecessary_type_check
  print(genericNullable(null) is List<Null>);
  print(genericNullable(null) is List<Never>);
  print(genericBounded() is List<int>);
  print(genericFilled<int>(6));
  print(genericFilled<String>('filled'));
  print(genericCast<int>(8));
  print(genericMatches<int>(9));
  print(genericMatches<String>(9));
  print(genericCallbackMatches<int>(genericIncrement));
  print(genericCallbackMatches<String>(genericIncrement));
  var applied = genericApply(genericIncrement, 10);
  print(applied);
  print(genericApply<int>((int value) => value + 2, 10));
  // ignore: unnecessary_type_check
  print(genericRelay('word') is List<String>);
  print(genericChoose(5));
  print(genericChoose(5, 6));
  print(genericNamed(second: genericNext(1), genericNext(2)));
  print(GenericHolder().value<int>(genericNext(3), other: genericNext(4)));
  print(genericTrace);
  print(GenericCalls.take<int>(11));
  print(GenericCalls().pick<int>(12, other: 13));
  print(GenericCalls()<String>('call'));
  print(genericFirst<int, List<int>>([14]));
  print(genericDependent(<int>[1]) is List<int>);
  print(genericLargest(1, 2));
  print(genericJoin(true, 3, 4));
  print(genericNegate(5));
  print(genericInvoke(genericIncrement));
  print(genericWrite([3]));
  print(genericCount([1, 2]));
  print(genericHead([7]));
  print(genericCopy(['a', 'b']));
  print(genericPattern([8]));
  print(genericRest(['first', 'second']));
  print(genericNest<int>(6, 15));
  List<List<int>> nested = genericSingle([]);
  print(nested);
  // ignore: unnecessary_type_check
  print(nested is List<List<int>>);
  var inferred = genericCopy(genericIdentity([1]));
  // ignore: unnecessary_type_check
  print(inferred is List<int>);
  var voidValues = [genericIdentity(print('void argument'))];
  print(voidValues.length);
}

const double floatingConstant = 1 + 2 * 3;
const double exactLarge = 100000000000000000000;
const floatingConstants = <num>[1, 1.25, -0.0, double.infinity, double.nan];

class FloatingBox {
  double value;
  FloatingBox(this.value);
  double get next => value + 0.5;
  set next(double number) {
    value = number - 0.5;
  }
}

class FrozenFloat {
  final num value;
  final double direct;
  const FrozenFloat(this.value, this.direct);
}

T floatingIdentity<T>(T value) => value;
double manyFloats(
  double a,
  double b,
  double c,
  double d,
  double e,
  double f,
  double g,
  double h,
  double i,
  double j,
) => a + b + c + d + e + f + g + h + i + j;

double floatingLoop(int count, double left, double right) {
  for (var i = 0; i < count; i++) {
    final previous = left;
    left = right;
    right = previous + left * 0.25;
    if ((i & 1) == 0) left = -left;
  }
  return left + right;
}

double floatingTap(double value) {
  print(value);
  return manyFloats(value, 1, 2, 3, 4, 5, 6, 7, 8, 9);
}

double floatingAcrossCall(double value) {
  final carried = value * 0.75 + 2;
  try {
    final result = floatingTap(value);
    if (value < 0) throw result;
    return carried + result;
  } catch (error) {
    print(error);
    return carried;
  } finally {
    print(carried);
  }
}

void doubleValues() {
  for (final value in <double>[
    0.0,
    -0.0,
    .5,
    -1.25,
    double.infinity,
    double.nan,
  ]) {
    print(floatingLoop(9, value, 1.25));
    print(floatingAcrossCall(value));
  }
  print([floatingConstant, exactLarge, floatingConstants]);
  const value = FrozenFloat(1.5, 2);
  print([value.value, value.direct]);
  print(identical(value, const FrozenFloat(1.5, 2)));
  final doubles = <double>[
    0,
    -0.0,
    .5,
    -1.25,
    4.9406564584124654e-324,
    2.2250738585072014e-308,
    double.maxFinite,
    double.infinity,
    double.negativeInfinity,
    double.nan,
  ];
  for (final a in doubles) {
    print([a, a.isNaN, a.isFinite, a.isInfinite, a.isNegative, -a]);
    dynamic dynamicA = a;
    print([
      -dynamicA,
      identical(a, dynamicA),
      a == dynamicA,
      // ignore: unnecessary_type_check
      a is double,
      // ignore: unnecessary_type_check
      a is num,
    ]);
    for (final b in <double>[0, -0.0, 2, -2.5, double.infinity, double.nan]) {
      print([a + b, a - b, a * b, a / b, a % b, a.remainder(b)]);
      print([a == b, a != b, a < b, a <= b, a > b, a >= b, a.compareTo(b)]);
      dynamic dynamicB = b;
      print([
        dynamicA + dynamicB,
        dynamicA - dynamicB,
        dynamicA * dynamicB,
        dynamicA / dynamicB,
        dynamicA % dynamicB,
      ]);
      print([
        dynamicA == dynamicB,
        dynamicA != dynamicB,
        dynamicA < dynamicB,
        dynamicA <= dynamicB,
        dynamicA > dynamicB,
        dynamicA >= dynamicB,
      ]);
    }
  }
  for (final integer in <int>[
    0,
    -1,
    1,
    9007199254740993,
    9223372036854775807,
    -9223372036854775808,
  ]) {
    final number = integer.toDouble();
    print([number, number.toInt(), integer / 3, integer / 0, integer % 2.5]);
    print([
      number == integer,
      integer == number,
      number < integer,
      integer < number,
      number.compareTo(integer),
      integer.compareTo(number),
    ]);
  }
  for (final text in <String>[
    '.25',
    '-0.0',
    '1.',
    '1.e2',
    '1e400',
    '5e-324',
    '  -NaN ',
    'bad',
    '',
    '0x10',
  ]) {
    final parsed = double.tryParse(text);
    print(parsed);
    if (parsed != null) print(double.parse(text));
  }
  double? optional = 1;
  // ignore: dead_code, dead_null_aware_expression
  print(optional ?? 2.5);
  optional = null;
  optional ??= 3;
  print(optional + 1);
  final mixed = [1, 2.5];
  // ignore: unnecessary_type_check
  print([mixed is List<num>, mixed is List<int>, mixed is List<double>]);
  final widened = <double>[1, 2, 3.5];
  List<num> numbers = widened;
  print(numbers[1]);
  final box = FloatingBox(1)..next = 2.5;
  print([box.value++, ++box.value, box.next, box.value += 0.25]);
  var captured = 1.25;
  double closure(double other) => captured += other;
  print([closure(.5), closure(1), captured]);
  print(manyFloats(1, 2, 3, 4, 5, 6, 7, 8, 9, 10.25));
  print(floatingIdentity<double>(1.25));
  print(floatingIdentity<num>(-0.0));
  print([7.5 ~/ 2, -7.5 ~/ 2, 7 ~/ 2.5, -7 ~/ 2.5]);
  const constants = <Object>[
    1 / 0,
    0 / 0,
    -0.0,
    1.5 + 2,
    5.5 % 2,
    5.5 ~/ 2,
    0.0 == -0.0,
    // ignore: unnecessary_nan_comparison
    double.nan == double.nan,
    identical(0.0, -0.0),
    identical(double.nan, 0 / 0),
    '$floatingConstant',
  ];
  print(constants);
  const negativeNaN = -double.nan;
  const nanIdentities = <bool>[
    identical(double.nan, negativeNaN),
    identical(negativeNaN, -double.nan),
    identical(<double>[double.nan], <double>[negativeNaN]),
    identical(FrozenFloat(double.nan, 1), FrozenFloat(negativeNaN, 1)),
  ];
  print(nanIdentities);
  dynamic nanValue = double.parse('NaN');
  print([identical(nanValue, nanValue), identical(nanValue, -nanValue)]);
  const invalidConstants = <double>[
    0 / 0,
    double.infinity - double.infinity,
    double.infinity + double.negativeInfinity,
    0 * double.infinity,
  ];
  final zero = double.parse('0');
  final infinity = double.parse('Infinity');
  final invalidResults = <double>[
    zero / zero,
    infinity - infinity,
    infinity + -infinity,
    zero * infinity,
  ];
  for (var i = 0; i < invalidResults.length; i++)
    print(identical(invalidConstants[i], invalidResults[i]));
  print(1_2.5_0e-1_0);
}

String floatingPattern(num number) => switch (number) {
  1 => 'one',
  > 1.0 && < 2 => 'fraction',
  double(isNaN: true) => 'nan',
  int() => 'int',
  _ => 'double',
};

void floatingContexts() {
  double divided = 9007199254740993 / 2;
  double added = 9007199254740993 + 0.5;
  double multiplied = 9007199254740993 * 0.5;
  double modulo = 9007199254740993 % 0.5;
  int integer = 7;
  double product = integer * 2;
  double remainder = integer.remainder(2);
  int integerRemainder = integer.remainder(2);
  final doubleRemainders = <double>[integer.remainder(2)];
  double compound = 1;
  compound += 9007199254740993;
  print([
    divided,
    added,
    multiplied,
    modulo,
    product,
    remainder,
    integerRemainder,
    doubleRemainders,
    compound,
  ]);
  const double constDivision = 9007199254740993 / 2;
  const double constAddition = 9007199254740993 + 1;
  print([constDivision, constAddition]);
  double hex = 0x8000000000000000;
  double a = 1 + 2, b = 1 * 2, c = -1;
  // ignore: dead_code
  double d = true ? 1 : 2;
  var values = <double>[1, 2.5];
  values[0] /= 2;
  a /= 2;
  print([hex, a, b, c, d, values]);
  print(identical(const <double>[1], const <double>[1.0]));
  print(identical(const <double>[0], const <double>[-0.0]));
  for (final number in <num>[1.0, 1.5, 2.0, double.nan, 3])
    print(floatingPattern(number));
  final text = <String>[
    '1.00000000000000011102230246251565404236316680908203125',
    '1.00000000000000011102230246251565404236316680908203126',
    '2.4703282292062327e-324',
    '2.4703282292062328e-324',
    '1.7976931348623157e308',
    '1.7976931348623159e308',
  ];
  for (final input in text) print(double.parse(input));
  var trace = '';
  double left() {
    trace += 'L';
    return 5.5;
  }

  double right() {
    trace += 'R';
    return 2;
  }

  print(left() / right());
  print(trace);
}

int lateReads = 0;
int lateEffect(int value) {
  lateReads++;
  return value;
}

late int lateGlobal = lateEffect(10);
late final int lateOnce;
late int? lateNullable;
int lateRecursions = 0;
late int lateRecursive = ++lateRecursions == 1 ? lateRecursive + 1 : 10;
int ordinaryRecursive = ++lateRecursions == 3 ? ordinaryRecursive + 1 : 20;
late int lateOverwritten = lateWrite();
int lateWrite() {
  lateOverwritten = 4;
  return 5;
}

late final int lateAccessor = 1;
set lateAccessor(int value) => print(value);

class LateFields {
  int base;
  int recursions = 0;
  late int value = lateEffect(this.base);
  late final int once;
  late int? nullable;
  late final double fraction = base / 2;
  late int recursive = ++recursions == 1 ? recursive + 1 : 10;
  late int overwritten = write();
  late int Function() callback = () => base;
  late final int paired = 2;
  set paired(int value) => print(value);
  static late int shared = lateEffect(3);
  static late final double sharedOnce;
  static late int? sharedNullable;
  static late final int sharedPaired = 3;
  static set sharedPaired(int value) => print(value);
  LateFields(this.base);

  int write() {
    overwritten = 4;
    return 5;
  }

  int Function() get reader =>
      () => value;
  int read() => value;
}

class LateInitialized {
  late final int value;
  LateInitialized.base(this.value);
  LateInitialized() : this.base(9);
}

class LateSkipped {
  late int value = lateEffect(100);
  LateSkipped() : value = 3;
}

T lateGeneric<T>(T value) {
  late T result = value;
  return result;
}

void lateBranch(bool branch) {
  late final int value;
  if (branch) value = 1;
  if (!branch) value = 2;
  print(value);
}

int late(int value) => value + 1;

void lateValues() {
  print(late(2));
  {
    var late = 4;
    late++;
    print(late);
  }
  late final int firstLocal = lateEffect(7), nextLocal = firstLocal + 1;
  print(lateReads);
  print([nextLocal, firstLocal, nextLocal, lateReads]);
  var source = 1;
  late int local = lateEffect(source);
  source = 2;
  print(lateReads);
  print([local, local, lateReads]);
  late int skipped = lateEffect(100);
  skipped = 9;
  late final inferred = lateEffect(3);
  late int? nullable = null;
  late double floating = 1;
  floating += 2.5;
  late List<int> context = [];
  context.add(1);
  late int Function(int) callback = (n) => n + 1;
  late int? promoted = 1;
  print([
    skipped,
    inferred,
    inferred,
    nullable,
    nullable,
    floating,
    context,
    callback(3),
    promoted + 1,
    lateReads,
  ]);

  late int captured;
  void set(int n) {
    captured = n;
  }

  int read() => captured;
  set(3);
  print(read());
  set(4);
  print(read());
  late final int once;
  void initialize() {
    once = 5;
  }

  initialize();
  print(once);
  late int delayed = lateEffect(6);
  int readDelayed() => delayed;
  print([readDelayed(), readDelayed(), lateReads]);
  int Function()? reenter;
  var recursions = 0;
  late int recursive = ++recursions == 1 ? reenter!() + 1 : 4;
  reenter = () => recursive;
  print([recursive, recursions]);
  // A wildcard does not cause a lazy initializer to run.
  late var _ = lateEffect(100);
  print(lateReads);
  lateBranch(true);
  lateBranch(false);
  print([lateGeneric<double>(2.5), lateGeneric<String>('late')]);
  final callbacks = <int Function()>[];
  for (var i = 0; i < 2; i++) {
    late int value = lateEffect(i);
    callbacks.add(() => value);
  }
  print([callbacks[0](), callbacks[1](), callbacks[0](), lateReads]);

  lateGlobal = 2;
  lateOnce = 3;
  lateNullable = null;
  print([lateGlobal, lateOnce, lateNullable, lateReads]);
  print([lateRecursive, ordinaryRecursive, lateRecursions, lateOverwritten]);
  lateAccessor = 4;
  print(lateAccessor);
  final first = LateFields(6), second = LateFields(8);
  first.value = 3;
  first.once = 4;
  first.nullable = null;
  print([
    first.read(),
    second.reader(),
    second.reader(),
    first.once,
    first.nullable,
    first.fraction,
    first.fraction,
    first.recursive,
    first.overwritten,
    first.callback(),
    lateReads,
  ]);
  if (second case LateFields(value: var value)) print(value);
  print([LateInitialized().value, LateSkipped().value, lateReads]);
  first.paired = 5;
  print(first.paired);
  LateFields.sharedOnce = 2.5;
  LateFields.sharedNullable = null;
  LateFields.sharedPaired = 6;
  print([
    LateFields.shared,
    LateFields.shared,
    LateFields.sharedOnce,
    LateFields.sharedNullable,
    LateFields.sharedPaired,
    lateReads,
  ]);
}

abstract class ArithmeticInterface {
  num add(num value, [num extra = 1]);
  String named({int x = 1, required int y});
  int get value;
  set value(int next);
  int apply(int value);
  T echo<T extends num>(T value);
}

class FieldArithmetic implements ArithmeticInterface {
  int value;
  FieldArithmetic(this.value);
  num add(num value, [num extra = 20]) => this.value + value + extra;
  String named({required int y, int x = 2}) => '$x:$y';
  int apply(int input) => input + value;
  T echo<T extends num>(T input) => input;
}

class AccessorArithmetic implements ArithmeticInterface {
  int storage;
  AccessorArithmetic(this.storage);
  num add(num value, [num extra = 30]) => storage + value + extra;
  String named({int x = 3, required int y, bool extra = false}) =>
      '$x:$y:$extra';
  int get value => storage;
  set value(int next) {
    storage = next * 2;
  }

  int apply(int input) => input * storage;
  U echo<U extends num>(U input) => input;
}

abstract class IndirectArithmetic implements ArithmeticInterface {}

typedef BoundedIndirect<T extends ArithmeticInterface> = IndirectArithmetic;
typedef BoundedArithmeticList<T extends ArithmeticInterface> = List<T>;
typedef FieldArithmeticList = BoundedArithmeticList<FieldArithmetic>;

class InferredArithmetic implements BoundedIndirect<FieldArithmetic> {
  int storage = 9;
  get value => storage;
  set value(next) {
    storage = next;
  }

  add(value, [extra = 40]) => value + extra;
  named({required y, x = 4}) => '$x:$y';
  apply(value) => value - 1;
  T echo<T extends num>(T value) => value;
}

abstract class IntegralInterface {
  num read(int input);
  num get value;
  set value(int next);
}

abstract class NumericInterface {
  int read(num input);
  int get value;
  set value(num next);
}

abstract class CombinedInterface
    implements IntegralInterface, NumericInterface {}

class CombinedArithmetic implements CombinedInterface {
  int read(num input) => input.toInt();
  int get value => 4;
  set value(num next) {
    print(next);
  }
}

class InterfaceConstant implements ConstantInterface {
  final int value;
  const InterfaceConstant(this.value);
  int read() => value;
}

abstract class ConstantInterface {
  int read();
}

const ConstantInterface interfaceConstant = InterfaceConstant(4);

class StoredInterface {
  int value;
  StoredInterface(this.value);
}

class StoredImplementation implements StoredInterface {
  int storage = 3;
  int get value => storage;
  set value(int next) {
    storage = next * 2;
  }
}

class LateStoredImplementation implements StoredInterface {
  late int value = interfaceArgument(4);
}

class FinalSetterImplementation implements NumericInterface {
  final int value = 4;
  int read(num input) => input.toInt();
  set value(num next) {
    print(next);
  }
}

abstract class OptionalInterface {
  int read(int value);
  T echo<T extends Object?>(T value);
}

class OptionalImplementation implements OptionalInterface {
  int read([int value = 3, int extra = 10]) => value + extra;
  U echo<U extends dynamic>(U value) => value;
}

abstract class StringInterface {
  String toString();
}

class DefaultStringImplementation implements StringInterface {}

class DeclaredStringImplementation implements StringInterface {
  String toString();
}

class ExplicitStringImplementation implements StringInterface {
  String toString() => 'explicit';
}

int interfaceConsume(ArithmeticInterface value) => value.apply(2);
V interfaceGeneric<V extends num>(ArithmeticInterface value, V input) =>
    value.echo<V>(input);
int interfaceArgument(int value) {
  print(value);
  if (value == 2) throw value;
  return value;
}

class UntypedOrdinaryFields {
  var value;
  final once;
  late var delayed;
  UntypedOrdinaryFields(this.once);
  UntypedOrdinaryFields.narrow(int this.value, this.once);
  UntypedOrdinaryFields.zero() : this(0);
}

abstract class InferredNumber {
  num get number;
}

abstract class InferredFieldTypes extends InferredNumber {
  String get text;
  void set text(String value);
  double get fraction;
  List<num> get numbers;
  String? get optional;
  void set optional(String? value);
}

class InferredOrdinaryFields implements InferredFieldTypes {
  var number;
  var text;
  var fraction = 1;
  var numbers = [1, 2];
  var optional;
  InferredOrdinaryFields(this.number, this.text);
}

class InferredLateText extends InferredOrdinaryFields {
  late var text;
  InferredLateText() : super(2, 'base');
}

class InferredFinalNumber implements InferredNumber {
  final number;
  InferredFinalNumber(this.number);
  InferredFinalNumber.narrow(int this.number);
}

class InferredLateFinalNumber implements InferredNumber {
  late final number;
}

int fieldNumberInitializer() {
  print('field initializer');
  return 3;
}

class InitializedInferredNumber implements InferredNumber {
  var number = fieldNumberInitializer();
}

class PrimaryInferredNumber(num seed) implements InferredNumber {
  var number = seed;
}

const inferredFieldSeed = inferredFieldTail;
const inferredFieldTail = 7;

int inferredFieldCallback(int value) => value + 1;

class InferredInitializerFields {
  static const label = 'inferred';
  var number = 1 + 2 * 3;
  final fraction = 1 / 2;
  var absent = null;
  var text = label;
  var seed = inferredFieldSeed;
  var mixed = true ? 1 : 2.5;
  var values = [1, 2];
  var nested = [
    [1],
    [2],
  ];
  var selected = [
    if (true) 1 else 2.5,
    ...[3, 4],
  ];
  var empty = [];
  var first = [1, 2][0];
  var length = 'hello'.length;
  var nonnull = null ?? 4;
  var callback = inferredFieldCallback;
  var object = new Box(fieldNumberInitializer());
  late var delayed = Box(fieldNumberInitializer());
  late var lateText = 'late';
  late final lateNumber = 1.5;
}

class InferredInitializerChild extends InferredInitializerFields {
  var number = 2;
}

class InferredConstInitializer {
  final number = 3;
  const InferredConstInitializer();
}

class InferredInitializedFormal {
  late var number = 1;
  InferredInitializedFormal(this.number);
}

void interfaceValues() {
  final field = FieldArithmetic(5);
  FieldArithmeticList fields = [field];
  print(fields[0].apply(2));
  final accessor = AccessorArithmetic(7);
  for (final value in <ArithmeticInterface>[
    field,
    accessor,
    InferredArithmetic(),
  ]) {
    print(value.add(2));
    print(value.add(2, 4));
    print(value.named(y: 8));
    print(value.named(y: 8, x: 6));
    print(value.value);
    value.value += 3;
    print(value.value);
    final method = value.apply;
    print(method(4));
    print(method == value.apply);
    print(value.echo<int>(8));
    print(value.echo(1.5));
  }
  ArithmeticInterface same = field;
  print(same.apply == field.apply);
  dynamic erased = field;
  print(erased is ArithmeticInterface);
  print((erased as ArithmeticInterface).value);
  dynamic values = <FieldArithmetic>[field];
  print(values is List<ArithmeticInterface>);
  print((values as List<ArithmeticInterface>)[0].value);
  Object object = InferredArithmetic();
  print(object is IndirectArithmetic);
  print(object is ArithmeticInterface);
  final inferred = <FieldArithmetic>[field].isEmpty ? field : accessor;
  print(inferred.add(1));
  int Function(FieldArithmetic) callback = interfaceConsume;
  print(callback(field));
  print(interfaceGeneric(field, 7));
  print(interfaceGeneric(accessor, 1.5));
  try {
    throw accessor;
  } on ArithmeticInterface catch (value) {
    print(value.value);
  }
  try {
    same.add(interfaceArgument(1), interfaceArgument(2));
  } catch (error) {
    print(error);
  }
  print(same.add(interfaceArgument(3)));
  CombinedInterface combined = CombinedArithmetic();
  print(combined.read(2.5));
  print(combined.value);
  combined.value = 3.5;
  IntegralInterface integral = combined;
  NumericInterface numeric = combined;
  print(integral.read(3));
  print(numeric.read(4.5));
  print(interfaceConstant.read());
  print(interfaceConstant is InterfaceConstant);
  print(identical(interfaceConstant, const InterfaceConstant(4)));
  StoredInterface stored = StoredImplementation();
  print(stored.value++);
  print(stored.value);
  print(stored.value += 4);
  print(stored.value);
  StoredInterface lateStored = LateStoredImplementation();
  print(lateStored.value++);
  print(lateStored.value);
  StoredInterface assignedLateStored = LateStoredImplementation();
  assignedLateStored.value = 9;
  print(assignedLateStored.value);
  NumericInterface finalSetter = FinalSetterImplementation();
  print(finalSetter.value);
  finalSetter.value += 2.5;
  OptionalInterface optional = OptionalImplementation();
  print(optional.read(2));
  print(optional.echo(3));
  print(optional.echo(null));
  print(OptionalImplementation().read());
  for (final value in <StringInterface>[
    DefaultStringImplementation(),
    DeclaredStringImplementation(),
    ExplicitStringImplementation(),
  ]) {
    print(value.toString());
    print('$value');
  }
  print(DeclaredStringImplementation().toString());
  print('${DeclaredStringImplementation()}');
  final untyped = UntypedOrdinaryFields('once');
  print([untyped.value, untyped.once]);
  untyped.value = 1;
  untyped.value = 'changed';
  untyped.delayed = true;
  print([untyped.value, untyped.delayed, UntypedOrdinaryFields.zero().once]);
  final narrowUntyped = UntypedOrdinaryFields.narrow(1, null);
  final dynamicValues = [narrowUntyped.value];
  print(dynamicValues is List<int>);
  final inferredFields = InferredOrdinaryFields(2, 'inferred');
  final inferredNumbers = [inferredFields.number];
  print(inferredNumbers is List<num>);
  print(inferredNumbers is List<int>);
  print([
    inferredFields.text,
    inferredFields.fraction,
    inferredFields.numbers is List<int>,
    inferredFields.optional,
  ]);
  inferredFields.number = 2.5;
  inferredFields.text = 'updated';
  inferredFields.optional = 'present';
  print([inferredFields.number, inferredFields.text, inferredFields.optional]);
  final lateText = InferredLateText();
  lateText.text = 'late inferred';
  print(lateText.text);
  final finalNumber = InferredFinalNumber.narrow(4);
  print([finalNumber.number] is List<num>);
  print([finalNumber.number] is List<int>);
  final lateFinalNumber = InferredLateFinalNumber();
  lateFinalNumber.number = 5.5;
  print(lateFinalNumber.number);
  print([InitializedInferredNumber().number] is List<int>);
  print([PrimaryInferredNumber(6).number] is List<num>);
  print('before inferred initializers');
  final initializers = InferredInitializerFields();
  print('after inferred initializers');
  print([initializers.number] is List<int>);
  print([initializers.fraction] is List<double>);
  print([initializers.text] is List<String>);
  print([initializers.mixed] is List<num>);
  print([initializers.mixed] is List<int>);
  print([initializers.seed, initializers.first, initializers.length]);
  print([initializers.nonnull] is List<int>);
  initializers.absent = 'changed';
  print(initializers.absent);
  initializers.values.add(3);
  print(initializers.values);
  print(initializers.values is List<int>);
  print(initializers.nested is List<List<int>>);
  print(initializers.selected is List<num>);
  initializers.empty.add('dynamic');
  print(initializers.empty);
  print(initializers.callback(2));
  print([initializers.callback] is List<int Function(int)>);
  print([initializers.object] is List<Box>);
  print(initializers.object.value);
  print(initializers.delayed.value);
  print(initializers.delayed.value);
  print(initializers.lateText);
  initializers.lateText = 'changed';
  print(initializers.lateText);
  print(initializers.lateNumber);
  final child = InferredInitializerChild();
  print([child.number] is List<int>);
  print(child.number);
  print(child.values);
  const constant = InferredConstInitializer();
  print([constant.number] is List<int>);
  print(constant.number);
  print(InferredInitializedFormal(5).number);
}

class CovariantBase {
  int take(covariant num value, [covariant Object? extra = 'base']) => 0;
  int named({covariant num value = 3, covariant Object? extra = 'base'}) => 0;
  int mixed({covariant num value = 1, String extra = 'base'}) => 0;
  void set item(covariant num value) {}
  num operator +(covariant num other) => other;
  bool operator <(covariant num other) => false;
  T choose<T extends num>(covariant num value) => value as T;
}

class CovariantNarrow extends CovariantBase {
  int take(int value, [String? extra = 'child']) {
    print(extra);
    return value + 1;
  }

  int named({int value = 4, String? extra = 'child'}) {
    print(extra);
    return value + 2;
  }

  int mixed({String extra = 'child', int value = 2}) {
    print(extra);
    return value;
  }

  void set item(int value) {
    print(value);
  }

  int operator +(int other) => other + 3;
  bool operator <(int other) => other > 0;
  T choose<T extends num>(T value) => value;
}

abstract class CovariantContract {
  int method(covariant int value);
}

abstract class CovariantWideContract {
  int method(num value);
}

class CovariantImplementation {
  int method(int value) => value + 4;
}

class CovariantCombined extends CovariantImplementation
    implements CovariantContract, CovariantWideContract {
  void checkSuper() {
    print(super.method is int Function(Object?));
    print(this.method is int Function(Object?));
    print(super.method == this.method);
    print(this.method == this.method);
  }
}

abstract class CovariantSetter {
  void set item(covariant num value);
}

class CovariantField implements CovariantSetter {
  int item = 1;
}

class CovariantCallback {
  int apply(covariant int callback(int value)) => callback(4);
}

class InferredCovariant extends CovariantBase {
  int take(value, [extra = 'inferred']) {
    print(extra);
    return value as int;
  }
}

class VoidCovariantBase {
  void take(void value) {}
}

class VoidCovariant extends VoidCovariantBase {
  void take(covariant int value) {
    print(value);
  }
}

class StaticCovariantBase {
  static void take(String value) {}
}

class StaticCovariantChild extends StaticCovariantBase {
  void take(covariant int value) {
    print(value);
  }
}

class DeclaredCovariantFields {
  covariant num first = 1, second = 2;
  covariant late num lazy;
  covariant late final num once;
  covariant() => 19;
}

class NarrowCovariantFields extends DeclaredCovariantFields {
  int first = 4, second = 5;
  late int lazy;
  late final int once;
}

class CovariantFieldSetter extends DeclaredCovariantFields {
  void set second(int value) {
    print(value);
  }
}

class CovariantPrimaryFields(
  covariant var num value, {
  required covariant var num count,
});

class NarrowCovariantPrimary(
  covariant var int value, {
  required covariant var int count,
}) extends CovariantPrimaryFields {
  this : super(value, count: count);
}

class InferredCovariantPrimary(covariant var value)
    extends CovariantPrimaryFields {
  this : super(value, count: 1);
}

class CovariantFunctionField(covariant var int callback(int value));

int covariantIncrement(int value) => value + 1;

void covariantValues() {
  int identifier(covariant) => covariant + 1;
  print(identifier(1));
  CovariantBase value = CovariantNarrow();
  print(value.take(2));
  print(value.take(3, null));
  print(value.named(extra: 'named', value: 5));
  print(value.named());
  value.item = 6;
  print(value + 7);
  if (value case < 8) print('covariant pattern');
  print(value.choose<int>(9));
  print(value.choose<double>(2.5));
  var method = value.take;
  print(method is int Function(Object?, [Object?]));
  print(method is int Function(String, [List<int>]));
  print(method(10));
  var named = value.named;
  print(named is int Function({Object? value, Object? extra}));
  print(named(value: 11));
  var mixed = value.mixed;
  print(mixed is int Function({Object? value, String extra}));
  print(mixed is int Function({Object? value, Object? extra}));
  print(mixed(extra: 'mixed', value: 15));
  var inferred = InferredCovariant().take;
  print(inferred is int Function(Object?, [Object?]));
  print(inferred(16));
  var combined = CovariantCombined();
  CovariantWideContract wide = combined;
  print(wide.method(12));
  var inherited = combined.method;
  print(inherited is int Function(Object?));
  print(inherited(13));
  combined.checkSuper();
  print(CovariantImplementation().method is int Function(Object?));
  var field = CovariantField();
  CovariantSetter setter = field;
  setter.item = 14;
  print(field.item);
  print(CovariantCallback().apply(covariantIncrement));
  VoidCovariantBase voidParameter = VoidCovariant();
  voidParameter.take(17);
  StaticCovariantChild().take(18);
  DeclaredCovariantFields fields = NarrowCovariantFields();
  print([fields.first, fields.second]);
  fields.first = 20;
  fields.second += 1;
  fields.lazy = 21;
  fields.once = 22;
  print([fields.first, fields.second, fields.lazy, fields.once]);
  print(fields.covariant());
  fields = CovariantFieldSetter();
  fields.second = 23;
  CovariantPrimaryFields primary = NarrowCovariantPrimary(24, count: 25);
  primary.value = 26;
  primary.count = 27;
  print([primary.value, primary.count]);
  final inferredField = InferredCovariantPrimary(1);
  inferredField.value = 2.5;
  print(inferredField.value);
  print(CovariantFunctionField(covariantIncrement).callback(28));
}

class InheritedChild extends InheritedBase {
  int value = 10;
  String child = 'child';
  late int cached = super.value + 5;
  InheritedChild(super.initial) : super.named();
  int add(int input, [int extra = 20]) => super.add(input) + extra;
  T echo<T extends num>(T input) => super.echo<T>(input);
  int baseValue() => super.value;
  void changeBase(int next) {
    super.value = next;
  }

  int Function() parentRead() => super.read;
  int Function() nestedRead() =>
      () => super.read();
  int Function() nestedWrite() => () {
    super.value += 2;
    return super.value;
  };
}

class InheritedBase {
  int value;
  String base = 'base';
  late final String lazy = 'lazy';
  InheritedBase.named(this.value);
  int read() => value;
  int add(int input, [int extra = 1]) => value + input + extra;
  int invoke() => add(2);
  T echo<T extends num>(T input) => input;
  String toString() => '$base:$value';
}

class InheritedLeaf extends InheritedChild {
  InheritedLeaf(super.value);
}

class InheritedGetterBase {
  int value = 1;
}

class InheritedGetter extends InheritedGetterBase {
  int get value => super.value * 2;
  void add(int input) {
    super.value += input;
  }
}

class InheritedDefaultBase {
  final int value;
  const InheritedDefaultBase([this.value = 7]);
}

class InheritedDefault extends InheritedDefaultBase {
  const InheritedDefault([super.value]);
}

class InheritedImplicit extends InheritedDefaultBase {}

abstract class InheritedConstantBase {
  final int value;
  const InheritedConstantBase(this.value);
  int read() => value;
}

class InheritedConstant extends InheritedConstantBase {
  final int value;
  final String label;
  const InheritedConstant(super.base, this.value, this.label);
  const InheritedConstant.named(String label) : this(2, 3, label);
  int baseValue() => super.value;
}

class InheritedConcrete {
  int read(int value) => value + 1;
}

abstract class InheritedAbstract extends InheritedConcrete {
  int read(int value);
}

class InheritedConcreteLeaf extends InheritedAbstract {}

class InheritedObject {
  InheritedObject() : super();
  String toString() => 'prefix:' + super.toString();
}

class InheritedObjectLeaf extends InheritedObject {}

class InheritedCallable {
  int call(int value) => value + 1;
}

class InheritedCallableChild extends InheritedCallable {
  int call(int value) => super(value) + 2;
}

class InheritedCallableLeaf extends InheritedCallableChild {}

class InheritedGenericCallable {
  T call<T>(T value) => value;
}

class InheritedGenericCallableChild extends InheritedGenericCallable {
  T call<T>(T value) => super<T>(value);
}

class InheritedCallback {
  int Function(int) callback = (value) => value + 1;
  int Function(int) get reader {
    print(1);
    return callback;
  }
}

class InheritedCallbackChild extends InheritedCallback {
  int change() {
    print(2);
    callback = (value) => value + 10;
    return 3;
  }

  int direct() => super.reader(change());
  int field() => super.callback(change());
  int value() => (super.reader)(change());
}

int inheritanceMark(int value) {
  print(value);
  return value;
}

class InheritedOrderBase {
  int declared = inheritanceMark(1);
  int value;
  InheritedOrderBase(this.value) {
    print(2);
  }
}

class InheritedOrder extends InheritedOrderBase {
  int own = inheritanceMark(3);
  int explicit;
  InheritedOrder(int input)
    : explicit = inheritanceMark(4),
      super(inheritanceMark(input)) {
    print(5);
  }
}

class InheritedThrowBase {
  int value = inheritanceMark(11);
  InheritedThrowBase() {
    throw 12;
  }
}

class InheritedThrow extends InheritedThrowBase {
  int child = inheritanceMark(13);
  InheritedThrow() {
    print(14);
  }
}

class SuperNarrowBase {
  final num? value;
  const SuperNarrowBase([this.value = 1.5]);
}

class SuperNarrow extends SuperNarrowBase {
  const SuperNarrow([int? super.value]);
}

class SuperIntegerBase {
  final num value;
  const SuperIntegerBase([this.value = 1]);
}

class SuperInteger extends SuperIntegerBase {
  const SuperInteger([int super.value]);
}

class SuperOptional extends InheritedConstantBase {
  const SuperOptional([super.value = 8]);
}

class SuperOrderBase {
  final int first;
  final int middle;
  final int last;
  SuperOrderBase(this.first, {required this.middle, required this.last});
}

class SuperOrder extends SuperOrderBase {
  SuperOrder({required super.middle})
    : super(last: inheritanceMark(21), inheritanceMark(22));
}

int superScopeValue = 9;

class SuperScopeBase {
  SuperScopeBase(int value);
}

class SuperScope extends SuperScopeBase {
  final int copied;
  final int Function() read;
  SuperScope(super.superScopeValue)
    : copied = (superScopeValue),
      read = (() => superScopeValue) {
    print(superScopeValue);
  }
  SuperScope.simple(super.superScopeValue)
    : read = (() => superScopeValue),
      copied = (superScopeValue) {
    print(superScopeValue);
  }
  SuperScope.choose(super.superScopeValue, bool condition)
    : copied = superScopeValue,
      read = condition ? (() => superScopeValue) : (() => 0);
}

class SuperCallbackBase {
  final int Function(int)? callback;
  SuperCallbackBase([int this.callback(int value)?]);
}

class SuperCallback extends SuperCallbackBase {
  SuperCallback([int super.callback(int value)?]);
}

class SuperWildBase {
  final int first;
  final int second;
  SuperWildBase(this.first, this.second);
}

class SuperWild extends SuperWildBase {
  SuperWild(super._, super._);
}

void inheritanceValues() {
  for (final instance in <InheritedBase>[
    InheritedBase.named(3),
    InheritedChild(4),
    InheritedLeaf(5),
  ]) {
    print(instance.add(1));
    print(instance.add(2, 3));
    final bound = instance.add;
    print(bound(1));
    instance.value += 2;
    print(instance.value);
    print(instance.read());
    print(instance.echo(4.5));
  }
  final child = InheritedLeaf(2);
  InheritedBase base = child;
  print(child.base + child.child);
  print(child.value);
  print(base.value);
  print(child.baseValue());
  child.changeBase(7);
  print(child.baseValue());
  print(child.cached);
  print(child.lazy);
  print(base.add(2));
  print(child.add(2, 30));
  print(base.invoke());
  print(base.echo(2.5));
  print(child.parentRead()());
  print(child.nestedRead()());
  print(child.nestedWrite()());
  print(child.parentRead() == child.read);
  print(child is InheritedBase);
  print(child.toString());
  print('$child');
  final getter = InheritedGetter();
  print(getter.value);
  getter.value = 4;
  print(getter.value);
  getter.add(2);
  print(getter.value);
  print(getter.value++);
  print(getter.value);
  getter.value += 3;
  print(getter.value);
  print(const InheritedDefault().value);
  print(InheritedDefault(12).value);
  print(InheritedImplicit().value);
  const value = InheritedConstant(2, 3, 'constant');
  const InheritedConstantBase constantBase = value;
  print(constantBase.read());
  print(value.baseValue());
  print(value.label);
  print(identical(value, const InheritedConstant.named('constant')));
  print(identical(value, const InheritedConstant(9, 3, 'constant')));
  print(InheritedConstant(2, 3, 'constant').baseValue());
  print(InheritedConcreteLeaf().read(4));
  print(InheritedObjectLeaf());
  print(InheritedCallableLeaf()(3));
  int Function(int) callable = InheritedCallableLeaf();
  print(callable(4));
  print(InheritedGenericCallableChild()<String>('inherited call'));
  print(InheritedCallbackChild().direct());
  print(InheritedCallbackChild().field());
  print(InheritedCallbackChild().value());
  print(const SuperNarrow().value);
  print(SuperNarrow(3).value);
  print(const SuperInteger().value);
  print(const SuperOptional().value);
  final forwarded = SuperOrder(middle: inheritanceMark(23));
  print(forwarded.first + forwarded.middle + forwarded.last);
  final scope = SuperScope(2);
  print(scope.copied);
  print(scope.read());
  print(SuperScope.simple(3).copied);
  print(SuperScope.choose(4, true).read());
  print(SuperScope.choose(4, false).read());
  print(SuperCallback().callback);
  print(SuperCallback((value) => value + 2).callback!(3));
  final wildcard = SuperWild(4, 5);
  print(wildcard.first + wildcard.second);
  final order = InheritedOrder(6);
  print(order.declared + order.value + order.own + order.explicit);
  try {
    InheritedThrow();
  } catch (error) {
    print(error);
  }
}

class PrimaryMutable(var int value, final String label) {
  final int Function() initial = () => value;
  late int Function() current = () => value;
  this {
    value += 2;
  }
}

int primaryValue = 8;

class PrimaryScope(int primaryValue) {
  final int copied = primaryValue + 1;
  final int Function() captured = () => primaryValue;
  late int lateValue = primaryValue;
  static int staticValue = primaryValue;
  this {
    primaryValue += 5;
    if (primaryValue == 7) return;
    PrimaryPoint point() => PrimaryPoint(primaryValue);
    print(point().sum);
  }
}

class const PrimaryPoint(final int x, [final int y = 3]) {
  final int sum = x + y;
  const new origin() : this(0, 0);
}

class PrimaryDefaults([
  var number = 1,
  final label = 'primary',
  final absent,
  final values = const [2, 3],
  final point = const PrimaryPoint(4),
]);

class PrimaryObject(final value);

abstract class PrimaryGetter {
  num get value;
}

class PrimaryInferred([final value = 1]) implements PrimaryGetter;

abstract class PrimarySetter {
  set value(int value);
}

class PrimaryWrite(var value) implements PrimarySetter;

abstract class PrimaryAccessors {
  int get value;
  set value(int value);
}

class PrimaryBoth(var value) implements PrimaryAccessors;

class PrimarySplitBase {
  num get value => 1;
  set value(int value) {
    print(value);
  }
}

class PrimaryFinal(final value) extends PrimarySplitBase;

class PrimaryTyped(this.value) {
  int value;
}

class PrimaryCallback([final int callback(int value)?]);

class PrimaryEmpty;

class PrimaryWildcard(_, _);

class PrimaryNamed.new(final int value);

class AbbreviatedConstructor {
  final int value;
  new(this.value);
  new named(int value) : this(value + 1);
}

class PrimaryOrder(var int input) {
  final int first = inheritanceMark(input + 1);
  final int second = inheritanceMark(input + 2);
  this {
    print(input);
  }
}

void primaryConstructorValues() {
  final mutable = PrimaryMutable(2, 'mutable');
  print(mutable.value);
  print(mutable.label);
  print(mutable.initial());
  print(mutable.current());
  mutable.value = 9;
  print(mutable.initial());
  print(mutable.current());
  final scope = PrimaryScope(2);
  print(scope.copied);
  print(scope.captured());
  print(scope.lateValue);
  print(PrimaryScope.staticValue);
  print(PrimaryScope(3).copied);
  const point = PrimaryPoint(2);
  print(point.sum);
  print(const PrimaryPoint(3).sum);
  print(PrimaryPoint(4).sum);
  print(identical(const PrimaryPoint.origin(), const PrimaryPoint(0, 0)));
  final defaults = PrimaryDefaults();
  print(defaults.number + 2);
  defaults.number = 4;
  print(defaults.number);
  print(defaults.label.length);
  print(defaults.absent);
  print(defaults.values[1]);
  print(defaults.point.sum);
  print(PrimaryObject(1).value);
  print(PrimaryObject(null).value);
  print(PrimaryInferred().value);
  print(PrimaryInferred(2.5).value);
  final write = PrimaryWrite(3);
  print(write.value + 1);
  write.value = 7;
  print(write.value);
  print(PrimaryBoth(4).value + 1);
  final split = PrimaryFinal(2.5);
  print(split.value);
  split.value = 3;
  print(PrimaryTyped(2).value);
  print(PrimaryCallback().callback);
  print(PrimaryCallback((value) => value + 2).callback!(3));
  print(PrimaryEmpty() is PrimaryEmpty);
  print(PrimaryWildcard(1, 2) is PrimaryWildcard);
  print(PrimaryNamed.new(2).value);
  print(AbbreviatedConstructor(2).value);
  print(AbbreviatedConstructor.named(2).value);
  final order = PrimaryOrder(inheritanceMark(30));
  print(order.first + order.second);
}

abstract class FactoryValue {
  num get value;
  const factory FactoryValue([int value]) = FactoryBridge;
  const factory FactoryValue.named({required int value, int bonus}) =
      FactoryProduct.named;
  factory FactoryValue.extra() = FactoryProduct;
  factory FactoryValue.body(int value) => FactoryProduct(value + 1);
}

typedef NullableFactory = FactoryValue?;

abstract class FactoryBridge implements FactoryValue {
  const factory FactoryBridge([num value]) = FactoryProduct;
}

class const FactoryProduct([final num value = 4.5]) implements FactoryBridge {
  const FactoryProduct.named({required int value, int bonus = 3})
    : this(value + bonus);
}

class FactoryBox._(final int value) {
  static final FactoryBox cached = FactoryBox._(0);
  factory FactoryBox(int value) {
    if (value == 0) return cached;
    FactoryBox create() => FactoryBox._(value);
    value++;
    return create();
  }
  factory twice(int value) => FactoryBox(value * 2);
  factory from(dynamic value) => value;
  factory fail() => throw 'factory';
}

class FactoryNew {
  static factory() => 9;
  final int value;
  FactoryNew._(this.value);
  factory FactoryNew.new(int value) => FactoryNew._(value);
}

class FactoryAbbreviated._(final int value) {
  factory(int value) => FactoryAbbreviated._(value);
}

abstract class FactoryPrivate {
  int get value;
  const factory FactoryPrivate({int value}) = FactoryPrivateProduct;
}

class FactoryPrivateProduct implements FactoryPrivate {
  final int _value;
  const FactoryPrivateProduct({this._value = 6});
  int get value => _value;
}

abstract class FactoryNullable {
  num? get value;
  factory FactoryNullable([int value]) = FactoryNullableProduct;
}

class FactoryNullableProduct([final num? value]) implements FactoryNullable;

abstract class FactoryMutable {
  int value = 3;
  late final int later;
  const factory FactoryMutable() = FactoryMutableProduct;
}

class FactoryMutableProduct implements FactoryMutable {
  const FactoryMutableProduct();
  int get value => 5;
  void set value(int value) {}
  int get later => 6;
  void set later(int value) {}
}

abstract class FactoryPayload {
  Object? get value;
  const factory FactoryPayload(void value) = FactoryPayloadProduct;
}

class const FactoryPayloadProduct(final Object? value)
    implements FactoryPayload;

abstract class FactoryCallback {
  int get value;
  factory FactoryCallback(int callback(int x)) = FactoryCallbackProduct;
}

class FactoryCallbackProduct implements FactoryCallback {
  final int value;
  FactoryCallbackProduct(int Function(int) callback) : value = callback(3);
}

int oldStyleCallback(int callback(int value), int value) => callback(value);
int nullableOldStyle([int callback(int value)?]) =>
    callback == null ? 0 : callback(4);

class ConstructorValue {
  final int value;
  ConstructorValue(this.value);
  const ConstructorValue.optional([this.value = 4]);
  const ConstructorValue.named({this.value = 5});
  ConstructorValue.forward({int value = 6}) : this(value);
  ConstructorValue.ordered(int first, {required int second})
    : value = functionMark(3) + first + second {
    functionMark(4);
  }
  ConstructorValue.fail() : value = 0 {
    throw 'constructor';
  }
  int named() => value + 1;
  static ConstructorValue Function([int]) get callback =>
      ConstructorValue.optional;
}

typedef ConstructorAlias = ConstructorValue;
typedef NullableConstructorAlias = ConstructorValue?;

const savedConstructor = ConstructorValue.new;
const savedConstructors = <ConstructorValue Function(int)>[
  savedConstructor,
  ConstructorAlias.new,
];
ConstructorValue defaultConstructor([
  ConstructorValue Function(int) make = ConstructorValue.new,
]) => make(2);

class InferredConstructorHolder([final make = InferredConstructorChild.new]);
class InferredConstructorParent([final value = 9]);

class InferredConstructorChild extends InferredConstructorParent {
  InferredConstructorChild([super.value]);
}

class InferredPrimaryHolder([final make = InferredPrimary.new]);
class InferredPrimary([final value = 11]);

class EmptyConstructorValue {}

void constructorValues() {
  print(savedConstructor(1).value);
  print(defaultConstructor().value);
  print((ConstructorValue.new)(3).value);
  print((ConstructorValue.optional)().value);
  print((ConstructorValue.named).call().value);
  print(ConstructorValue.callback().value);
  final named = ConstructorValue.named;
  print(named(value: 10).named());
  print(identical(savedConstructor, ConstructorAlias.new));
  print(identical(savedConstructor, NullableConstructorAlias.new));
  print(identical(savedConstructors[0], savedConstructors[1]));
  print(identical(savedConstructor, ConstructorValue.optional));
  print(identical(savedConstructor, ConstructorValue.forward));
  const equal = ConstructorAlias.new == ConstructorValue.new;
  print(equal);
  print(switch (savedConstructor) {
    const (ConstructorValue.new) => 'constructor match',
    _ => 'wrong constructor',
  });
  // The contextual namespace is the instance class, not the function type.
  print(switch (ConstructorValue(0)) {
    .new => 1,
    _ => 2,
  });
  functionTrace = 0;
  final ordered = ConstructorValue.ordered;
  print(ordered(second: functionMark(2), functionMark(1)).value);
  print(functionTrace);
  final forward = ConstructorValue.forward;
  print(forward().value);
  final factory = FactoryValue.new;
  print(factory().value);
  print(factory(12).value);
  print(factory is FactoryValue Function([int]));
  print(factory is FactoryValue Function([num]));
  print(identical(factory, FactoryProduct.new));
  final factoryNamed = FactoryValue.named;
  print(factoryNamed(value: 3).value);
  print(factoryNamed(bonus: 2, value: 3).value);
  final factoryExtra = FactoryValue.extra;
  print(factoryExtra().value);
  final privateNamed = FactoryPrivateProduct.new;
  print(privateNamed(value: 8).value);
  final nullable = FactoryNullable.new;
  print(nullable().value);
  final payload = FactoryPayload.new;
  print(payload(13).value);
  final box = FactoryBox.new;
  print(identical(box(0), FactoryBox.cached));
  print(box(1).value);
  final body = FactoryValue.body;
  print(body(5).value);
  dynamic checked = savedConstructor;
  ConstructorValue Function(int) checkedConstructor = checked;
  print(checkedConstructor(14).value);
  final holder = InferredConstructorHolder();
  print(holder.make().value);
  print(holder.make is InferredConstructorChild Function([int]));
  print(holder.make is InferredConstructorChild Function([String]));
  final primary = InferredPrimaryHolder();
  print(primary.make().value);
  print(primary.make is InferredPrimary Function([int]));
  final empty = EmptyConstructorValue.new;
  print(empty() is EmptyConstructorValue);
  final failures = <Object Function()>[ConstructorValue.fail, FactoryBox.fail];
  for (final failure in failures) {
    try {
      failure();
    } catch (error) {
      print(error);
    } finally {
      print('constructor finally');
    }
  }
}

void factoryValues() {
  print(FactoryPayload(5).value);
  print(FactoryPayload('payload').value);
  print((const FactoryPayload(6)).value);
  print(FactoryCallback((value) => value + 1).value);
  print(oldStyleCallback((value) => value + 2, 5));
  print(nullableOldStyle());
  print(nullableOldStyle((value) => value + 3));
  final fresh = FactoryValue();
  print(fresh.value);
  print(FactoryValue(2).value);
  print(FactoryValue.body(2).value);
  print(FactoryValue.extra().value);
  print(
    FactoryValue.named(
      bonus: inheritanceMark(3),
      value: inheritanceMark(4),
    ).value,
  );
  const constant = FactoryValue();
  print(pass([const NullableFactory(2)]) is List<FactoryValue>);
  print(constant.value);
  print(identical(constant, const FactoryProduct()));
  print(identical(const FactoryValue(2), const FactoryProduct(2)));
  print((const FactoryValue.named(value: 2)).value);
  print(identical(fresh, FactoryValue()));
  print(identical(fresh, constant));
  print(identical(FactoryBox(0), FactoryBox(0)));
  print(FactoryBox(2).value);
  print(FactoryBox.twice(2).value);
  print(FactoryBox.from(FactoryBox(0)).value);
  try {
    FactoryBox.fail();
  } catch (error) {
    print(error);
  }
  print(FactoryNew.new(7).value);
  print(FactoryNew.factory());
  print(FactoryAbbreviated(8).value);
  const private = FactoryPrivate();
  print(private.value);
  print(FactoryPrivate(value: 9).value);
  print(identical(private, const FactoryPrivateProduct()));
  print(FactoryNullable().value);
  print(FactoryNullable(4).value);
  const mutable = FactoryMutable();
  print(mutable.value);
  print(mutable.later);
}

void main(List<String> args) {
  allocationValues();
  enumValues();
  operatorValues();
  factoryValues();
  shorthandValues();
  shorthandContexts();
  primaryConstructorValues();
  inheritanceValues();
  interfaceValues();
  covariantValues();
  finallyValues();
  exceptionValues();
  stackTraceValues();
  lateValues();
  doubleValues();
  floatingContexts();
  genericFunctions();
  patternSwitchStatements();
  destructuringValues();
  ifCaseValues();
  objectPatterns();
  listPatterns();
  sublistValues();
  collectionValues();
  nullAwareValues();
  cascadeValues();
  staticMembers();
  namedConstructors();
  constructorInitializers();
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
  constObjects();
  functionValues();
  switchExpressions();
  relationalPatterns();
  genericAliases();
  legacyAliases();
  bufferValues();
  stringBoundaries();
  listGrowth(args);
}

class AllocationValue {
  final int value;
  AllocationValue? next;
  AllocationValue(this.value);
}

T Function() allocationKeep<T>(T value) =>
    () => value;

void allocationValues() {
  final values = <AllocationValue>[
    for (var i = 0; i < 4096; i++) AllocationValue(i),
  ];
  values.first.next = values.last;
  values.last.next = values.first;
  final keep = allocationKeep<List<AllocationValue>>(values);
  final spare = List<AllocationValue?>.filled(300000, null, growable: true);
  spare.clear();
  final text = String.fromCharCodes([
    for (var i = 0; i < 512; i++) 65 + i % 26,
  ]);
  final tagged = <Object>[text.substring(1, 511), 9223372036854775807, 1.25];
  var checksum = 0;
  for (var round = 0; round < 4; round++) {
    for (var i = 0; i < 50000; i++) {
      final batch = <AllocationValue>[
        AllocationValue(i),
        AllocationValue(i + 1),
      ];
      checksum += batch[0].value + batch[1].value;
    }
    spare.add(keep()[round]);
    print([spare.last!.value, keep().last.next!.value, tagged]);
  }
  print(checksum);
  print(values.first.next!.value);
  print(text.length);
}

enum EnumColor { red, green, blue }

abstract class EnumShape {
  double area();
}

enum EnumKind implements EnumShape {
  unit(1),
  twice(2),
  named.make(3),
  other.make(4);

  const EnumKind(this.side);
  const EnumKind.make(int s) : this(s * 10);
  final int side;
  static const EnumKind first = unit;
  static int total() => EnumKind.values.length;
  double area() => side * 2.0;
  String label() => 'k$side';
  bool get big => side > 20;
  factory EnumKind.pick(int n) => n > 0 ? unit : other;
}

enum EnumNamed {
  a('first'),
  b('second');

  const EnumNamed(this.name);
  final String name;
  String toString() => 'N:$name';
}

class EnumTag {
  final EnumColor color;
  const EnumTag(this.color);
}

@EnumTag(EnumColor.green)
EnumColor enumDefault([EnumColor c = EnumColor.blue]) => c;

String enumStatement(EnumColor c) {
  switch (c) {
    case EnumColor.red:
      return 'R';
    case EnumColor.green:
    case EnumColor.blue:
      return 'GB';
  }
}

int enumNullable(EnumColor? c) => switch (c) {
  EnumColor.red || EnumColor.green => 1,
  EnumColor.blue => 2,
  null => 3,
};

String enumShorthand(EnumColor c) {
  switch (c) {
    case .red:
      return 'dr';
    default:
      return 'd?';
  }
}

String enumGuard(EnumColor c) => switch (c) {
  EnumColor.red when c.index == 0 => 'zero-red',
  EnumColor.red => 'red',
  EnumColor.green => 'green',
  EnumColor.blue => 'blue',
};

void enumValues() {
  print(EnumColor.red);
  print(EnumColor.values.length);
  print(EnumColor.green.index);
  print(EnumColor.blue.name);
  print('${EnumColor.red} ${EnumColor.blue.index}');
  print(EnumKind.unit.side);
  print(EnumKind.named.side);
  print(EnumKind.other.area());
  print(EnumKind.twice.label());
  print(EnumKind.first == EnumKind.unit);
  print(EnumKind.total());
  print(EnumKind.other.big);
  print(EnumKind.pick(1));
  print(EnumKind.pick(0));
  print(EnumNamed.a);
  print(EnumNamed.b.name);
  print(EnumNamed.a.index);
  EnumShape shape = EnumKind.unit;
  print(shape.area());
  Enum e = EnumColor.green;
  print(e.index);
  print(e.name);
  dynamic d = EnumColor.red;
  print(d is EnumColor);
  print(d is Enum);
  print(d is EnumKind);
  print(enumStatement(EnumColor.red) + enumStatement(EnumColor.blue));
  print(enumNullable(EnumColor.green));
  print(enumNullable(null));
  print(enumShorthand(EnumColor.red));
  print(enumShorthand(EnumColor.blue));
  print(enumGuard(EnumColor.red));
  print(enumGuard(EnumColor.blue));
  print(enumDefault());
  print(enumDefault(EnumColor.red));
  const list = [EnumColor.red, EnumColor.blue];
  print(list.length);
  print(identical(list[0], EnumColor.red));
  print(identical(EnumColor.values[1], EnumColor.green));
  var sum = 0;
  for (final c in EnumColor.values) {
    sum += c.index;
  }
  print(sum);
  if (EnumColor.green case EnumColor.green || EnumColor.blue) print('case');
  EnumColor chosen = .blue;
  print(chosen == EnumColor.blue);
  EnumColor? maybe = EnumColor.values.length > 3 ? EnumColor.red : null;
  print(maybe == null);
  maybe = EnumColor.blue;
  print(maybe.name);
}

class OpVec {
  final int x;
  final int y;
  const OpVec(this.x, this.y);
  OpVec operator +(OpVec o) => OpVec(x + o.x, y + o.y);
  OpVec operator -(OpVec o) => OpVec(x - o.x, y - o.y);
  OpVec operator -() => OpVec(-x, -y);
  OpVec operator ~() => OpVec(y, x);
  OpVec operator *(int k) => OpVec(x * k, y * k);
  OpVec operator <<(int n) => OpVec(x << n, y << n);
  OpVec operator >>>(int n) => OpVec(x >>> n, y >>> n);
  OpVec operator ~/(int k) => OpVec(x ~/ k, y ~/ k);
  bool operator <(OpVec o) => x * x + y * y < o.x * o.x + o.y * o.y;
  bool operator >=(OpVec o) => !(this < o);
  int operator [](int i) => i == 0 ? x : y;
  String toString() => 'OpVec($x, $y)';
}

const opA = OpVec(1, 2);
const opB = OpVec(3, 5);

String shorthandTrace = '';

class ShorthandValue {
  final int value;
  const ShorthandValue(this.value);
  const ShorthandValue.zero() : value = 0;
  factory ShorthandValue.make([int value = 3]) => .new(value);
  static const ShorthandValue one = .new(1);
  static ShorthandValue get two => .new(2);
  static ShorthandValue? get absent => null;
  static List<ShorthandValue> get many => <ShorthandValue>[.one];
  static ShorthandValue from(int value) => .new(value);
  static ShorthandValue Function(int) get maker {
    shorthandTrace += 'getter';
    return from;
  }

  static T? choose<T>() {
    print(<T>[] is List<ShorthandValue>);
    return null;
  }

  ShorthandValue next() => .new(value + 1);
}

class ShorthandHolder {
  ShorthandValue field = .new(8);
  final ShorthandValue child;
  ShorthandHolder(this.child);
  ShorthandHolder.named(int value) : this(.new(value));
  ShorthandValue get value => .one;
  set value(ShorthandValue next) {
    field = next;
  }
}

class ShorthandConstant {
  final ShorthandValue child;
  const ShorthandConstant(this.child);
  const ShorthandConstant.named() : child = const .new(4);
}

typedef ShorthandAlias = ShorthandValue?;
typedef ShorthandIdentity<T> = T;

ShorthandValue shorthandReturn(bool first) => first ? .one : .make(5);
int shorthandDefault([ShorthandValue value = const .new(4)]) => value.value;
ShorthandValue shorthandArgument(
  ShorthandValue value, {
  required ShorthandValue other,
}) => .new(value.value + other.value);
List<T> shorthandGeneric<T>(T value) => .filled(0, value);
T shorthandId<T>(T value) => value;
ShorthandValue Function() shorthandClosure() =>
    () => .new(6);
ShorthandValue shorthandSwitch(int value) => switch (value) {
  0 => .one,
  _ => .new(value),
};

void shorthandValues() {
  ShorthandValue value = .new(4);
  print(value.value);
  value = .zero();
  print(value.value);
  value = .two;
  print(value.value);
  value = .from(7);
  print(value.value);
  value = .many[0].next();
  print(value.value);
  ShorthandValue? nullable = .absent?.next();
  print(nullable == null);
  nullable ??= .one;
  print(nullable.value);
  value = .absent ?? .one;
  print(value.value);
  value = (.one);
  print(value.value);
  ShorthandAlias alias = .new(5);
  print(alias!.value);
  {
    final ShorthandValue = 10;
    final one = 20;
    ShorthandIdentity<ShorthandAlias> unshadowed = .one;
    print(unshadowed!.value + ShorthandValue + one);
  }
  print(shorthandReturn(true).value);
  print(shorthandReturn(false).value);
  print(shorthandDefault());
  print(shorthandArgument(.one, other: .new(3)).value);
  print(shorthandClosure()().value);
  print(shorthandSwitch(9).value);
  ShorthandAlias inferred = shorthandId(.new(11));
  print(inferred!.value);
  ShorthandHolder holder = .named(12);
  print(holder.field.value);
  print(holder.child.value);
  print(holder.value.value);
  holder.value = .two;
  print(holder.field.value);
}

int shorthandMarkedArgument() {
  shorthandTrace += 'argument';
  return 8;
}

void shorthandContexts() {
  ShorthandValue created = .maker(shorthandMarkedArgument());
  print(created.value);
  print(shorthandTrace);
  final list = <ShorthandValue>[
    .one,
    .new(3),
    if (true) .two,
    for (var i = 0; i < 2; i++) .new(i),
    ?.absent,
    ?.absent ?? .two,
  ];
  for (final value in list) print(value.value);
  List<ShorthandValue>? filled = .filled(2, .one);
  print(filled![0].value);
  print(filled.length);
  print(shorthandGeneric<int>(2) is List<int>);
  int number = .parse('42');
  double floating = .parse('4.5');
  double fallback = .tryParse('bad') ?? 1.5;
  String string = .fromCharCodes([65]);
  print(<Object>[number, floating, fallback, string]);
  const ShorthandValue constant = .new(4);
  const constants = <ShorthandValue>[.one, .new(4)];
  const ShorthandValue conditional = true ? .one : .new(3);
  const ShorthandConstant outer = .new(.new(4));
  ShorthandConstant initializer = const .named();
  print(identical(constant, constants[1]));
  print(identical(constant, outer.child));
  print(identical(constant, initializer.child));
  print(conditional.value);
  ShorthandValue actual = .one;
  print(actual == .one);
  print(actual != .two);
  const bool equal = ShorthandValue.one == .one;
  print(equal);
  print(actual == .choose());
  print(switch (actual) {
    .one => 1,
    _ => 0,
  });
  print(switch (actual) {
    const .new(1) => 1,
    _ => 0,
  });
  print(switch (actual) {
    == .one => 1,
    _ => 0,
  });
  print(switch (actual) {
    != .one => 1,
    _ => 0,
  });
  print(switch (actual) {
    const (true ? .one : .new(2)) => 1,
    _ => 0,
  });
  if (actual case .one) print('matched');
  double relation = 1;
  print(switch (relation) {
    < .infinity => 1,
    _ => 0,
  });
  print(switch (relation) {
    >= .negativeInfinity => 1,
    _ => 0,
  });
}
