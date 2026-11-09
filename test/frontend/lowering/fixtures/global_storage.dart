// Each observation owns its slots: SDK library state is not reset between tests.
// ignore_for_file: unnecessary_null_comparison, dead_null_aware_expression, unnecessary_late
import 'effects.dart';

int untouched = tick(901);
int unusedInitializer() => tick(1);

int firstRead = tick(10);
int secondRead = tick(20);
String lazyReadOrder() =>
    observe([secondRead, firstRead, firstRead, secondRead]);

int? nullableDefault;
dynamic dynamicDefault;
String defaultNulls() => observe([nullableDefault, dynamicDefault]);

int? makeNull(int event) {
  tick(event);
  return null;
}

int? initializedNull = makeNull(11);
String nullableInitializerOnce() => observe([initializedNull, initializedNull]);

final int immutable = tick(12);
String finalInitializerOnce() => observe([immutable, immutable]);

int overwritten = tick(902);
int assignmentSkipsInitializer() {
  overwritten = tick(13);
  return overwritten;
}

int compound = tick(14);
String compoundUpdates() {
  final added = compound += tick(2);
  final before = compound++;
  final after = ++compound;
  return observe([added, before, after, compound]);
}

int? coalescingNull = makeNull(15);
int? coalescingValue = tick(16);
String coalescingUpdates() {
  final first = coalescingNull ??= tick(3);
  final second = coalescingNull ??= tick(903);
  final third = coalescingValue ??= tick(904);
  return observe([first, second, third]);
}

class GenericStorage<T>(final T value) {
  static int count = tick(17);
  static final int fixed = tick(18);
  static int unrelated() => tick(19);
  int read() => count;
  int update() => ++count;
}

String staticInitializationAndSharing() {
  final first = GenericStorage<int>(1);
  final second = GenericStorage<String>('x');
  final unrelated = GenericStorage.unrelated();
  tick(20);
  return observe([
    unrelated,
    first.read(),
    second.update(),
    first.read(),
    GenericStorage.fixed,
    GenericStorage.fixed,
  ]);
}

class OtherStorage() {
  static int count = tick(21);
}

class AnotherStorage() {
  static int count = tick(22);
}

String staticOwnerIdentity() {
  OtherStorage.count += tick(1);
  return observe([AnotherStorage.count, OtherStorage.count]);
}

int retryAttempts = 0;
final retryToken = <int>[7];
int retrying = retryInitializer();
int retryInitializer() {
  retryAttempts++;
  tick(30 + retryAttempts);
  if (retryAttempts < 3) throw retryToken;
  return tick(34);
}

String failedInitializerRetries() {
  for (var i = 0; i < 2; i++) {
    try {
      retrying;
    } catch (error) {
      if (!identical(error, retryToken)) return observe([-1]);
      tick(35 + i);
    } finally {
      tick(37 + i);
    }
  }
  return observe([retrying, retrying, retryAttempts]);
}

Object? originalError;
StackTrace? originalTrace;
final traceToken = <int>[8];
int tracedFailure = tracedInitializer();
int tracedInitializer() {
  try {
    throw traceToken;
  } catch (error, trace) {
    originalError = error;
    originalTrace = trace;
    tick(40);
    rethrow;
  } finally {
    tick(41);
  }
}

bool initializerPreservesThrowAndTrace() {
  try {
    tracedFailure;
  } catch (error, trace) {
    return identical(error, originalError) && identical(trace, originalTrace);
  } finally {
    tick(42);
  }
  return false;
}

int writtenBeforeThrow = writeThenThrow();
int writeThenThrow() {
  tick(43);
  writtenBeforeThrow = 30;
  throw 7;
}

String failedInitializerRetainsWrite() {
  try {
    writtenBeforeThrow;
  } on int catch (error) {
    tick(error);
  } finally {
    tick(44);
  }
  return observe([writtenBeforeThrow, writtenBeforeThrow]);
}

