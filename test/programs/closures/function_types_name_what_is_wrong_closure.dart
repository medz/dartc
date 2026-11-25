void show(Object? o) {
  if (o == null) {
    print('null');
  } else if (o is int) {
    number(o);
  } else if (o is bool) {
    truth(o);
  } else if (o is double) {
    print('double');
    number((o * 2).toInt());
  } else {
    print('other');
  }
}

int twice(int n) => n * 2;
int apply(int Function(int) f, int n) => f(n);
void run(void Function() f) => f();

class A {
  final int n;
  const A(this.n);
  int add(int m) => n + m;
  void shout() => number(n);
  int get g => n;
}

class B extends A {
  const B(super.n);
  @override
  int add(int m, [int k = 100]) => n + m + k;
}

class String2 {}

void main() {
  print('a'); // expect: a
  Object o;
  o = (String2 a, {int? b}) => true;
  o as A;
}

void number(int n) => print(n);

void truth(bool b) => print(b);
// stderr: Unhandled exception:
// stderr: type '(String2, {int? b}) => bool' is not a subtype of type 'A' in type cast
// exit: 255
