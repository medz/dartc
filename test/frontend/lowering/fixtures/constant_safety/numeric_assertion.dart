import 'numeric.dart';

class const Rejected(num value) {
  this : assert(value == floating, 'The numeric values must be equal.');
}

const rejected = Rejected(integer);
