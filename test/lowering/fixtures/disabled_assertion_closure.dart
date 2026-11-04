// ignore_for_file: use_primary_constructors

// The closure needs unsupported collection lowering only when assertions run.
int skippedClosure() {
  assert((() => <int>[1].isNotEmpty)());
  return 5;
}

class Skipped {
  new() : assert((() => <int>[1].isNotEmpty)());
}

int skippedConstructor() {
  Skipped();
  return 6;
}
