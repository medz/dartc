class P {
  final int n;
  P(this.n);
  @override
  bool operator ==(Object o) {
    number(n);
    return super == o;
  }

  bool differs(P o) => super != o;
}

void main() {
  final p = P(1);
  truth(p == p);
  // expect: 1
  // expect: true
  truth(p == P(2));
  // expect: 1
  // expect: false
  truth(p.differs(p)); // expect: false
  truth(p.differs(P(3))); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
