// ignore_for_file: unnecessary_late, use_primary_constructors, use_declaring_parameters, use_super_parameters, unnecessary_type_name_in_constructor, unnecessary_null_comparison, dead_null_aware_expression, overridden_fields, unnecessary_this, prefer_function_declarations_over_variables
import 'effects.dart';

String observe(List<Object?> values) => '$values';

int? makeNull(int event) {
  tick(event);
  return null;
}

class LazyFields {
  final int eager = tick(1);
  late int first = tick(2);
  late final int second = tick(3);
  LazyFields() {
    tick(4);
  }
}

int constructorDoesNotInitializeLate() => LazyFields().eager;

String lazyReadOrderAndInstanceIsolation() {
  final a = LazyFields();
  final b = LazyFields();
  return observe([a.second, a.first, a.first, b.first, b.second, a.second]);
}

class ConstructorRead {
  late int value = tick(5);
  ConstructorRead() {
    tick(6);
    tick(value);
    tick(7);
  }
}

int constructorBodyTriggersGetter() => ConstructorRead().value;

class ReadingBase {
  int get value => 0;
  ReadingBase() {
    tick(8);
    tick(value);
    tick(9);
  }
}

class ReadingChild extends ReadingBase {
  @override
  late int value = tick(10);
  ReadingChild() {
    tick(11);
  }
}

int superBodyTriggersOverriddenGetter() => ReadingChild().value;

class ConstructorBinding {
  late int value = tick(901);
  ConstructorBinding.formal(this.value) {
    tick(value);
  }
  ConstructorBinding.list(int seed) : value = seed {
    tick(value);
  }
}

String constructorBindingSkipsInitializer() => observe([
  ConstructorBinding.formal(tick(12)).value,
  ConstructorBinding.list(tick(13)).value,
]);

class FinalConstructorBinding {
  late final int value;
  FinalConstructorBinding(this.value);
}

int finalFieldFormalBindsOnce() {
  final box = FinalConstructorBinding(tick(14));
  try {
    box.value = tick(15);
  } on Error {
    tick(16);
  }
  return box.value;
}

class NullableFields {
  late int? mutable;
  late final int? fixed;
  late int? initialized = makeNull(17);
  late final int? initializedFinal = makeNull(18);
}

String nullableBoundAndUnbound() {
  final box = NullableFields();
  try {
    box.mutable;
  } on Error {
    tick(19);
  }
  box.mutable = null;
  final first = box.mutable;
  box.mutable = tick(20);
  return observe([
    first,
    box.mutable,
    box.initialized,
    box.initialized,
    box.initializedFinal,
    box.initializedFinal,
  ]);
}

int? finalNullCountsAsFirstWrite() {
  final box = NullableFields();
  box.fixed = null;
  try {
    box.fixed = tick(21);
  } on Error {
    tick(22);
  } finally {
    tick(23);
  }
  return box.fixed;
}

int? unboundNullableRead() {
  try {
    return NullableFields().mutable;
  } finally {
    tick(24);
  }
}

int? unboundCoalescingReadsBeforeRhs() =>
    NullableFields().mutable ??= tick(902);

class WritableFields {
  late int value = tick(903);
  late final int fixed;
}

int assignmentSkipsInitializer() {
  final box = WritableFields();
  box.value = tick(25);
  return box.value;
}

String compoundAndCoalescingUpdates() {
  final box = LazyFields();
  final added = box.first += tick(26);
  final before = box.first++;
  final after = ++box.first;
  final nullable = NullableFields();
  final nullWrite = nullable.initialized ??= tick(27);
  final skipped = nullable.initialized ??= tick(904);
  return observe([added, before, after, box.first, nullWrite, skipped]);
}

int finalSecondWriteEvaluatesRhs() {
  final box = WritableFields();
  box.fixed = tick(28);
  try {
    box.fixed = tick(29);
  } finally {
    tick(box.fixed);
  }
  return box.fixed;
}

dynamic wrongValue() {
  tick(30);
  return 'wrong';
}

int finalCastPrecedesBoundCheck() {
  final box = WritableFields();
  box.fixed = 31;
  try {
    box.fixed = wrongValue();
  } on TypeError {
    tick(32);
  } on Error {
    tick(905);
  }
  return box.fixed;
}

int failedFirstCastLeavesUnbound() {
  final box = WritableFields();
  try {
    box.fixed = wrongValue();
  } on TypeError {
    tick(33);
  }
  box.fixed = tick(34);
  return box.fixed;
}

class FieldBase {
  late int value = tick(35);
  late final int fixed = tick(36);
}

class AccessorOverride extends FieldBase {
  @override
  int get value => tick(37) + super.value;
  @override
  set value(int next) {
    tick(38);
    super.value = next;
  }

  @override
  int get fixed => tick(39) + super.fixed;
  int readParent() => super.value;
}

String explicitOverridesAndSuper() {
  final child = AccessorOverride();
  final FieldBase base = child;
  final first = base.value;
  base.value = tick(40);
  return observe([
    first,
    base.value,
    child.readParent(),
    base.fixed,
    base.fixed,
  ]);
}

