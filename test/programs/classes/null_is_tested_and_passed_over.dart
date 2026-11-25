class C {
  C? next;
  int n = 1;
  C? f(int x) {
    number(x);
    return next;
  }

  void g() => print('g');
}

void main() {
  C? a, b = C();
  a?.g();
  b.g(); // expect: g
  a?.f(trace(5));
  b.f(trace(6));
  // expect: 6
  // expect: 6
  C? c = b;
  if (1 < 2) c.next = C();
  truth(a?.next == null); // expect: true
  truth(c.next?.next == null); // expect: true
  final d = a ?? b;
  truth(d == b); // expect: true
  a ??= C();
  truth(a == b); // expect: false
  a ??= b;
  truth(a == b); // expect: false
  if (c.next != null && b.next == null)
    print('no');
  else
    print('yes'); // expect: yes
  for (C? at = b; at != null; at = at.next) number(at.n);
  // expect: 1
  // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
