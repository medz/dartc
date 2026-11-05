// ignore_for_file: unnecessary_late, unused_local_variable, prefer_function_declarations_over_variables, unnecessary_type_check, dead_code, unnecessary_null_comparison, dead_null_aware_expression, use_primary_constructors, use_declaring_parameters, unnecessary_type_name_in_constructor, unnecessary_this
import 'effects.dart';

String observe(List<Object?> values) => '$values';

int? nullValue(int event) {
  tick(event);
  return null;
}

dynamic wrongValue(int event) {
  tick(event);
  return 'wrong';
}

int unusedInitializer() {
  late int unused = tick(901);
  late final int unusedFinal = tick(902);
  tick(1);
  return 2;
}

String lazyFirstRead() {
  late int value = tick(3);
  late final int fixed = tick(4);
  tick(5);
  return observe([fixed, value, value, fixed]);
}

String earlierMutableLatestValue() {
  var source = tick(6);
  late int value = source + tick(7);
  source = tick(8);
  final first = value;
  source = tick(9);
  return observe([first, value, source]);
}

String earlierClosureSharesLatestValue() {
  var source = 1;
  int readSource() => source;
  late final int value = readSource() + tick(10);
  source = 5;
  final first = value;
  source = 6;
  return observe([first, value, readSource()]);
}

int multipleDeclaratorsReadEarlier() {
  late int first = tick(11), second = first + tick(12);
  return second + first;
}

int captureUnboundWithoutRead() {
  late int value;
  int read() => value;
  final saved = read;
  tick(13);
  value = tick(14);
  return saved();
}

int unboundCapturedRead(bool bind) {
  late int value;
  if (bind) value = 2;
  int read() => value;
  tick(15);
  try {
    return read();
  } finally {
    tick(16);
  }
}

int unboundFinalCapturedRead(bool bind) {
  late final int value;
  if (bind) value = 3;
  int read() => value;
  tick(17);
  return read();
}

int assignmentBypassesInitializer() {
  late int value = tick(903);
  value = tick(18);
  return value;
}

int closureAssignmentBypassesInitializer() {
  late int value = tick(904);
  void write(int next) => value = next;
  write(tick(19));
  return value;
}

String nullableBoundAndUnbound() {
  late int? value;
  int? read() => value;
  try {
    read();
  } on Error {
    tick(20);
  }
  value = null;
  final first = read();
  value = tick(21);
  return observe([first, read()]);
}

String lazyNullIsBound() {
  late int? value = nullValue(22);
  late final int? fixed = nullValue(23);
  return observe([value, value, fixed, fixed]);
}

int? finalNullIsFirstWrite() {
  late final int? value;
  void write(int? next) => value = next;
  write(null);
  try {
    write(tick(24));
  } on Error {
    tick(25);
  } finally {
    tick(26);
  }
  return value;
}

int? unboundCoalescingReadsBeforeRhs() {
  late int? value;
  int? initialize() => value ??= tick(905);
  return initialize();
}

String compoundAndCoalescingUpdates() {
  late int value = tick(27);
  final added = value += tick(28);
  final before = value++;
  final after = ++value;
  late int? nullable = nullValue(29);
  final first = nullable ??= tick(30);
  final second = nullable ??= tick(906);
  return observe([added, before, after, value, first, second]);
}

int finalSecondWriteEvaluatesRhs() {
  late final int value;
  void write(int next) => value = next;
  write(tick(31));
  try {
    write(tick(32));
  } finally {
    tick(value);
  }
  return value;
}

int finalCastPrecedesBoundCheck() {
  late final int value;
  void write(dynamic next) => value = next;
  write(tick(33));
  try {
    write(wrongValue(34));
  } on TypeError {
    tick(35);
  } on Error {
    tick(907);
  }
  try {
    write(tick(36));
  } on Error {
    tick(37);
  }
  return value;
}

int failedFirstCastLeavesUnbound() {
  late final int value;
  void write(dynamic next) => value = next;
  int read() => value;
  try {
    write(wrongValue(38));
  } on TypeError {
    tick(39);
  }
  try {
    read();
  } on Error {
    tick(40);
  }
  write(tick(41));
  return value;
}

