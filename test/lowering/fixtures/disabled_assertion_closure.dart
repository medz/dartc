int skippedClosure() {
  assert((() => <int>[1].isNotEmpty)());
  return 5;
}

class Skipped() {
  this : assert((() => <int>[1].isNotEmpty)());
}

int skippedConstructor() {
  Skipped();
  return 6;
}

extension type SkippedExtension(int x) {
  this : assert((() => <int>[1].isNotEmpty)());
}

int skippedExtension() => SkippedExtension(3).x;
