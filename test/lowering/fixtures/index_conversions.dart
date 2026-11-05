import 'effects.dart';

class Indices(var int value) {
  int operator [](Object key) => tick(2) + value;
  void operator []=(int key, int next) {
    tick(5);
    value = next;
  }
}

class ExtensionIndices(var int value);

extension Indexed on ExtensionIndices {
  int operator [](Object key) => tick(2) + value;
  void operator []=(int key, int next) {
    tick(5);
    value = next;
  }
}

class NullableIndices(var int? value) {
  int? operator [](Object key) {
    tick(2);
    return value;
  }

  void operator []=(int key, int next) {
    tick(5);
    value = next;
  }
}

class NullableExtensionIndices(var int? value);

extension NullableIndexed on NullableExtensionIndices {
  int? operator [](Object key) {
    tick(2);
    return value;
  }

  void operator []=(int key, int next) {
    tick(5);
    value = next;
  }
}

dynamic key(bool valid) {
  tick(1);
  return valid ? 0 : 'bad';
}

int ordinary(bool valid, int mode) {
  final box = Indices(7);
  try {
    return switch (mode) {
      0 => box[key(valid)] = tick(3),
      1 => box[key(valid)] += tick(3),
      2 => box[key(valid)]++,
      _ => ++box[key(valid)],
    };
  } finally {
    tick(8);
  }
}

int implicitExtension(bool valid, int mode) {
  final box = ExtensionIndices(7);
  try {
    return switch (mode) {
      0 => box[key(valid)] = tick(3),
      1 => box[key(valid)] += tick(3),
      2 => box[key(valid)]++,
      _ => ++box[key(valid)],
    };
  } finally {
    tick(8);
  }
}

int explicitExtension(bool valid, int mode) {
  final box = ExtensionIndices(7);
  try {
    // Explicit simple assignment has a separately documented SDK order gap.
    return switch (mode) {
      1 => Indexed(box)[key(valid)] += tick(3),
      2 => Indexed(box)[key(valid)]++,
      _ => ++Indexed(box)[key(valid)],
    };
  } finally {
    tick(8);
  }
}

int ifNullOrdinary(bool valid, bool empty) {
  final box = NullableIndices(empty ? null : 7);
  try {
    return box[key(valid)] ??= tick(3);
  } finally {
    tick(8);
  }
}

int ifNullImplicit(bool valid, bool empty) {
  final box = NullableExtensionIndices(empty ? null : 7);
  try {
    return box[key(valid)] ??= tick(3);
  } finally {
    tick(8);
  }
}

int ifNullExplicit(bool valid, bool empty) {
  final box = NullableExtensionIndices(empty ? null : 7);
  try {
    return NullableIndexed(box)[key(valid)] ??= tick(3);
  } finally {
    tick(8);
  }
}
