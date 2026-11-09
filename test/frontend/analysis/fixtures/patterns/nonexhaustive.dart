import '../numeric_constants.dart';

const same = integer > floating;

int classify(bool value) => switch (value) {
  true => 1,
  same => 2,
};
