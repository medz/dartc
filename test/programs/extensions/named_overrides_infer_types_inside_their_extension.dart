extension F<A, B extends List<A>> on List<A> {
  (Type, Type) get types => (A, B);

  void show() {
    final receiver = this;
    print(F(this).types);
    print(F(receiver).types);
    print(F<A, B>(this).types);
  }
}

void main() {
  F<num, List<int>>(<int>[]).show();
  // expect: (num, List<num>)
  // expect: (num, List<num>)
  // expect: (num, List<int>)
  print(F(<int>[]).types); // expect: (int, List<int>)
}
