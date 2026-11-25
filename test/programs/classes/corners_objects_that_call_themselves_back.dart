class Even {
  final Odd odd = Odd();
  bool test(int n) => n == 0 || odd.test(n - 1, this);
}

class Odd {
  bool test(int n, Even e) => n != 0 && e.test(n - 1);
}

void main() {
  truth(Even().test(10)); // expect: true
  truth(Even().test(7)); // expect: false
}

void truth(bool b) => print(b);
