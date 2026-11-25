import 'dart:core' as core;

void print(core.int x) {
  core.print('mine');
}

void main() {
  print(1); // expect: mine
}
