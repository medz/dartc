abstract class A {
  set x(Object? value);
}

class B implements A {
  external covariant int x;
}

class C implements A {
  covariant int x = 0;
}

abstract class D {
  set x(covariant Object? value);
}

class E implements D {
  external int x;
}

class F<T> {
  external T x;
}

class G extends F<int> {
  external int x;
}

class H<T> implements D {
  external covariant T x;

  void assignTyped(T value) {
    this.x = value;
  }

  void assignErased(Object? value) {
    (this as D).x = value;
  }
}

Object? argument() {
  print('argument');
  return null;
}

void attempt(void Function() assign) {
  try {
    assign();
  } catch (e) {
    print('$e'.split('\n').first);
  }
}

void main() {
  for (final receiver in <A>[B(), C()]) {
    attempt(() => receiver.x = argument());
  }
  // expect: argument
  // expect: type 'Null' is not a subtype of type 'int' of '#externalFieldValue'
  // expect: argument
  // expect: type 'Null' is not a subtype of type 'int' of 'value'
  attempt(
    () => (B() as A).x = 3,
  ); // expect: NoSuchMethodError: No static setter 'x=' declared in class 'B'.
  final D inherited = E();
  attempt(() => inherited.x = argument());
  // expect: argument
  // expect: type 'Null' is not a subtype of type 'int' of '#externalFieldValue'
  final F<Object?> generic = G();
  attempt(() => generic.x = argument());
  // expect: argument
  // expect: NoSuchMethodError: No static setter 'x=' declared in class 'G'.
  final sameReceiver = H<int>();
  attempt(() => sameReceiver.assignTyped(1)); // expect: NoSuchMethodError: No static setter 'x=' declared in class 'H<dynamic>'.
  attempt(() => sameReceiver.assignErased(null)); // expect: type 'Null' is not a subtype of type 'int' of '#externalFieldValue'
  final dynamic dynamicReceiver = B();
  attempt(() => dynamicReceiver.x = argument());
  // expect: argument
  // expect: type 'Null' is not a subtype of type 'int' of '#externalFieldValue'
}