int writtenBeforeReturn = writeThenReturn();
int writeThenReturn() {
  writtenBeforeReturn = tick(10);
  return tick(11);
}

String successfulInitializerReplacesWrite() =>
    observe([writtenBeforeReturn, writtenBeforeReturn]);

int mutableDepth = 0;
int recursiveMutable = mutableRecursion();
int mutableRecursion() {
  final depth = ++mutableDepth;
  tick(50 + depth);
  if (depth == 2) return 5;
  return recursiveMutable + 1;
}

String finiteMutableRecursion() =>
    observe([recursiveMutable, recursiveMutable]);

int finalDepth = 0;
final int recursiveFinal = finalRecursion();
int finalRecursion() {
  final depth = ++finalDepth;
  try {
    tick(60 + depth);
    if (depth == 2) return 6;
    return recursiveFinal + 1;
  } finally {
    tick(63 + depth);
  }
}

String finiteFinalRecursion() {
  try {
    recursiveFinal;
  } on Error {
    tick(66);
  } finally {
    tick(67);
  }
  return observe([recursiveFinal, recursiveFinal, finalDepth]);
}

int lateFinalDepth = 0;
late final int recursiveLateFinal = lateFinalRecursion();
int lateFinalRecursion() {
  final depth = ++lateFinalDepth;
  try {
    tick(70 + depth);
    if (depth == 2) return 7;
    return recursiveLateFinal + 1;
  } finally {
    tick(73 + depth);
  }
}

String finiteLateFinalRecursion() {
  try {
    recursiveLateFinal;
  } on Error {
    tick(76);
  } finally {
    tick(77);
  }
  return observe([recursiveLateFinal, recursiveLateFinal, lateFinalDepth]);
}

late int lateInitialized = tick(80);
String lateInitializerOnce() => observe([lateInitialized, lateInitialized]);

late int lateOverwritten = tick(905);
int lateAssignmentSkipsInitializer() {
  lateOverwritten = tick(81);
  return lateOverwritten;
}

late int? lateNullable;
String lateNullableBinding() {
  try {
    lateNullable;
  } on Error {
    tick(82);
  }
  lateNullable = null;
  final first = lateNullable;
  lateNullable = tick(83);
  return observe([first, lateNullable]);
}

late int? unreadLate;
int? uninitializedLateRead() {
  try {
    return unreadLate;
  } finally {
    tick(84);
  }
}

late final int? finalNullable;
int? lateFinalNullBinding() {
  finalNullable = null;
  try {
    finalNullable = tick(85);
  } on Error {
    tick(86);
  } finally {
    tick(87);
  }
  return finalNullable;
}

late final int twiceBound;
int lateFinalSecondWrite() {
  twiceBound = tick(88);
  try {
    twiceBound = tick(89);
  } finally {
    tick(twiceBound);
  }
  return twiceBound;
}

late final int checkedFinal;
dynamic wrongValue() {
  tick(90);
  return 'wrong';
}

int lateFinalCastBeforeWriteCheck() {
  checkedFinal = 9;
  try {
    checkedFinal = wrongValue();
  } on TypeError {
    tick(91);
  } on Error {
    tick(906);
  }
  return checkedFinal;
}

late int? unboundCoalescing;
int? lateCoalescingReadsBeforeRhs() => unboundCoalescing ??= tick(907);

late final int lateConstant = tick(92);
String lateFinalInitializerOnce() => observe([lateConstant, lateConstant]);

final int Function(int) callback = createCallback();
int Function(int) createCallback() {
  tick(100);
  var count = 0;
  return (int value) => count += value;
}

String functionStorageAndCallOrder() {
  final first = callback(tick(101));
  final saved = callback;
  final second = saved(tick(102));
  return observe([first, second, identical(saved, callback), callback(1)]);
}

class StaticLate() {
  static late int? nullable;
  static late final int? bound;
  static late int initialized = tick(110);
  static late final int fixed = tick(111);
  static int? defaultValue;
}

