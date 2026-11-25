import 'dart:io';

var unusedGlobal = 1;
const limit = 3;
void main() {
  if (limit > 2) exit(4);
  main();
}
// exit: 4
