int f(int x) {
  var r = 0;
  switch (x) {
    case 1:
    case -2:
      r = 10;
    case 3:
      r = 20;
      break;
    case 4:
      return 99;
    default:
      r = 30;
  }
  return r;
}

void main() {
  print([
    for (final x in [1, -2, 3, 4, 5]) f(x),
  ]); // expect: [10, 10, 20, 99, 30]
}
