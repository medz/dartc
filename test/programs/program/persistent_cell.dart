class Cell {
  int value = 0;
}

void main() {
  final cell = Cell();
  for (var i = 0; i < 1000; i++) {
    cell.value = cell.value + i;
  }
  print(cell.value); // expect: 499500
}
