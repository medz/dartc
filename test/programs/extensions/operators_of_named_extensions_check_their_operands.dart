class Box<T> {
  final T value;
  Box(this.value);
}

extension E<T> on Box<T> {
  T operator +(T other) => other;
}

void main() {
  print(E<int>(Box<int>(1)) + 'x'); // error 31: The argument type 'String' can't be assigned to the parameter type 'T'. 
}