String failedInitializerRetries() {
  var attempts = 0;
  final token = <int>[42];
  int initialize() {
    tick(42 + ++attempts);
    if (attempts < 3) throw token;
    return tick(46);
  }

  late int value = initialize();
  for (var i = 0; i < 2; i++) {
    try {
      value;
    } catch (error) {
      if (!identical(error, token)) return 'wrong error';
      tick(47 + i);
    } finally {
      tick(49 + i);
    }
  }
  return observe([value, value, attempts]);
}

String finalInitializerRetries() {
  var attempts = 0;
  int initialize() {
    tick(51 + ++attempts);
    if (attempts < 2) throw 54;
    return 55;
  }

  late final int value = initialize();
  try {
    value;
  } on int catch (error) {
    tick(error);
  }
  return observe([value, value, attempts]);
}

bool initializerPreservesThrowAndTrace() {
  final token = <int>[56];
  Object? originalError;
  StackTrace? originalTrace;
  int initialize() {
    try {
      throw token;
    } catch (error, trace) {
      originalError = error;
      originalTrace = trace;
      tick(57);
      rethrow;
    } finally {
      tick(58);
    }
  }

  late final int value = initialize();
  try {
    value;
  } catch (error, trace) {
    return identical(error, token) &&
        identical(error, originalError) &&
        identical(trace, originalTrace);
  } finally {
    tick(59);
  }
  return false;
}

String initializerFailureRetainsWrite() {
  late void Function() write;
  var attempts = 0;
  int initialize() {
    tick(60 + ++attempts);
    write();
    throw 62;
  }

  late int value = initialize();
  write = () => value = tick(63);
  try {
    value;
  } on int catch (error) {
    tick(error);
  } finally {
    tick(64);
  }
  return observe([value, value, attempts]);
}

String initializerReturnReplacesWrite() {
  late void Function() write;
  int initialize() {
    write();
    return tick(65);
  }

  late int value = initialize();
  write = () => value = tick(66);
  return observe([value, value]);
}

String initializerCastFailureRetainsWrite() {
  late void Function() write;
  dynamic initialize() {
    write();
    return wrongValue(67);
  }

  late int value = initialize();
  write = () => value = tick(68);
  try {
    value;
  } on TypeError {
    tick(69);
  }
  return observe([value, value]);
}

String initializerCastFailureRetries() {
  var attempts = 0;
  dynamic initialize() {
    tick(70 + ++attempts);
    if (attempts == 1) return 'wrong';
    return 73;
  }

  late final int value = initialize();
  try {
    value;
  } on TypeError {
    tick(74);
  }
  return observe([value, value, attempts]);
}

String boundedMutableRecursion() {
  late int Function() read;
  var depth = 0;
  int initialize() {
    final current = ++depth;
    try {
      tick(75 + current);
      return current < 3 ? read() + 10 : 1;
    } finally {
      tick(79 + current);
    }
  }

  late int value = initialize();
  read = () => value;
  return observe([value, value, depth]);
}

String boundedFinalRecursion() {
  late int Function() read;
  var depth = 0;
  int initialize() {
    final current = ++depth;
    try {
      tick(83 + current);
      return current < 3 ? read() + 10 : 1;
    } finally {
      tick(87 + current);
    }
  }

  late final int value = initialize();
  read = () => value;
  try {
    value;
  } on Error {
    tick(91);
  } finally {
    tick(92);
  }
  return observe([value, value, depth]);
}

String recursiveFinalCastPrecedesBoundCheck() {
  late int Function() read;
  var depth = 0;
  dynamic initialize() {
    tick(93 + ++depth);
    if (depth == 2) return 96;
    read();
    return 'wrong';
  }

  late final int value = initialize();
  read = () => value;
  try {
    value;
  } on TypeError {
    tick(97);
  } on Error {
    tick(908);
  }
  return observe([value, value, depth]);
}

T genericLocal<T>(T initial, T replacement) {
  late T value = initial;
  initial = replacement;
  return value;
}

bool genericInitializerType<T>(Object? candidate) {
  late final bool value = candidate is T;
  return value;
}

String genericLocalEnvironment() => observe([
  genericLocal<int>(1, 2),
  genericLocal<String>('before', 'after'),
  genericLocal<int?>(3, null),
  genericInitializerType<int>(4),
  genericInitializerType<int>('wrong'),
  genericInitializerType<int?>(null),
]);

