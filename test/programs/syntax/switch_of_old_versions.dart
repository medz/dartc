// @dart=2.19
const c = 3;

class A {
  final int n;
  const A(this.n);
  static const one = A(1);
}

enum E { a, b }

String f(Object? x) {
  switch (x) {
    case 1:
      return 'one';
    case 1 + 1:
      return 'two';
    case c:
      return 'c';
    case 'text':
    case null:
      return 'text or null';
    case A.one:
      return 'A';
    case E.a:
      break;
    case E.b:
      continue more;
    more:
    case const A(2):
      return 'A 2';
    default:
      return 'default';
  }
  return 'after';
}

int loop(List<int> xs) {
  var sum = 0;
  for (final x in xs) {
    switch (x) {
      case 1:
        continue;
      case 2:
        sum += 10;
        break;
      default:
        sum += x;
    }
  }
  return sum;
}

void main() {
  for (final x in [
    1,
    2,
    3,
    'text',
    null,
    const A(1),
    E.a,
    E.b,
    const A(2),
    9
  ]) {
    print(f(x));
  }
  // expect: one
  // expect: two
  // expect: c
  // expect: text or null
  // expect: text or null
  // expect: A
  // expect: after
  // expect: A 2
  // expect: A 2
  // expect: default
  print(loop([1, 2, 3, 4])); // expect: 17
  switch (E.a) {
    case E.a:
      print('a');
      break;
    case E.b:
      print('b');
  }
  // expect: a
}
