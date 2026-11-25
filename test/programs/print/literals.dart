void main() {
  print('a'); // expect: a
  print(
    "b"
    'c',
  ); // expect: bc
  print(r'\n'); // expect: \n
  print('''d
e''');
  // expect: d
  // expect: e
  print('\u{1F600}\x41'); // expect: 😀A
  print(('f')); // expect: f
  print(''); // expect:
}
