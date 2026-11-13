// Exercise conventional constructors alongside the existing primary fixtures.
// ignore_for_file: use_primary_constructors, unnecessary_type_name_in_constructor

import 'effects.dart';

extension RecordAccess<T extends (int, {int named, int Function(int) apply})>
    on T {
  int get total => $1 + named;
  int callImplicit(int value) => apply(value) + $1;
  int Function() get captured =>
      () => $1 + named;
}

int recordMembers(int seed) {
  final record = (seed, named: seed + 2, apply: (int n) => tick(n));
  return record.total +
      record.callImplicit(seed + 3) +
      record.captured() +
      record.apply(seed + 4);
}

int? optionalRecordCall(bool absent, int seed) {
  final record = absent ? null : (apply: (int n) => tick(n));
  return record?.apply(tick(seed));
}

class Cell<T> {
  final List<T> values;
  Cell(T value) : values = [value];
}

extension Access<T> on Cell<T> {
  T get item {
    tick(2);
    return values[0];
  }

  set item(T value) {
    tick(5);
    values[0] = value;
  }

  T operator [](int index) {
    tick(2);
    return values[index];
  }

  void operator []=(int index, T value) {
    tick(5);
    values[index] = value;
  }

  T get _private => item;
  int Function(int) get callable {
    tick(2);
    return (int n) => tick(n);
  }

  int lexical(int n) => callable(tick(n));
  T lexicalItem() => _private;
}

Cell<T> receiver<T>(Cell<T> cell) {
  tick(1);
  return cell;
}

int key() {
  tick(6);
  return 0;
}

int rhs(int seed) {
  tick(3);
  return seed;
}

Object getterSetter(int seed) {
  final cell = Cell<int>(seed);
  final result = Access<int>(receiver(cell)).item = rhs(seed + 1);
  return summarize([
    result,
    cell.item,
    Access<int>(cell)._private,
    cell.lexicalItem(),
  ]);
}

Object updates(int seed) {
  final cell = Cell<int>(seed);
  final a = receiver(cell).item += rhs(3);
  final b = receiver(cell).item++;
  final c = ++receiver(cell).item;
  final d = receiver(cell)[key()] += rhs(4);
  final e = receiver(cell)[key()]++;
  final f = ++receiver(cell)[key()];
  return summarize([a, b, c, d, e, f, cell.values[0]]);
}

Object explicitIndex(int seed) {
  final cell = Cell<int>(seed);
  final a = receiver(cell)[key()] = rhs(seed + 1);
  final b = Access(receiver(cell))[key()]++;
  return summarize([a, b, Access<int>(cell)[0]]);
}

Object nullableAssignments(bool absent, bool empty) {
  final cell = absent ? null : Cell<int?>(empty ? null : 8);
  final a = cell?.item ??= rhs(7);
  final b = cell?[key()] ??= rhs(9);
  final c = cell
    ?..item = rhs(10)
    ..[key()] = rhs(11);
  return summarize([a, b, c?.values[0]]);
}

Object ifNullIndex(bool empty) {
  final cell = Cell<int?>(empty ? null : 4);
  final a = receiver(cell)[key()] ??= rhs(7);
  final b = receiver(cell)[key()] ??= rhs(9);
  return summarize([a, b, cell.values[0]]);
}

Object getterCall(int seed) {
  final cell = Cell<int>(seed);
  final a = receiver(cell).callable(tick(3));
  final b = Access(cell).callable(tick(4));
  final c = cell.lexical(7);
  return summarize([a, b, c]);
}

class Amount {
  final int value;
  Amount(this.value);
}

extension Arithmetic on Amount {
  Amount operator +(int other) {
    tick(4);
    return Amount(value + other);
  }

  Amount operator -(int other) {
    tick(4);
    return Amount(value - other);
  }

  Amount operator -() {
    tick(4);
    return Amount(-value);
  }

  int operator ~() {
    tick(4);
    return ~value;
  }

  bool operator >(int other) {
    tick(4);
    return value > other;
  }
}

