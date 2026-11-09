// ignore_for_file: unnecessary_this, prefer_function_declarations_over_variables, avoid_shadowing_type_parameters
import 'effects.dart';

typedef ContraDefault = void Function(Never);
typedef AppliedDefault<T> = void Function(T);

extension Arithmetic on int {
  int? optional() => null;
  int plus(int value, [int extra = 3]) => this + value + extra;
  int named({int left = 4, required int right}) => this + left + right;
  int lexical(int value) => plus(value) + (() => plus(value, 1))();
  int Function() capture() =>
      () => this;
  int lateCapture() {
    late final value = this + 1;
    return (() => (() => value)())();
  }

  static int shared = tick(20);
  static int same() => shared;
  static bool recursiveDefault<V extends Comparable<V>>() =>
      V == Comparable<dynamic>;
  static bool contraDefault<V extends void Function(V)>() => V == ContraDefault;

  // Declarations already use the flattened ABI; access remains a later phase.
  int get laterGetter => this;
  set laterSetter(int value) {}
  int operator -() => -this;
}

extension Alternate on int {
  int plus(int value, [int extra = 30]) => this - value - extra;
  static int shared = tick(30);
  static int same() => shared;
}

extension NullableNumber on int? {
  int orZero() => this ?? 0;
  int Function() captureNullable() =>
      () => this ?? 0;
}

extension Pair on (int, int) {
  int sum() => this.$1 + this.$2;
  int Function() capturePair() =>
      () => this.$1 - this.$2;
}

extension Callable on int Function(int) {
  int apply(int value) => this(value);
  int Function(int) captureCallable() =>
      (value) => this(value) + 1;
}

extension Universal<T> on T {
  int recordType() => tick(null is T ? 1 : 2);
  T self() => this;
  T Function() captureSelf() =>
      () => this;
}

extension TypedList<T> on List<T> {
  bool accepts(Object? value) => value is T;
  bool kind<U extends T>() => U == T;
  bool contraKind<V extends void Function(T)>() => V == AppliedDefault<T>;
  U choose<U extends T>(U value, {bool first = false}) =>
      first ? this[0] as U : value;
  bool Function(Object?) captureType() =>
      (value) => accepts(value);
  bool Function(Object?) shadow<T>() =>
      (value) => value is T;
  bool Function<U extends T>(Object?) captureDefault() =>
      <U extends T>(Object? value) => value is U;
  bool Function<U>(Object?, Object?) captureBoth() {
    bool check<U>(Object? outer, Object? inner) => accepts(outer) && inner is U;
    return check;
  }
}

extension Phantom<T extends num> on int {
  bool phantom(Object? value) => value is T;
}

int directExtension(int seed) =>
    Arithmetic(seed).plus(2) +
    Arithmetic(seed).plus(3, 4) +
    Alternate(seed).plus(5);

int implicitExtension(int seed) =>
    seed.named(right: 2) + seed.named(right: 3, left: 5) + seed.lexical(2);

int nullableExtension(int? seed) => seed.orZero() + seed.captureNullable()();
int nullAwareExtension(int? seed) => seed?.named(right: tick(9)) ?? 17;
int explicitNullAwareExtension(int? seed) =>
    NullableNumber(seed)?.orZero() ?? 19;
int recordExtension(int seed) => (seed, 3).sum() + (seed, 3).capturePair()();
int functionExtension(int seed) {
  int function(int value) => value + seed;
  return function.apply(4) + function.captureCallable()(5);
}

T _genericReceiver<T>(T value) => value.self().captureSelf()();
int typeVariableExtension(int seed) => _genericReceiver(seed);
int capturedExtension(int seed) => seed.capture()() + seed.lateCapture();

bool staticViewExtension(Object? value) {
  final List<int> ints = [1];
  final List<num> numbers = ints;
  return ints.accepts(value) == (value is int) &&
      numbers.accepts(value) == (value is num);
}

bool phantomExtension(Object? value) =>
    1.phantom(value) == (value is num) &&
    Phantom<int>(1).phantom(value) == (value is int);

int genericExtension(int seed) {
  final list = [seed];
  return list.choose<int>(seed + 1) + list.choose(seed, first: true);
}

bool escapedExtension(Object? value) {
  final ints = <int>[1].captureType();
  final strings = <String>['x'].captureType();
  final both = <int>[1].captureBoth();
  return ints(value) == (value is int) &&
      strings(value) == (value is String) &&
      both<String>(value, 'x') == (value is int);
}

int staticExtension() => Arithmetic.same() + Alternate.same();

int explicitReceiverCheck(Object? value) {
  dynamic receiver = value;
  return Arithmetic(receiver).plus(tick(7));
}

int receiverOrder(int seed) => Arithmetic(tick(seed)).plus(tick(2), tick(3));

int cascadeExtension(int seed) {
  final value = seed
    ..named(right: tick(1))
    ..capture();
  return value;
}

bool extensionClosureDefaults(Object? value) {
  dynamic ints = <int>[1].captureDefault();
  dynamic numbers = <num>[1].captureDefault();
  final shadow = <int>[1].shadow<String>();
  return ints(value) == (value is int) &&
      numbers(value) == (value is num) &&
      shadow(value) == (value is String);
}

bool extensionDependentDefaults() =>
    <int>[1].kind() && <num>[1].kind() && <int>[1].contraKind();

bool extensionStaticRecursiveDefault() {
  dynamic function = Arithmetic.recursiveDefault;
  return function();
}

bool extensionStaticContraDefault() {
  dynamic function = Arithmetic.contraDefault;
  return function();
}

bool nullableGeneric(bool absent, Object? value) {
  final List<int>? list = absent ? null : [1];
  final bool? accepted = list?.accepts(value);
  final cascaded = list?..accepts(value);
  return absent
      ? accepted == null && cascaded == null
      : accepted == (value is int) && cascaded != null;
}

int? nestedCascadeExtension(int? seed) {
  // ignore: avoid_single_cascade_in_expression_statements
  seed?..optional().recordType();
  return seed;
}

int overrideArgumentBoundary(int? seed) =>
    NullableNumber(seed?.named(right: tick(8))).orZero() + tick(3);

class LexicalHost<T>() {
  bool matches(Object? value) => lexicalAccepts(value);
  bool Function(Object?) capture() =>
      (value) => lexicalAccepts(value);
}

class LexicalChild() extends LexicalHost<num>;

extension LexicalMethods<T> on LexicalHost<T> {
  bool lexicalAccepts(Object? value) => value is T;
}

bool classLexicalExtension(Object? value) =>
    LexicalHost<int>().matches(value) == (value is int) &&
    LexicalHost<String>().capture()(value) == (value is String) &&
    LexicalChild().matches(value) == (value is num) &&
    LexicalChild().capture()(value) == (value is num);

enum const LexicalEnum<T>() {
  number<int>(),
  text<String>();

  bool matches(Object? value) => enumAccepts(value);
  bool Function(Object?) capture() =>
      (value) => enumAccepts(value);
}

extension LexicalEnumMethods<T> on LexicalEnum<T> {
  bool enumAccepts(Object? value) => value is T;
}

bool enumLexicalExtension(Object? value) =>
    LexicalEnum.number.matches(value) == (value is int) &&
    LexicalEnum.text.capture()(value) == (value is String);

int? explicitDynamicNullAware(Object? value) {
  dynamic receiver = value;
  return Arithmetic(receiver)?.plus(tick(7));
}
