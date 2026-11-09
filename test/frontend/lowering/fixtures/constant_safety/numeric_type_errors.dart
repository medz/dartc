import 'numeric.dart';

class const Parameter(final int value);

class const Field(num value) {
  final int result = (value == floating ? 1 : 'wrong') as dynamic;
}

abstract class Narrow {
  const factory(int value) = Wide;
}

class const Wide(final num value) implements Narrow;
