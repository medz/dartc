// SDK constant evaluation rounds the integer before comparing it.
// ignore_for_file: const_eval_throws_exception, variable_type_mismatch

import 'numeric_constants.dart';

const accepted = Above(integer);
const zero = Equal(9007199254740992);

class const Zero() {
  this : assert(0.0 == -0.0);
}

const signedZeros = Zero();
const int selected = (integer > floating ? 7 : 'wrong') as dynamic;

@Above(integer)
int annotated([Object value = const Above(integer)]) => 1;

int defaultValue([int value = (integer > floating ? 7 : 'wrong') as dynamic]) =>
    value;

int evaluated() {
  const local = Above(integer);
  return local == accepted ? 1 : 0;
}
