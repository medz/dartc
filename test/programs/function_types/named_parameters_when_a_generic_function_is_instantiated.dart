typedef F = void Function<T>({T? a, T? z});
void top<T>({T? z, T? a}) {}
void nested<T>({void Function<U extends T>(U, T)? z, T? a}) {}
void check(F f) {
  final type = f<int>.runtimeType;
  print(type);
  print(type == top<int>.runtimeType);
}

void main() {
  void local<T>({T? z, T? a}) {}
  print(top.runtimeType); // expect: <Y0>({Y0? z, Y0? a}) => void
  print(local.runtimeType); // expect: <Y0>({Y0? a, Y0? z}) => void
  check(top);
  // expect: ({int? z, int? a}) => void
  // expect: true
  check(local);
  // expect: ({int? a, int? z}) => void
  // expect: false
  final f = nested;
  print(
    f<num>.runtimeType,
  ); // expect: ({(<Y0 extends num>(Y0, num) => void)? z, num? a}) => void
  print(f<num>.runtimeType == nested<num>.runtimeType); // expect: true
}
