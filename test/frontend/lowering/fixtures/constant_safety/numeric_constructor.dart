// Explicit super calls also exercise the initializer argument environment.
// ignore_for_file: use_super_parameters

import 'numeric.dart';

class const Initializer(num input) {
  final bool result = input > floating;
}

class const Default([bool input = integer == floating]) implements Choice {
  @override
  final bool result = input;
}

class const Listed(num input) {
  final bool result;
  this : result = input > floating;
}

class const Inherited([super.input]) extends Default;

class const ExplicitSuper(num input) extends Initializer {
  this : super(input);
}

abstract class Choice {
  bool get result;
  const factory([bool input]) = Default;
}

class const Redirected(final bool result) {
  const new from(num input) : this(input > floating);
}

class const Typed<T>(final T value, num input) {
  final bool result = input > floating;
}

class const GenericInherited<T>(T value, num input) extends Typed<T> {
  this : super(value, input);
}

extension type const Flag(bool result) {
  const new from(num input) : this(input > floating);
}

enum const Ordering(num input) {
  exact(integer);

  final bool result = input > floating;
}

class const Asserted(num input) {
  final bool result = input > floating;
  this : assert(input == floating || input > floating);
}

const initializer = Initializer(integer);
const defaultValue = Default();
const explicitDefault = Default(true);
const listed = Listed(integer);
const inherited = Inherited();
const explicitSuper = ExplicitSuper(integer);
const factoryDefault = Choice();
const redirected = Redirected.from(integer);
const generic = Typed<int>(7, integer);
const genericInherited = GenericInherited<String>('value', integer);
const erased = Flag.from(integer);
const enumValue = Ordering.exact;
const asserted = Asserted(integer);
const sharedDependency = (integer == floating, Initializer(integer));
