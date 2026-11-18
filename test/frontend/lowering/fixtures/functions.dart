import 'effects.dart' as effects;

bool gate(bool a, bool b, int n) => a && (b || effects.probe(n));

int pair({required int a, required int b}) => a * 10 + b;

int ordered(int n) => pair(b: effects.tick(n), a: effects.tick(n + 1));

int sum(int n, bool twice) {
  var i = 0;
  var result = 0;
  while (i < n) {
    final term = effects.tick(i);
    if (twice) {
      result = result + term * 2;
    } else {
      result = result + term;
    }
    i = i + 1;
  }
  return result;
}

void discard(int n) {
  effects.tick(n);
}

void voidResult(int n) => effects.tick(n);

void forwardVoid(int n) {
  return voidResult(n);
}

set effectValue(int value) => effects.tick(value + 1);

class SetterBody() {
  set value(int value) => effects.tick(value + 2);
}

extension SetterExtension on int {
  set effect(int value) => effects.tick(value + this);
}

int setterResults(int n) {
  final top = effectValue = n;
  final instance = SetterBody().value = n;
  final extension = 3.effect = n;
  return top + instance + extension;
}

bool choose({required int first, required bool second}) => first < 3 && second;

bool nestedArguments(int n, bool enabled) =>
    choose(first: effects.tick(n), second: enabled && effects.probe(n + 1));

int early(bool a) {
  while (true) {
    if (a) return 1;
    return 2;
  }
}

int literalBranch() {
  if (true) return 42;
}
