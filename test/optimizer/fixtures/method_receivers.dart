class Base() {
  int value() => 1;
  int read() => value();
}

class Child() extends Base {
  @override
  int value() => 2;
  int readSuper() => super.read();
}

class Implementation() implements Base {
  @override
  int value() => 3;
  @override
  int read() => value();
}

mixin Reading on Base {
  int readMixed() => super.read();
}

class Mixed() extends Base with Reading {
  @override
  int value() => 4;
}

int readInterface(Base value) => value.read();
