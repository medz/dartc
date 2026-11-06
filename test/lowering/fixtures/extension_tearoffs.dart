// ignore_for_file: unnecessary_this, prefer_function_declarations_over_variables
import 'effects.dart';

extension NumberMethods on int {
  int add([int value = 7]) => this + value;
  int named({int left = 3, required int right}) => this + left + right;
  int call(int value) => this + value;
  Never fail() => throw this;
  void discard() {
    tick(this);
  }

  void forward() => tick(this);
  int lexical() {
    final first = add;
    return first() + (() => add)()(2);
  }
}

extension NullableMethods on int? {
  int orDefault() => this ?? 42;
}

extension Twice on int Function([int]) {
  int twice() => this(2) + this(3);
}

int chainedTearOffs(int seed) {
  final twice = seed.add.twice;
  return twice();
}

int cleanupTearOff(int seed) {
  try {
    if (seed < 0) throw seed;
    if (seed > 0) return seed;
  } finally {
    final add = seed.add;
    tick(add(10));
  }
  return seed;
}

extension GenericMethods<T> on List<T> {
  T firstValue() => this[0];
  U choose<U extends T>(U value, {bool first = false}) =>
      first ? this[0] as U : value;
  bool kind<U extends T>() => null is U;
  bool recursive<U extends T>(Object? value, bool again) {
    if (!again) return value is U;
    final same = recursive;
    return same<U>(value, false);
  }
}

num extractedDefaults(int seed) {
  final add = seed.add;
  final named = NumberMethods(seed).named;
  dynamic dynamicAdd = add;
  dynamic dynamicNamed = named;
  return add() +
      add(2) +
      named(right: 4) +
      dynamicAdd() +
      dynamicNamed(right: 5, left: 6);
}

int capturedReceiver(int seed) {
  var value = seed;
  final add = value.add;
  value = seed + 100;
  return add() + value;
}

int extractedLexical(int seed) => seed.lexical();
int extractedCallMethod(int seed) {
  int Function(int) function = seed.call;
  return function(5);
}

int nullableTearOff(int? seed) {
  final function = NullableMethods(seed).orDefault;
  return function();
}

int nullAwareTearOff(int? seed) {
  final function = seed?.add;
  return function?.call(tick(2)) ?? 99;
}

int objectPatternTearOff(int seed) {
  final int(add: function) = seed;
  return function();
}

bool extractedIdentity(int seed) {
  final first = seed.add;
  final second = seed.add;
  return first == first && first != second;
}

bool genericIdentity() {
  final values = <num>[1];
  final first = values.choose;
  final second = values.choose;
  return (first<int>) == (first<int>) &&
      (first<int>) != (second<int>) &&
      (first<int>).hashCode == (first<int>).hashCode;
}

num genericTearOff() {
  final values = <num>[4];
  final choose = values.choose;
  final explicit = GenericMethods<num>(values).choose<int>;
  dynamic dynamicChoose = choose;
  return choose<int>(2) + explicit(3, first: true) + dynamicChoose<double>(1.5);
}

bool dependentDynamicDefault() {
  dynamic function = <num>[1].kind;
  return function();
}

bool recursiveBinderIdentity() => <num>[1].recursive<int>(1.5, true);

T Function() escapeReceiver<T>(T value) => <T>[value].firstValue;
int escapedTypeEnvironment(int seed) => escapeReceiver<int>(seed)();

int checkedExtraction(Object? value) {
  try {
    dynamic receiver = value;
    final add = NumberMethods(receiver).add;
    tick(1);
    return add(tick(2));
  } finally {
    tick(3);
  }
}

int extractionEffects(int seed) {
  final add = tick(seed).add;
  tick(10);
  return add(tick(20));
}

int extractedNever(int seed) {
  final fail = seed.fail;
  try {
    fail();
  } finally {
    tick(30);
  }
}

int extractedVoid(int seed) {
  final discard = seed.discard;
  discard();
  return 1;
}

final initializedTearOff = 3.add;
int globalTearOff() => initializedTearOff();

extension PairMethods on (int, int) {
  int sum() => this.$1 + this.$2;
}

extension FunctionMethods on int Function(int) {
  int apply(int value) => this(value);
}

extension ValueMethods<T> on T {
  T self() => this;
}

int nonClassReceivers(int seed) {
  final sum = (seed, 2).sum;
  int local(int value) => value + seed;
  final apply = local.apply;
  final self = ValueMethods<int>(seed).self;
  return sum() + apply(3) + self();
}

Object? extractedVoidResult(int seed) {
  dynamic function = seed.forward;
  return function();
}

bool patternReuse(int seed) {
  int Function([int])? previous;
  bool remember(int Function([int]) function) {
    previous = function;
    return false;
  }

  return switch (seed) {
    int(add: final function) when remember(function) => false,
    int(add: final function) => previous == function,
  };
}

typedef BottomCallback = void Function(Never);

extension DefaultTemplates<T> on List<T> {
  Type independent<U extends num>() => U;
  Type dependent<U extends T>() => U;
  Type covariantDefault<U extends List<T>>() => U;
  Type contravariantDefault<U extends void Function(T)>() => U;
  Type recursiveDefault<U extends Comparable<U>>() => U;
  Type recursiveContra<U extends void Function(U)>() => U;
  bool coupled<U extends num, V extends List<U>>() =>
      U == num && V == List<num>;
  Type dependentPair<U extends T, V extends U>() => V;
}

extension BoundedDefaults<T extends num> on List<T> {
  Type bounded<U extends T>() => U;
  Type boundedCovariant<U extends List<T>>() => U;
  Type boundedContra<U extends void Function(T)>() => U;
}

bool independentTearOffDefault() {
  dynamic function = <int>[1].independent;
  return function() == num;
}

bool coupledTearOffDefaults() {
  dynamic function = <int>[1].coupled;
  return function();
}

bool boundedTearOffDefault() {
  dynamic function = <int>[1].bounded;
  return function() == num;
}

bool boundedCovariantDefault() {
  dynamic function = <int>[1].boundedCovariant;
  return function() == List<num>;
}

bool boundedContravariantDefault() {
  dynamic function = <int>[1].boundedContra;
  return function() == BottomCallback;
}

bool covariantTearOffDefault() {
  dynamic function = <num>[1].covariantDefault;
  return function() == List<dynamic>;
}

bool contravariantTearOffDefault() {
  dynamic function = <num>[1].contravariantDefault;
  return function() == BottomCallback;
}

bool recursiveTearOffDefault() {
  dynamic function = <num>[1].recursiveDefault;
  return function() == Comparable<dynamic>;
}

bool recursiveContraTearOffDefault() {
  dynamic function = <num>[1].recursiveContra;
  return function() == BottomCallback;
}

bool dependentPairTearOffDefault() {
  dynamic function = <num>[1].dependentPair;
  return function() == dynamic;
}

bool explicitTearOffDefault() {
  dynamic function = DefaultTemplates<num>(<num>[1]).dependent;
  return function() == dynamic;
}

bool patternTearOffDefault() {
  final List<num>(dependent: function) = <num>[1];
  dynamic dynamicFunction = function;
  return dynamicFunction() == dynamic;
}

bool patternIndependentDefault() {
  final List<num>(independent: function) = <num>[1];
  dynamic dynamicFunction = function;
  return dynamicFunction() == num;
}

bool boundedSuccessfulDefault() {
  dynamic function = BoundedDefaults<num>(<int>[1]).bounded;
  return function() == num;
}
