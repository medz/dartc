class P {
  int n;
  P(this.n) {
    number(n);
  }
  P? next;
}

final P one = P(1);
P two = P(2);
void main() {
  truth(one == one);
  // expect: 1
  // expect: true
  two.next = one; // expect: 2
  two.n = 8;
  number(two.n); // expect: 8
  truth(two.next == one); // expect: true
  two = P(3); // expect: 3
  number(two.n); // expect: 3
  two.next = two;
  truth(two.next != one); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
