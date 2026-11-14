class Missing() {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #calculate &&
        invocation.isMethod &&
        invocation.typeArguments.single == int &&
        invocation.positionalArguments.single == 7 &&
        invocation.namedArguments[#z] == 11 &&
        invocation.namedArguments[#a] == 13) {
      return 31;
    }
    return -1;
  }
}

int missing() {
  dynamic value = Missing();
  return value.calculate<int>(7, z: 11, a: 13);
}

class Accessors() {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    if (invocation.isGetter && invocation.memberName == #_value) return 17;
    if (invocation.isSetter &&
        invocation.memberName == const Symbol('_value=')) {
      return invocation.positionalArguments.single;
    }
    return -100;
  }
}

int accessors() {
  dynamic value = Accessors();
  final int first = value._value;
  value._value = 23;
  return first + (value.calls as int);
}

class Box<T>(final T value) {
  T Function(T) get action =>
      (T other) => T == int ? other : value;
}

int getterCall() {
  dynamic value = Box<int>(7);
  return value.action(19);
}

int rejectedShape() {
  int local(int value) => value + 1;
  dynamic function = local;
  try {
    function(1, 2);
  } on NoSuchMethodError {
    return 37;
  }
  return -1;
}

int rejectedTypes() {
  T local<T>(T value) => value;
  dynamic function = local;
  try {
    function<int, String>(1);
  } on NoSuchMethodError {
    return 41;
  }
  return -1;
}

abstract class Contract() {
  int calculate<T>(int value, {required int z, required int a});
}

class Forwarded() extends Missing implements Contract;

int forwarded() => Forwarded().calculate<int>(7, z: 11, a: 13);

int nullable(bool present) {
  dynamic value = present ? Box<int>(7) : null;
  try {
    return value.action(19);
  } on NoSuchMethodError {
    return 43;
  }
}
