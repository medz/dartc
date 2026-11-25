Stream<Never> s() async* {
  throw 's';
}

Stream<Never> e() async* {}
void main() async {
  try {
    await for (final x in s()) {
      print(x);
    }
  } catch (e) {
    print(e);
  }
  // expect: s
  await for (final x in e()) {
    print('no');
  }
  await for (Never _ in e()) {}
  for (final x in <Never>[]) {
    print(x);
  }
  for (Never x in const <Never>[]) {
    print('z');
  }
  print([for (final x in <Never>[]) x]); // expect: []
  print([await for (final x in e()) x]); // expect: []
  l:
  for (final x in <Never>[]) {
    continue l;
  }
  for (final Never x in <Never>[]) {
    break;
  }
  int k = 0;
  for (k in <Never>[]) {}
  print(k); // expect: 0
  outer:
  await for (final x in e()) {
    break outer;
  }
  print('end'); // expect: end
}