class FieldOverride extends FieldBase {
  @override
  late int value = tick(41);
  int readParent() => super.value;
  int writeParent(int next) => super.value = next;
}

String overriddenFieldsKeepSeparateSlots() {
  final child = FieldOverride();
  final FieldBase base = child;
  final first = base.value;
  final parent = child.readParent();
  child.writeParent(tick(42));
  base.value = tick(43);
  return observe([first, parent, base.value, child.readParent()]);
}

class Retrying {
  int attempts = 0;
  final token = <int>[44];
  late int value = initialize();
  int initialize() {
    tick(44 + ++attempts);
    if (attempts < 3) throw token;
    return tick(48);
  }
}

String failedInitializerRetries() {
  final box = Retrying();
  for (var i = 0; i < 2; i++) {
    try {
      box.value;
    } catch (error) {
      if (!identical(error, box.token)) return 'wrong error';
      tick(49 + i);
    } finally {
      tick(51 + i);
    }
  }
  return observe([box.value, box.value, box.attempts]);
}

class TracedFailure {
  Object? error;
  StackTrace? trace;
  final token = <int>[53];
  late final int value = initialize();
  int initialize() {
    try {
      throw token;
    } catch (caught, stack) {
      error = caught;
      trace = stack;
      tick(54);
      rethrow;
    } finally {
      tick(55);
    }
  }
}

bool initializerPreservesThrowAndTrace() {
  final box = TracedFailure();
  try {
    box.value;
  } catch (error, trace) {
    return identical(error, box.error) && identical(trace, box.trace);
  } finally {
    tick(56);
  }
  return false;
}

class WritesDuringInitialization {
  late int throwing = writeThenThrow();
  late int returning = writeThenReturn();
  late int invalid = writeThenInvalid();
  int writeThenThrow() {
    throwing = tick(57);
    throw 58;
  }

  int writeThenReturn() {
    returning = tick(59);
    return tick(60);
  }

  dynamic writeThenInvalid() {
    invalid = tick(61);
    return 'wrong';
  }
}

String initializerFailureRetainsWrite() {
  final box = WritesDuringInitialization();
  try {
    box.throwing;
  } on int catch (error) {
    tick(error);
  } finally {
    tick(62);
  }
  return observe([box.throwing, box.throwing]);
}

String initializerReturnReplacesWrite() {
  final box = WritesDuringInitialization();
  return observe([box.returning, box.returning]);
}

String initializerCastFailureRetainsWrite() {
  final box = WritesDuringInitialization();
  try {
    box.invalid;
  } on TypeError {
    tick(63);
  }
  return observe([box.invalid, box.invalid]);
}

class CastRetry {
  int attempts = 0;
  late final int value = initialize();
  dynamic initialize() {
    tick(64 + ++attempts);
    if (attempts == 1) return 'wrong';
    return 67;
  }
}

String initializerCastFailureRetries() {
  final box = CastRetry();
  try {
    box.value;
  } on TypeError {
    tick(68);
  }
  return observe([box.value, box.value, box.attempts]);
}

class MutableRecursion {
  int depth = 0;
  late int value = initialize();
  int initialize() {
    final current = ++depth;
    try {
      tick(70 + current);
      if (current == 2) return 73;
      return value + 1;
    } finally {
      tick(74 + current);
    }
  }
}

String finiteMutableRecursion() {
  final box = MutableRecursion();
  return observe([box.value, box.value, box.depth]);
}

class FinalRecursion {
  int depth = 0;
  late final int value = initialize();
  int initialize() {
    final current = ++depth;
    try {
      tick(80 + current);
      if (current == 2) return 83;
      return value + 1;
    } finally {
      tick(84 + current);
    }
  }
}

String finiteFinalRecursion() {
  final box = FinalRecursion();
  try {
    box.value;
  } on Error {
    tick(87);
  } finally {
    tick(88);
  }
  return observe([box.value, box.value, box.depth]);
}

class GenericBase<T>(final T seed) {
  late T value = seed;
  T get inherited => value;
}

class GenericChild<A, B> extends GenericBase<B> {
  final A other;
  GenericChild(this.other, B seed) : super(seed);
  late final B fromThis = this.seed;
  late final B fromSuper = super.inherited;
  late final bool Function(Object?) checker = (() {
    tick(90);
    return (Object? candidate) => (() => candidate is B)();
  })();
  late final B Function(B) identity = (B value) => value;
}

String genericInitializerEnvironment() {
  final child = GenericChild<String, int>('a', 91);
  final other = GenericChild<int, String>(92, 'b');
  return observe([
    child.fromThis,
    child.fromSuper,
    child.checker(1),
    child.checker('x'),
    other.checker(1),
    other.checker('x'),
    child.identity(93),
    other.identity('c'),
    identical(child.checker, child.checker),
  ]);
}

class GenericCast<T>(final dynamic input) {
  late T value = input;
}

bool genericInitializerUsesActualType() {
  final GenericCast<num> box = GenericCast<int>(1.5);
  try {
    box.value;
  } on TypeError {
    tick(94);
    try {
      box.value;
    } on TypeError {
      tick(95);
      return true;
    }
  }
  return false;
}

