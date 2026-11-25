const a = 'x', b = '$a-$a';

class C {
  static const c = 'z';
}

void main() {
  const d =
      'l'
      'm';
  print(a); // expect: x
  print(b); // expect: x-x
  print('$b$d${(a)}'); // expect: x-xlmx
  print(C.c); // expect: z
  print('${C.c}!'); // expect: z!
}
