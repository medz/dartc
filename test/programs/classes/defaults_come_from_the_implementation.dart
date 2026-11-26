// official: Dart 3.14.0 takes the default of the abstract declaration (dart-lang/sdk#52557).
class Base {
  int f([num x = 1]) => x.toInt();
}

abstract class Narrow extends Base {
  int f([covariant int x = 2]);
}

class Child extends Narrow {}

class Aligned {
  int f([num x = 1]) => x.toInt();
}

abstract class AlignedNarrow extends Aligned {
  int f([covariant int x = 1]);
}

class AlignedChild extends AlignedNarrow {}

void main() {
  print(Child().f()); // expect: 1
  final torn = Child().f;
  print(torn()); // expect: 1
  print(Child().f(5)); // expect: 5
  print(AlignedChild().f()); // expect: 1
}
