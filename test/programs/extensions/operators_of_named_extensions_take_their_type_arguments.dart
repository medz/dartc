class Box<T> {
  final T value;
  Box(this.value);
}

extension E<T> on Box<T> {
  T operator +(T other) => other;
  Box<T> operator *(T other) => Box(other);
}

void main() {
  print(E<int>(Box<int>(1)) + 7); // expect: 7
  print(E(Box<int>(1)) + 8); // expect: 8
  print(Box<int>(1) + 9); // expect: 9
  final int r = E<int>(Box<int>(1)) + 10;
  print(r); // expect: 10
  print((E<String>(Box('a')) * 'b').value); // expect: b
}
