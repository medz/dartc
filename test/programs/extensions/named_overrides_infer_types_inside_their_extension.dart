extension F<A, B extends List<A>> on List<A> {
  (Type, Type) get types => (A, B);

  void show() {
    final receiver = this;
    print(F(this).types);
    print(F(receiver).types);
    print(F<A, B>(this).types);
  }
}

extension Repeated<T> on Map<T, T> {
  Type get type => T;
}

extension Nullable<T extends Object> on T? {
  Type get type => T;
}

extension Dependent<A extends B, B extends num> on int {
  Type get type => A;
}

Type nullable(int? value) => Nullable(value).type;

void main() {
  F<num, List<int>>(<int>[]).show();
  // expect: (num, List<num>)
  // expect: (num, List<num>)
  // expect: (num, List<int>)
  print(F(<int>[]).types); // expect: (int, List<int>)
  print(Repeated(<int, num>{}).type); // expect: num
  print(nullable(null)); // expect: int
  print(Dependent(0).type); // expect: num
}