String staticLateStorage() {
  try {
    StaticLate.nullable;
  } on Error {
    tick(112);
  }
  StaticLate.nullable = null;
  StaticLate.bound = null;
  try {
    StaticLate.bound = tick(113);
  } on Error {
    tick(114);
  }
  return observe([
    StaticLate.nullable,
    StaticLate.bound,
    StaticLate.initialized,
    StaticLate.initialized,
    StaticLate.fixed,
    StaticLate.fixed,
    StaticLate.defaultValue,
  ]);
}

enum EnumStorage() {
  one,
  two;

  static int mutable = tick(120);
  static final int fixed = tick(121);
  static late int? nullable;
  static late final int bound;
  static late int initialized = tick(122);
  static late final int lateFixed = tick(123);
  static int? defaultValue;
  int update() => ++mutable;
}

String enumStaticStorage() {
  tick(EnumStorage.two.index);
  final first = EnumStorage.one.update();
  EnumStorage.bound = tick(124);
  try {
    EnumStorage.nullable;
  } on Error {
    tick(125);
  }
  EnumStorage.nullable = null;
  try {
    EnumStorage.bound = tick(126);
  } on Error {
    tick(127);
  }
  return observe([
    first,
    EnumStorage.mutable,
    EnumStorage.fixed,
    EnumStorage.fixed,
    EnumStorage.nullable,
    EnumStorage.bound,
    EnumStorage.initialized,
    EnumStorage.initialized,
    EnumStorage.lateFixed,
    EnumStorage.lateFixed,
    EnumStorage.defaultValue,
  ]);
}

int isolated = tick(130);
int runnerIsolation() => ++isolated;

const globalConstant = 7;

class ConstantStorage() {
  static const value = 8;
}

int accessorState = 0;
int get explicitAccessor => tick(140) + accessorState;
set explicitAccessor(int value) {
  tick(141);
  accessorState = value;
}

String constantsAndExplicitAccessors() {
  explicitAccessor = tick(142);
  return observe([
    globalConstant,
    ConstantStorage.value,
    explicitAccessor,
    explicitAccessor,
  ]);
}

String observe(List<Object?> values) => '$values';

final int Function(int) directClosure = (() {
  tick(150);
  var captured = 0;
  return (int amount) => captured += amount;
})();

class GenericClosure<T>() {
  static final int Function(int) shared = (() {
    tick(151);
    var captured = 0;
    return (int amount) => captured += amount;
  })();
  int apply(int amount) => shared(amount);
}

String directInitializerClosures() {
  final first = directClosure(tick(152));
  final saved = directClosure;
  final integer = GenericClosure<int>();
  final string = GenericClosure<String>();
  return observe([
    first,
    saved(1),
    identical(saved, directClosure),
    directClosure(2),
    integer.apply(3),
    string.apply(4),
    integer.apply(5),
  ]);
}

int initializerCastAttempts = 0;
final int castInitialized = dynamicInitializer();
dynamic dynamicInitializer() {
  tick(170 + ++initializerCastAttempts);
  if (initializerCastAttempts == 1) return 'wrong';
  return 173;
}

String initializerCastRetries() {
  try {
    castInitialized;
  } on TypeError {
    tick(174);
  }
  return observe([castInitialized, castInitialized, initializerCastAttempts]);
}

int castWritten = castWritingInitializer();
dynamic castWritingInitializer() {
  tick(180);
  castWritten = 181;
  return 'wrong';
}

String initializerCastRetainsWrite() {
  try {
    castWritten;
  } on TypeError {
    tick(182);
  }
  return observe([castWritten, castWritten]);
}

late int? lateInitializedNull = makeNull(183);
late final int? finalInitializedNull = makeNull(184);
String lateNullableInitializersOnce() => observe([
  lateInitializedNull,
  lateInitializedNull,
  finalInitializedNull,
  finalInitializedNull,
]);

Never throwingNever = throw tick(185);
Never throwingNeverRead() => throwingNever;

late Never unboundNever;
Never unboundNeverRead() => unboundNever;