Object operatorUpdates(int seed) {
  final cell = Cell(Amount(seed));
  final a = receiver(cell).item += rhs(3);
  final b = receiver(cell)[key()]++;
  final c = --receiver(cell).item;
  return summarize([
    a.value,
    b.value,
    c.value,
    (-Amount(seed)).value,
    ~Amount(seed),
  ]);
}

extension GenericOperator<T> on Cell<T> {
  int operator +(int other) {
    tick(4);
    return other is T ? other : -1;
  }

  bool operator -() {
    tick(4);
    return T == int;
  }
}

Object explicitOperators(int seed) {
  final cell = Cell<int>(seed);
  return summarize([
    GenericOperator<int>(receiver(cell)) + rhs(seed + 1),
    -GenericOperator<int>(receiver(cell)),
    receiver(cell) + rhs(seed + 2),
  ]);
}

Object patterns(int seed) {
  final cell = Cell<int>(seed);
  final a = switch (cell) {
    Cell<int>(item: final n) => n,
  };
  final b = switch (cell) {
    Cell<int>(item: _) => 1,
  };
  final c = switch (Amount(seed)) {
    > 0 => 2,
    _ => 3,
  };
  return summarize([a, b, c]);
}

class Lexical<T> extends Cell<T> {
  Lexical(super.value);
  T read() => item;
  T Function() capture() =>
      () => item;
  T write(T value) => item = value;
}

Object lexicalAccess(int seed) {
  final cell = Lexical<int>(seed);
  return summarize([
    cell.read(),
    cell.capture()(),
    cell.write(seed + 1),
    cell.read(),
  ]);
}

extension NullableAccess on int? {
  int get fallback => this ?? 42;
}

Object nullableGetter(int? seed) => summarize([seed.fallback, seed?.fallback]);

extension WriteOnly on Cell<int> {
  set sink(int value) {
    tick(5);
    values[0] = value;
  }
}

Object setterOnly(int seed) {
  final cell = Cell(seed);
  return summarize([
    WriteOnly(receiver(cell)).sink = rhs(seed),
    cell.values[0],
  ]);
}

Object receiverCheck(bool valid) {
  dynamic cell = valid ? Cell<int>(1) : Cell<String>('bad');
  try {
    return Access<int>(cell).item = rhs(7);
  } finally {
    tick(8);
  }
}

Object operatorReceiverCheck(bool valid) {
  dynamic cell = valid ? Cell<int>(1) : Cell<String>('bad');
  try {
    return GenericOperator<int>(cell) + rhs(7);
  } finally {
    tick(8);
  }
}

Object indexCheck(Object? input) {
  final cell = Cell<int>(1);
  dynamic index = input;
  try {
    return receiver(cell)[index] = rhs(7);
  } finally {
    tick(8);
  }
}

extension DynamicAccess on dynamic {
  int operator -() {
    tick(27);
    return 11;
  }

  int operator ~() {
    tick(28);
    return 12;
  }

  int get fixed => 10;
  set fixed(int value) {
    tick(value);
  }

  int operator +(int value) {
    tick(4);
    return value;
  }
}

Object explicitDynamic(Object? input) {
  final a = DynamicAccess(input).fixed = rhs(7);
  return summarize([
    a,
    DynamicAccess(input).fixed,
    DynamicAccess(input) + rhs(9),
    -DynamicAccess(input),
    ~DynamicAccess(input),
    ~GenericDynamicUnary<dynamic>(input),
  ]);
}

class Failing {
  final int stage;
  int value = 1;
  Failing(this.stage);
}

void step(Failing value, int stage) {
  tick(value.stage == stage ? -stage : stage);
}

Failing failingReceiver(Failing value) {
  step(value, 1);
  return value;
}

int failingRhs(Failing value) {
  step(value, 3);
  return 7;
}

extension FailureAccess on Failing {
  int get item {
    step(this, 2);
    return value;
  }

  set item(int input) {
    step(this, 5);
    value = input;
  }
}

Object exceptionalUpdate(int stage) {
  final cell = Failing(stage);
  try {
    return failingReceiver(cell).item += failingRhs(cell);
  } finally {
    tick(8);
  }
}

class PatternBase {}

