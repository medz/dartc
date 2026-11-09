// ignore_for_file: non_exhaustive_switch_expression, unreachable_switch_case
import '../numeric_constants.dart';

const opposite = integer == floating;

int classify(bool value, bool guard) => switch (value) {
  true => 1,
  opposite when guard => 2,
};
