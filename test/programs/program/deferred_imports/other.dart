int f() => 1;
Object? g(void x) => 'g';
int v = 1;
const c = 'constant';
T id<T>(T t) => t;

class A {
  final int i;
  A(this.i);
  A.named(Object? i) : i = i as int;
  factory A.other() => A(9);
  static int s = 7;
  static A make(int i) => A(i);
}

enum E { a }

extension X on int {
  int get twice => this * 2;
}

typedef B = A;

class G<T> {}

int? n;
final list = [0];
int Function(Object?) function = (x) => x as int;
Future<int> later() async => 3;
