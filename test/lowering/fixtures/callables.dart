import 'effects.dart' as effects;

typedef Transform = int Function(int n, {int extra});
// ignore: prefer_generic_function_type_aliases
typedef int OldTransform(int n);

int add(int n, {int extra = 4}) => effects.tick(n) + extra;
const Transform fallback = add;

class Base(final int offset) {
  int apply(int n, {int extra = 1}) => offset + effects.tick(n) + extra;
  Transform get operation {
    effects.tick(3);
    return apply;
  }

  static int scale(int n, {int extra = 2}) => effects.tick(n) * extra;
}

class Sub(super.offset) extends Base {
  @override
  int apply(int n, {int extra = 9}) => super.apply(n, extra: extra + 1);
  Transform parent() => super.apply;
}

abstract class Ticket() {
  factory create({int value}) = Product;
  int get value;
}

class Product({@override final int value = 6}) implements Ticket;

int indirect(int mode, int n) => _choose(mode, n);
int _choose(int mode, int n, [Transform fn = add]) {
  final Base instance = Sub(2);
  final op = switch (mode) {
    0 => fn,
    1 => Base.scale,
    2 => instance.apply,
    3 => instance.operation,
    _ => Sub(2).parent(),
  };
  return op(effects.tick(n)) + op.call(1, extra: 2);
}

int factoryValue(bool redirected) {
  final Ticket Function({int value}) build = redirected
      ? Ticket.create
      : Product.new;
  return build().value + build(value: 3).value;
}

int? optionalCall(Transform? fn, int n) => fn?.call(effects.tick(n));

int? selectedCall(bool missing, int n) {
  final Base? obj = missing ? null : Sub(4);
  final chosen = obj?.apply;
  return optionalCall(chosen, n);
}

bool sameMethods(int mode) {
  final a = Sub(2), b = Sub(2);
  return switch (mode) {
    0 => a.apply == a.apply,
    1 => a.apply == b.apply,
    2 => a.parent() == a.apply,
    _ => fallback == add,
  };
}

abstract class Sink() {
  int accept(Object value);
}

class IntSink() implements Sink {
  @override
  int accept(covariant int value) => effects.tick(value);
}

int covariantValue(Object? n) {
  final Object fn = IntSink().accept;
  if (fn is int Function(Object?)) {
    try {
      return fn(n);
    } on TypeError {
      return 9;
    }
  }
  return 0;
}

class Callable(final int base) {
  int call(int n) => base + n;
}

int applyOld(OldTransform fn, int n) => fn(n);
int objectCall(int n) {
  final value = Callable(4);
  // ignore: implicit_call_tearoffs
  return applyOld(value, n) + value(n) + applyOld(effects.tick, n);
}

bool selfDefault() => _self();
bool _self([Function? fn = _self]) => fn == _self;

int getterCall(int n) => Sub(5).operation(effects.tick(n));
int parenthesizedGetter(int n) => (Sub(5).operation)(effects.tick(n));
bool callIdentity(Transform f) => f.call == f;
bool sameCallable() => callIdentity(add);
