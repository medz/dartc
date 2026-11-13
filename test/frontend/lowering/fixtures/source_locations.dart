import 'dart:math';

part 'source_locations_part.dart';

external int leaf(int value);
external Future<int> pending(int value);

int callSites(bool first) {
  if (first) {
    return leaf(leaf(1));
  }
  return leaf(2);
}

int nested() {
  int local() {
    return leaf(3);
  }

  return local();
}

Future<int> suspended() async {
  final value = await pending(leaf(4));
  throw value;
}

int guarded() {
  try {
    return leaf(5);
  } catch (_) {
    rethrow;
  }
}

double squareRoot(num value) => sqrt(value);

class SourceParent(int value);

class SourceChild() extends SourceParent {
  this : super(leaf(7));
}