String genericWriteCheck<T>(T initial, dynamic bad) {
  late final T value;
  void write(dynamic next) => value = next;
  write(initial);
  try {
    write(bad);
  } on TypeError {
    tick(98);
  } on Error {
    tick(909);
  }
  return observe([value]);
}

String genericFinalWriteCheck() => genericWriteCheck<int>(99, 'wrong');

class LocalOwner<T> {
  T source;
  int offset;
  LocalOwner(this.source, this.offset);

  T Function() captureSource() {
    late T value = this.source;
    return () => value;
  }

  int Function() captureOffset(int seed) {
    late final int value = seed + this.offset + tick(100);
    seed = 2;
    return () => value;
  }

  bool Function<V>(Object?) captureType<U>() {
    late bool Function(Object?) value = (candidate) => candidate is T;
    bool check<V>(Object? candidate) =>
        value(candidate) && candidate is U && candidate is V;
    return check;
  }
}

String receiverAndGenericCaptures() {
  final owner = LocalOwner<int>(1, 2);
  final readSource = owner.captureSource();
  final readOffset = owner.captureOffset(8);
  owner.source = 3;
  owner.offset = 4;
  final source = readSource();
  final offset = readOffset();
  owner.source = 5;
  owner.offset = 6;
  final check = owner.captureType<num>();
  return observe([
    source,
    readSource(),
    offset,
    readOffset(),
    check<int>(7),
    check<String>('wrong'),
  ]);
}

int Function() Function() nestedFactory(int source) {
  late int value = source + tick(101);
  int Function() middle() {
    int inner() => value;
    return inner;
  }

  source = 2;
  return middle;
}

int nestedClosuresShareBinding() {
  final factory = nestedFactory(1);
  final first = factory();
  final second = factory();
  tick(102);
  return first() + second();
}

String lazyFunctionValue() {
  var source = 1;
  late int Function() value = () => source + tick(103);
  source = 2;
  final saved = value;
  source = 3;
  return observe([saved(), value(), identical(saved, value)]);
}

int functionReadBeforeArguments() {
  int Function(int) initialize() {
    tick(104);
    return (argument) => argument + tick(105);
  }

  late int Function(int) value = initialize();
  return value(tick(106));
}

int unboundFunctionReadBeforeArguments(bool bind) {
  late int Function(int) value;
  if (bind) value = (argument) => argument;
  int call() => value(tick(910));
  return call();
}

String mutualFunctionCalls() {
  late int Function(int) first;
  int second(int count) => count == 0 ? tick(107) : first(count - 1) + 1;
  first = (count) => count == 0 ? tick(108) : second(count - 1) + 1;
  late int result = first(4);
  return observe([result, result, second(3)]);
}

int Function() returnThenFinally() {
  var source = 1;
  late final int value = source + tick(109);
  try {
    return () => value;
  } finally {
    source = tick(110);
  }
}

int initializerReadsAfterReturnFinally() => returnThenFinally()();

int returnReadRunsBeforeFinally() {
  late int value = tick(111);
  try {
    return value;
  } finally {
    value = tick(112);
  }
}

int initializerFailureFinallyReturn() {
  int initialize() {
    try {
      throw 113;
    } finally {
      tick(114);
    }
  }

  late int value = initialize();
  try {
    return value;
  } on int catch (error) {
    tick(error);
    value = 115;
    return value;
  } finally {
    tick(value);
  }
}

bool nestedUnwindPreservesTrace() {
  Object? originalError;
  StackTrace? originalTrace;
  int initialize() {
    try {
      throw 116;
    } catch (error, trace) {
      originalError = error;
      originalTrace = trace;
      rethrow;
    } finally {
      tick(117);
    }
  }

  late int value = initialize();
  int read() {
    try {
      return value;
    } finally {
      tick(118);
    }
  }

  try {
    read();
  } catch (error, trace) {
    return identical(error, originalError) && identical(trace, originalTrace);
  } finally {
    tick(119);
  }
  return false;
}

String loopBodyClosures(bool skip) {
  final readers = <int Function()>[];
  for (var i = 0; i < 3; i++) {
    late int value = i + tick(120 + i);
    readers.add(() => value);
    if (skip) continue;
    tick(124 + i);
  }
  tick(127);
  return observe([
    readers[0](),
    readers[1](),
    readers[2](),
    readers[0](),
    readers[1](),
    readers[2](),
  ]);
}

