void main() {
  double d = 1.5;
  Object? r;
  try {
    r = d as int;
  } catch (e) {
    print(e);
  }
  // expect: type 'double' is not a subtype of type 'int' in type cast
  try {
    r = true as int;
  } catch (e) {
    print(e);
  }
  // expect: type 'bool' is not a subtype of type 'int' in type cast
  try {
    r = 1 as double;
  } catch (e) {
    print(e);
  }
  // expect: type 'int' is not a subtype of type 'double' in type cast
  print(r); // expect: null
  if (d case int i) print(i);
  print(d is int); // expect: false
  print(1 is double); // expect: false
  int n = 1;
  try {
    print((n as double) + 1);
  } catch (e) {
    print(e);
  }
  // expect: type 'int' is not a subtype of type 'double' in type cast
  print(switch (n) {
    double x => x,
    _ => 'n',
  }); // expect: n
  print(switch (true) {
    int() => 1,
    String s => s,
    bool b => b,
  }); // expect: true
  if (n case double() && > 3) print('q');
  print(switch (2.5) {
    int(isEven: true) => 'e',
    num(sign: var s) => s,
  }); // expect: 1.0
  final (a, b) = (1, 2.0);
  if ((a, b) case (double x, int y))
    print((x, y));
  else
    print('no'); // expect: no
  if ([1.5] case [int x]) print(x);
}
