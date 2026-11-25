class A {
  final int n;
  A(this.n);
}

class B extends A {
  B(super.n);
}

abstract class I {}

class C implements I {
  const C();
}

int zero() => 0;
bool yes() => zero() == 0;

/// Says what any object is.
void show(Object? o) {
  if (o == null) {
    print('null');
  } else if (o is int) {
    number(o);
  } else if (o is double) {
    print('double');
    number((o * 2).toInt());
  } else if (o is bool) {
    truth(o);
  } else if (o is B) {
    print('B');
    number(o.n);
  } else if (o is A) {
    print('A');
    number(o.n);
  } else {
    print('other');
  }
}

Object? pick(int n) {
  switch (n) {
    case 0:
      return 7;
    case 1:
      return 2.5;
    case 2:
      return true;
    case 3:
      return A(3);
    case 4:
      return B(4);
    case 5:
      return null;
    case 6:
      return C();
    case 7:
      return -0.0;
    case 8:
      return false;
    case 9:
      return 0 / 0;
  }
  return 1 << 62;
}

void t(int n) {
  final o = pick(n);
  try {
    number(o as int);
  } on TypeError {
    print('no int');
  }
  try {
    show(o as num?);
  } on TypeError {
    print('no num?');
  }
  try {
    number((o as A).n);
  } on TypeError {
    print('no A');
  }
  try {
    show(o as B?);
  } on TypeError {
    print('no B?');
  }
  try {
    truth(o as bool);
  } on TypeError {
    print('no bool');
  }
  try {
    show(o as Object);
  } on TypeError {
    print('no Object');
  }
  try {
    show((o as double) + 1);
  } on TypeError {
    print('no double');
  }
}

void main() {
  for (var i = 0; i < 7; i++) t(i);
  // expect: 7
  // expect: 7
  // expect: no A
  // expect: no B?
  // expect: no bool
  // expect: 7
  // expect: no double
  // expect: no int
  // expect: double
  // expect: 5
  // expect: no A
  // expect: no B?
  // expect: no bool
  // expect: double
  // expect: 5
  // expect: double
  // expect: 7
  // expect: no int
  // expect: no num?
  // expect: no A
  // expect: no B?
  // expect: true
  // expect: true
  // expect: no double
  // expect: no int
  // expect: no num?
  // expect: 3
  // expect: no B?
  // expect: no bool
  // expect: A
  // expect: 3
  // expect: no double
  // expect: no int
  // expect: no num?
  // expect: 4
  // expect: B
  // expect: 4
  // expect: no bool
  // expect: B
  // expect: 4
  // expect: no double
  // expect: no int
  // expect: null
  // expect: no A
  // expect: null
  // expect: no bool
  // expect: no Object
  // expect: no double
  // expect: no int
  // expect: no num?
  // expect: no A
  // expect: no B?
  // expect: no bool
  // expect: other
  // expect: no double
  show(1 as num); // expect: 1
  show(1 as Object); // expect: 1
  try {
    show((1 as dynamic) as double);
  } on TypeError {
    print('no');
  }
  // expect: no
}

void number(int n) => print(n);

void truth(bool b) => print(b);
