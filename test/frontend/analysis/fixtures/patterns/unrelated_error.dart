// ignore_for_file: non_exhaustive_switch_expression, unreachable_switch_case, return_of_invalid_type
import '../numeric_constants.dart';

const opposite = integer == floating;

int classify(bool value) => switch (value) {
  true => 'wrong',
  opposite => 2,
};
