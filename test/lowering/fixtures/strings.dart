// ignore_for_file: unnecessary_brace_in_string_interps, unnecessary_type_name_in_constructor, use_primary_constructors
String scalars(Object? a, Object? b) => 'left=$a; right=${b}!';
String adjacent(Object? a, Object? b) =>
    'left=$a'
    '; right=${b}'
    '!';
String concat(String a, String b) => a + b;
String compound(String a, String b) {
  a += b;
  return a;
}

class Trace {
  String log = '';
  int value = 1;
  bool fail = false;
  Trace();
  Trace first() {
    log += 'A';
    return this;
  }

  int second() {
    log += 'B';
    value = 2;
    return 7;
  }

  @override
  String toString() {
    log += 'S';
    if (fail) throw 99;
    return 'value=$value';
  }
}

String order(bool fail) {
  final t = Trace();
  t.fail = fail;
  String result;
  try {
    result = '${t.first()}/${t.second()}';
  } catch (_) {
    result = 'caught';
  }
  return '$result:${t.log}';
}

String adjacentOrder(bool fail) {
  final t = Trace();
  t.fail = fail;
  String result;
  try {
    result =
        '${t.first()}'
        '/'
        '${t.second()}';
  } catch (_) {
    result = 'caught';
  }
  return '$result:${t.log}';
}

String nestedOrder() {
  final t = Trace();
  final result = '${'${t.first()}'}${t.second()}';
  return '$result:${t.log}';
}

String recordValue(Object? value) => '${(value, z: 2, a: (1,))}';

class Plain {}

String plainObject() => '${Plain()}';

class Child extends Trace {
  @override
  String toString() => 'child';
}

String virtualObject() {
  Trace value = Child();
  return '$value';
}

String parenthesizedOrder() {
  final t = Trace();
  final result = '${('x${t.first()}y')}${t.second()}';
  return '$result:${t.log}';
}

String conditionalOrder(bool flag) {
  final t = Trace();
  final result = '${flag ? '${t.first()}' : ''}${t.second()}';
  return '$result:${t.log}';
}

String recordOrder() {
  final t = Trace();
  final result = '${(t.first(), z: t.first(), a: t.first())}${t.second()}';
  return '$result:${t.log}';
}
