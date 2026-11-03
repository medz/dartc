final calls = <int>[];

int tick(int value) {
  calls.add(value);
  if (value < 0) throw StateError('negative tick');
  return value;
}

bool probe(int value) => tick(value) > 0;
