import 'numeric.dart';

class const Parameter(final int value);

class const Field(num value) {
  final int result = (value == floating ? 1 : 'wrong') as dynamic;
}

abstract class Narrow {
  const factory(int value) = Wide;
}

class const Wide(final num value) implements Narrow;

const parameter = Parameter((integer == floating ? 1 : 'wrong') as dynamic);
const field = Field(integer);
const factoryParameter = Narrow((integer == floating ? 1 : 1.5) as dynamic);
