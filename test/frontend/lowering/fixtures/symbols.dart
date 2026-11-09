// ignore_for_file: unnecessary_type_check, unnecessary_type_name_in_constructor, unnecessary_nullable_for_final_variable_declarations, unrelated_type_equality_checks

import 'effects.dart';
import 'symbols_public.dart' as other;

typedef SymbolName = Symbol;
typedef GenericSymbol<T> = Symbol;

class const SymbolBox<T>(final T value);

class const SymbolDefaults([
  final Symbol value = #alpha,
  final SymbolBox<Symbol> nested = const SymbolBox<Symbol>(#beta),
]);

class const UserSymbol(final String name) implements Symbol {
  @override
  bool operator ==(Object other) => other is UserSymbol && name == other.name;

  @override
  int get hashCode => name == 'alpha' ? 5 : 4;

  @override
  String toString() => 'user:$name';
}

class const AliasSymbol(final Symbol value) implements Symbol {
  @override
  bool operator ==(Object other) => other == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'alias:$value';
}

const alpha = #alpha;
const alphaConstructor = Symbol('alpha');
const symbolFactory = Symbol.new;
const aliasFactory = SymbolName.new;
const nestedSymbols = SymbolBox<List<Symbol>>(<Symbol>[
  #alpha,
  Symbol('beta'),
  Symbol.empty,
  Symbol.unaryMinus,
]);
const symbolRecord = (#alpha, named: <Symbol>[#beta, #foo._bar]);
const symbolMap = <Symbol, Symbol>{#alpha: #beta, #beta: #alpha};
const symbolSet = <Symbol>{#alpha, #beta};

String symbolLiterals() {
  const values = <Symbol>[
    #alpha,
    Symbol('alpha='),
    #foo.bar,
    #foo._bar,
    #+,
    #-,
    #*,
    #/,
    #~/,
    #%,
    #==,
    #<,
    #<=,
    #>,
    #>=,
    #<<,
    #>>,
    #>>>,
    #&,
    #|,
    #^,
    #~,
    #[],
    #[]=,
  ];
  var result = '';
  for (final value in values) {
    result = '$result$value|';
  }
  return result;
}

bool symbolConstants() =>
    alpha == alphaConstructor &&
    identical(alpha, alphaConstructor) &&
    identical(#alpha, const SymbolName('alpha')) &&
    identical(Symbol.empty, const Symbol('')) &&
    identical(Symbol.unaryMinus, const Symbol('unary-')) &&
    Symbol.unaryMinus != #- &&
    #foo._bar == const Symbol('foo._bar') &&
    #[] == const Symbol('[]') &&
    #[]= == const Symbol('[]=') &&
    #>>> == const Symbol('>>>') &&
    alpha.hashCode == alphaConstructor.hashCode;

String symbolStaticNames() => '${Symbol.empty}|${Symbol.unaryMinus}';

bool symbolNestedConstants() =>
    identical(nestedSymbols.value[0], alpha) &&
    identical(nestedSymbols.value[1], #beta) &&
    identical(nestedSymbols.value[2], Symbol.empty) &&
    identical(nestedSymbols.value[3], Symbol.unaryMinus) &&
    identical(symbolRecord.$1, alphaConstructor) &&
    identical(symbolRecord.named[1], const Symbol('foo._bar')) &&
    identical(symbolMap[#alpha], #beta) &&
    containsSymbol(symbolSet, const Symbol('alpha')) &&
    identical(
      const SymbolBox<Symbol>(#alpha),
      const SymbolBox<Symbol>(Symbol('alpha')),
    ) &&
    identical(const <Symbol>[#alpha], const <Symbol>[Symbol('alpha')]);

int optionalSymbols([
  Symbol first = #alpha,
  Symbol second = const Symbol('beta'),
  SymbolDefaults defaults = const SymbolDefaults(),
]) =>
    (first == #alpha ? 1 : 0) +
    (second == #beta ? 2 : 0) +
    (defaults.value == #alpha ? 4 : 0) +
    (defaults.nested.value == #beta ? 8 : 0);

int namedSymbols({
  Symbol value = Symbol.empty,
  SymbolBox<Symbol> box = const SymbolBox<Symbol>(Symbol.unaryMinus),
}) =>
    (identical(value, Symbol.empty) ? 16 : 0) +
    (identical(box.value, Symbol.unaryMinus) ? 32 : 0);

int symbolDefaultValues() =>
    optionalSymbols() +
    optionalSymbols(#beta, #alpha, const SymbolDefaults(#beta)) * 100 +
    namedSymbols();

int symbolRuntimeIdentity(String name) {
  final first = Symbol(name);
  final second = SymbolName(name);
  final Object erased = first;
  final Symbol? nullable = erased as Symbol;
  var result = 0;
  if (first == second) result += 1;
  if (!identical(first, second)) result += 2;
  if (!identical(first, alpha)) result += 4;
  if (identical(first, nullable)) result += 8;
  if (first.hashCode == second.hashCode) result += 16;
  if (erased is Symbol) result += 32;
  if (first != name) result += 64;
  if (first == alpha) result += 128;
  if (first == alpha && first.hashCode == alpha.hashCode) result += 256;
  if (first != #beta) result += 512;
  return result;
}

String symbolRuntimeText(String name) {
  final value = Symbol(name);
  return '$value|${value.toString()}';
}

String symbolBoundText(String name) {
  final value = Symbol(name);
  final render = value.toString;
  return render();
}

bool symbolConstructorTearoffs(String name) {
  final factory = Symbol.new;
  final first = factory(name);
  final second = symbolFactory(name);
  final third = aliasFactory(name);
  return first == second &&
      second == third &&
      !identical(first, second) &&
      !identical(second, third) &&
      factory == symbolFactory &&
      symbolFactory == aliasFactory &&
      first.hashCode == third.hashCode;
}

Symbol tracedSymbol(int marker, String name) {
  tick(marker);
  return Symbol(name);
}

bool symbolEvaluationOrder() =>
    tracedSymbol(1, 'alpha') == tracedSymbol(2, 'alpha') &&
    !identical(tracedSymbol(3, 'alpha'), tracedSymbol(4, 'alpha'));

String tracedName(int marker, String name) {
  tick(marker);
  return name;
}

String symbolConstructorOrder() {
  final factory = Symbol.new;
  final first = Symbol(tracedName(5, 'alpha'));
  final second = factory(tracedName(6, 'beta'));
  return '$first|$second';
}

int symbolChecks(Object? value) {
  var result = 0;
  if (value is Symbol) result += 1;
  if (value is Symbol?) result += 2;
  try {
    final cast = value as Symbol?;
    if (cast == null) result += 4;
  } on TypeError {
    result += 8;
  }
  return result;
}

int symbolTypeChecks() =>
    symbolChecks(#alpha) +
    symbolChecks(Symbol('alpha')) * 10 +
    symbolChecks(const UserSymbol('alpha')) * 100 +
    symbolChecks(null) * 1000 +
    symbolChecks(42) * 10000;

bool symbolGenericCollections() {
  final runtime = Symbol('alpha');
  final list = <Symbol>[#alpha, runtime, #beta, const UserSymbol('alpha')];
  final set = <Symbol>{#alpha, runtime, #beta};
  final map = <Symbol, int>{#alpha: 1, #beta: 2};
  map[runtime] = 3;
  final Object erasedList = list;
  final Object erasedSet = set;
  final Object erasedMap = map;
  final box = SymbolBox<Symbol>(runtime);
  return list.length == 4 &&
      containsSymbol(list, Symbol('alpha')) &&
      containsSymbol(list, const UserSymbol('alpha')) &&
      set.length == 2 &&
      containsSymbol(set, Symbol('beta')) &&
      map.length == 2 &&
      map[#alpha] == 3 &&
      map[Symbol('beta')] == 2 &&
      erasedList is List<Symbol> &&
      erasedList is! List<String> &&
      erasedSet is Set<Symbol> &&
      erasedMap is Map<Symbol, int> &&
      identical(box.value, runtime);
}

int symbolConstantPattern(String name) => switch (Symbol(name)) {
  #alpha => 1,
  const Symbol('beta') => 2,
  #foo._bar => 3,
  Symbol.empty => 4,
  Symbol.unaryMinus => 5,
  #[] => 6,
  _ => 7,
};

int symbolObjectPattern(int kind) {
  final Object? value = switch (kind) {
    0 => #alpha,
    1 => Symbol('alpha'),
    2 => const UserSymbol('alpha'),
    3 => null,
    _ => 42,
  };
  if (value case Symbol(hashCode: final hash)) {
    return hash == value.hashCode ? 1 : -1;
  }
  return 0;
}

bool symbolNestedPatterns() {
  final Object value = <Symbol>[Symbol('alpha'), Symbol('beta')];
  if (value case <Symbol>[#alpha, Symbol(hashCode: final hash)]) {
    return hash == (#beta).hashCode;
  }
  return false;
}

bool symbolUserEquality() {
  final Symbol first = UserSymbol('alpha');
  final Symbol second = UserSymbol('alpha');
  final Symbol other = UserSymbol('beta');
  final Object erased = first;
  final Object builtin = #alpha;
  return first == second &&
      erased == second &&
      first != other &&
      first != #alpha &&
      builtin != first &&
      first.hashCode == second.hashCode &&
      erased.hashCode == first.hashCode &&
      !identical(first, second);
}

String symbolUserText() {
  final Symbol value = UserSymbol('alpha');
  final Object erased = value;
  final render = value.toString;
  return '${value.toString()}|${render()}|$value|$erased';
}

bool symbolUserCollections() {
  final Symbol first = UserSymbol('alpha');
  final Symbol second = UserSymbol('alpha');
  final values = <Symbol>{first, second, #alpha};
  final map = <Symbol, int>{first: 1, #alpha: 2};
  map[second] = 3;
  return values.length == 2 &&
      containsSymbol(values, UserSymbol('alpha')) &&
      map.length == 2 &&
      map[first] == 3 &&
      map[#alpha] == 2;
}

bool symbolUserAsymmetry() {
  final Symbol custom = AliasSymbol(#alpha);
  final Symbol builtin = #alpha;
  final Object erasedCustom = custom;
  final Object erasedBuiltin = builtin;
  return custom == builtin &&
      erasedCustom == builtin &&
      builtin != custom &&
      erasedBuiltin != custom &&
      custom.hashCode == builtin.hashCode;
}

bool symbolUserConstants() {
  const value = UserSymbol('alpha');
  const box = SymbolBox<Symbol>(AliasSymbol(#alpha));
  final Symbol symbol = value;
  return value.name == 'alpha' &&
      value.hashCode == 5 &&
      identical(value, const UserSymbol('alpha')) &&
      symbol == const UserSymbol('alpha') &&
      symbol != #alpha &&
      box.value == #alpha &&
      #alpha != box.value &&
      box.value.hashCode == (#alpha).hashCode &&
      symbol.toString() == 'user:alpha';
}

int symbolRawNameEquality(String raw, String plain) {
  final first = Symbol(raw);
  final second = Symbol(plain);
  final set = <Symbol>{first, second};
  final map = <Symbol, int>{first: 1, second: 2};
  return (first == second ? 1 : 0) +
      (first.toString() == second.toString() ? 2 : 0) +
      (identical(first, second) ? 4 : 0) +
      (first.hashCode == second.hashCode ? 8 : 0) +
      set.length * 100 +
      map[Symbol(raw)]! * 1000 +
      map[Symbol(plain)]! * 10000;
}

bool containsSymbol(Iterable<Symbol> values, Symbol expected) {
  for (final value in values) {
    if (value == expected) return true;
  }
  return false;
}

bool symbolPublicLibraries() =>
    identical(#alpha, other.alpha) &&
    identical(const Symbol('alpha'), other.alpha) &&
    identical(#foo._bar, other.qualified) &&
    identical(Symbol.empty, other.empty) &&
    identical(Symbol.unaryMinus, other.unaryMinus) &&
    other.nested.$1[0] == #alpha &&
    identical(other.nested.named, #foo._bar);

bool symbolRuntimeStaticIdentity() {
  final empty = Symbol('');
  final minus = Symbol('unary-');
  return empty == Symbol.empty &&
      !identical(empty, Symbol.empty) &&
      minus == Symbol.unaryMinus &&
      !identical(minus, Symbol.unaryMinus) &&
      empty.hashCode == Symbol.empty.hashCode &&
      minus.hashCode == Symbol.unaryMinus.hashCode;
}

int symbolCheckedArgument(dynamic value, bool tearoff) {
  tick(1);
  try {
    final factory = Symbol.new;
    final symbol = tearoff ? factory(value) : Symbol(value);
    tick(2);
    return symbol == #alpha ? 1 : 0;
  } on TypeError {
    tick(3);
    return -1;
  }
}

String symbolArbitraryConstants() {
  const values = <Symbol>[
    Symbol('_private'),
    Symbol('_foo.bar'),
    Symbol('get:foo'),
    Symbol('abc@123'),
    Symbol('a b'),
    Symbol('"quoted"'),
    Symbol('line\nend'),
    Symbol('\u0000'),
    Symbol('Σ🌈'),
  ];
  var result = '';
  for (final value in values) {
    result = '$result$value|';
  }
  return result;
}

bool symbolPrivateNameConstructors() {
  const value = Symbol('_private');
  final runtime = Symbol('_private');
  const raw = Symbol('get:foo');
  return value == runtime &&
      identical(value, const Symbol('_private')) &&
      !identical(value, runtime) &&
      value.hashCode == runtime.hashCode &&
      raw != #foo &&
      raw.toString() == (#foo).toString() &&
      identical(raw, const Symbol('get:foo'));
}

int symbolGenericAlias(String name) {
  final first = GenericSymbol<int>.new;
  final second = GenericSymbol<String>.new;
  final generic = GenericSymbol.new;
  final applied = generic<int>;
  final a = first(name);
  final b = applied(name);
  final c = GenericSymbol<String>(name);
  var result = 0;
  if (a == b && b == c && c == generic<String>(name)) result += 1;
  if (!identical(a, b) && !identical(b, c)) result += 2;
  if (first == second) result += 4;
  if (identical(first, second)) result += 8;
  if (first == Symbol.new) result += 16;
  if (identical(first, Symbol.new)) result += 32;
  if (applied == first) result += 64;
  if (identical(applied, first)) result += 128;
  if (identical(const GenericSymbol<int>('alpha'), const Symbol('alpha'))) {
    result += 256;
  }
  return result;
}

class DirectHash() {
  int calls = 0;

  @override
  // This fixture checks virtual dispatch separately from direct super access.
  // ignore: hash_and_equals
  int get hashCode {
    calls++;
    tick(calls);
    if (calls > 1) throw 7;
    return super.hashCode + 1;
  }

  int baseHash() => super.hashCode;
}

class DirectSymbolHash() implements Symbol {
  int calls = 0;

  @override
  // This fixture checks virtual dispatch separately from direct super access.
  // ignore: hash_and_equals
  int get hashCode {
    calls++;
    tick(calls);
    if (calls > 1) throw 7;
    return super.hashCode + 1;
  }

  int baseHash() => super.hashCode;
}

int symbolOrdinarySuperHash() {
  final value = DirectHash();
  final Object erased = value;
  try {
    erased.hashCode;
    return value.calls;
  } on int catch (failure) {
    return failure;
  }
}

int symbolUserSuperHash(bool erase) {
  final value = DirectSymbolHash();
  final Symbol symbol = value;
  final Object object = value;
  try {
    if (erase) {
      object.hashCode;
    } else {
      symbol.hashCode;
    }
    return value.calls;
  } on int catch (failure) {
    return failure;
  }
}

bool symbolSuperHashStability() {
  final ordinary = DirectHash();
  final custom = DirectSymbolHash();
  final ordinaryBase = ordinary.baseHash();
  final customBase = custom.baseHash();
  return ordinaryBase == ordinary.baseHash() &&
      customBase == custom.baseHash() &&
      ordinary.hashCode == ordinaryBase + 1 &&
      custom.hashCode == customBase + 1 &&
      ordinaryBase == ordinary.baseHash() &&
      customBase == custom.baseHash() &&
      ordinary.calls == 1 &&
      custom.calls == 1;
}
