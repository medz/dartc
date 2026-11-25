class P {
  int x = 3;
  double y = 2.5;
  bool z = true;
  P? next;
}

void main() {
  final p = P(), q = P();
  p.x = 8;
  p.next = q;
  q.y = -1;
  q.z = false;
  q.next = p;
  number(p.x); // expect: 8
  number(q.x); // expect: 3
  truth(p.y == 2.5); // expect: true
  truth(q.y < 0); // expect: true
  truth(p.z); // expect: true
  truth(q.z); // expect: false
  truth(p.next == q); // expect: true
  truth(q.next == p); // expect: true
  truth(p.next?.next == p); // expect: true
  truth(p == q); // expect: false
  truth(P().next == null); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