class GenericMutable<T> {
  late T value;
}

bool mutableGenericCovariantWrite() {
  final GenericMutable<num> box = GenericMutable<int>();
  try {
    box.value = 1.5;
  } on TypeError {
    tick(96);
    box.value = 97;
    return box.value == 97;
  }
  return false;
}

class ExplicitCovariantFinal<T> {
  covariant late final T value;
}

bool explicitCovariantFinalWrite() {
  final ExplicitCovariantFinal<num> box = ExplicitCovariantFinal<int>();
  try {
    box.value = 1.5;
  } on TypeError {
    tick(98);
    box.value = 99;
    return box.value == 99;
  }
  return false;
}

abstract class CovariantContract {
  set value(covariant num next);
}

class InheritedCovariantFinal implements CovariantContract {
  @override
  late final int value;
}

int inheritedCovariantFinalWrite() {
  final CovariantContract box = InheritedCovariantFinal();
  try {
    box.value = 1.5;
  } on TypeError {
    tick(100);
  }
  box.value = 101;
  return (box as InheritedCovariantFinal).value;
}

class ImplicitCovariantFinal<T> {
  late final T value;
}

// Deliberately not an SDK comparison. Dart 3.13.7 currently omits the implicit
// by-class setter check here. The runner must preserve sound field storage.
// https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/fragment/field/declaration.dart#L914-L934
num implicitCovariantFinalKnownSdkDifference() {
  final ImplicitCovariantFinal<num> box = ImplicitCovariantFinal<int>();
  box.value = 1.5;
  return box.value;
}

class PrimaryFields(final int seed) {
  late int value = seed + this.seed;
}

int primaryDeclaringFieldInLateInitializer() => PrimaryFields(102).value;

class FunctionFields {
  late int Function(int) unbound;
  late final int Function(int) callback = (() {
    tick(103);
    var total = 0;
    return (int amount) => total += amount;
  })();
}

String functionReadBeforeArguments() {
  final box = FunctionFields();
  final first = box.callback(tick(104));
  final saved = box.callback;
  final second = saved(tick(105));
  return observe([
    first,
    second,
    identical(saved, box.callback),
    box.callback(1),
  ]);
}

int unboundFunctionReadBeforeArguments() => FunctionFields().unbound(tick(906));

class NeverFields {
  late Never unbound;
  late Never initialized = throw tick(106);
  late final Never fixed = throw tick(107);
}

Never unboundNeverGetter() => NeverFields().unbound;
Never throwingNeverInitializer() => NeverFields().initialized;
Never throwingFinalNeverInitializer() => NeverFields().fixed;

int neverInitializerRetries() {
  final box = NeverFields();
  for (var i = 0; i < 2; i++) {
    try {
      box.fixed;
    } on int catch (error) {
      tick(error);
    } finally {
      tick(108 + i);
    }
  }
  return 2;
}

class MultipleConstructors<T> {
  final T seed;
  MultipleConstructors(this.seed) {
    tick(114);
  }
  MultipleConstructors.named(this.seed) {
    tick(115);
  }
  late final T Function() callback = (() {
    tick(116);
    return () => this.seed;
  })();
}

String multipleConstructorsShareInitializerBody() {
  final first = MultipleConstructors<int>(117);
  final second = MultipleConstructors<String>.named('second');
  return observe([
    first.callback(),
    second.callback(),
    first.callback(),
    identical(first.callback, first.callback),
  ]);
}

class FinalRecursiveCast {
  int depth = 0;
  late final int value = initialize();
  dynamic initialize() {
    tick(118 + ++depth);
    if (depth == 2) return 121;
    value;
    return 'wrong';
  }
}

int recursiveFinalCastPrecedesBoundCheck() {
  final box = FinalRecursiveCast();
  try {
    box.value;
  } on TypeError {
    tick(122);
  } on Error {
    tick(907);
  }
  return box.value;
}

int implicitCovariantFinalFailedWriteLeavesUnbound() {
  final ImplicitCovariantFinal<num> box = ImplicitCovariantFinal<int>();
  try {
    box.value = 1.5;
  } on TypeError {
    box.value = 125;
    return box.value as int;
  }
  return -1;
}

num genericMutableCollectionWrite() {
  final GenericMutable<List<num>> box = GenericMutable<List<int>>();
  try {
    box.value = <num>[1.5];
  } on TypeError {
    tick(126);
  }
  box.value = <int>[127];
  return box.value[0];
}

int genericMutableFunctionWrite() {
  final GenericMutable<Function> box = GenericMutable<int Function(int)>();
  try {
    box.value = (String value) => value;
  } on TypeError {
    tick(128);
  }
  box.value = (int value) => value + 1;
  return (box.value as int Function(int))(129);
}

int? genericMutableNullableWrite() {
  final GenericMutable<num?> box = GenericMutable<int?>();
  box.value = null;
  try {
    box.value = 1.5;
  } on TypeError {
    tick(130);
  }
  return box.value as int?;
}