class PatternChild extends PatternBase {}

extension BasePatternAccess on PatternBase {
  int get marker {
    tick(20);
    return 1;
  }

  bool operator >(int other) {
    tick(23);
    return false;
  }
}

extension ChildPatternAccess on PatternChild {
  int get marker {
    tick(21);
    return 2;
  }

  bool operator >(int other) {
    tick(24);
    return true;
  }
}

extension GenericPatternAccess<T> on Cell<T> {
  bool get isInt {
    tick(22);
    return T == int;
  }

  bool operator >(int other) {
    tick(25);
    return T == int;
  }
}

Object patternSelection() {
  Object object = PatternChild();
  final a = switch (object) {
    PatternBase(marker: 0) => 0,
    PatternChild(marker: 2) => 1,
    _ => 2,
  };
  final b = switch (object) {
    PatternBase() && > 0 => 0,
    PatternChild() && > 0 => 1,
    _ => 2,
  };
  Object cell = Cell<int>(1);
  final c = switch (cell) {
    Cell<num>(isInt: true) => 0,
    Cell<int>(isInt: true) => 1,
    _ => 2,
  };
  final d = switch (cell) {
    Cell<num>() && > 0 => 0,
    Cell<int>() && > 0 => 1,
    _ => 2,
  };
  return summarize([a, b, c, d]);
}

Object patternReuse(int seed) {
  final cell = Cell<int>(seed);
  return switch (cell) {
    Cell<int>(item: 100) => 1,
    Cell<int>(item: 200) => 2,
    Cell<int>(item: final value) => value,
  };
}

String summarize(List<Object?> values) {
  var result = '';
  for (final value in values) {
    result = '$result|$value';
  }
  return result;
}

class Token<T> {
  final T value;
  Token(this.value);
}

extension TokenOperators<T> on Token<T> {
  T operator +(T other) {
    tick(4);
    return other;
  }

  T operator -() {
    tick(4);
    return value;
  }
}

Object implicitGenericOperators(int seed) {
  final value = Token<int>(seed);
  return summarize([value + rhs(seed + 1), -value]);
}

int repeatedOperator(int seed) {
  if (Amount(seed) case > 0 || > 0) return 1;
  return 0;
}

extension NullableCompare on int? {
  bool operator <(int other) {
    tick(26);
    return this == null || this! < other;
  }
}

int nullablePattern(int? seed) => switch (seed) {
  < 0 => 1,
  _ => 2,
};

int implicitSetterValue(int seed) {
  final cell = Cell<int>(seed);
  return receiver(cell).item = rhs(seed + 1);
}

int implicitSetterStatement(int seed) {
  final cell = Cell<int>(seed);
  receiver(cell).item = rhs(seed + 1);
  return cell.values[0];
}

Object explicitIndexCheck(Object? input) {
  final cell = Cell<int>(1);
  dynamic index = input;
  try {
    Access<int>(receiver(cell))[index] = rhs(7);
    return cell.values[0];
  } finally {
    tick(8);
  }
}

extension GenericDynamicUnary<T> on T {
  int operator ~() {
    tick(29);
    return this == null ? 1 : 0;
  }
}

int explicitIndexValue(int seed) {
  final cell = Cell<int>(seed);
  return Access<int>(receiver(cell))[key()] = rhs(seed + 1);
}

Cell<int> orderReceiver(int stage) {
  tick(stage == 1 ? -1 : 1);
  return Cell<int>(0);
}

dynamic orderIndex(int stage) {
  tick(stage == 2 ? -2 : 2);
  return stage == 4 ? 'bad' : 0;
}

dynamic orderValue(int stage) {
  tick(stage == 3 ? -3 : 3);
  return stage == 5 ? 'bad' : 7;
}

int explicitIndexFailure(int stage) {
  try {
    return Access<int>(orderReceiver(stage))[orderIndex(stage)] = orderValue(
      stage,
    );
  } finally {
    tick(8);
  }
}

int implicitSetterFailure(int stage) {
  try {
    return orderReceiver(stage).item = orderValue(stage);
  } finally {
    tick(8);
  }
}
