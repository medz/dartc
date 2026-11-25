class Trace {
  String log = '';
  int v = 1;
  int first() {
    log += 'A';
    return v;
  }

  S second() {
    log += 'B';
    return S(this);
  }
}

class S {
  final Trace t;
  S(this.t);
  String toString() {
    t.log += 'S';
    t.v = 2;
    return '7';
  }
}

void main() {
  final t = Trace();
  print(
    '${'${t.first()}'}${t.second()}${("x${t.first()}"
        'y${t.second()}')}z',
  ); // expect: 17x1y7z
  print(t.log); // expect: ABABSS
  print('${'a'}'); // expect: a
  print(
    '${'a'
        'b${1}'}',
  ); // expect: ab1
  print('${''}'); // expect:
}