String forInBodyClosures() {
  final readers = <int Function()>[];
  for (final i in [1, 2, 3]) {
    late final int value = i + tick(128 + i);
    readers.add(() => value);
    continue;
  }
  tick(132);
  return observe([readers[0](), readers[1](), readers[2]()]);
}

String outerLateSurvivesContinue() {
  late int value = tick(911);
  final readers = <int Function()>[];
  for (var i = 0; i < 3; i++) {
    value = tick(133 + i);
    late int copy = value + i;
    readers.add(() => copy);
    continue;
  }
  return observe([value, readers[0](), readers[1](), readers[2]()]);
}

Never neverValue() {
  tick(136);
  throw 137;
}

int unusedNeverInitializer() {
  late Never value = neverValue();
  return tick(138);
}

int throwingNeverInitializer() {
  late Never value = neverValue();
  try {
    value;
  } finally {
    tick(139);
  }
}

int throwingFinalNeverInitializer() {
  late final Never value = neverValue();
  return value;
}

Never unboundNeverRead() {
  late Never value;
  // A possible captured write keeps the read a runtime late check.
  // ignore: unused_element
  void write(Never next) => value = next;
  Never read() => value;
  return read();
}

int neverInitializerRetries() {
  late Never value = neverValue();
  for (var i = 0; i < 2; i++) {
    try {
      value;
    } on int catch (error) {
      tick(error);
    }
  }
  return 140;
}

String switchPatternInitializerClosure() {
  var source = (1, 2);
  late int Function() value = switch (source) {
    (var left, var right) => () => left + right + tick(141),
  };
  source = (3, 4);
  final saved = value;
  source = (5, 6);
  return observe([saved(), value(), identical(saved, value)]);
}

String collectionForInitializerClosures() {
  var source = 1;
  late List<int Function()> readers = [
    for (var i = 0; i < 3; i++) () => source + i + tick(142 + i),
    for (final j in [4, 5]) () => source + j + tick(145 + j),
  ];
  source = 10;
  final saved = readers;
  source = 20;
  return observe([
    saved[0](),
    saved[1](),
    saved[2](),
    saved[3](),
    saved[4](),
    identical(saved, readers),
  ]);
}

String initializerNestedClosureEnvironment() {
  var source = 1;
  late int Function() value = (() {
    var inside = source + tick(151);
    return () => ++inside + source;
  })();
  source = 2;
  final saved = value;
  source = 3;
  return observe([saved(), value(), saved(), identical(saved, value)]);
}

final int Function() globalLateReader = (() {
  var source = 1;
  late int value = source + tick(152);
  source = 2;
  return () => value;
})();

int lateInsideGlobalInitializer() {
  tick(153);
  return globalLateReader() + globalLateReader();
}

class InitializerContexts {
  int offset = 1;
  final int Function() eager = (() {
    var source = 3;
    late final int value = source + tick(154);
    source = 4;
    return () => value;
  })();
  late int Function() lazy = (() {
    late int value = offset + tick(155);
    return () => value;
  })();
  late final int Function() constructorReader;

  InitializerContexts() {
    late int value = offset + tick(156);
    constructorReader = () => value;
    offset = 5;
  }
}

String lateInsideFieldInitializers() {
  final owner = InitializerContexts();
  owner.offset = 6;
  final eager = owner.eager;
  final lazy = owner.lazy;
  tick(157);
  final first = lazy();
  owner.offset = 7;
  return observe([eager(), eager(), first, lazy()]);
}

String lateInsideConstructorBody() {
  final owner = InitializerContexts();
  owner.offset = 8;
  tick(158);
  final first = owner.constructorReader();
  owner.offset = 9;
  return observe([first, owner.constructorReader()]);
}

String joinedPatternInitializerClosure(bool first) {
  var source = (1, 0);
  late int Function() value = switch (source) {
    (var item, 0) || (0, var item) => () => item + tick(159),
    _ => () => -1,
  };
  source = first ? (3, 0) : (0, 4);
  final saved = value;
  source = (5, 6);
  return observe([saved(), value(), identical(saved, value)]);
}
