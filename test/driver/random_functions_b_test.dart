@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(10)
library;

import 'package:test/test.dart';

import 'random_functions.dart';

void main() => compareFunctions([for (var i = 6; i < 12; i++) i]);
