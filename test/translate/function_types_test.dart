import 'support.dart';

void main() {
  agrees('named parameters in runtime function types', r'''
    typedef AB = void Function({int? a, int? b});
    typedef BA = void Function({int? b, int? a});
    void ba({int? b, int? a}) {}
    void ab({int? a, int? b}) {}
    void requiredB({required int b, String? a}) {}
    void mixed(num value, {required String z, bool? a}) {}
    class C { void ba({int? b, int? a}) {} }

    void main() {
      final first = ba.runtimeType, second = ab.runtimeType;
      print(first);
      print(second);
      print(first == second);
      print(C().ba.runtimeType == first);
      print({first: 1, second: 2}[C().ba.runtimeType]);
      print(BA);
      print(AB == BA);
      print(first == BA);
      print(second == BA);
      Object f = ba;
      print(f is AB);
      print(f is void Function({int? b}));
      print(f is void Function({int? c}));
      f = mixed;
      print(f.runtimeType);
      print(f is void Function(int, {bool? a, required String z}));
      print(f is void Function(int, {bool? a}));
      f = requiredB;
      print(f is void Function({String? a, required int b}));
      print(f is void Function({String? a, int b}));
      print(f is void Function({required num b}));
    }
  ''');

  agrees('named parameters when a generic function is instantiated', r'''
    typedef F = void Function<T>({T? a, T? z});
    void top<T>({T? z, T? a}) {}
    void nested<T>({void Function<U extends T>(U, T)? z, T? a}) {}
    void check(F f) {
      final type = f<int>.runtimeType;
      print(type);
      print(type == top<int>.runtimeType);
    }
    void main() {
      void local<T>({T? z, T? a}) {}
      print(top.runtimeType);
      print(local.runtimeType);
      check(top);
      check(local);
      final f = nested;
      print(f<num>.runtimeType);
      print(f<num>.runtimeType == nested<num>.runtimeType);
    }
  ''');

  agrees('functions with type arguments take all that they can', r'''
    typedef Narrow = int Function<T>();
    typedef Wider = num Function<T>();
    typedef One = Object? Function<T>(int a);
    typedef Two = Object? Function<A, B>(A a);
    int wide<T>({int? extra}) => extra ?? 0;
    String both<T>(num a, {String? s, T? t}) => '$T $a $s $t';
    String two<A, B>(A a, [B? b, int c = 1]) => '$A $B $a $b $c';
    class C {
      final int n; C(this.n);
      String m<T>(int a, {T? t, int k = 2}) => '$T $a $t $k $n';
      static int s<T>([int k = 3]) => k;
    }
    class D extends C {
      D(super.n);
      String m<T>(num a, {T? t, int k = 3, String? more}) => 'D $T $a $t $k $n $more';
    }
    Object bind(Narrow f) => f<int>;
    Object bindWider(Wider f) => f<int>;
    Object one(One f) => f<int>;
    Object bindTwo(Two f) => f<int, String>;
    void go(Object? Function() f) {
      try { print(f()); } on NoSuchMethodError { print('N'); } catch (e) { print(e); }
    }
    void main() {
      final p = bind(wide);
      print(p is int Function({int? extra}));
      if (p is int Function({int? extra})) {
        go(() => p(extra: 7)); go(() => p()); go(() => p(extra: null));
      }
      dynamic d = p;
      go(() => d(extra: 7)); go(() => d()); go(() => d.call(extra: 8)); go(() => d(extra: 'x'));
      go(() => Function.apply(d, [], {#extra: 9})); go(() => Function.apply(d, []));
      final q = one(both);
      if (q is Object? Function(num, {String? s, int? t})) {
        go(() => q(1.5, s: 'a', t: 3)); go(() => q(1, t: 3));
      }
      if (q is Object? Function(int, {String? s})) go(() => q(5, s: 'only'));
      go(() => (q as dynamic)(2.5, s: 'b')); go(() => (q as dynamic)(2.5, t: 'b'));
      go(() => Function.apply(q as Function, [2], {#t: 4, #s: 'c'}));
      final r = bindTwo(two);
      if (r is Object? Function(int, [String?, int])) {
        go(() => r(1, 'b', 3)); go(() => r(1, 'b')); go(() => r(1));
      }
      go(() => (r as dynamic)(1, 'x', 9)); go(() => Function.apply(r as Function, [1, 'y']));
      for (final c in [C(4), D(5)]) {
        final s = one(c.m);
        print(s is Object? Function(int, {int? t, int k}));
        print(s is Object? Function(num, {String? more}));
        if (s is Object? Function(int, {int? t, int k})) go(() => s(1, t: 2, k: 8));
        if (s is Object? Function(num, {String? more})) go(() => s(1.5, more: 'z'));
        go(() => (s as dynamic)(1, t: 6)); go(() => (s as dynamic)(1, t: 'bad'));
      }
      final u = bind(C.s);
      if (u is int Function(int)) go(() => u(12));
      final local = <T>(int a, {T? t}) => '$T $a $t ${p == d}';
      final t = one(local);
      if (t is Object? Function(int, {int? t})) go(() => t(1, t: 2));
      go(() => (t as dynamic)(1, t: 3));
      // What does not fit.
      go(() => d(1)); go(() => d(other: 1)); go(() => d<int>()); go(() => d.call(1));
      go(() => (q as dynamic)()); go(() => (q as dynamic)(1, u: 2));
      go(() => Function.apply(d, [1])); go(() => Function.apply(d, [], {#other: 1}));
      go(() => (r as dynamic)()); go(() => (r as dynamic)(1, 2));
      // How the type is written where they get their arguments does not matter.
      print((bind(wide) == bind(wide), bind(wide) == bindWider(wide), bind(wide).hashCode == bindWider(wide).hashCode));
      print(({bind(wide): 1}[bindWider(wide)], bind(wide) == bind(C.s)));
    }
  ''');
}
