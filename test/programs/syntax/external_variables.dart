external int x;
external final String y;
external List<int>? z, w;

class A {
  external int i;
  external final int f;
  external static int s;
  external static final double t;
  int own = 5;
  external static int get get;
  external static set set(int v);
}

class K<X extends num, Y> {
  external X k;
  external static int ks<T>(T a, {int? b});
}

class B extends A {
  int get i => 2;
  set i(int v) => print('set $v');
  int above() => super.f;
}

class C implements A {
  int i = 3;
  int f = 4;
  int own = 6;
}

extension E on int {
  external int e;
  external static int es;
}

extension type T(int v) {
  external int e;
  external static int es;
}

enum N {
  a;

  external int get n;
  external static int ns;
}

abstract class G<X> {
  external X g;
  external covariant num c;
}

class H extends G<String> {}

void main() {
  for (final use in <Object? Function()>[
    () => x,
    () => x = 1,
    () => x++,
    () => y,
    () => z,
    () => w ??= [1],
    () => A().i,
    () => A().i = 2,
    () => A().f,
    () => A().own,
    () => A.s,
    () => A.s += 1,
    () => A.s = 3,
    () => A.t,
    () => A.get,
    () => A.set = 1,
    () => K<int, String>().k,
    () => K.ks<int>(1),
    () => B().i,
    () => B().i = 7,
    () => B().f,
    () => B().above(),
    () => C().i + C().f,
    () => (C() as A).i,
    () => 1.e,
    () => 1.e = 2,
    () => E.es,
    () => T(1).e,
    () => T(1).e = 2,
    () => T.es,
    () => T.es = 3,
    () => N.a.n,
    () => N.ns,
    () => H().g,
    () => H().g = 'a',
    () => H().c = 1,
    () => (H() as G<Object>).g = 1,
    () => (A() as dynamic).i,
    () => (A() as dynamic).i = 3,
    () => (A() as dynamic).i = 'a',
    () => switch (A()) {
      A(:final i) => i,
    },
  ]) {
    try {
      print(use());
    } catch (e) {
      print(e);
    }
  }
  // expect: NoSuchMethodError: No top-level getter 'x' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: x
  // expect: NoSuchMethodError: No top-level setter 'x=' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: x=
  // expect: NoSuchMethodError: No top-level getter 'x' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: x
  // expect: NoSuchMethodError: No top-level getter 'y' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: y
  // expect: NoSuchMethodError: No top-level getter 'z' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: z
  // expect: NoSuchMethodError: No top-level getter 'w' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: w
  // expect: NoSuchMethodError: No static getter 'i' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: i
  // expect: NoSuchMethodError: No static setter 'i=' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: i=
  // expect: NoSuchMethodError: No static getter 'f' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: f
  // expect: 5
  // expect: NoSuchMethodError: No static getter 's' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: s
  // expect: NoSuchMethodError: No static getter 's' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: s
  // expect: NoSuchMethodError: No static setter 's=' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: s=
  // expect: NoSuchMethodError: No static getter 't' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: t
  // expect: NoSuchMethodError: No static getter 'get' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: get
  // expect: NoSuchMethodError: No static setter 'set=' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: set=
  // expect: NoSuchMethodError: No static getter 'k' declared in class 'K<num, dynamic>'.
  // expect: Receiver: K<num, dynamic>
  // expect: Tried calling: k
  // expect: NoSuchMethodError: No static method 'ks' with matching arguments declared in class 'K<num, dynamic>'.
  // expect: Receiver: K<num, dynamic>
  // expect: Tried calling: ks()
  // expect: Found: ks<Y0>(Y0, {int? b}) => int
  // expect: 2
  // expect: set 7
  // expect: 7
  // expect: NoSuchMethodError: No static getter 'f' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: f
  // expect: NoSuchMethodError: No static getter 'f' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: f
  // expect: 7
  // expect: 3
  // expect: NoSuchMethodError: No top-level method 'E|get#e' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: E|get#e()
  // expect: NoSuchMethodError: No top-level method 'E|set#e' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: E|set#e()
  // expect: NoSuchMethodError: No top-level getter 'E|es' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: E|es
  // expect: NoSuchMethodError: No top-level method 'T|get#e' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: T|get#e()
  // expect: NoSuchMethodError: No top-level method 'T|set#e' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: T|set#e()
  // expect: NoSuchMethodError: No top-level getter 'T|es' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: T|es
  // expect: NoSuchMethodError: No top-level setter 'T|es=' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: T|es=
  // expect: NoSuchMethodError: No static getter 'n' declared in class 'N'.
  // expect: Receiver: N
  // expect: Tried calling: n
  // expect: NoSuchMethodError: No static getter 'ns' declared in class 'N'.
  // expect: Receiver: N
  // expect: Tried calling: ns
  // expect: NoSuchMethodError: No static getter 'g' declared in class 'G<dynamic>'.
  // expect: Receiver: G<dynamic>
  // expect: Tried calling: g
  // expect: NoSuchMethodError: No static setter 'g=' declared in class 'G<dynamic>'.
  // expect: Receiver: G<dynamic>
  // expect: Tried calling: g=
  // expect: NoSuchMethodError: No static setter 'c=' declared in class 'G<dynamic>'.
  // expect: Receiver: G<dynamic>
  // expect: Tried calling: c=
  // expect: NoSuchMethodError: No static setter 'g=' declared in class 'G<dynamic>'.
  // expect: Receiver: G<dynamic>
  // expect: Tried calling: g=
  // expect: NoSuchMethodError: No static getter 'i' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: i
  // expect: NoSuchMethodError: No static setter 'i=' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: i=
  // expect: type 'String' is not a subtype of type 'int' of '#externalFieldValue'
  // expect: NoSuchMethodError: No static getter 'i' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: i
}
