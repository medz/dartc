class Base<T>(final T value) {
  T read() => value;
}

mixin Counter {
  int count = 0;
  int next() => ++count;
  int Function() capture() =>
      () => ++count;
}

class Applied<T>(super.value) extends Base<T> with Counter;

class Fixed(super.value) extends Base<int> with Counter;

class Alias<T> = Base<T> with Counter;

mixin Box<T> {
  late T item;
  final List<T> history = [];
  late T saved = item;
  T assign(T value) => item = value;
  T throughExtension() => item.unwrap();
  T Function() capture() =>
      () => item;
  R echo<R extends T>(R value) => value;
  R Function(R) local<R extends T>() {
    S identity<S extends R>(S value) => value;
    return identity<R>;
  }

  T Function(T) remember(T value) {
    return (next) {
      final old = value;
      value = next;
      return old;
    };
  }
}

extension Identity<T> on T {
  T unwrap() => this;
}

class Generic<T>() with Box<T>;

class Concrete() with Box<int>;

mixin Reader<T> on Base<T> {
  T inherited() => super.read();
  T Function() inheritedClosure() =>
      () => super.read();
}

class Read<T>(super.value) extends Base<T> with Reader<T>;

abstract class Value<T>() {
  T read();
}

mixin AbstractReader<T> implements Value<T> {
  @override
  T read();
  T invoke() => read();
}

class Inherited<T>(super.value) extends Base<T> with AbstractReader<T>;

class Override() with AbstractReader<int> {
  @override
  int read() => 11;
}

mixin ImplementedReader implements Value<int> {
  @override
  int read() => 12;
}

class Implemented() with ImplementedReader;

mixin Missing {
  @override
  dynamic noSuchMethod(Invocation call) => 13;
}

class Forwarded() with Missing implements Value<int>;

mixin class Nested<T> = Object with Box<T>;

mixin class Twice<T> = Object with Nested<T>;

class NestedApplication<T>() with Twice<T>;

String nested() {
  final a = NestedApplication<String>()..item = 'nested';
  final b = NestedApplication<int>()..item = 15;
  final Object erased = a;
  return '${a.capture()()}:${b.assign(16)}:${erased is Twice<String>}:${erased is Box<String>}';
}

class CovariantBase() {
  int accept(covariant int value) => value;
}

mixin Accept {
  int accept(int value) => value;
}

class CovariantApplied() extends CovariantBase with Accept;

class const ConstantBase<T>(final T value);

mixin ConstantReader<T> on ConstantBase<T> {
  T read() => value;
}

class ConstantAlias<T> = ConstantBase<T> with ConstantReader<T>;

class const ConstantApplied<T>(super.value)
    extends ConstantBase<T>
    with ConstantReader<T>;

String constants() {
  const value = ConstantApplied<String>('constant');
  const alias = ConstantAlias<int>(14);
  return '${value.read()}:${alias.read()}:${identical(value, const ConstantApplied<String>('constant'))}';
}

String inheritedCovariance() {
  final object = CovariantApplied();
  final Object tearoff = object.accept;
  return '${tearoff is int Function(int)}:${tearoff is int Function(dynamic)}';
}

String abstractMembers() =>
    '${Inherited<String>('inherited').invoke()}:${Override().invoke()}:${Implemented().read()}:${Forwarded().read()}';

String genericOwners() {
  final a = Applied<int>(3), b = Applied<String>('text');
  final next = a.capture();
  final Object erasedA = a, erasedB = b;
  return '${a.read()}:${b.read()}:${a.next()}:${next()}:${b.next()}:${erasedA is Base<int>}:${erasedB is Counter}';
}

String genericAliases() {
  final make = Alias<String>.new;
  final a = make('text'), b = Alias<int>(4);
  return '${a.read()}:${b.read()}:${a.next()}:${b.next()}:${Fixed(5).read()}';
}

String genericMixins() {
  final value = Generic<String>()..item = 'first';
  final capture = value.capture();
  value.assign('second');
  final concrete = Concrete()..item = 4;
  final identity = concrete.local<int>();
  final remember = concrete.remember(8);
  value.history.add(value.saved);
  return '${capture()}:${value.echo<String>('third')}:${concrete.echo<int>(5)}:${identity(6)}:${remember(9)}:${remember(10)}:${value.history[0]}:${value.throughExtension()}';
}

String genericSuper() {
  final value = Read<int>(7);
  final Object erased = value;
  return '${value.inherited()}:${value.inheritedClosure()()}:${erased is Reader<int>}';
}

String covariance() {
  Box<num> value = Concrete();
  var errors = '';
  try {
    value.item = 1.5;
  } on TypeError {
    errors += 'field;';
  }
  try {
    value.assign(1.5);
  } on TypeError {
    errors += 'method;';
  }
  try {
    value.echo<num>(1.5);
  } on TypeError {
    errors += 'bound;';
  }
  return errors;
}
