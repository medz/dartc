// ignore_for_file: unnecessary_null_in_if_null_operators, unnecessary_type_check, unnecessary_type_name_in_constructor, dead_code
T identity<T>(T value) => value;
bool phantom<T>(Object candidate) => candidate is T;

const generic = identity;
const concrete = identity<int>;
const throughAlias = generic<int>;
const selected = true ? phantom<int> : phantom<String>;
const fallback = (null ?? phantom<String>);
const bundle = (identity<int>, named: phantom<String>);
const constructor = Container.new;
const concreteConstructor = Container<int>.new;
const stringConstructor = Container<String>.new;

class Container<T>(final T value);

int defaults(int value, [int Function(int) function = identity<int>]) =>
    function(value);
int recordDefaults(
  int value, [
  (int Function(int), {bool Function(Object) named}) functions = (
    identity<int>,
    named: phantom<String>,
  ),
]) => functions.$1(value) + (functions.named('yes') ? 10 : 0);

int genericConstantCalls(int value) =>
    concrete(value) +
    throughAlias(value + 1) +
    generic<int>(value + 2) +
    defaults(value + 3) +
    recordDefaults(value + 4);

bool genericConstantChecks(Object value) =>
    selected(value) != fallback(value) &&
    bundle.named(value) == fallback(value);

int genericConstantConstructors(int value) =>
    constructor<int>(value).value + concreteConstructor(value + 1).value;

int genericConstantPattern(bool chooseInt) {
  final Object function = chooseInt ? phantom<int> : phantom<String>;
  return switch (function) {
    selected => 1,
    fallback => 2,
    _ => 3,
  };
}

bool genericConstantIdentity() =>
    concrete == throughAlias &&
    selected == (phantom<int>) &&
    selected != (phantom<String>) &&
    fallback == (phantom<String>) &&
    bundle.$1 == concrete;

int genericConstructorPattern(bool chooseInt) {
  final Object function = chooseInt
      ? Container<int>.new
      : Container<String>.new;
  return switch (function) {
    concreteConstructor => 1,
    stringConstructor => 2,
    _ => 3,
  };
}

class Pair<A, B>(final A first, final B second);
typedef Flip<A, B> = Pair<B, A>;
typedef OtherFlip<A, B> = Pair<B, A>;
typedef Fixed<T> = Pair<int, T>;
typedef Phantom<A, B> = Pair<A, A>;
const rawFlip = Flip.new;
const appliedFlip = rawFlip<int, String>;
const appliedOther = (OtherFlip.new)<int, String>;
const selectedAlias = true ? appliedFlip : appliedOther;
const aliasBundle = (appliedFlip, generic: rawFlip);
const nestedAliasBundle = (aliasBundle,);
const rawFixed = Fixed.new;
const appliedFixed = rawFixed<String>;
const rawPhantom = Phantom.new;
const phantomString = rawPhantom<int, String>;
const phantomBool = rawPhantom<int, bool>;
int _aliasDefault(
  int value, [
  Pair<String, int> Function(String, int) make = appliedFlip,
]) => make('x', value).second;

int genericAliasConstants(int value) =>
    appliedFlip('x', value).second +
    selectedAlias('x', value).second +
    aliasBundle.generic<int, String>('x', value).second +
    nestedAliasBundle.$1.$1('x', value).second +
    appliedFixed(value, 'x').first +
    _aliasDefault(value);

bool genericAliasConstantIdentity() =>
    appliedFlip == selectedAlias &&
    appliedFlip != appliedOther &&
    appliedFlip != Pair<String, int>.new &&
    phantomString != phantomBool &&
    phantomString != Pair<int, int>.new;

int genericAliasConstantPattern(bool first) {
  final Object function = first ? appliedFlip : appliedOther;
  return switch (function) {
    appliedFlip => 1,
    appliedOther => 2,
    _ => 3,
  };
}

int genericInlineAliasPattern(bool first) {
  final Object function = first ? appliedFlip : appliedOther;
  return switch (function) {
    const (rawFlip<int, String>) => 1,
    const ((OtherFlip.new)<int, String>) => 2,
    _ => 3,
  };
}
