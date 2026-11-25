class Noisy {
  final int n;
  Noisy(this.n);
  int get value {
    print('value');
    return n;
  }

  Noisy get self {
    print('self');
    return this;
  }
}

class L {
  final List<int> l;
  L(this.l);
  int get length {
    print('length');
    return l.length;
  }

  int operator [](int i) {
    print('[$i]');
    return l[i];
  }
}

String what(Object o) => switch (o) {
  Noisy(value: 1) => 'one',
  Noisy(value: 2) => 'two',
  Noisy(self: Noisy(value: 3)) => 'three',
  Noisy(value: var v, self: Noisy(value: > 4)) => 'many $v',
  Noisy(value: var v) => 'some $v',
  _ => 'none',
};
void main() {
  for (final n in [1, 2, 3, 4, 5]) print(what(Noisy(n)));
  // expect: value
  // expect: one
  // expect: value
  // expect: two
  // expect: value
  // expect: self
  // expect: value
  // expect: three
  // expect: value
  // expect: self
  // expect: value
  // expect: some 4
  // expect: value
  // expect: self
  // expect: value
  // expect: many 5
  switch (Noisy(7)) {
    case Noisy(value: 6):
      print(6);
    case Noisy(value: 7) when Noisy(1).value == 2:
      print('when');
    case Noisy(value: < 9 && var w):
      print(w);
  }
  // expect: value
  // expect: value
  // expect: 7
  if (Noisy(3) case Noisy(value: 2) || Noisy(value: 3)) print('yes');
  // expect: value
  // expect: yes
}
