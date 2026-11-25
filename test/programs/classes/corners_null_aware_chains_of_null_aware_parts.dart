class C {
  C? next;
  int n = 3;
  C? get self => this;
}

void main() {
  final c = C();
  C? none;
  c.next = C();
  truth(c.next?.next?.next == null); // expect: true
  truth(c.self?.next?.self == c.next); // expect: true
  truth(none?.next?.self == null); // expect: true
}

void truth(bool b) => print(b);
