import 'dart:ffi';

class P implements Finalizable {}

List<int> collect(bool include) => [
  if (include)
    for (P? p = P(); p != null; p = null)
      (() {
        p = null;
        return 1;
      })(),
];

void main() {
  print(collect(false)); // expect: []
  print(collect(true)); // expect: [1]
}
