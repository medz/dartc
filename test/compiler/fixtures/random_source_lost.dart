import 'dart:math';

import 'random_unavailable.dart' show checkUnavailable;

void main() => checkUnavailable(Random.secure());
