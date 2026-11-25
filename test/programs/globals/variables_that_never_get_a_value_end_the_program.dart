import 'dart:io';

int a = exit(4);
void main() {
  print('a'); // expect: a
  number(a);
}

void number(int n) => print(n); // exit: 4
