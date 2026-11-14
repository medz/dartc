int unused(int value) => value - 999;
int increment(int value) => value + 1;

int replacedFunction(int value) {
  final functions = <int Function(int)>[];
  functions.add(unused);
  functions[0] = increment;
  return functions[0](value);
}

T carried<T>(T value) {
  final values = <T>[];
  values.add(value);
  return values[0];
}

int carriedInteger(int value) => carried<int>(value);
Object? carriedObject(Object? value) => carried<Object?>(value);
