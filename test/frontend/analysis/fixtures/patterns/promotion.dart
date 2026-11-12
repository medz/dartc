// ignore_for_file: undefined_getter
class Cell(final Object? _value);

bool invalid(Cell cell) {
  if (cell._value case [int()]) return cell._value.isEven;
  return false;
}
