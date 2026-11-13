import 'effects.dart' as effects;

int get value => effects.tick(1);
set value(int n) {
  effects.tick(n);
}

int? get maybe => null;
set maybe(int? n) {
  effects.tick(n!);
}

int Function(int) get callback {
  effects.tick(2);
  return effects.tick;
}

class Access() {
  static int get value => effects.tick(3);
  static set value(int n) {
    effects.tick(n);
  }

  static Access get origin => Access();
  int get result => 8;
}

mixin Shared {
  static const offset = 4;
  static int get value => effects.tick(offset);
  static set value(int n) {
    effects.tick(n);
  }

  static int call(int n) => effects.tick(n);
}

int access(int n, int mode) {
  try {
    return switch (mode) {
      0 => value += effects.tick(n),
      1 => ++Access.value,
      2 => Access.value++,
      3 => maybe ??= effects.tick(n),
      4 => callback(effects.tick(n)),
      5 => Access.value = effects.tick(n),
      6 => Shared.value += effects.tick(n),
      7 => Shared.offset,
      8 => Shared.call(n),
      _ => value = effects.tick(n),
    };
  } catch (_) {
    return -1;
  }
}

int shorthandGetter() {
  Access a = .origin;
  return a.result;
}
