// ignore_for_file: unnecessary_type_check, unrelated_type_equality_checks, use_primary_constructors, unnecessary_type_name_in_constructor, prefer_is_empty

import 'effects.dart';

typedef InvocationAlias = Invocation;
typedef NullableObject = Object?;
typedef InvocationRecord = (int, {String name});
typedef InvocationFunction = T Function<T>(T);

const methodFactory = Invocation.method;
const genericFactory = Invocation.genericMethod;
const getterFactory = Invocation.getter;
const setterFactory = Invocation.setter;

class const InvocationSymbol(final String name) implements Symbol;

Invocation makeInvocation(int kind, bool tearoff, bool nullArguments) {
  final Symbol name = kind == 3 ? const Symbol('value=') : #value;
  final types = nullArguments ? null : <Type>[int, List<String>];
  final positional = nullArguments ? null : <Object?>[7, null, 'tail'];
  final named = nullArguments
      ? null
      : <Symbol, Object?>{#zeta: 9, #alpha: null};
  return switch (kind) {
    0 =>
      tearoff
          ? methodFactory(name, positional, named)
          : Invocation.method(name, positional, named),
    1 =>
      tearoff
          ? genericFactory(name, types, positional, named)
          : Invocation.genericMethod(name, types, positional, named),
    2 => tearoff ? getterFactory(name) : Invocation.getter(name),
    _ =>
      tearoff
          ? setterFactory(name, nullArguments ? null : 23)
          : Invocation.setter(name, nullArguments ? null : 23),
  };
}

String invocationFactories(int kind, bool tearoff, bool nullArguments) {
  final value = makeInvocation(kind, tearoff, nullArguments);
  final name = kind == 3 ? const Symbol('value=') : #value;
  var result =
      '${value.memberName == name}:'
      '${value.isMethod}/${value.isGetter}/${value.isSetter}/${value.isAccessor}:'
      '${value.typeArguments.length}/${value.positionalArguments.length}/'
      '${value.namedArguments.length}';
  for (final type in value.typeArguments) {
    result = '$result:${type == int}/${type == List<String>}';
  }
  for (final argument in value.positionalArguments) {
    result = '$result:$argument';
  }
  for (final entry in value.namedArguments.entries) {
    result = '$result:${entry.key}:${entry.value}';
  }
  return result;
}

bool invocationTearoffIdentity() =>
    identical(methodFactory, Invocation.method) &&
    identical(genericFactory, Invocation.genericMethod) &&
    identical(getterFactory, Invocation.getter) &&
    identical(setterFactory, Invocation.setter) &&
    identical(InvocationAlias.method, Invocation.method) &&
    methodFactory != genericFactory &&
    getterFactory != setterFactory;

bool invocationDefaults(bool generic, bool tearoff, bool explicitNull) {
  final Invocation value;
  if (generic) {
    value = tearoff
        ? (explicitNull
              ? genericFactory(#method, null, null, null)
              : genericFactory(#method, null, null))
        : (explicitNull
              ? Invocation.genericMethod(#method, null, null, null)
              : Invocation.genericMethod(#method, null, null));
  } else {
    value = tearoff
        ? (explicitNull
              ? methodFactory(#method, null, null)
              : methodFactory(#method, null))
        : (explicitNull
              ? Invocation.method(#method, null, null)
              : Invocation.method(#method, null));
  }
  return value.memberName == #method &&
      value.isMethod &&
      !value.isGetter &&
      !value.isSetter &&
      !value.isAccessor &&
      value.typeArguments.length == 0 &&
      value.positionalArguments.length == 0 &&
      value.namedArguments.length == 0;
}

bool invocationSymbolIdentity(int kind, bool custom) {
  final Symbol name = custom
      ? InvocationSymbol('custom')
      : Symbol('any symbol, including without equals');
  final value = switch (kind) {
    0 => Invocation.method(name, null),
    1 => Invocation.genericMethod(name, null, null),
    2 => Invocation.getter(name),
    _ => Invocation.setter(name, null),
  };
  return identical(value.memberName, name) &&
      identical(value.memberName, value.memberName) &&
      (value.memberName is InvocationSymbol) == custom;
}

String invocationNamedOrder(bool generic) {
  final named = <Symbol, Object?>{#zeta: 1, #alpha: 2, #middle: 3};
  named[#alpha] = 8;
  final value = generic
      ? Invocation.genericMethod(#f, null, null, named)
      : Invocation.method(#f, null, named);
  named[#zeta] = 9;
  named[#later] = 4;
  var result = '';
  for (final entry in value.namedArguments.entries) {
    result = '$result${entry.key}:${entry.value}|';
  }
  return result;
}

bool invocationSnapshots() {
  final types = <Type>[int, List<String>];
  final child = <int>[5];
  final positional = <Object?>[child, null];
  final named = <Symbol, Object?>{#child: child, #empty: null};
  final value = Invocation.genericMethod(#f, types, positional, named);
  final method = Invocation.method(#f, positional, named);
  final setter = Invocation.setter(#f, child);
  types[0] = String;
  types.add(bool);
  positional[0] = 7;
  positional.add(8);
  named[#child] = 9;
  named[#later] = 10;
  child.add(6);
  return value.typeArguments.length == 2 &&
      value.typeArguments[0] == int &&
      (value.typeArguments[1] == List<String>) &&
      value.positionalArguments.length == 2 &&
      identical(value.positionalArguments[0], child) &&
      identical(value.positionalArguments[1], null) &&
      value.namedArguments.length == 2 &&
      identical(value.namedArguments[#child], child) &&
      identical(value.namedArguments[#empty], null) &&
      identical(method.positionalArguments[0], child) &&
      identical(method.namedArguments[#child], child) &&
      identical(setter.positionalArguments[0], child) &&
      (value.positionalArguments[0] as List<int>)[1] == 6 &&
      !identical(value.typeArguments, types) &&
      !identical(value.positionalArguments, positional) &&
      !identical(value.namedArguments, named);
}

bool invocationEmptySnapshots() {
  final types = <Type>[];
  final positional = <Object?>[];
  final named = <Symbol, Object?>{};
  final value = Invocation.genericMethod(#f, types, positional, named);
  types.add(int);
  positional.add(1);
  named[#x] = 2;
  return value.typeArguments.length == 0 &&
      value.positionalArguments.length == 0 &&
      value.namedArguments.length == 0;
}

// The public API promises unmodifiable arguments. The exact canonical empty
// objects, runtime collection types, and fresh-copy identities below pin the
// SDK used for differential testing; they are not language-wide guarantees.
String invocationCollectionIdentity(int kind, int inputKind) {
  final Iterable<Type>? types = switch (inputKind) {
    0 => null,
    1 => const <Type>[],
    2 => <Type>[],
    3 => const <Type>[int],
    _ => Invocation.genericMethod(#source, <Type>[int], null).typeArguments,
  };
  final Iterable<Object?>? positional = switch (inputKind) {
    0 => null,
    1 => const <Object?>[],
    2 => <Object?>[],
    3 => const <Object?>[1],
    _ => Invocation.method(#source, <Object?>[1]).positionalArguments,
  };
  final Map<Symbol, Object?>? named = switch (inputKind) {
    0 => null,
    1 => const <Symbol, Object?>{},
    2 => <Symbol, Object?>{},
    3 => const <Symbol, Object?>{#x: 1},
    _ => Invocation.method(#source, null, <Symbol, Object?>{
      #x: 1,
    }).namedArguments,
  };
  Invocation create() => switch (kind) {
    0 => Invocation.method(#f, positional, named),
    1 => Invocation.genericMethod(#f, types, positional, named),
    2 => Invocation.getter(#f),
    _ => Invocation.setter(#f, 1),
  };
  final first = create();
  final second = create();
  return '${identical(first.typeArguments, types)}/'
      '${identical(first.positionalArguments, positional)}/'
      '${identical(first.namedArguments, named)}:'
      '${identical(first.typeArguments, second.typeArguments)}/'
      '${identical(first.positionalArguments, second.positionalArguments)}/'
      '${identical(first.namedArguments, second.namedArguments)}:'
      '${identical(first.typeArguments, const <Type>[])}/'
      '${identical(first.positionalArguments, const <Object?>[])}/'
      '${identical(first.positionalArguments, const <Object>[])}/'
      '${identical(first.positionalArguments, const <dynamic>[])}/'
      '${identical(first.namedArguments, const <Symbol, Object?>{})}/'
      '${identical(first.namedArguments, const <Symbol, Object>{})}/'
      '${identical(first.namedArguments, const <Symbol, dynamic>{})}:'
      '${identical(first.typeArguments, first.typeArguments)}/'
      '${identical(first.positionalArguments, first.positionalArguments)}/'
      '${identical(first.namedArguments, first.namedArguments)}';
}

String invocationCollectionTypes(int kind, bool empty) {
  final value = makeInvocation(kind, false, empty);
  final Object types = value.typeArguments;
  final Object positional = value.positionalArguments;
  final Object named = value.namedArguments;
  return '${types is List<Type>}/${types is List<Object>}/'
      '${types is List<String>}:'
      '${positional is List<Object?>}/${positional is List<Object>}/'
      '${positional is List<int>}:'
      '${named is Map<Symbol, Object?>}/${named is Map<Symbol, Object>}/'
      '${named is Map<Symbol, int>}';
}

void invocationMutation(int kind, int target, bool empty) {
  final value = makeInvocation(kind, false, empty);
  tick(1);
  switch (target) {
    case 0:
      value.typeArguments.add(String);
    case 1:
      value.typeArguments[0] = String;
    case 2:
      value.positionalArguments.add(99);
    case 3:
      value.positionalArguments[0] = 99;
    case 4:
      value.namedArguments[#newName] = 99;
  }
  tick(2);
}

bool invocationTypeArguments<T>() {
  final types = <Type>[
    T,
    List<T>,
    InvocationRecord,
    InvocationFunction,
    dynamic,
    NullableObject,
    Never,
  ];
  final value = Invocation.genericMethod(#f, types, null);
  return value.typeArguments.length == 7 &&
      value.typeArguments[0] == T &&
      (value.typeArguments[1] == List<T>) &&
      value.typeArguments[2] == InvocationRecord &&
      value.typeArguments[3] == InvocationFunction &&
      value.typeArguments[4] == dynamic &&
      value.typeArguments[5] == NullableObject &&
      value.typeArguments[6] == Never &&
      value.typeArguments[4] != value.typeArguments[5] &&
      identical(value.typeArguments[0], T);
}

bool invocationReifiedTypes() =>
    invocationTypeArguments<int>() && invocationTypeArguments<String>();

class CustomInvocation() implements Invocation {
  final symbol = InvocationSymbol('custom');
  final types = <Type>[String];
  final positional = <Object?>[42];
  final named = <Symbol, Object?>{#custom: 7};

  @override
  Symbol get memberName {
    tick(11);
    return symbol;
  }

  @override
  List<Type> get typeArguments {
    tick(12);
    return types;
  }

  @override
  List<dynamic> get positionalArguments {
    tick(13);
    return positional;
  }

  @override
  Map<Symbol, dynamic> get namedArguments {
    tick(14);
    return named;
  }

  @override
  bool get isMethod {
    tick(15);
    return true;
  }

  @override
  bool get isGetter {
    tick(16);
    return true;
  }

  @override
  bool get isSetter {
    tick(17);
    return true;
  }

  @override
  bool get isAccessor {
    tick(18);
    return false;
  }
}

bool invocationCustomGetters() {
  final custom = CustomInvocation();
  final Invocation value = custom;
  return identical(value.memberName, custom.symbol) &&
      identical(value.typeArguments, custom.types) &&
      identical(value.positionalArguments, custom.positional) &&
      identical(value.namedArguments, custom.named) &&
      value.isMethod &&
      value.isGetter &&
      value.isSetter &&
      !value.isAccessor;
}

String invocationObjectPattern(int kind) {
  final Object? object = switch (kind) {
    0 || 1 || 2 || 3 => makeInvocation(kind, false, false),
    4 => CustomInvocation(),
    5 => InheritedInvocation(false, true, false, false),
    6 => null,
    _ => 42,
  };
  if (object case Invocation(
    :final memberName,
    :final typeArguments,
    :final positionalArguments,
    :final namedArguments,
    :final isMethod,
    :final isGetter,
    :final isSetter,
    :final isAccessor,
  )) {
    return '${memberName is InvocationSymbol}:'
        '${typeArguments.length}/${positionalArguments.length}/${namedArguments.length}:'
        '$isMethod/$isGetter/$isSetter/$isAccessor';
  }
  return 'not an Invocation';
}

int invocationTypeChecks(int kind) {
  final Object? object = switch (kind) {
    0 || 1 || 2 || 3 => makeInvocation(kind, false, false),
    4 => CustomInvocation(),
    5 => InheritedInvocation(false, true, false, false),
    6 => null,
    _ => 42,
  };
  var result = 0;
  if (object is Invocation) result += 1;
  if (object is Invocation?) result += 2;
  try {
    final value = object as Invocation?;
    result += 4;
    if (value == null) result += 8;
  } on TypeError {
    result += 16;
  }
  return result;
}

// Extending Invocation exercises its public no-op generative constructor,
// inherited typeArguments, and isAccessor's virtual short-circuiting getters.
class InheritedInvocation extends Invocation {
  final bool getter;
  final bool setter;
  final bool failGetter;
  final bool failSetter;
  InheritedInvocation(
    this.getter,
    this.setter,
    this.failGetter,
    this.failSetter,
  ) : super() {
    tick(20);
  }

  @override
  Symbol get memberName => #inherited;
  @override
  List<dynamic> get positionalArguments => const <Object?>[];
  @override
  Map<Symbol, dynamic> get namedArguments => const <Symbol, Object?>{};
  @override
  bool get isMethod => false;
  @override
  bool get isGetter {
    tick(21);
    if (failGetter) throw 121;
    return getter;
  }

  @override
  bool get isSetter {
    tick(22);
    if (failSetter) throw 122;
    return setter;
  }

  bool inheritedAccessor() => super.isAccessor;
  List<Type> inheritedTypes() => super.typeArguments;
}

bool invocationInheritedAccessor(
  bool getter,
  bool setter,
  bool failGetter,
  bool failSetter,
  bool superAccess,
) {
  final custom = InheritedInvocation(getter, setter, failGetter, failSetter);
  final Invocation value = custom;
  return superAccess ? custom.inheritedAccessor() : value.isAccessor;
}

bool invocationInheritedTypes() {
  final custom = InheritedInvocation(false, false, false, false);
  final Invocation value = custom;
  return value.typeArguments.length == 0 &&
      identical(value.typeArguments, const <Type>[]) &&
      identical(custom.inheritedTypes(), value.typeArguments);
}

class InvocationSequence<T>(
  final List<T> values,
  final int marker,
  final int failure,
) implements Iterable<T> {
  @override
  Iterator<T> get iterator {
    tick(marker + 1);
    if (failure == marker + 1) throw failure;
    return InvocationCursor(values, marker, failure);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 999;
}

class InvocationCursor<T>(
  final List<T> values,
  final int marker,
  final int failure,
) implements Iterator<T> {
  int index = -1;
  @override
  bool moveNext() {
    tick(marker + 2);
    if (failure == marker + 2 || (failure == marker + 4 && index == 0)) {
      throw failure;
    }
    index++;
    return index < values.length;
  }

  @override
  T get current {
    tick(marker + 3);
    if (failure == marker + 3 || (failure == marker + 5 && index == 1)) {
      throw failure;
    }
    return values[index];
  }
}

class InvocationMap(final bool empty, final int failure)
    implements Map<Symbol, Object?> {
  @override
  bool get isEmpty {
    tick(31);
    if (failure == 31) throw failure;
    return empty;
  }

  @override
  void forEach(void Function(Symbol, Object?) action) {
    tick(32);
    action(#zeta, 7);
    if (failure == 32) throw failure;
    tick(33);
    action(#alpha, null);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 999;
}

String invocationCopyProtocols(int failure, bool emptyMap, bool tearoff) {
  Symbol name() {
    tick(1);
    return #f;
  }

  Iterable<Type> types() {
    tick(2);
    return InvocationSequence<Type>(<Type>[int, String], 10, failure);
  }

  Iterable<Object?> positional() {
    tick(3);
    return InvocationSequence<Object?>(<Object?>[7, null], 20, failure);
  }

  Map<Symbol, Object?> named() {
    tick(4);
    return InvocationMap(emptyMap, failure);
  }

  final value = tearoff
      ? genericFactory(name(), types(), positional(), named())
      : Invocation.genericMethod(name(), types(), positional(), named());
  tick(40);
  var result =
      '${value.typeArguments[0] == int}/'
      '${value.typeArguments[1] == String}:'
      '${value.positionalArguments[0]}/${value.positionalArguments[1]}:';
  for (final entry in value.namedArguments.entries) {
    result = '$result${entry.key}=${entry.value}|';
  }
  return result;
}

bool invocationNamedSymbolIdentity() {
  final Symbol key = InvocationSymbol('named');
  final child = <int>[1];
  final named = <Symbol, Object?>{key: child};
  final value = Invocation.method(#f, null, named);
  named[key] = 9;
  child.add(2);
  var result = false;
  for (final entry in value.namedArguments.entries) {
    result = identical(entry.key, key) && identical(entry.value, child);
  }
  return result &&
      identical(value.namedArguments[key], child) &&
      (value.namedArguments[key] as List<int>)[1] == 2;
}

class OverriddenInvocation extends InheritedInvocation {
  final types = <Type>[String];
  OverriddenInvocation() : super(false, true, false, false);

  @override
  List<Type> get typeArguments {
    tick(51);
    return types;
  }

  @override
  bool get isAccessor {
    tick(52);
    return false;
  }
}

bool invocationOverriddenDefaults() {
  final custom = OverriddenInvocation();
  final Invocation value = custom;
  return identical(value.typeArguments, custom.types) &&
      !value.isAccessor &&
      identical(custom.inheritedTypes(), const <Type>[]) &&
      custom.inheritedAccessor();
}

// SDK List copying reads a custom List's length before its iterator. These
// checks intentionally pin that observable protocol, including inconsistent
// lengths, without claiming that it is a public Invocation API guarantee.
class InvocationList<T>(
  final List<T> values,
  final int reportedLength,
  final int marker,
  final int failure,
) implements List<T> {
  @override
  int get length {
    tick(marker + 6);
    if (failure == marker + 6) throw failure;
    return reportedLength;
  }

  @override
  T operator [](int index) {
    tick(marker + 7);
    return values[index];
  }

  @override
  Iterator<T> get iterator {
    tick(marker + 1);
    if (failure == marker + 1) throw failure;
    return InvocationCursor(values, marker, failure);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 999;
}

String invocationListProtocols(int kind, int reportedLength, int failure) {
  final Iterable<Type>? types = kind == 1
      ? InvocationList<Type>(<Type>[int, String], reportedLength, 10, failure)
      : null;
  final Iterable<Object?>? positional = kind != 1
      ? InvocationList<Object?>(<Object?>[7, null], reportedLength, 20, failure)
      : null;
  tick(1);
  final value = kind == 0
      ? Invocation.method(#f, positional)
      : Invocation.genericMethod(#f, types, positional);
  tick(40);
  return '${value.typeArguments.length}/${value.positionalArguments.length}';
}

class InvocationSet<T> extends InvocationSequence<T> implements Set<T> {
  final int reportedLength;
  InvocationSet(List<T> values, this.reportedLength, int marker, int failure)
    : super(values, marker, failure);

  @override
  int get length {
    tick(marker + 6);
    if (failure == marker + 6) throw failure;
    return reportedLength;
  }
}

String invocationSetProtocols(int kind, int reportedLength, int failure) {
  final Iterable<Type>? types = kind == 1
      ? InvocationSet<Type>(<Type>[int, String], reportedLength, 10, failure)
      : null;
  final Iterable<Object?>? positional = kind != 1
      ? InvocationSet<Object?>(<Object?>[7, null], reportedLength, 20, failure)
      : null;
  tick(1);
  final value = kind == 0
      ? Invocation.method(#f, positional)
      : Invocation.genericMethod(#f, types, positional);
  tick(40);
  return '${value.typeArguments.length}/${value.positionalArguments.length}';
}

// Redeclaring an inherited concrete getter as abstract changes the statically
// selected owner, but does not remove Invocation's inherited implementation.
abstract class RedeclaredInvocation extends Invocation {
  @override
  List<Type> get typeArguments;
  @override
  bool get isAccessor;
}

class ConcreteRedeclaredInvocation(final bool getter, final bool failSetter)
    extends RedeclaredInvocation {
  @override
  Symbol get memberName => #redeclared;
  @override
  List<dynamic> get positionalArguments => const <Object?>[];
  @override
  Map<Symbol, dynamic> get namedArguments => const <Symbol, Object?>{};
  @override
  bool get isMethod => false;
  @override
  bool get isGetter {
    tick(61);
    return getter;
  }

  @override
  bool get isSetter {
    tick(62);
    if (failSetter) throw 162;
    return true;
  }
}

class OverrideRedeclaredInvocation extends ConcreteRedeclaredInvocation {
  OverrideRedeclaredInvocation(super.getter, super.failSetter);

  @override
  List<Type> get typeArguments {
    tick(63);
    return const <Type>[String];
  }

  @override
  bool get isAccessor {
    tick(64);
    return false;
  }
}

String invocationRedeclaredDefaults(
  bool getter,
  bool failSetter,
  bool override,
  bool pattern,
) {
  final RedeclaredInvocation value = override
      ? OverrideRedeclaredInvocation(getter, failSetter)
      : ConcreteRedeclaredInvocation(getter, failSetter);
  if (pattern) {
    final Object object = value;
    if (object case RedeclaredInvocation(
      :final typeArguments,
      :final isAccessor,
    )) {
      return '${identical(typeArguments, const <Type>[])}:'
          '${typeArguments.length}/$isAccessor';
    }
    return 'not matched';
  }
  return '${identical(value.typeArguments, const <Type>[])}:'
      '${value.typeArguments.length}/${value.isAccessor}';
}

abstract interface class InvocationDefaultsInterface {
  List<Type> get typeArguments;
  bool get isAccessor;
}

class InterfaceInvocation(final bool getter, final bool failSetter)
    extends Invocation
    implements InvocationDefaultsInterface {
  @override
  Symbol get memberName => #interface;
  @override
  List<dynamic> get positionalArguments => const <Object?>[];
  @override
  Map<Symbol, dynamic> get namedArguments => const <Symbol, Object?>{};
  @override
  bool get isMethod => false;
  @override
  bool get isGetter {
    tick(71);
    return getter;
  }

  @override
  bool get isSetter {
    tick(72);
    if (failSetter) throw 172;
    return true;
  }
}

class OverrideInterfaceInvocation extends InterfaceInvocation {
  OverrideInterfaceInvocation(super.getter, super.failSetter);

  @override
  List<Type> get typeArguments {
    tick(73);
    return const <Type>[String];
  }

  @override
  bool get isAccessor {
    tick(74);
    return false;
  }
}

String invocationInterfaceDefaults(
  bool getter,
  bool failSetter,
  bool override,
  bool pattern,
) {
  final InvocationDefaultsInterface value = override
      ? OverrideInterfaceInvocation(getter, failSetter)
      : InterfaceInvocation(getter, failSetter);
  if (pattern) {
    final Object object = value;
    if (object case InvocationDefaultsInterface(
      :final typeArguments,
      :final isAccessor,
    )) {
      return '${identical(typeArguments, const <Type>[])}:'
          '${typeArguments.length}/$isAccessor';
    }
    return 'not matched';
  }
  return '${identical(value.typeArguments, const <Type>[])}:'
      '${value.typeArguments.length}/${value.isAccessor}';
}
