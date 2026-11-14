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

int aliasedInteger(int value) {
  final values = <int>[value];
  final alias = values;
  alias[0] = value + 1;
  return values[0];
}

int loopInteger(int value, int count) {
  final values = <int>[value];
  for (var index = 0; index < count; index++) {
    values[0] = values[0] + index;
  }
  return values[0];
}

int observedInteger(int value, void Function(List<int>) observe) {
  final values = <int>[value];
  observe(values);
  return values[0];
}

int checkedInteger(int value, int index) {
  final values = <int>[value];
  return values[index];
}
