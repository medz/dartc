import 'numeric.dart';

class const Initializer(num input) {
  final bool result = input > floating;
}

class const Default([bool input = integer == floating]) {
  final bool result = input;
}

const initializer = Initializer(integer);
const defaultValue = Default();
const sharedDependency = (integer == floating, Initializer(integer));
