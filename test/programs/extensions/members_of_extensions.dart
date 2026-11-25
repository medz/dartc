extension Numbers on int {
  static int made = 0;
  static int make(int n) {
    made++;
    return n * 2;
  }

  int get doubled => this * 2;
  int plus(int other, {int times = 1}) => this + other * times;
  int operator [](int i) => (this >> i) & 1;
  bool get isBig {
    bool check() => this > 100;
    return check();
  }

  set note(int n) {
    print('$this notes $n');
  }

  int again() => plus(1) + doubled + abs();
}

extension on double {
  double half() => this / 2;
}

extension Texts on String? {
  String orElse(String other) => this ?? other;
  bool get isMissing => this == null;
}

extension Anything on Object? {
  String get shown => '<$this>';
}

void main() {
  print(3.doubled); // expect: 6
  print(3.plus(4)); // expect: 7
  print(3.plus(4, times: 5)); // expect: 23
  print(6[1]); // expect: 1
  print(6[0]); // expect: 0
  print(200.isBig); // expect: true
  print(2.isBig); // expect: false
  5.note = 9; // expect: 5 notes 9
  var n = 4;
  n.note = 1; // expect: 4 notes 1
  print(4.again()); // expect: 17
  print(Numbers.make(21)); // expect: 42
  print(Numbers.made); // expect: 1
  print(3.5.half()); // expect: 1.75
  String? none = DateTime.now().year < 3 ? 'x' : null;
  print(none.orElse('other')); // expect: other
  print(none.isMissing); // expect: true
  print('a'.orElse('b')); // expect: a
  print(none?.shown); // expect: null
  print(none.shown); // expect: <null>
  print(3.shown); // expect: <3>
  print(null.shown); // expect: <null>
  print([1].shown); // expect: <[1]>
  print(Numbers(7).doubled); // expect: 14
  print(Numbers(7)[0]); // expect: 1
  print(Texts(none).orElse('z')); // expect: z
  int? some = n, missing = none?.length;
  print(some?.doubled); // expect: 8
  print(missing?.doubled); // expect: null
  print(some?.plus(2, times: 3)); // expect: 10
  print(missing?.plus(2)); // expect: null
  missing?.note = 4;
}
