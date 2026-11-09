// ignore_for_file: unnecessary_this, implicit_call_tearoffs, prefer_function_declarations_over_variables
import 'effects.dart';
import 'extension_types_interfaces_other.dart' as other;

extension type const Base<T>(int value) {
  int optional([int extra = 7]) => value + extra;
  int named({int extra = 9}) => value + extra;
  bool accepts(Object? input) => input is T;
  bool Function(Object?) capture() =>
      (input) => input is T;
  int get doubled => value * 2;
  set observed(T input) {
    tick(value);
  }

  bool operator [](Object? input) => input is T;
  void operator []=(int index, T input) {
    tick(index);
  }

  bool operator +(Object? input) => input is T;
  T call(T input) => input;
  U choose<U extends T>(U input) => input;
  Type defaults<U extends T>() => U;
}

extension type const Middle<A>(int value) implements Base<List<A>> {}

extension type const Leaf<B>(int value) implements Middle<B> {
  int own() => doubled + this.value;
  int Function() lexical() =>
      () => doubled;
}

extension type Other<T>(int value) {
  bool other(Object? input) => input is T;
}

extension type Combined<T>(int value) implements Base<T>, Other<List<T>> {}

extension type Override<T>(int value) implements Base<T> {
  bool accepts(Object? input) => input is List<T>;
}

extension type Diamond<T>(int value) implements Middle<T>, Base<List<T>> {}

abstract class Interface<T>() {
  T get item;
  set item(T value);
  T method(T value);
  T call(T value);
  T operator [](int index);
  void operator []=(int index, T value);
}

class Representation<T>(T initial) implements Interface<T> {
  @override
  T item = initial;
  @override
  T method(T value) => value;
  @override
  T call(T value) => value;
  @override
  T operator [](int index) => item;
  @override
  void operator []=(int index, T value) {
    item = value;
  }
}

class Specialized<T>(super.initial) extends Representation<T> {
  @override
  T method(T value) {
    tick(9);
    return value;
  }
}

extension type View<T>(Representation<T> value) implements Interface<T> {}

extension type ViewChild<U>(Specialized<U> value) implements View<U> {}

extension type ListView<T>(List<T> value) implements List<T> {}

extension type NonNull<T extends Object>(T value) implements Object {
  T get() => value;
}

bool inherited(int seed) {
  final leaf = Leaf<int>(seed);
  return leaf.accepts(<int>[1]) &&
      !leaf.accepts(<String>['a']) &&
      leaf.own() == seed * 3 &&
      leaf.lexical()() == seed * 2;
}

bool multiple() =>
    Combined<int>(1).accepts(2) &&
    Combined<int>(1).other(<int>[3]) &&
    Diamond<int>(1).accepts(<int>[2]);
bool overridden() =>
    Override<int>(1).accepts(<int>[2]) && !Override<int>(1).accepts(2);
bool methods() {
  final leaf = Leaf<int>(1);
  final accepts = leaf.accepts;
  final choose = leaf.choose;
  return accepts(<int>[1]) &&
      choose<List<int>>(<int>[2])[0] == 2 &&
      leaf.capture()(<int>[3]);
}

bool defaultMethod() {
  dynamic f = Leaf<int>(1).defaults;
  return f() == dynamic;
}

bool operators() {
  final value = Combined<int>(3);
  value.observed = tick(1);
  value[tick(2)] = tick(3);
  int Function(int) call = value;
  return value[4] && !(value + 'bad') && call(5) == 5;
}

int dispatched(int seed) {
  final value = ViewChild<int>(Specialized<int>(seed));
  final method = value.method;
  final call = value.call;
  value.item = tick(seed + 1);
  value[tick(2)] = tick(seed + 2);
  return value.method(seed) +
      method(seed + 3) +
      call(seed + 4) +
      value[0] +
      value.item;
}

int coreList(int seed) {
  final list = ListView<int>([seed]);
  list.add(2);
  list[0] = seed + 1;
  return list.length + list[0] + list[1];
}

bool objectMember() => NonNull<int>(3).runtimeType == int;
bool patterns() => switch (1) {
  Leaf<int>(accepts: final fn, doubled: 2) => fn(<int>[2]),
  _ => false,
};
int interfacePattern(int seed) =>
    switch (ViewChild<int>(Specialized<int>(seed))) {
      ViewChild<int>(item: final value, method: final f) => f(value),
    };

extension type MostSpecific<T>(int value) implements Override<T> {}

extension type Parent<T>(T raw) {
  T get() => raw;
  T Function() capture() =>
      () => raw;
}

extension type Child<U>(U data) implements Parent<U> {}

extension type Private<T>(int value) implements other.Foreign<T> {
  bool _hidden(Object? input) => input is List<T>;
}

bool mostSpecific() {
  final current = MostSpecific<int>(1);
  Base<int> parent = current;
  return current.accepts(<int>[2]) &&
      !current.accepts(2) &&
      parent.accepts(2) &&
      !parent.accepts(<int>[2]);
}

int inheritedRepresentation(int seed) {
  final value = Child<int>(seed);
  final get = value.get;
  return value.raw + value.get() + value.capture()() + get();
}

int inheritedNullable(int? seed) {
  final value = Child<int?>(seed);
  return (value.raw ?? 0) + (value.get() ?? 1) + (value.capture()() ?? 2);
}

int inheritedRecord(int seed) => Child<(int, int)>((seed, 2)).raw.$1;
int inheritedFunction(int seed) => Child<int Function()>(() => seed).get()();
bool privateLibrary() {
  final value = Private<int>(1);
  final reveal = value.reveal;
  return value.reveal(2) &&
      reveal(2) &&
      value.hide()(2) &&
      !value._hidden(2) &&
      value._hidden(<int>[2]);
}

bool inheritedPatternViews() {
  bool Function(Object?)? previous;
  bool remember(bool Function(Object?) function) {
    previous = function;
    return false;
  }

  return switch (1) {
    MostSpecific<int>(accepts: final function) when remember(function) => false,
    Base<int>(accepts: final function) => !previous!(2) && function(2),
  };
}

int covariantInterface(dynamic argument) {
  final concrete = Specialized<int>(1);
  View<num> widened = View<int>(concrete);
  return widened.method(argument) as int;
}

int covariantTearOff(dynamic argument) {
  final concrete = Specialized<int>(1);
  View<num> widened = View<int>(concrete);
  final method = widened.method;
  return method(argument) as int;
}

extension type StaticView<T>(Representation<T> value) implements Interface<T> {
  T method(T input) {
    tick(7);
    return input;
  }
}

int ordinaryView(int seed) {
  final view = StaticView<int>(Specialized<int>(seed));
  Interface<int> ordinary = view;
  final direct = view.method;
  final virtual = ordinary.method;
  return view.method(seed) +
      ordinary.method(seed) +
      direct(seed) +
      virtual(seed);
}

int boundMember<B extends NonNull<int>>(B value) => value.get();
int sourceBound(int seed) => boundMember(NonNull<int>(seed));

int inheritedDefaults() {
  final value = Leaf<int>(1);
  final optional = value.optional;
  final named = value.named;
  dynamic dynamicOptional = optional;
  return value.optional() +
      value.named() +
      optional() +
      named() +
      (dynamicOptional() as int);
}
